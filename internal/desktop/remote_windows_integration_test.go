//go:build windows

package desktop

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
	"unsafe"

	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"
)

// This opt-in source integration runs real WebView2 and real secondary HWNDs.
// Its about:blank scripts and loopback popup data are test fixtures, not live
// account authorization, media-session acceptance or final-package evidence.
func TestWindowsWebView2Integration(t *testing.T) {
	if os.Getenv("HOMETUNNEL_WEBVIEW2_INTEGRATION") != "1" {
		t.Skip("set HOMETUNNEL_WEBVIEW2_INTEGRATION=1 on an interactive Windows runner")
	}
	if os.Getenv("HOMETUNNEL_WEBVIEW2_CHILD") != "1" {
		// The parent owns the temporary profile and removes it only after the
		// child process (and its WebView2 file handles) has exited.
		command := exec.Command(os.Args[0], "-test.run=^TestWindowsWebView2Integration$", "-test.v", "-test.timeout=4m")
		profile := t.TempDir()
		t.Cleanup(func() {
			// WebView2's browser process may take a moment to notice its host exit.
			deadline := time.Now().Add(5 * time.Second)
			for time.Now().Before(deadline) {
				if os.RemoveAll(profile) == nil {
					return
				}
				time.Sleep(50 * time.Millisecond)
			}
		})
		command.Env = append(os.Environ(), "HOMETUNNEL_WEBVIEW2_CHILD=1", "APPDATA="+profile)
		output, err := command.CombinedOutput()
		t.Log(string(output))
		if err != nil {
			t.Fatalf("real WebView2 integration process failed: %v", err)
		}
		return
	}
	if unsafe.Sizeof(remoteScriptHandlerVtbl{}) != 4*unsafe.Sizeof(uintptr(0)) {
		t.Fatal("unexpected completion-handler COM ABI")
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	ole32 := windows.NewLazySystemDLL("ole32.dll")
	hr, _, _ := ole32.NewProc("CoInitializeEx").Call(0, 2) // COINIT_APARTMENTTHREADED
	if int32(hr) < 0 {
		t.Fatalf("COM STA initialization failed: %#x", hr)
	}
	defer ole32.NewProc("CoUninitialize").Call()
	if err := createNativeWindow("about:blank"); err != nil {
		t.Fatal(err)
	}
	closed := make(chan uint64, 64)
	host := &Host{}
	host.SetRemoteClosed(func(generation uint64) { closed <- generation })
	setEmergencyHost(host)
	defer setEmergencyHost(nil)
	result := make(chan error, 1)
	go func() {
		err := exerciseRemoteRenderer(closed)
		if err == nil {
			err = exerciseApprovalPopup()
		}
		result <- err
		quitNativeWindow()
	}()
	runNativeWindow()
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	t.Log("Real WebView2: 30 remote open/WM_CLOSE cycles, bounded HWND/core, removable scripts, cancelled registration, close generations, live main loop, and popup hidden/rendered/opaque/reopen checks passed")
}

func integrationDispatch(work func() error) error {
	result := make(chan error, 1)
	nativeView.Dispatch(func() { result <- work() })
	select {
	case err := <-result:
		return err
	case <-time.After(20 * time.Second):
		return fmt.Errorf("main UI thread did not process a dispatch")
	}
}

func integrationUntil(label string, predicate func() bool) error {
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		ready := false
		if err := integrationDispatch(func() error { ready = predicate(); return nil }); err != nil {
			return err
		}
		if ready {
			return nil
		}
		time.Sleep(20 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for %s", label)
}

type integrationScriptMessage struct {
	Cycle   int   `json:"cycle"`
	Scripts []int `json:"scripts"`
}

func integrationReadScript(messages <-chan string, cycle int) error {
	deadline := time.NewTimer(15 * time.Second)
	defer deadline.Stop()
	for {
		select {
		case text := <-messages:
			var message integrationScriptMessage
			if err := json.Unmarshal([]byte(text), &message); err != nil || message.Cycle != cycle {
				continue
			}
			if len(message.Scripts) != 1 || message.Scripts[0] != cycle {
				return fmt.Errorf("cycle %d executed stale init scripts: %v", cycle, message.Scripts)
			}
			return nil
		case <-deadline.C:
			return fmt.Errorf("cycle %d did not execute its actual WebView2 initialization script", cycle)
		}
	}
}

func integrationStageRemote(cycle int) (*remoteScriptRegistration, error) {
	pending := &remoteScriptRegistration{
		generation: uint64(cycle), address: "about:blank", result: make(chan error, 1),
		script: fmt.Sprintf(`window.__htFixtureScripts=(window.__htFixtureScripts||[]).concat(%d);setTimeout(()=>chrome.webview.postMessage(JSON.stringify({cycle:%d,scripts:window.__htFixtureScripts})),0);`, cycle, cycle),
	}
	if err := integrationDispatch(func() error {
		if remotePending != nil || remotePoisoned {
			return fmt.Errorf("renderer was not reusable before cycle %d", cycle)
		}
		pending.closeRevision = remoteCloseRevision
		remotePending = pending
		registerRemoteScript()
		return nil
	}); err != nil {
		return nil, err
	}
	return pending, nil
}

func integrationAwaitOpen(pending *remoteScriptRegistration) error {
	select {
	case err := <-pending.result:
		return err
	case <-time.After(20 * time.Second):
		return fmt.Errorf("AddScript registration did not complete")
	}
}

func exerciseRemoteRenderer(closed <-chan uint64) error {
	messages := make(chan string, 256)
	if err := integrationDispatch(func() error {
		if !ensureRemoteWindow() {
			return ErrRemoteWindowUnavailable
		}
		remoteView.MessageCallback = func(message string) { messages <- message }
		remoteView.Navigate("about:blank")
		return nil
	}); err != nil {
		return err
	}
	if err := integrationUntil("remote core interface", func() bool { return remoteCore != nil }); err != nil {
		return err
	}
	var hwnd uintptr
	var core *remoteCoreWebView2
	if err := integrationDispatch(func() error { hwnd, core = remoteHWND, remoteCore; return nil }); err != nil {
		return err
	}
	postMessage := user32.NewProc("PostMessageW")
	closeCycle := func(cycle int) error {
		postMessage.Call(hwnd, wmClose, 0, 0)
		select {
		case generation := <-closed:
			if generation != uint64(cycle) {
				return fmt.Errorf("close generation = %d, expected %d", generation, cycle)
			}
		case <-time.After(15 * time.Second):
			return fmt.Errorf("actual WM_CLOSE did not notify the host")
		}
		return integrationDispatch(func() error {
			visible, _, _ := procIsWindowVisible.Call(hwnd)
			if visible != 0 || remoteGeneration != 0 || remoteScriptID != "" || remoteHWND != hwnd || remoteCore != core {
				return fmt.Errorf("close failed to hide, remove script, clear generation, or retain one renderer")
			}
			return nil
		})
	}
	for cycle := 1; cycle <= 30; cycle++ {
		pending, err := integrationStageRemote(cycle)
		if err != nil {
			return err
		}
		if err := integrationAwaitOpen(pending); err != nil {
			return err
		}
		if err := integrationReadScript(messages, cycle); err != nil {
			return err
		}
		if err := integrationDispatch(func() error {
			visible, _, _ := procIsWindowVisible.Call(hwnd)
			if visible == 0 || remoteHWND != hwnd || remoteCore != core || remoteScriptID == "" || remoteGeneration != uint64(cycle) {
				return fmt.Errorf("cycle %d did not reuse its one real visible HWND/core", cycle)
			}
			return nil
		}); err != nil {
			return err
		}
		if err := closeCycle(cycle); err != nil {
			return err
		}
	}
	// Keep a healthy document open while another asynchronous registration is
	// cancelled, then prove that only the old script survives a real reload.
	live, err := integrationStageRemote(100)
	if err != nil {
		return err
	}
	if err := integrationAwaitOpen(live); err != nil {
		return err
	}
	if err := integrationReadScript(messages, 100); err != nil {
		return err
	}
	if err := integrationDispatch(func() error {
		pending := &remoteScriptRegistration{generation: 101, closeRevision: remoteCloseRevision, address: "about:blank", script: `window.__htFixtureScripts=(window.__htFixtureScripts||[]).concat(101);`, result: make(chan error, 1)}
		remotePending = pending
		registerRemoteScript()
		if remotePending != pending {
			return fmt.Errorf("expected asynchronous AddScript registration before cancellation")
		}
		cancelRemoteRegistration(pending)
		if remoteGeneration != 100 || remoteScriptID == "" {
			return fmt.Errorf("cancelling pending registration damaged the healthy window")
		}
		return nil
	}); err != nil {
		return err
	}
	if err := integrationUntil("cancelled registration cleanup", func() bool { return remotePending == nil }); err != nil {
		return err
	}
	if err := integrationDispatch(func() error {
		for len(messages) > 0 {
			<-messages
		}
		remoteView.Navigate("about:blank")
		return nil
	}); err != nil {
		return err
	}
	if err := integrationReadScript(messages, 100); err != nil {
		return err
	}
	return closeCycle(100)
}

func exerciseApprovalPopup() error {
	var mu sync.Mutex
	state := map[string]any{"access_requests": []any{}, "pending": []any{}, "grants": []any{}}
	assets := http.FileServer(http.Dir(filepath.Join("..", "gui", "web")))
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/local/remote/state" {
			mu.Lock()
			defer mu.Unlock()
			writer.Header().Set("content-type", "application/json")
			_ = json.NewEncoder(writer).Encode(state)
			return
		}
		if strings.HasPrefix(request.URL.Path, "/local/") {
			writer.Header().Set("content-type", "application/json")
			_, _ = writer.Write([]byte(`{"ok":true}`))
			return
		}
		assets.ServeHTTP(writer, request)
	}))
	defer server.Close()
	address := server.URL + "/popup.html#session=source-integration-fixture"
	if !showNativeApprovalPopup(address, "request", false) {
		return fmt.Errorf("actual popup did not initialize")
	}
	if err := integrationUntil("popup JavaScript readiness", func() bool { return popupLoaded }); err != nil {
		return err
	}
	if err := integrationDispatch(func() error {
		visible, _, _ := procIsWindowVisible.Call(popupHWND)
		if visible != 0 {
			return fmt.Errorf("empty popup appeared before populated content")
		}
		return nil
	}); err != nil {
		return err
	}
	mu.Lock()
	state["access_requests"] = []any{map[string]any{"id": "fixture-request", "requester_name": "QA controller", "controller_endpoint_id": "fixture-peer", "expires_at": time.Now().Add(time.Minute).Format(time.RFC3339)}}
	mu.Unlock()
	if !showNativeApprovalPopup(address, "request", false) {
		return fmt.Errorf("populated popup could not be requested")
	}
	if err := integrationUntil("real popup visibility after rendered-content handshake", func() bool { visible, _, _ := procIsWindowVisible.Call(popupHWND); return visible != 0 }); err != nil {
		return err
	}
	messages := make(chan string, 16)
	if err := integrationDispatch(func() error {
		original := popupView.MessageCallback
		popupView.MessageCallback = func(message string) {
			original(message)
			if strings.HasPrefix(message, "fixture:") {
				messages <- strings.TrimPrefix(message, "fixture:")
			}
		}
		getStyle := user32.NewProc("GetWindowLongPtrW")
		exStyle, _, _ := getStyle.Call(popupHWND, ^uintptr(19)) // GWL_EXSTYLE = -20
		if exStyle&(0x00080000|0x00000020) != 0 {               // WS_EX_LAYERED | WS_EX_TRANSPARENT
			return fmt.Errorf("popup host unexpectedly uses transparent/layered window styles")
		}
		controller := popupView.GetController().GetICoreWebView2Controller2()
		if controller == nil {
			return fmt.Errorf("WebView2 controller2 background interface unavailable")
		}
		abi := (*integrationController2)(unsafe.Pointer(controller))
		var color edge.COREWEBVIEW2_COLOR
		hr, _, _ := abi.vtbl.GetDefaultBackgroundColor.Call(uintptr(unsafe.Pointer(controller)), uintptr(unsafe.Pointer(&color)))
		abi.vtbl.Release.Call(uintptr(unsafe.Pointer(controller)))
		if int32(hr) < 0 || color.A != 255 {
			return fmt.Errorf("popup WebView2 backing color is not opaque: alpha=%d HRESULT=%#x", color.A, hr)
		}
		popupView.Eval(`chrome.webview.postMessage("fixture:"+JSON.stringify({who:document.getElementById("request-who").textContent,requestHidden:document.getElementById("request").hidden,colors:[document.documentElement,document.body,document.getElementById("request")].map(el=>getComputedStyle(el).backgroundColor),opacity:getComputedStyle(document.getElementById("request")).opacity}));`)
		return nil
	}); err != nil {
		return err
	}
	select {
	case text := <-messages:
		var result struct {
			Who     string   `json:"who"`
			Hidden  bool     `json:"requestHidden"`
			Colors  []string `json:"colors"`
			Opacity string   `json:"opacity"`
		}
		if err := json.Unmarshal([]byte(text), &result); err != nil || result.Hidden || result.Who != "QA controller" || result.Opacity != "1" || len(result.Colors) != 3 {
			return fmt.Errorf("popup did not render the genuine request: %s", text)
		}
		for _, color := range result.Colors {
			if !strings.HasPrefix(color, "rgb(") {
				return fmt.Errorf("popup layer is not opaque: %s", color)
			}
		}
	case <-time.After(10 * time.Second):
		return fmt.Errorf("popup DOM verification did not respond")
	}
	for cycle := 0; cycle < 3; cycle++ {
		user32.NewProc("PostMessageW").Call(popupHWND, wmClose, 0, 0)
		if err := integrationUntil("popup dismissal", func() bool {
			visible, _, _ := procIsWindowVisible.Call(popupHWND)
			return visible == 0 && popupMode == ""
		}); err != nil {
			return err
		}
		if !showNativeApprovalPopup(address, "request", false) {
			return fmt.Errorf("popup could not reopen")
		}
		if err := integrationUntil("popup reopening", func() bool { visible, _, _ := procIsWindowVisible.Call(popupHWND); return visible != 0 }); err != nil {
			return err
		}
	}
	hideNativeApprovalPopup()
	return integrationUntil("final popup hide", func() bool { visible, _, _ := procIsWindowVisible.Call(popupHWND); return visible == 0 })
}

// Public controller2 ABI, verified against the pinned edge dependency and
// Microsoft.Web.WebView2 1.0.4129.50 WebView2.h. GetDefaultBackgroundColor writes
// a COREWEBVIEW2_COLOR value (not a pointer to one).
type integrationController2Vtbl struct {
	QueryInterface, AddRef, Release                                                    edge.ComProc
	GetIsVisible, PutIsVisible, GetBounds, PutBounds                                   edge.ComProc
	GetZoomFactor, PutZoomFactor, AddZoomFactorChanged, RemoveZoomFactorChanged        edge.ComProc
	SetBoundsAndZoomFactor, MoveFocus, AddMoveFocusRequested, RemoveMoveFocusRequested edge.ComProc
	AddGotFocus, RemoveGotFocus, AddLostFocus, RemoveLostFocus                         edge.ComProc
	AddAcceleratorKeyPressed, RemoveAcceleratorKeyPressed                              edge.ComProc
	GetParentWindow, PutParentWindow, NotifyParentWindowPositionChanged                edge.ComProc
	Close, GetCoreWebView2, GetDefaultBackgroundColor, PutDefaultBackgroundColor       edge.ComProc
}
type integrationController2 struct{ vtbl *integrationController2Vtbl }
