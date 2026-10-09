package gui

import (
	"encoding/json"
	"fmt"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestRemoteWindowURLBindsServerAndDevice(t *testing.T) {
	const deviceID = "12345678-1234-1234-1234-123456789abc"
	address, err := remoteWindowURL("https://console.example.com/prefix?unused=1", deviceID)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := url.Parse(address)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Scheme != "https" || parsed.Host != "console.example.com" || parsed.Path != "/admin" || parsed.Fragment != "remote" || parsed.Query().Get("remoteDevice") != deviceID || parsed.Query().Has("unused") {
		t.Fatalf("unexpected remote URL: %s", address)
	}
	assistance, err := remoteAssistanceURL("https://console.example.com", "")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err = url.Parse(assistance)
	if err != nil || parsed.Query().Get("remoteAssist") != "1" || parsed.Query().Has("remoteDevice") || parsed.Fragment != "remote" {
		t.Fatalf("unexpected assistance URL: %s", assistance)
	}
	assistance, err = remoteAssistanceURL("https://console.example.com", "123456789")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err = url.Parse(assistance)
	if err != nil || parsed.Query().Get("remoteAssist") != "1" || parsed.Query().Get("remoteAccessId") != "123456789" {
		t.Fatalf("unexpected prefilled assistance URL: %s", assistance)
	}
	for _, base := range []string{"javascript:alert(1)", "https://user:password@console.example.com", "//console.example.com"} {
		if _, err := remoteWindowURL(base, deviceID); err == nil {
			t.Fatalf("accepted unsafe base: %q", base)
		}
	}
}

func TestRemoteWindowRequiresValidDeviceAndLogin(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "missing.json")})
	server.SetOpenRemote(func(model.RemoteWindowLaunch) error { t.Fatal("remote window must not open"); return nil })
	for _, test := range []struct {
		body   string
		status int
	}{
		{`{"device_id":"https://attacker.example"}`, http.StatusBadRequest},
		{`{"device_id":"12345678-1234-1234-1234-123456789abc","assist":true}`, http.StatusBadRequest},
		{`{"device_id":"12345678-1234-1234-1234-123456789abc"}`, http.StatusUnauthorized},
		{`{"assist":true}`, http.StatusUnauthorized},
		{`{"assist":true,"access_id":"123456789"}`, http.StatusUnauthorized},
		{`{"assist":true,"access_id":"12345678x"}`, http.StatusBadRequest},
		{`{"assist":true,"access_id":"123 456 789"}`, http.StatusBadRequest},
		{`{"device_id":"12345678-1234-1234-1234-123456789abc","access_id":"123456789"}`, http.StatusBadRequest},
	} {
		recorder := httptest.NewRecorder()
		server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/remote/window", strings.NewReader(test.body)))
		if recorder.Code != test.status {
			t.Fatalf("remote window status = %d, want %d", recorder.Code, test.status)
		}
	}
}

