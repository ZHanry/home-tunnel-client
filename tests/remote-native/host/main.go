//go:build windows && remote_native_e2e

// This opt-in executable connects the real Go host service to its pinned native
// engine. It only approves the fixed test scopes from one isolated controller;
// input additionally requires the runner's dedicated target process ID.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"golang.org/x/sys/windows"
)

type configuration struct {
	Origin           string `json:"origin"`
	AccountToken     string `json:"account_token"`
	DeviceID         string `json:"device_id"`
	ServerInstanceID string `json:"server_instance_id"`
	ActiveKid        string `json:"active_kid"`
	StorePath        string `json:"store_path"`
	Worker           string `json:"worker"`
	SHA256           string `json:"sha256"`
	InputTargetPID   uint32 `json:"input_target_pid"`
}

type command struct {
	ID            int64  `json:"id"`
	Action        string `json:"action"`
	TargetID      string `json:"target_id"`
	ControllerID  string `json:"controller_id"`
	ControllerJKT string `json:"controller_jkt"`
}

var outputMu sync.Mutex

func emit(value any) {
	outputMu.Lock()
	defer outputMu.Unlock()
	raw, _ := json.Marshal(value)
	fmt.Printf("HT_NATIVE %s\n", raw)
}

func main() {
	if err := run(); err != nil {
		// Arbitrary errors may contain protocol content; expose only an opaque code.
		emit(map[string]any{"event": "fatal", "code": "RD_NATIVE_HOST_FAILED"})
		os.Exit(1)
	}
}

