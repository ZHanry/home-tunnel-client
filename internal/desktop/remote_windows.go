//go:build windows

package desktop

import (
	"runtime"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"
)

// Own the secondary HWND instead of creating go-webview2 WebView wrappers.
// The wrapper retains every HWND in its process-global windowContext map. One
// reusable Chromium/controller and one removable init script keep this bounded.
const remoteWindowClass = "HomeTunnelRemoteWindow"

var (
	remoteView          *edge.Chromium
	remoteCore          *remoteCoreWebView2
	remoteHWND          uintptr
	remoteGeneration    uint64
	remoteScriptID      string
	remotePending       *remoteScriptRegistration
	remoteCloseRevision uint64
	remoteRegistered    bool
	remotePoisoned      bool
	remoteWndProc       = windows.NewCallback(remoteWindowProc)
	procLoadIcon        = user32.NewProc("LoadIconW")
)

// These operations are named separately so the registration transaction can be
// tested without creating a native window; production always uses this renderer.
var navigateRemoteDocument = func(address string) { remoteView.Navigate(address) }
var presentRemoteDocument = func() {
	procShowWindow.Call(remoteHWND, swRestore)
	procShowWindow.Call(remoteHWND, swShow)
	procSetForeground.Call(remoteHWND)
	remoteView.Resize()
	remoteView.Focus()
}

type remoteScriptRegistration struct {
	generation    uint64
	address       string
	script        string
	result        chan error
	adding        bool
	closeRevision uint64
	// 0: pending, 1: cancelled, 2: committing on the UI thread.
	phase atomic.Uint32
	done  bool
}

func (pending *remoteScriptRegistration) finish(err error) {
	if !pending.done {
		pending.done = true
		pending.result <- err
	}
}

func openNativeRemoteWindow(launch model.RemoteWindowLaunch) error {
	script, err := remoteHandoffScript(launch)
	if err != nil {
		return err
	}
	if nativeView == nil {
		return ErrRemoteWindowUnavailable
	}
	pending := &remoteScriptRegistration{generation: launch.Generation, address: launch.URL, script: script, result: make(chan error, 1)}
	nativeView.Dispatch(func() {
		if remotePending != nil || remotePoisoned {
			pending.script = ""
			pending.finish(ErrRemoteWindowUnavailable)
			return
		}
		if pending.phase.Load() == 1 || !ensureRemoteWindow() {
			pending.script = ""
			pending.finish(ErrRemoteWindowUnavailable)
			return
		}
		pending.closeRevision = remoteCloseRevision
		remotePending = pending
		if remoteCore != nil {
			registerRemoteScript()
		} else {
			// The navigation callback supplies the core interface owned by Chromium.
			remoteView.Navigate("about:blank")
		}
	})
	select {
	case err := <-pending.result:
		return err
	case <-time.After(25 * time.Second):
		// Once the UI starts committing, let it finish the atomic replacement.
		if !pending.phase.CompareAndSwap(0, 1) {
			return <-pending.result
		}
		nativeView.Dispatch(func() { cancelRemoteRegistration(pending) })
		return ErrRemoteWindowUnavailable
	}
}

func ensureRemoteWindow() bool {
	if remoteView != nil {
		return true
	}
	var instance windows.Handle
	_ = windows.GetModuleHandleEx(0, nil, &instance)
	className, _ := windows.UTF16PtrFromString(remoteWindowClass)
	if !remoteRegistered {
		cursor, _, _ := procLoadCursor.Call(0, idcArrow)
		icon, _, _ := procLoadIcon.Call(uintptr(instance), 1)
		class := wndClassEx{WndProc: remoteWndProc, Instance: instance, Cursor: windows.Handle(cursor), Icon: windows.Handle(icon), IconSm: windows.Handle(icon), Background: windows.Handle(6), ClassName: className}
		class.Size = uint32(unsafe.Sizeof(class))
		if atom, _, _ := procRegisterClassEx.Call(uintptr(unsafe.Pointer(&class))); atom == 0 {
			return false
		}
		remoteRegistered = true
	}
	area := workArea()
	width, height := min(1280, area.Right-area.Left-64), min(840, area.Bottom-area.Top-64)
	width, height = max(320, width), max(240, height)
	left, top := area.Left+(area.Right-area.Left-width)/2, area.Top+(area.Bottom-area.Top-height)/2
	title, _ := windows.UTF16PtrFromString("Home Tunnel · 远程控制")
	hwnd, _, _ := procCreateWindowEx.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)),
		0x00CF0000|wsClipChildren, uintptr(left), uintptr(top), uintptr(width), uintptr(height), 0, 0, uintptr(instance), 0) // WS_OVERLAPPEDWINDOW
	if hwnd == 0 {
		return false
	}
	view := edge.NewChromium()
	view.MessageCallback = func(string) {}
	view.NavigationCompletedCallback = func(sender *edge.ICoreWebView2, _ *edge.ICoreWebView2NavigationCompletedEventArgs) {
		if remoteCore == nil {
			remoteCore = (*remoteCoreWebView2)(unsafe.Pointer(sender))
			if remotePending != nil && !remotePending.adding {
				registerRemoteScript()
			}
		}
	}
	remoteHWND, remoteView = hwnd, view
	embedded := view.Embed(hwnd)
	nativeView.Dispatch(func() {}) // Embed may consume the dispatch wake-up.
	if !embedded {
		procDestroyWindow.Call(hwnd)
		remoteHWND, remoteView, remotePoisoned = 0, nil, true
		return false
	}
	if settings, err := view.GetSettings(); err == nil {
		_ = settings.PutAreDefaultContextMenusEnabled(false)
		_ = settings.PutAreDevToolsEnabled(false)
		_ = settings.PutIsStatusBarEnabled(false)
	}
	view.Resize()
	return true
}