func TestNativeRemoteWindowSessionLifecycle(t *testing.T) {
	const localID = "12345678-1234-1234-1234-123456789abc"
	const targetID = "87654321-4321-4321-4321-cba987654321"
	var server *Server
	var lock sync.Mutex
	closed := map[string]bool{}
	var tokens int
	mode := "success"
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lock.Lock()
		currentMode := mode
		lock.Unlock()
		switch r.URL.Path {
		case "/api/v1/auth/device":
			lock.Lock()
			tokens++
			token := fmt.Sprintf("access-%d", tokens)
			lock.Unlock()
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": token, "refresh_token": "refresh", "access_expires_at": time.Now().Add(time.Hour)})
		case "/api/v1/client/remote-devices":
			_ = json.NewEncoder(w).Encode(map[string]any{"items": []map[string]any{{"id": targetID, "status": "active", "online": currentMode != "offline"}}})
		case "/api/v2/auth/native-remote-handoff":
			if currentMode == "unsupported" {
				w.WriteHeader(http.StatusNotFound)
				_, _ = w.Write([]byte(`{"error_code":"NOT_FOUND"}`))
				return
			}
			if currentMode == "account-change" {
				server.beginAccountChange(nil)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"code": strings.Repeat("S", 43), "window_id": localID, "expires_at": time.Now().Add(30 * time.Second)})
		case "/api/v2/auth/session/close":
			lock.Lock()
			closed[r.Header.Get("Authorization")] = true
			lock.Unlock()
			w.WriteHeader(http.StatusNoContent)
		default:
			t.Errorf("unexpected upstream request %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer upstream.Close()
	oldTransport := http.DefaultTransport
	http.DefaultTransport = upstream.Client().Transport
	defer func() { http.DefaultTransport = oldTransport }()
	store := statepkg.Store{Path: filepath.Join(t.TempDir(), "state.json")}
	if err := store.Save(model.State{InstallID: "sample", DeviceID: localID, DeviceCredential: "sample-device-credential", Profile: model.Profile{PublicBaseURL: upstream.URL, APIBaseURL: upstream.URL + "/api/v1/"}}); err != nil {
		t.Fatal(err)
	}
	server = New(Options{LocalToken: testLocalToken, StatePath: store.Path})
	var launches []model.RemoteWindowLaunch
	server.SetOpenRemote(func(launch model.RemoteWindowLaunch) error { launches = append(launches, launch); return nil })
	request := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPost, "/local/remote/window", strings.NewReader(body)))
		return rec
	}
	setMode := func(value string) { lock.Lock(); mode = value; lock.Unlock() }
	wasClosed := func(token string) bool { lock.Lock(); defer lock.Unlock(); return closed["Bearer "+token] }
	first := request(`{"device_id":"` + targetID + `"}`)
	if first.Code != http.StatusOK || len(launches) != 1 {
		t.Fatalf("first launch failed %d %s", first.Code, first.Body)
	}
	if strings.Contains(launches[0].URL, launches[0].HandoffCode) || strings.Contains(first.Body.String(), launches[0].HandoffCode) {
		t.Fatal("handoff code exposed to URL/local response")
	}
	for _, test := range []struct {
		mode, body string
		status     int
	}{{"success", `{"device_id":"` + strings.ToUpper(localID) + `"}`, 409}, {"offline", `{"device_id":"` + targetID + `"}`, 404}, {"unsupported", `{"device_id":"` + targetID + `"}`, 426}} {
		setMode(test.mode)
		response := request(test.body)
		if response.Code != test.status {
			t.Fatalf("%s status=%d %s", test.mode, response.Code, response.Body)
		}
		if len(launches) != 1 || wasClosed("access-1") {
			t.Fatalf("failed replacement killed active remote: %s", test.mode)
		}
	}
	server.remoteHost = &localRemoteHost{accessProfile: remotehost.AccessProfile{DeviceID: "123456789"}}
	setMode("success")
	selfAssist := request(`{"assist":true,"access_id":"123456789"}`)
	if selfAssist.Code != 409 || !strings.Contains(selfAssist.Body.String(), "RD_SELF_CONNECTION") || wasClosed("access-1") {
		t.Fatalf("self assist guard failed %d %s", selfAssist.Code, selfAssist.Body)
	}
	replacement := request(`{"device_id":"` + targetID + `"}`)
	if replacement.Code != 200 || len(launches) != 2 || !wasClosed("access-1") {
		t.Fatalf("replacement failed %d %s", replacement.Code, replacement.Body)
	}
	lock.Lock()
	currentToken := fmt.Sprintf("access-%d", tokens)
	lock.Unlock()
	server.RemoteWindowClosed(launches[0].Generation)
	if wasClosed(currentToken) {
		t.Fatal("late old-window close revoked newer window")
	}
	server.RemoteWindowClosed(launches[1].Generation)
	if !wasClosed(currentToken) {
		t.Fatal("window close left parent session alive")
	}
	setMode("account-change")
	cancelled := request(`{"device_id":"` + targetID + `"}`)
	if cancelled.Code == 200 || len(launches) != 2 {
		t.Fatal("account switch did not cancel pending remote open")
	}
}

func TestRemoteOpenCannotStartDuringFailedLogout(t *testing.T) {
	const localID = "12345678-1234-1234-1234-123456789abc"
	const targetID = "87654321-4321-4321-4321-cba987654321"
	logoutStarted, releaseLogout := make(chan struct{}), make(chan struct{})
	var logins atomic.Int32
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/auth/device":
			logins.Add(1)
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "logout-access", "refresh_token": "refresh", "access_expires_at": time.Now().Add(time.Hour)})
		case "/api/v2/auth/logout":
			close(logoutStarted)
			<-releaseLogout
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error_code":"UNAVAILABLE"}`))
		default:
			t.Errorf("unexpected upstream during logout: %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer upstream.Close()
	oldTransport := http.DefaultTransport
	http.DefaultTransport = upstream.Client().Transport
	defer func() { http.DefaultTransport = oldTransport }()
	store := statepkg.Store{Path: filepath.Join(t.TempDir(), "state.json")}
	if err := store.Save(model.State{InstallID: "sample", DeviceID: localID, DeviceCredential: "sample-device-credential", Profile: model.Profile{PublicBaseURL: upstream.URL, APIBaseURL: upstream.URL + "/api/v1/"}}); err != nil {
		t.Fatal(err)
	}
	server := New(Options{LocalToken: testLocalToken, StatePath: store.Path})
	server.SetOpenRemote(func(model.RemoteWindowLaunch) error { t.Error("remote window opened during logout"); return nil })
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		server.Handler().ServeHTTP(httptest.NewRecorder(), trustedLocalRequest(http.MethodPost, "/local/logout", strings.NewReader(`{}`)))
	}()
	<-logoutStarted
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, trustedLocalRequest(http.MethodPost, "/local/remote/window", strings.NewReader(`{"device_id":"`+targetID+`"}`)))
	if response.Code != http.StatusConflict || logins.Load() != 1 {
		t.Errorf("remote auth escaped in-progress logout: status=%d logins=%d", response.Code, logins.Load())
	}
	close(releaseLogout)
	<-finished
	response = httptest.NewRecorder()
	server.Handler().ServeHTTP(response, trustedLocalRequest(http.MethodPost, "/local/remote/window", strings.NewReader(`{"device_id":"`+targetID+`"}`)))
	if response.Code == 200 || logins.Load() != 1 {
		t.Errorf("remote auth escaped completed failed-network logout: %d", response.Code)
	}
}