func run() error {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 65536)
	if !scanner.Scan() {
		return errors.New("missing private configuration")
	}
	var initial configuration
	if err := json.Unmarshal(scanner.Bytes(), &initial); err != nil {
		return err
	}
	origin, err := url.Parse(initial.Origin)
	if err != nil || origin.Scheme != "http" || origin.Hostname() != "127.0.0.1" || origin.Port() == "" || origin.User != nil || origin.RawQuery != "" || origin.Fragment != "" || origin.Path != "" || !filepath.IsAbs(initial.StorePath) {
		return errors.New("fixture must be isolated IPv4 loopback")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	engine, err := remoteengine.New(ctx, remoteengine.Options{ExecutablePath: initial.Worker, ExpectedSHA256: initial.SHA256, InputTargetProcessID: initial.InputTargetPID})
	if err != nil {
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE"})
		return err
	}
	defer engine.Shutdown()
	caps, err := engine.Capabilities(ctx)
	if err != nil || !caps.Available || caps.Status != "ready" || len(caps.Displays) == 0 {
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE"})
		return remotehost.ErrUnavailable
	}
	scopes := []string{"view"}
	if initial.InputTargetPID != 0 {
		scopes = append(scopes, "input.keyboard", "input.pointer", "input.text")
	}
	for _, scope := range scopes {
		found := false
		for _, supported := range caps.Permissions {
			found = found || supported == scope
		}
		if !found {
			emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE"})
			return remotehost.ErrUnavailable
		}
	}
	store, err := remotehost.OpenStore(initial.StorePath)
	if err != nil {
		return err
	}
	service, err := remotehost.New(remotehost.Config{
		Origin: initial.Origin, Store: store, Engine: engine, AllowInsecureLoopback: true,
		AccountToken: func(context.Context) (string, error) { return initial.AccountToken, nil },
		InitialTrust: func(_ context.Context, actual string, keys remotehost.Keyset) error {
			if actual != initial.Origin || keys.ServerInstanceID != initial.ServerInstanceID || keys.ActiveKid != initial.ActiveKid {
				return remotehost.ErrAuthorization
			}
			return nil
		},
	})
	if err != nil {
		return err
	}
	defer func() {
		stop, release := context.WithTimeout(context.Background(), 5*time.Second)
		defer release()
		_ = service.SetEnabled(stop, false)
	}()
	if err = service.Enroll(ctx, remotehost.Enrollment{LinkedDeviceID: initial.DeviceID, Name: "Native acceptance host", Platform: "windows"}); err != nil {
		return err
	}
	if err = service.SetEnabled(ctx, true); err != nil {
		return err
	}
	var approvalMu sync.Mutex
	var expectedWorkerCrash atomic.Bool
	approvals := map[string]remotehost.ApprovalEvent{}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case event := <-service.Approvals():
				approvalMu.Lock()
				approvals[event.ID] = event
				approvalMu.Unlock()
				emit(map[string]any{"event": "approval", "approval": event})
			}
		}
	}()
	go func() {
		if service.Run(ctx) != nil && ctx.Err() == nil && !expectedWorkerCrash.Load() {
			emit(map[string]any{"event": "fatal", "code": "RD_NATIVE_HOST_SIGNAL_FAILED"})
		}
	}()
	state := service.State(ctx)
	emit(map[string]any{"event": "host", "endpoint_id": state.EndpointID, "capabilities": caps})
	var controllerID, controllerJKT string
	for scanner.Scan() {
		var request command
		if json.Unmarshal(scanner.Bytes(), &request) != nil || request.ID < 1 {
			return errors.New("invalid command")
		}
		var operation error
		details := map[string]any{}
		switch request.Action {
		case "state":
			details["session_idle"] = service.State(ctx).ActiveSessionID == ""
		case "input_target_point":
			if initial.InputTargetPID == 0 || !targetFocused(initial.InputTargetPID) {
				operation = remotehost.ErrLocalApproval
			} else {
				var point map[string]any
				point, operation = targetPoint(initial.InputTargetPID, caps.Displays[0])
				if operation == nil {
					details["point"] = point
				}
			}
		case "diagnostics":
			var diagnostic map[string]json.RawMessage
			diagnostic, operation = engine.Diagnostics(ctx)
			if operation == nil {
				details["native"] = diagnostic
			}
		case "crash_worker":
			if initial.InputTargetPID == 0 || controllerID == "" || engine.ProcessID() <= 0 {
				operation = remotehost.ErrLocalApproval
			} else {
				// The adapter owns this exact process. Never find/kill by filename:
				// its independent release guard deliberately uses the same image.
				var worker *os.Process
				worker, operation = os.FindProcess(engine.ProcessID())
				if operation == nil {
					expectedWorkerCrash.Store(true)
					operation = worker.Kill()
					_ = worker.Release()
				}
			}
		case "input_focus", "focus_input_target":
			if initial.InputTargetPID == 0 {
				operation = remotehost.ErrLocalApproval
			} else {
				if request.Action == "focus_input_target" {
					found, activated := focusTarget(initial.InputTargetPID, caps.Displays[0])
					details["target_window_found"] = found
					details["target_window_activated"] = activated
				}
				details["foreground_matches_target"] = targetFocused(initial.InputTargetPID)
				details["window_diagnostics"] = targetWindowDiagnostics(initial.InputTargetPID)
			}
		case "bind_controller":
			if controllerID != "" || len(request.ControllerID) != 36 || len(request.ControllerJKT) != 43 {
				operation = remotehost.ErrLocalApproval
			} else {
				controllerID, controllerJKT = request.ControllerID, request.ControllerJKT
			}
		case "approve_pairing", "approve_session":
			approvalMu.Lock()
			approval, exists := approvals[request.TargetID]
			approvalMu.Unlock()
			if !exists || controllerID == "" || approval.ControllerEndpointID != controllerID || approval.ControllerThumbprint != controllerJKT || !sameScopes(approval.Permissions, scopes) || approval.Mode != "one_session" || !approval.ExpiresAt.After(time.Now()) {
				operation = remotehost.ErrLocalApproval
			} else if request.Action == "approve_pairing" && approval.Kind == "pairing" {
				operation = service.ApprovePairing(ctx, approval.ID, scopes, "one_session", time.Now().Add(3*time.Minute))
			} else if request.Action == "approve_session" && approval.Kind == "session" {
				operation = service.ApproveSessionExpected(ctx, approval.ID, approval.ConnectionEpoch, approval.StateVersion)
			} else {
				operation = remotehost.ErrLocalApproval
			}
		case "shutdown":
			emit(map[string]any{"id": request.ID, "ok": true})
			return nil
		default:
			operation = errors.New("unknown action")
		}
		result := map[string]any{"id": request.ID, "ok": operation == nil}
		for key, value := range details {
			result[key] = value
		}
		if operation != nil {
			result["code"] = "RD_NATIVE_E2E_ACTION_FAILED"
		}
		emit(result)
	}
	return scanner.Err()
}

