//go:build windows

package desktop

import (
	"fmt"
	"syscall"
	"unsafe"

	"github.com/jchv/go-webview2"
	"golang.org/x/sys/windows"
)

const (
	wmClose       = 0x0010
	wmHotKey      = 0x0312
	emergencyID   = 0x4848
	emergencyMods = 0x4000 | 0x0001 | 0x0002 | 0x0004
	swHide        = 0
	swShow        = 5
	swRestore     = 9
	mbOk          = 0x00000000
	mbIconError   = 0x00000010
)

var (
	user32               = windows.NewLazySystemDLL("user32.dll")
	procShowWindow       = user32.NewProc("ShowWindow")
	procSetForeground    = user32.NewProc("SetForegroundWindow")
	procSetWindowLongPtr = user32.NewProc("SetWindowLongPtrW")
	procCallWindowProc   = user32.NewProc("CallWindowProcW")
	procMessageBoxW      = user32.NewProc("MessageBoxW")
	procGetSystemMetrics = user32.NewProc("GetSystemMetrics")
	procRegisterHotKey   = user32.NewProc("RegisterHotKey")
	procUnregisterHotKey = user32.NewProc("UnregisterHotKey")
)

var (
	nativeView             webview2.WebView
	nativeHWND             uintptr
	remoteView             webview2.WebView
	remoteHWND             uintptr
	originalProcs          = map[uintptr]uintptr{}
	emergencyHost          *Host
	registeredEmergencyKey string
)

func setEmergencyHost(host *Host) { emergencyHost = host }

func (host *Host) emergencyHotkey() string {
	host.mu.Lock()
	defer host.mu.Unlock()
	if host.emergencyKey == "" {
		return "X"
	}
	return host.emergencyKey
}

func emergencyVirtualKey(key string) uintptr {
	if key == "F12" {
		return 0x7B
	}
	if key == "Q" {
		return 'Q'
	}
	return 'X'
}

func registerEmergencyHotkey(key string) error {
	if registeredEmergencyKey == key {
		return nil
	}
	previous := registeredEmergencyKey
	if previous != "" {
		procUnregisterHotKey.Call(nativeHWND, emergencyID)
	}
	result, _, _ := procRegisterHotKey.Call(nativeHWND, emergencyID, emergencyMods, emergencyVirtualKey(key))
	if result == 0 {
		if previous != "" {
			procRegisterHotKey.Call(nativeHWND, emergencyID, emergencyMods, emergencyVirtualKey(previous))
		}
		return fmt.Errorf("cannot register Ctrl+Alt+Shift+%s emergency disconnect hotkey", key)
	}
	registeredEmergencyKey = key
	return nil
}

func setNativeEmergencyHotkey(key string) error {
	if nativeView == nil {
		return nil
	}
	result := make(chan error, 1)
	nativeView.Dispatch(func() { result <- registerEmergencyHotkey(key) })
	return <-result
}

func createNativeWindow(url string) error {
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	width, height := uint(1120), uint(780)
	if screenWidth > 128 {
		width = min(width, uint(screenWidth)-64)
	}
	if screenHeight > 192 {
		height = min(height, uint(screenHeight)-96)
	}
	view := webview2.NewWithOptions(webview2.WebViewOptions{
		AutoFocus: true,
		WindowOptions: webview2.WindowOptions{
			Title:  "Home Tunnel",
			Width:  width,
			Height: height,
			IconId: 1,
			Center: true,
		},
	})
	if view == nil {
		showWebView2Error()
		return fmt.Errorf("Microsoft Edge WebView2 runtime is not available")
	}
	nativeView = view
	nativeHWND = uintptr(view.Window())
	subclassHideOnClose(nativeHWND)
	if emergencyHost != nil {
		if err := registerEmergencyHotkey(emergencyHost.emergencyHotkey()); err != nil {
			view.Terminate()
			return err
		}
	}
	view.Navigate(url)
	return nil
}

func runNativeWindow() {
	if nativeView != nil {
		nativeView.Run()
	}
}

func showNativeWindow() {
	if nativeView == nil {
		return
	}
	nativeView.Dispatch(func() {
		if nativeHWND == 0 {
			return
		}
		procShowWindow.Call(nativeHWND, swRestore)
		procShowWindow.Call(nativeHWND, swShow)
		procSetForeground.Call(nativeHWND)
	})
}

func quitNativeWindow() {
	if nativeView != nil {
		nativeView.Terminate()
	}
}

func openNativeRemoteWindow(url string) error {
	if nativeView == nil {
		return ErrRemoteWindowUnavailable
	}
	result := make(chan error, 1)
	nativeView.Dispatch(func() {
		if remoteView == nil {
			remoteView = webview2.NewWithOptions(webview2.WebViewOptions{
				AutoFocus: true,
				WindowOptions: webview2.WindowOptions{
					Title: "Home Tunnel · 远程控制", Width: 1280, Height: 840, IconId: 1, Center: true,
				},
			})
			if remoteView == nil {
				result <- ErrRemoteWindowUnavailable
				return
			}
			remoteHWND = uintptr(remoteView.Window())
			subclassHideOnClose(remoteHWND)
		}
		remoteView.Navigate(url)
		procShowWindow.Call(remoteHWND, swRestore)
		procShowWindow.Call(remoteHWND, swShow)
		procSetForeground.Call(remoteHWND)
		result <- nil
	})
	return <-result
}

func closeNativeRemoteWindow() {
	if nativeView == nil {
		return
	}
	nativeView.Dispatch(func() {
		if remoteView != nil {
			remoteView.Navigate("about:blank")
			procShowWindow.Call(remoteHWND, swHide)
		}
	})
}

func subclassHideOnClose(hwnd uintptr) {
	cb := syscall.NewCallback(hideOnCloseProc)
	originalProcs[hwnd], _, _ = procSetWindowLongPtr.Call(hwnd, ^uintptr(3), cb)
}

func hideOnCloseProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	if msg == wmHotKey && hwnd == nativeHWND && wParam == emergencyID {
		if emergencyHost != nil {
			go emergencyHost.EmergencyStop()
		}
		return 0
	}
	if msg == wmClose {
		if hwnd == remoteHWND && remoteView != nil {
			remoteView.Navigate("about:blank")
		}
		procShowWindow.Call(hwnd, swHide)
		return 0
	}
	ret, _, _ := procCallWindowProc.Call(originalProcs[hwnd], hwnd, msg, wParam, lParam)
	return ret
}

func showWebView2Error() {
	title, _ := windows.UTF16PtrFromString("Home Tunnel")
	text, _ := windows.UTF16PtrFromString("无法创建窗口。请安装 Microsoft Edge WebView2 Runtime 后再打开 Home Tunnel。")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), mbOk|mbIconError)
}