func closeNativeRemoteWindow() {
	if nativeView != nil {
		nativeView.Dispatch(func() { clearRemoteWindow() })
	}
}

// Remove all handoff authority before navigation. If removal fails, refuse to
// reuse the renderer rather than carry an old initialization script forward.
func cancelRemoteRegistration(pending *remoteScriptRegistration) {
	if pending == nil {
		return
	}
	pending.phase.Store(1)
	pending.script = ""
	pending.finish(ErrRemoteWindowUnavailable)
	if remotePending == pending && !pending.adding {
		remotePending = nil
	}
}

func clearRemoteWindow() bool {
	remoteCloseRevision++
	remoteGeneration = 0
	cancelRemoteRegistration(remotePending)
	if remoteView == nil {
		return !remotePoisoned
	}
	procShowWindow.Call(remoteHWND, swHide)
	if remoteScriptID != "" {
		if !removeRemoteScript(remoteScriptID) {
			remotePoisoned = true
		}
		remoteScriptID = ""
	}
	navigateRemoteDocument("about:blank")
	return !remotePoisoned
}

func remoteWindowProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	switch msg {
	case wmSize:
		if remoteView != nil {
			remoteView.Resize()
		}
		return 0
	case wmMove:
		if remoteView != nil {
			_ = remoteView.NotifyParentWindowPositionChanged()
		}
	case 0x0007: // WM_SETFOCUS
		if remoteView != nil {
			remoteView.Focus()
		}
		return 0
	case wmClose:
		generation := remoteGeneration
		clearRemoteWindow()
		if generation != 0 && emergencyHost != nil {
			go emergencyHost.RemoteClosed(generation)
		}
		return 0
	case 0x0002: // WM_DESTROY must never quit the main window's message loop.
		return 0
	}
	result, _, _ := procDefWindowProc.Call(hwnd, msg, wParam, lParam)
	return result
}

// This prefix matches ICoreWebView2's public COM ABI exactly. The member order
// is taken from the pinned go-webview2/pkg/edge/corewebview2.go (56598839c808).
// That dependency exposes Init but discards the asynchronous script ID; this
// narrow adapter preserves the ID and implements RemoveScript.
// Also verified against Microsoft.Web.WebView2 1.0.4129.50 WebView2.h.
// https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/icorewebview2
// AddScript completes asynchronously: navigation must wait for its callback.
type remoteCoreVtbl struct {
	QueryInterface, AddRef, Release                                             edge.ComProc
	GetSettings, GetSource, Navigate, NavigateToString                          edge.ComProc
	AddNavigationStarting, RemoveNavigationStarting                             edge.ComProc
	AddContentLoading, RemoveContentLoading                                     edge.ComProc
	AddSourceChanged, RemoveSourceChanged                                       edge.ComProc
	AddHistoryChanged, RemoveHistoryChanged                                     edge.ComProc
	AddNavigationCompleted, RemoveNavigationCompleted                           edge.ComProc
	AddFrameNavigationStarting, RemoveFrameNavigationStarting                   edge.ComProc
	AddFrameNavigationCompleted, RemoveFrameNavigationCompleted                 edge.ComProc
	AddScriptDialogOpening, RemoveScriptDialogOpening                           edge.ComProc
	AddPermissionRequested, RemovePermissionRequested                           edge.ComProc
	AddProcessFailed, RemoveProcessFailed                                       edge.ComProc
	AddScriptToExecuteOnDocumentCreated, RemoveScriptToExecuteOnDocumentCreated edge.ComProc
}