func sameScopes(actual, expected []string) bool {
	if len(actual) != len(expected) {
		return false
	}
	for index, scope := range expected {
		if actual[index] != scope {
			return false
		}
	}
	return true
}

var user32 = windows.NewLazySystemDLL("user32.dll")

func windowProcess(window uintptr) uint32 {
	var process uint32
	_, _, _ = user32.NewProc("GetWindowThreadProcessId").Call(window, uintptr(unsafe.Pointer(&process)))
	return process
}

func targetFocused(process uint32) bool {
	window, _, _ := user32.NewProc("GetForegroundWindow").Call()
	return window != 0 && windowProcess(window) == process
}

func focusTarget(process uint32, display remotehost.Display) (bool, bool) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	old, _, _ := user32.NewProc("SetThreadDpiAwarenessContext").Call(^uintptr(3))
	if old != 0 {
		defer user32.NewProc("SetThreadDpiAwarenessContext").Call(old)
	}
	displayX, displayY, err := displayOrigin(display)
	if err != nil {
		return false, false
	}
	var target uintptr
	callback := syscall.NewCallback(func(window, _ uintptr) uintptr {
		visible, _, _ := user32.NewProc("IsWindowVisible").Call(window)
		var title [256]uint16
		_, _, _ = user32.NewProc("GetWindowTextW").Call(window, uintptr(unsafe.Pointer(&title[0])), uintptr(len(title)))
		if visible != 0 && windowProcess(window) == process && strings.HasPrefix(windows.UTF16ToString(title[:]), "Home Tunnel isolated input test target") {
			target = window
			return 0
		}
		return 1
	})
	_, _, _ = user32.NewProc("EnumWindows").Call(callback, 0)
	if target != 0 && windowProcess(target) == process {
		// Background test helpers may lack an input queue or foreground rights.
		// Temporarily associate this thread with the existing queues, then detach
		// on every path. No global keyboard/mouse event is synthesized here.
		var message [8]uintptr
		_, _, _ = user32.NewProc("PeekMessageW").Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0, 0)
		current, _, _ := windows.NewLazySystemDLL("kernel32.dll").NewProc("GetCurrentThreadId").Call()
		foreground, _, _ := user32.NewProc("GetForegroundWindow").Call()
		foregroundThread, _, _ := user32.NewProc("GetWindowThreadProcessId").Call(foreground, 0)
		targetThread, _, _ := user32.NewProc("GetWindowThreadProcessId").Call(target, 0)
		attached := []uintptr{}
		for _, thread := range []uintptr{foregroundThread, targetThread} {
			if thread == 0 || thread == current || (len(attached) != 0 && attached[0] == thread) {
				continue
			}
			ok, _, _ := user32.NewProc("AttachThreadInput").Call(current, thread, 1)
			if ok != 0 {
				attached = append(attached, thread)
			}
		}
		defer func() {
			for _, thread := range attached {
				_, _, _ = user32.NewProc("AttachThreadInput").Call(current, thread, 0)
			}
		}()
		_, _, _ = user32.NewProc("ShowWindowAsync").Call(target, 9)
		// Keep the isolated target visible above this test's controller window;
		// its process is disposed at teardown, so no user window is modified.
		_, _, _ = user32.NewProc("SetWindowPos").Call(target, ^uintptr(0), uintptr(displayX+40), uintptr(displayY+40), 0, 0, 0x41)
		_, _, _ = user32.NewProc("BringWindowToTop").Call(target)
		_, _, _ = user32.NewProc("SetForegroundWindow").Call(target)
		_, _, _ = user32.NewProc("SetFocus").Call(target)
		time.Sleep(100 * time.Millisecond)
		return true, targetFocused(process)
	}
	return false, false
}

