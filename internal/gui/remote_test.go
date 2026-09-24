package gui

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remote"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func TestRemoteCapabilityRequiresLocalSessionAndDoesNotInventMedia(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken})
	request := trustedLocalRequest(http.MethodGet, "/local/remote/capabilities", nil)
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, request)
	var result remote.Capabilities
	if recorder.Code != http.StatusOK || json.Unmarshal(recorder.Body.Bytes(), &result) != nil {
		t.Fatal("capability endpoint failed")
	}
	if result.Available || result.CanHost || result.CanControl || result.Reason != "RD_BACKEND_UNAVAILABLE" {
		t.Fatal("missing media backend claimed available")
	}
	request.Header.Del("Authorization")
	recorder = httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatal("remote endpoint bypasses local authentication")
	}
}

type capabilityEngine struct {
	remotehost.UnavailableEngine
	caps remotehost.Capabilities
	err  error
}

func (e capabilityEngine) Capabilities(context.Context) (remotehost.Capabilities, error) {
	return e.caps, e.err
}

func TestRemoteCapabilitiesRequireReadyNativeHost(t *testing.T) {
	for _, tc := range []struct {
		name  string
		caps  remotehost.Capabilities
		err   error
		ready bool
	}{
		{"missing", remotehost.Capabilities{}, nil, false},
		{"initializing", remotehost.Capabilities{Available: true, Status: "initializing"}, nil, false},
		{"crashed", remotehost.Capabilities{Available: true, Status: "ready"}, errors.New("worker failed"), false},
		{"ready", remotehost.Capabilities{Available: true, Status: "ready"}, nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := New(Options{LocalToken: testLocalToken, RemoteEngine: capabilityEngine{caps: tc.caps, err: tc.err}})
			rec := httptest.NewRecorder()
			s.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodGet, "/local/remote/capabilities", nil))
			var result remote.Capabilities
			if json.Unmarshal(rec.Body.Bytes(), &result) != nil || result.CanHost != tc.ready || result.Available != tc.ready || result.CanControl {
				t.Fatalf("invalid capability result: %s", rec.Body.String())
			}
		})
	}
}

func TestAllRemoteControlsRequireNativeWindowSession(t *testing.T) {
	s := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "state.json")})
	for _, item := range []struct{ method, path string }{
		{"GET", "/local/remote/state"}, {"GET", "/local/remote/trust"}, {"POST", "/local/remote/action"}, {"POST", "/local/remote/files"},
	} {
		req := trustedLocalRequest(item.method, item.path, strings.NewReader(`{"action":"enable"}`))
		req.Header.Del("Authorization")
		rec := httptest.NewRecorder()
		s.Handler().ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s bypassed local auth: %d", item.path, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPost, "/local/remote/action", strings.NewReader(`{"action":"enable"}`)))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "RD_DEVICE_LOGIN_REQUIRED") {
		t.Fatal("remote enabled without device enrollment")
	}
}

func TestRemoteErrorsDoNotReflectArbitraryServerContent(t *testing.T) {
	for _, err := range []error{errors.New("secret-token"), &remotehost.APIError{Status: 400, Code: "RD_bad token-secret"}, &remotehost.APIError{Status: 400, Code: "RD_" + strings.Repeat("A", 100)}} {
		if safeRemoteCode(err) != "RD_REQUEST_FAILED" {
			t.Fatal("server content leaked")
		}
	}
	if safeRemoteCode(remotehost.ErrUnavailable) != "RD_BACKEND_UNAVAILABLE" {
		t.Fatal("known code lost")
	}
	for source, expected := range map[string]string{"MFA_REQUIRED": "RD_MFA_REQUIRED", "MFA_INVALID": "RD_MFA_INVALID"} {
		if got := safeRemoteCode(&remotehost.APIError{Status: 401, Code: source}); got != expected {
			t.Fatalf("MFA challenge lost: got %s, want %s", got, expected)
		}
	}
}

func TestRemoteTrustPinChangesWithServerIdentityAndKeyVersion(t *testing.T) {
	keys := remotehost.Keyset{ServerInstanceID: "server-a", KeysetVersion: 1, RestoreEpoch: 1, ActiveKid: "pin-a"}
	pin := keysetPin(keys)
	keys.ServerInstanceID = "server-b"
	if keysetPin(keys) == pin {
		t.Fatal("server replacement kept pin")
	}
	keys.ServerInstanceID = "server-a"
	keys.KeysetVersion = 2
	if keysetPin(keys) == pin {
		t.Fatal("keyset replacement kept pin")
	}
}

func TestSupersededAccountEnrollmentCannotSaveCredentials(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	s := New(Options{StatePath: path})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	old := s.beginAccountChange(cancel)
	s.beginAccountChange(nil)
	if ctx.Err() == nil {
		t.Fatal("old network operation was not canceled")
	}
	if err := s.commitEnrollment(context.Background(), old, model.State{DeviceID: "old-device", DeviceCredential: "discard-me"}); err == nil {
		t.Fatal("stale completion committed")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("stale credentials were persisted")
	}
	if !s.remoteBlocked || s.running {
		t.Fatal("stale enrollment restarted services")
	}
}

func TestRemoteStateIsReadAfterAccountLock(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	store := statepkg.Store{Path: path}
	state := model.State{InstallID: "11111111-1111-4111-8111-111111111111", DeviceID: "device-a", DeviceCredential: "credential-a", Profile: model.Profile{PublicBaseURL: "https://a.example", APIBaseURL: "https://a.example/api/v1/"}}
	if err := store.Save(state); err != nil {
		t.Fatal(err)
	}
	s := New(Options{StatePath: path})
	s.remoteMu.Lock()
	result := make(chan model.State, 1)
	go func() { _, observed, _ := s.localRemote(context.Background()); result <- observed }()
	state.DeviceID = "device-b"
	state.DeviceCredential = "credential-b"
	state.Profile.PublicBaseURL = "https://b.example"
	if err := store.Save(state); err != nil {
		s.remoteMu.Unlock()
		t.Fatal(err)
	}
	s.remoteMu.Unlock()
	if observed := <-result; observed.DeviceID != "device-b" {
		t.Fatal("remote manager used account state read before the account lock")
	}
}