type remoteCoreWebView2 struct{ vtbl *remoteCoreVtbl }
type remoteScriptHandlerVtbl struct{ QueryInterface, AddRef, Release, Invoke uintptr }
type remoteScriptHandler struct{ vtbl *remoteScriptHandlerVtbl }

var scriptHandlerVtbl = remoteScriptHandlerVtbl{
	QueryInterface: windows.NewCallback(remoteScriptQueryInterface),
	AddRef:         windows.NewCallback(func(uintptr) uintptr { return 1 }),
	Release:        windows.NewCallback(func(uintptr) uintptr { return 1 }),
	Invoke:         windows.NewCallback(remoteScriptAdded),
}

// A process-lifetime singleton is safe for COM to retain and never accumulates
// per-open Go callbacks. Only one AddScript registration may be outstanding.
var scriptHandler = remoteScriptHandler{vtbl: &scriptHandlerVtbl}

func remoteScriptQueryInterface(this *remoteScriptHandler, iid *windows.GUID, object **remoteScriptHandler) uintptr {
	if object == nil || iid == nil {
		return 0x80004003 // E_POINTER
	}
	*object = nil
	// Both IUnknown and the completed-handler interface use this exact vtable.
	requested := *iid
	unknown, _ := windows.GUIDFromString("{00000000-0000-0000-C000-000000000046}")
	handler, _ := windows.GUIDFromString("{B99369F3-9B11-47B5-BC6F-8E7895FCEA17}")
	if requested != unknown && requested != handler {
		return 0x80004002 // E_NOINTERFACE
	}
	*object = this
	return 0
}

func registerRemoteScript() {
	pending := remotePending
	if pending == nil || pending.adding || pending.phase.Load() == 1 || remoteCore == nil {
		return
	}
	pending.adding = true
	script, err := windows.UTF16PtrFromString(pending.script)
	pending.script = ""
	if err != nil {
		remotePending = nil
		pending.finish(ErrRemoteWindowUnavailable)
		return
	}
	hr, _, _ := remoteCore.vtbl.AddScriptToExecuteOnDocumentCreated.Call(uintptr(unsafe.Pointer(remoteCore)), uintptr(unsafe.Pointer(script)), uintptr(unsafe.Pointer(&scriptHandler)))
	runtime.KeepAlive(script)
	if int32(hr) < 0 && remotePending == pending {
		remotePending = nil
		pending.finish(ErrRemoteWindowUnavailable)
	}
}

func removeRemoteScript(id string) bool {
	if remoteCore == nil {
		return false
	}
	value, err := windows.UTF16PtrFromString(id)
	if err != nil {
		return false
	}
	hr, _, _ := remoteCore.vtbl.RemoveScriptToExecuteOnDocumentCreated.Call(uintptr(unsafe.Pointer(remoteCore)), uintptr(unsafe.Pointer(value)))
	runtime.KeepAlive(value)
	return int32(hr) >= 0
}

func remoteScriptAdded(_ *remoteScriptHandler, result uintptr, id *uint16) uintptr {
	pending := remotePending
	remotePending = nil
	scriptID := ""
	if id != nil {
		scriptID = windows.UTF16PtrToString(id)
	}
	if int32(result) < 0 || scriptID == "" {
		if scriptID != "" && !removeRemoteScript(scriptID) {
			remotePoisoned = true
		}
		if pending != nil {
			pending.finish(ErrRemoteWindowUnavailable)
		}
		return 0
	}
	if pending == nil || pending.closeRevision != remoteCloseRevision || !pending.phase.CompareAndSwap(0, 2) {
		if !removeRemoteScript(scriptID) {
			remotePoisoned = true
		}
		if pending != nil {
			pending.finish(ErrRemoteWindowUnavailable)
		}
		return 0
	}
	// Keep the previous healthy page and registration until the replacement is
	// ready. A failed or timed-out handoff cannot close an existing session.
	if remoteScriptID != "" && !removeRemoteScript(remoteScriptID) {
		remotePoisoned = true
		_ = removeRemoteScript(scriptID)
		pending.finish(ErrRemoteWindowUnavailable)
		return 0
	}
	if pending.closeRevision != remoteCloseRevision {
		if !removeRemoteScript(scriptID) {
			remotePoisoned = true
		}
		pending.finish(ErrRemoteWindowUnavailable)
		return 0
	}
	remoteScriptID, remoteGeneration = scriptID, pending.generation
	navigateRemoteDocument(pending.address)
	presentRemoteDocument()
	pending.finish(nil)
	return 0
}