func targetPoint(process uint32, display remotehost.Display) (map[string]any, error) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	old, _, _ := user32.NewProc("SetThreadDpiAwarenessContext").Call(^uintptr(3))
	if old != 0 {
		defer user32.NewProc("SetThreadDpiAwarenessContext").Call(old)
	}
	displayX, displayY, err := displayOrigin(display)
	if err != nil {
		return nil, err
	}
	window, _, _ := user32.NewProc("GetForegroundWindow").Call()
	if window == 0 || windowProcess(window) != process {
		return nil, remotehost.ErrLocalApproval
	}
	var rect struct{ Left, Top, Right, Bottom int32 }
	var origin struct{ X, Y int32 }
	valid, _, _ := user32.NewProc("GetClientRect").Call(window, uintptr(unsafe.Pointer(&rect)))
	if valid == 0 {
		return nil, remotehost.ErrLocalApproval
	}
	valid, _, _ = user32.NewProc("ClientToScreen").Call(window, uintptr(unsafe.Pointer(&origin)))
	if valid == 0 {
		return nil, remotehost.ErrLocalApproval
	}
	x, y := origin.X+(rect.Right-rect.Left)/2, origin.Y+(rect.Bottom-rect.Top)/2
	localX, localY := x-displayX, y-displayY
	if localX < 0 || localY < 0 || int(localX) >= display.Width || int(localY) >= display.Height {
		return nil, remotehost.ErrLocalApproval
	}
	hit, _, _ := user32.NewProc("WindowFromPoint").Call(uintptr(uint64(uint32(x)) | uint64(uint32(y))<<32))
	root, _, _ := user32.NewProc("GetAncestor").Call(window, 2)
	hitRoot, _, _ := user32.NewProc("GetAncestor").Call(hit, 2)
	var cloaked uint32
	_, _, _ = windows.NewLazySystemDLL("dwmapi.dll").NewProc("DwmGetWindowAttribute").Call(window, 14, uintptr(unsafe.Pointer(&cloaked)), unsafe.Sizeof(cloaked))
	var hitClass [256]uint16
	_, _, _ = user32.NewProc("GetClassNameW").Call(hit, uintptr(unsafe.Pointer(&hitClass[0])), uintptr(len(hitClass)))
	var bounds struct{ Left, Top, Right, Bottom int32 }
	_, _, _ = user32.NewProc("GetWindowRect").Call(window, uintptr(unsafe.Pointer(&bounds)))
	style, _, _ := user32.NewProc("GetWindowLongPtrW").Call(window, ^uintptr(19))
	hitOwner, _, _ := user32.NewProc("GetWindow").Call(hit, 4)
	var ownerClass [256]uint16
	_, _, _ = user32.NewProc("GetClassNameW").Call(hitOwner, uintptr(unsafe.Pointer(&ownerClass[0])), uintptr(len(ownerClass)))
	return map[string]any{"x": localX, "y": localY, "width": display.Width, "height": display.Height,
		"display_origin_x": displayX, "display_origin_y": displayY,
		"hit_matches_target_root": hit != 0 && root == hitRoot, "hit_matches_target_pid": hit != 0 && windowProcess(hit) == process,
		"hit_process_id": windowProcess(hit), "hit_owner_class": windows.UTF16ToString(ownerClass[:]), "hit_owner_process_id": windowProcess(hitOwner),
		"target_cloaked": cloaked, "hit_class": windows.UTF16ToString(hitClass[:]), "target_extended_style": style,
		"window_left": bounds.Left, "window_top": bounds.Top, "window_right": bounds.Right, "window_bottom": bounds.Bottom,
		"client_left": origin.X, "client_top": origin.Y, "client_width": rect.Right - rect.Left, "client_height": rect.Bottom - rect.Top}, nil
}

