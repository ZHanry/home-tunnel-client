//go:build windows

package desktop

import (
	"fmt"
	"time"
	"unsafe"

	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"
)

// The approval popup is a borderless, always-on-top tool window (no taskbar
// button) in the bottom-right corner of the primary work area. It is shown
// without activation so it never takes keyboard focus from what the user is
// typing; the buttons still work with a click.
const (
	wsPopup           = 0x80000000
	wsClipChildren    = 0x02000000
	wsExTopmost       = 0x00000008
	wsExToolWindow    = 0x00000080
	wmSize            = 0x0005
	wmMove            = 0x0003
	wmSettingChange   = 0x001A
	wmDisplayChange   = 0x007E
	swShowNoActivate  = 4
	swpNoActivate     = 0x0010
	spiGetWorkArea    = 0x0030
	spiSetWorkArea    = 0x002F
	idcArrow          = 32512
	flashwAll         = 0x00000003
	flashwTimerNoFG   = 0x0000000C
	dwmCornerPref     = 33
	dwmCornerRound    = 2
	popupClassName    = "HomeTunnelApprovalPopup"
	popupReplyTimeout = 3 * time.Second
)

var (
	procRegisterClassEx  = user32.NewProc("RegisterClassExW")
	procCreateWindowEx   = user32.NewProc("CreateWindowExW")
	procDestroyWindow    = user32.NewProc("DestroyWindow")
	procDefWindowProc    = user32.NewProc("DefWindowProcW")
	procSetWindowPos     = user32.NewProc("SetWindowPos")
	procSystemParamsInfo = user32.NewProc("SystemParametersInfoW")
	procLoadCursor       = user32.NewProc("LoadCursorW")
	procIsWindowVisible  = user32.NewProc("IsWindowVisible")
	procFlashWindowEx    = user32.NewProc("FlashWindowEx")
	procGetDpiForSystem  = user32.NewProc("GetDpiForSystem")
	dwmapi               = windows.NewLazySystemDLL("dwmapi.dll")
	procDwmSetAttribute  = dwmapi.NewProc("DwmSetWindowAttribute")
)

// All popup state is touched only on the UI thread (inside Dispatch or the
// window procedure).
var (
	popupView     *edge.Chromium
	popupHWND     uintptr
	popupLoaded   bool
	popupFailed   bool
	popupMode     string
	popupFlash    bool
	popupWndProc  = windows.NewCallback(popupWindowProc)
	popupRegister bool
)

type winRect struct{ Left, Top, Right, Bottom int32 }

type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   windows.Handle
	Icon       windows.Handle
	Cursor     windows.Handle
	Background windows.Handle
	MenuName   *uint16
	ClassName  *uint16
	IconSm     windows.Handle
}

type flashInfo struct {
	Size    uint32
	HWND    uintptr
	Flags   uint32
	Count   uint32
	Timeout uint32
}

func showNativeApprovalPopup(address, mode string, attention bool) bool {
	if nativeView == nil {
		return false
	}
	result := make(chan bool, 1)
	nativeView.Dispatch(func() {
		if !ensureApprovalPopup(address) {
			result <- false
			return
		}
		popupMode, popupFlash = mode, popupFlash || attention
		if popupLoaded {
			applyApprovalPopup()
		}
		result <- true
	})
	select {
	case shown := <-result:
		return shown
	case <-time.After(popupReplyTimeout):
		return false
	}
}

func hideNativeApprovalPopup() {
	if nativeView == nil {
		return
	}
	nativeView.Dispatch(func() {
		popupMode, popupFlash = "", false
		if popupHWND == 0 {
			return
		}
		procShowWindow.Call(popupHWND, swHide)
		if popupLoaded {
			popupView.Eval("window.htPopup&&window.htPopup.hide()")
		}
	})
}

