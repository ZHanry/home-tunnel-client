//go:build windows && remote_native_e2e

// This opt-in executable connects the real Go host service to its pinned native
// engine. It only approves the fixed test scopes from one isolated controller;
// input additionally requires the runner's dedicated target process ID.
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
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
	CAFile           string `json:"ca_file"`
	InputTargetPID   uint32 `json:"input_target_pid"`
	FileTestRoot     string `json:"file_test_root"`
	WebsiteClipboard bool   `json:"website_clipboard"`
}

type command struct {
	ID            int64  `json:"id"`
	Action        string `json:"action"`
	TargetID      string `json:"target_id"`
	ControllerID  string `json:"controller_id"`
	ControllerJKT string `json:"controller_jkt"`
	FixedPassword string `json:"fixed_password"`
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
	if err != nil || (origin.Scheme != "http" && origin.Scheme != "https") || origin.Hostname() != "127.0.0.1" || origin.Port() == "" || origin.User != nil || origin.RawQuery != "" || origin.Fragment != "" || origin.Path != "" || !filepath.IsAbs(initial.StorePath) {
		return errors.New("fixture must be isolated IPv4 loopback")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	engine, err := remoteengine.New(ctx, remoteengine.Options{ExecutablePath: initial.Worker, ExpectedSHA256: initial.SHA256, InputTargetProcessID: initial.InputTargetPID})
	if err != nil {
		stage := "worker_start_ipc"
		if strings.Contains(err.Error(), "version/ABI") {
			stage = "worker_start_version"
		} else if strings.Contains(err.Error(), "SHA256") || strings.Contains(err.Error(), "digest") {
			stage = "worker_start_integrity"
		}
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE", "stage": stage})
		return err
	}
	defer engine.Shutdown()
	caps, err := engine.Capabilities(ctx)
	if err != nil || !caps.Available || caps.Status != "ready" || len(caps.Displays) == 0 {
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE", "stage": "worker_capabilities"})
		return remotehost.ErrUnavailable
	}
	scopes := []string{"view"}
	if initial.InputTargetPID != 0 {
		scopes = append(scopes, "input.keyboard", "input.pointer", "input.text")
	}
	if initial.WebsiteClipboard {
		if initial.InputTargetPID == 0 {
			return errors.New("website clipboard acceptance requires an isolated input target")
		}
		scopes = append(scopes, "clipboard.read", "clipboard.write")
	}
	if initial.FileTestRoot != "" {
		if !filepath.IsAbs(initial.FileTestRoot) || filepath.Clean(initial.FileTestRoot) != filepath.Join(filepath.Dir(initial.StorePath), "file-fixture") {
			return errors.New("file fixture must be confined to this test directory")
		}
		info, check := os.Lstat(initial.FileTestRoot)
		if check != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("invalid file fixture")
		}
		scopes = append(scopes, "files.send", "files.receive")
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
	var tlsConfig *tls.Config
	var httpClient *http.Client
	if origin.Scheme == "https" {
		if initial.CAFile != filepath.Join(filepath.Dir(initial.StorePath), "ca.crt") {
			return errors.New("isolated test CA path is invalid")
		}
		certificate, readErr := os.ReadFile(initial.CAFile)
		if readErr != nil {
			return readErr
		}
		roots := x509.NewCertPool()
		if !roots.AppendCertsFromPEM(certificate) {
			return errors.New("isolated test CA is invalid")
		}
		tlsConfig = &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: roots}
		httpClient = &http.Client{Timeout: 12 * time.Second, Transport: &http.Transport{TLSClientConfig: tlsConfig}}
	}
	service, err := remotehost.New(remotehost.Config{
		Origin: initial.Origin, Store: store, Engine: engine, HTTPClient: httpClient, TLSConfig: tlsConfig, AllowInsecureLoopback: origin.Scheme == "http",
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
		if runError := service.Run(ctx); runError != nil && ctx.Err() == nil && !expectedWorkerCrash.Load() {
			code := "RD_NATIVE_HOST_SIGNAL_FAILED"
			stage := "signal"
			if strings.HasPrefix(runError.Error(), "server event ") {
				stage = strings.TrimPrefix(strings.SplitN(runError.Error(), ":", 2)[0], "server event ")
				for _, reason := range []string{"peer session unavailable", "peer session not started", "peer signature", "peer payload", "peer binding"} {
					if strings.Contains(runError.Error(), reason) {
						stage += "/" + strings.ReplaceAll(reason, " ", "_")
						break
					}
				}
			} else if strings.HasPrefix(runError.Error(), "engine event: ") {
				stage = "engine_event"
			}
			var apiError *remotehost.APIError
			switch {
			case errors.As(runError, &apiError):
				code = apiError.Code
			case errors.Is(runError, remotehost.ErrAuthorization):
				code = "RD_AUTHORIZATION_INVALID"
			case errors.Is(runError, remotehost.ErrUnavailable):
				code = "RD_BACKEND_UNAVAILABLE"
			case errors.Is(runError, remotehost.ErrLocalApproval):
				code = "RD_LOCAL_APPROVAL_REQUIRED"
			}
			emit(map[string]any{"event": "fatal", "code": code, "stage": stage, "session_active": service.State(ctx).ActiveSessionID != ""})
		}
	}()
	runDeadline := time.Now().Add(3 * time.Second)
	for !service.State(ctx).Running && time.Now().Before(runDeadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if !service.State(ctx).Running {
		return errors.New("isolated host signaling did not start")
	}
	state := service.State(ctx)
	client := httpClient
	if client == nil {
		client = &http.Client{Timeout: 12 * time.Second}
	}
	endpointRequest, err := http.NewRequestWithContext(ctx, http.MethodGet, initial.Origin+"/api/v1/rd/endpoints/"+url.PathEscape(state.EndpointID), nil)
	if err != nil {
		return err
	}
	endpointRequest.Header.Set("Authorization", "Bearer "+initial.AccountToken)
	endpointResponse, err := client.Do(endpointRequest)
	if err != nil {
		return err
	}
	defer endpointResponse.Body.Close()
	if endpointResponse.StatusCode != http.StatusOK {
		return errors.New("isolated host endpoint lookup failed")
	}
	var endpoint struct {
		JKT string `json:"jkt"`
	}
	if err = json.NewDecoder(io.LimitReader(endpointResponse.Body, 16384)).Decode(&endpoint); err != nil || len(endpoint.JKT) != 43 {
		return errors.New("isolated host endpoint fingerprint is invalid")
	}
	emit(map[string]any{"event": "host", "endpoint_id": state.EndpointID, "jkt": endpoint.JKT, "capabilities": caps})
	var controllerID, controllerJKT string
	for scanner.Scan() {
		var request command
		if json.Unmarshal(scanner.Bytes(), &request) != nil || request.ID < 1 {
			return errors.New("invalid command")
		}
		var operation error
		details := map[string]any{}
		switch request.Action {
		case "create_access_profile":
			var profile remotehost.AccessProfile
			profile, operation = service.AccessProfile(ctx, true)
			if operation == nil {
				details["profile"] = profile
			}
		case "set_fixed_password":
			var profile remotehost.AccessProfile
			profile, operation = service.SetFixedPassword(ctx, request.FixedPassword)
			if operation == nil {
				details["profile"] = profile
			}
		case "list_access_requests":
			var requests []remotehost.AccessRequest
			requests, operation = service.ListAccessRequests(ctx)
			if operation == nil {
				details["requests"] = requests
			}
		case "approve_access_request":
			operation = service.DecideAccessRequest(ctx, request.TargetID, true)
		case "create_invite":
			var invite remotehost.AssistInvite
			invite, operation = service.CreateAssistInvite(ctx)
			if operation == nil {
				details["invite"] = invite
			}
		case "revoke_invite":
			operation = service.RevokeAssistInvite(ctx, request.TargetID)
		case "file_state", "file_offer", "file_accept", "file_cancel":
			if initial.FileTestRoot == "" || controllerID == "" {
				operation = remotehost.ErrLocalApproval
				break
			}
			state := service.FileState()
			switch request.Action {
			case "file_state":
				details["files"] = state
			case "file_offer":
				operation = service.SelectFiles(ctx, state.SessionRef, func(context.Context) ([]string, error) {
					return []string{filepath.Join(initial.FileTestRoot, "native-empty.bin"), filepath.Join(initial.FileTestRoot, "native-multichunk.bin")}, nil
				})
			case "file_accept":
				operation = service.SelectDestination(ctx, state.SessionRef, request.TargetID, func(_ context.Context, name string) (string, error) {
					if name != "browser-empty.bin" && name != "browser-multichunk.bin" {
						return "", remotehost.ErrLocalApproval
					}
					return filepath.Join(initial.FileTestRoot, name), nil
				})
			case "file_cancel":
				operation = service.CancelFile(ctx, state.SessionRef, request.TargetID)
			}
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
			details["mode_matches"] = approval.Mode == "one_session"
			details["not_expired"] = approval.ExpiresAt.After(time.Now())
			if !exists || controllerID == "" || approval.ControllerEndpointID != controllerID || approval.ControllerThumbprint != controllerJKT || !sameScopes(approval.Permissions, scopes) || approval.Mode != "one_session" || !approval.ExpiresAt.After(time.Now()) {
				operation = remotehost.ErrLocalApproval
			} else if request.Action == "approve_pairing" && approval.Kind == "pairing" {
				operation = service.ApprovePairing(ctx, approval.ID, approval.Permissions, "one_session", time.Now().Add(3*time.Minute))
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
			code := "RD_NATIVE_E2E_ACTION_FAILED"
			var apiError *remotehost.APIError
			switch {
			case errors.As(operation, &apiError):
				code = apiError.Code
			case errors.Is(operation, remotehost.ErrLocalApproval):
				code = "RD_LOCAL_APPROVAL_REQUIRED"
			case errors.Is(operation, remotehost.ErrAuthorization):
				code = "RD_AUTHORIZATION_INVALID"
			case errors.Is(operation, remotehost.ErrUnavailable):
				code = "RD_BACKEND_UNAVAILABLE"
			}
			result["code"] = code
		}
		emit(result)
	}
	return scanner.Err()
}

func sameScopes(actual, expected []string) bool {
	if len(actual) != len(expected) {
		return false
	}
	remaining := make(map[string]bool, len(actual))
	for _, scope := range actual {
		if remaining[scope] {
			return false
		}
		remaining[scope] = true
	}
	for _, scope := range expected {
		if !remaining[scope] {
			return false
		}
		delete(remaining, scope)
	}
	return len(remaining) == 0
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