func displayOrigin(display remotehost.Display) (int32, int32, error) {
	// WebRTC's Windows screen source ID is the EnumDisplayDevices device index.
	// Resolve that same device so wire coordinates remain display-local even
	// when the selected monitor has a negative/nonzero desktop origin.
	index, err := strconv.ParseUint(display.ID, 10, 32)
	if err != nil {
		return 0, 0, remotehost.ErrLocalApproval
	}
	var device struct {
		Size        uint32
		Name        [32]uint16
		Description [128]uint16
		Flags       uint32
		ID, Key     [128]uint16
	}
	device.Size = uint32(unsafe.Sizeof(device))
	valid, _, _ := user32.NewProc("EnumDisplayDevicesW").Call(0, uintptr(index), uintptr(unsafe.Pointer(&device)), 0)
	if valid == 0 {
		return 0, 0, remotehost.ErrLocalApproval
	}
	var mode struct {
		DeviceName                                                                                     [32]uint16
		SpecVersion, DriverVersion, Size, DriverExtra                                                  uint16
		Fields                                                                                         uint32
		X, Y                                                                                           int32
		Orientation, FixedOutput                                                                       uint32
		Color, Duplex, YResolution, TTOption, Collate                                                  int16
		FormName                                                                                       [32]uint16
		LogPixels                                                                                      uint16
		BitsPerPixel, Width, Height, Flags, Frequency                                                  uint32
		ICMMethod, ICMIntent, MediaType, DitherType, Reserved1, Reserved2, PanningWidth, PanningHeight uint32
	}
	mode.Size = uint16(unsafe.Sizeof(mode))
	valid, _, _ = user32.NewProc("EnumDisplaySettingsExW").Call(uintptr(unsafe.Pointer(&device.Name[0])), ^uintptr(0), uintptr(unsafe.Pointer(&mode)), 0)
	if valid == 0 || int(mode.Width) != display.Width || int(mode.Height) != display.Height {
		return 0, 0, remotehost.ErrLocalApproval
	}
	return mode.X, mode.Y, nil
}

func targetWindowDiagnostics(process uint32) map[string]any {
	window, _, _ := user32.NewProc("GetForegroundWindow").Call()
	result := map[string]any{"foreground_matches_target": window != 0 && windowProcess(window) == process}
	if window == 0 || windowProcess(window) != process {
		return result
	}
	thread, _, _ := user32.NewProc("GetWindowThreadProcessId").Call(window, 0)
	var info struct {
		Size, Flags                                        uint32
		Active, Focus, Capture, MenuOwner, MoveSize, Caret uintptr
		CaretRect                                          struct{ Left, Top, Right, Bottom int32 }
	}
	info.Size = uint32(unsafe.Sizeof(info))
	valid, _, _ := user32.NewProc("GetGUIThreadInfo").Call(thread, uintptr(unsafe.Pointer(&info)))
	result["gui_thread_info"] = valid != 0
	result["focus_matches_target_pid"] = info.Focus != 0 && windowProcess(info.Focus) == process
	result["focus_is_foreground_frame"] = info.Focus == window
	if info.Focus != 0 && windowProcess(info.Focus) == process {
		var class [256]uint16
		_, _, _ = user32.NewProc("GetClassNameW").Call(info.Focus, uintptr(unsafe.Pointer(&class[0])), uintptr(len(class)))
		result["target_focus_class"] = windows.UTF16ToString(class[:])
	}
	return result
}