// ensureApprovalPopup creates the hidden window and its WebView2 once. The
// page loads while hidden and is shown after its rendered-content handshake, so the
// user never sees an empty white frame.
func ensureApprovalPopup(address string) bool {
	if popupHWND != 0 {
		return true
	}
	if popupFailed {
		return false
	}
	var instance windows.Handle
	_ = windows.GetModuleHandleEx(0, nil, &instance)
	className, _ := windows.UTF16PtrFromString(popupClassName)
	if !popupRegister {
		cursor, _, _ := procLoadCursor.Call(0, idcArrow)
		// COLOR_WINDOW + 1 supplies an opaque system brush while WebView2 paints.
		class := wndClassEx{WndProc: popupWndProc, Instance: instance, Cursor: windows.Handle(cursor), Background: windows.Handle(6), ClassName: className}
		class.Size = uint32(unsafe.Sizeof(class))
		if atom, _, _ := procRegisterClassEx.Call(uintptr(unsafe.Pointer(&class))); atom == 0 {
			popupFailed = true
			return false
		}
		popupRegister = true
	}
	title, _ := windows.UTF16PtrFromString("Home Tunnel · 远程控制请求")
	hwnd, _, _ := procCreateWindowEx.Call(wsExTopmost|wsExToolWindow, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)),
		wsPopup|wsClipChildren, 0, 0, popupRequestWidth, popupRequestHeight, 0, 0, uintptr(instance), 0)
	if hwnd == 0 {
		popupFailed = true
		return false
	}
	if procDwmSetAttribute.Find() == nil {
		preference := uint32(dwmCornerRound)
		procDwmSetAttribute.Call(hwnd, dwmCornerPref, uintptr(unsafe.Pointer(&preference)), unsafe.Sizeof(preference))
	}
	view := edge.NewChromium()
	view.MessageCallback = func(message string) {
		switch message {
		case "ht-popup:ready":
			popupLoaded = true
			if popupMode != "" {
				applyApprovalPopup()
			}
		case "ht-popup:rendered:request", "ht-popup:rendered:session":
			if popupLoaded && message == "ht-popup:rendered:"+popupMode {
				revealApprovalPopup()
			}
		case "ht-popup:empty:request", "ht-popup:empty:session":
			if message == "ht-popup:empty:"+popupMode {
				procShowWindow.Call(popupHWND, swHide)
			}
		}
	}
	popupHWND, popupView = hwnd, view
	// Embed pumps messages until the controller exists; a queued Dispatch
	// wake-up can be consumed there, so post a fresh one afterwards.
	embedded := view.Embed(hwnd)
	nativeView.Dispatch(func() {})
	if !embedded {
		procDestroyWindow.Call(hwnd)
		popupHWND, popupView, popupFailed = 0, nil, true
		return false
	}
	if settings, err := view.GetSettings(); err == nil {
		_ = settings.PutAreDefaultContextMenusEnabled(false)
		_ = settings.PutAreDevToolsEnabled(false)
		_ = settings.PutIsZoomControlEnabled(false)
		_ = settings.PutIsStatusBarEnabled(false)
		_ = settings.PutAreBrowserAcceleratorKeysEnabled(false)
	}
	// Never use a transparent WebView backing surface for the approval window.
	if controller := view.GetController().GetICoreWebView2Controller2(); controller != nil {
		_ = controller.PutDefaultBackgroundColor(edge.COREWEBVIEW2_COLOR{A: 255, R: 255, G: 255, B: 255})
	}
	view.Resize()
	view.Navigate(address)
	return true
}

func applyApprovalPopup() {
	// A mode change may temporarily have no matching JS state. Stay hidden until
	// the content acknowledgement rather than displaying an empty surface.
	procShowWindow.Call(popupHWND, swHide)
	width, height := popupSize(popupMode)
	dpi := uint32(96)
	if procGetDpiForSystem.Find() == nil {
		if value, _, _ := procGetDpiForSystem.Call(); value != 0 {
			dpi = uint32(value)
		}
	}
	bounds := popupBounds(workArea(), scaleForDPI(width, dpi), scaleForDPI(height, dpi), scaleForDPI(popupMargin, dpi))
	hwndTopmost := ^uintptr(0)
	procSetWindowPos.Call(popupHWND, hwndTopmost, uintptr(bounds.Left), uintptr(bounds.Top),
		uintptr(bounds.Right-bounds.Left), uintptr(bounds.Bottom-bounds.Top), swpNoActivate)
	popupView.Resize()
	popupView.Eval(fmt.Sprintf("window.htPopup&&window.htPopup.show(%q)", popupMode))
}

// Revealing is a separate step: popup.js acknowledges that its mode has real
// content. Navigation completion alone does not mean deferred scripts painted.
func revealApprovalPopup() {
	procShowWindow.Call(popupHWND, swShowNoActivate)
	popupView.Resize()
	if popupFlash {
		popupFlash = false
		// A tool window has no taskbar button; flash the main window's one
		// when it is open so the request is noticed without stealing focus.
		if visible, _, _ := procIsWindowVisible.Call(nativeHWND); visible != 0 {
			info := flashInfo{HWND: nativeHWND, Flags: flashwAll | flashwTimerNoFG, Count: 3}
			info.Size = uint32(unsafe.Sizeof(info))
			procFlashWindowEx.Call(uintptr(unsafe.Pointer(&info)))
		}
	}
}

func workArea() popupRect {
	var area winRect
	if ok, _, _ := procSystemParamsInfo.Call(spiGetWorkArea, 0, uintptr(unsafe.Pointer(&area)), 0); ok == 0 {
		width, _, _ := procGetSystemMetrics.Call(0)
		height, _, _ := procGetSystemMetrics.Call(1)
		return popupRect{Right: int(width), Bottom: int(height)}
	}
	return popupRect{Left: int(area.Left), Top: int(area.Top), Right: int(area.Right), Bottom: int(area.Bottom)}
}

func popupWindowProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	switch msg {
	case wmSize:
		if popupView != nil {
			popupView.Resize()
		}
		return 0
	case wmMove:
		if popupView != nil {
			_ = popupView.NotifyParentWindowPositionChanged()
		}
		return 0
	case wmSettingChange, wmDisplayChange:
		// Follow a moved or resized taskbar while the popup is visible.
		if (msg == wmDisplayChange || wParam == spiSetWorkArea) && popupMode != "" && popupLoaded {
			applyApprovalPopup()
		}
	case wmClose:
		// Alt+F4 only hides the popup; the request stays in the main window.
		popupMode = ""
		procShowWindow.Call(hwnd, swHide)
		if popupLoaded {
			popupView.Eval("window.htPopup&&window.htPopup.hide()")
		}
		return 0
	}
	ret, _, _ := procDefWindowProc.Call(hwnd, msg, wParam, lParam)
	return ret
}
