package gui

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func TestLocalDeviceRenameRejectsInvalidInputAndMissingSession(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "state.json")})
	for _, body := range []string{`{"name":" "}`, `{"name":"Desk","device_id":"other"}`, `{"name":"Desk"} {}`, `{"name":4}`} {
		rec := httptest.NewRecorder()
		server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPatch, "/local/device/name", strings.NewReader(body)))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("invalid rename accepted: %d %s", rec.Code, rec.Body)
		}
	}
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPatch, "/local/device/name", strings.NewReader(`{"name":"Desk"}`)))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("unbound rename accepted: %d", rec.Code)
	}
}

func TestLocalDeviceRenamePersistsAndHandlesFailureOrAccountChange(t *testing.T) {
	for _, mode := range []string{"success", "failure", "lost-response", "account-change"} {
		t.Run(mode, func(t *testing.T) {
			var server *Server
			var renameCalls atomic.Int32
			upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/api/v1/auth/device":
					_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "access", "refresh_token": "refresh", "access_expires_at": time.Now().Add(time.Hour)})
				case "/api/v1/devices/current/name":
					renameCalls.Add(1)
					if mode == "failure" {
						w.WriteHeader(http.StatusServiceUnavailable)
						_, _ = w.Write([]byte(`{"error_code":"UNAVAILABLE"}`))
						return
					}
					if mode == "lost-response" {
						connection, _, err := w.(http.Hijacker).Hijack()
						if err != nil {
							t.Error(err)
							return
						}
						_ = connection.Close()
						return
					}
					if mode == "account-change" {
						server.beginAccountChange(nil)
					}
					_, _ = w.Write([]byte(`{"device_id":"device-one","device_name":"Office PC"}`))
				case "/api/v2/auth/session/close":
					w.WriteHeader(http.StatusNoContent)
				default:
					t.Errorf("unexpected request: %s", r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			defer upstream.Close()
			oldTransport := http.DefaultTransport
			http.DefaultTransport = upstream.Client().Transport
			defer func() { http.DefaultTransport = oldTransport }()
			store := statepkg.Store{Path: filepath.Join(t.TempDir(), "state.json")}
			original := model.State{InstallID: "installation", DeviceID: "device-one", DeviceCredential: "credential", DeviceName: "Original",
				Profile: model.Profile{PublicBaseURL: upstream.URL + "/", APIBaseURL: upstream.URL + "/api/v1/"}}
			if err := store.Save(original); err != nil {
				t.Fatal(err)
			}
			server = New(Options{StatePath: store.Path, LocalToken: testLocalToken})
			rec := httptest.NewRecorder()
			server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPatch, "/local/device/name", strings.NewReader(`{"name":"  Office PC  "}`)))
			wantStatus, wantName := http.StatusOK, "Office PC"
			if mode == "failure" {
				wantStatus, wantName = http.StatusServiceUnavailable, "Original"
			}
			if mode == "lost-response" {
				wantStatus, wantName = http.StatusBadGateway, "Original"
			}
			if mode == "account-change" {
				wantStatus, wantName = http.StatusConflict, "Original"
			}
			if rec.Code != wantStatus || renameCalls.Load() != 1 {
				t.Fatalf("rename response: %d %s", rec.Code, rec.Body)
			}
			fresh, err := store.Load()
			if err != nil || fresh.DeviceName != wantName {
				t.Fatalf("unexpected persisted name %q: %v", fresh.DeviceName, err)
			}
			if mode == "lost-response" {
				server.reconcileDeviceName(fresh, []model.Device{{ID: "device-one", Name: "Office PC"}})
				recovered, err := store.Load()
				if err != nil || recovered.DeviceName != "Office PC" {
					t.Fatalf("could not reconcile uncertain server result: %#v %v", recovered, err)
				}
			}
			if mode == "success" && !strings.Contains(rec.Body.String(), `"device_name":"Office PC"`) {
				t.Fatal("canonical name missing")
			}
		})
	}
}

func TestReconcileDeviceNameDoesNotWriteToAnotherAccount(t *testing.T) {
	store := statepkg.Store{Path: filepath.Join(t.TempDir(), "state.json")}
	old := model.State{InstallID: "installation", DeviceID: "old", DeviceCredential: "old-credential", DeviceName: "Old",
		Profile: model.Profile{PublicBaseURL: "https://example.com/", APIBaseURL: "https://example.com/api/v1/"}}
	current := old
	current.DeviceID, current.DeviceCredential, current.DeviceName = "new", "new-credential", "New account"
	if err := store.Save(current); err != nil {
		t.Fatal(err)
	}
	server := New(Options{StatePath: store.Path})
	server.reconcileDeviceName(old, []model.Device{{ID: "old", Name: "Stale result"}})
	fresh, err := store.Load()
	if err != nil || fresh.DeviceName != "New account" {
		t.Fatalf("stale list changed account: %#v, %v", fresh, err)
	}
}

type accountChangingNameReader struct {
	reader io.Reader
	change func()
}

func (reader *accountChangingNameReader) Read(data []byte) (int, error) {
	if reader.change != nil {
		change := reader.change
		reader.change = nil
		change()
	}
	return reader.reader.Read(data)
}

func TestRenameCannotFollowAccountChangeWhileReadingRequest(t *testing.T) {
	server := New(Options{StatePath: filepath.Join(t.TempDir(), "state.json"), LocalToken: testLocalToken})
	body := &accountChangingNameReader{reader: strings.NewReader(`{"name":"Old account intent"}`), change: func() { server.beginAccountChange(nil) }}
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPatch, "/local/device/name", body))
	if rec.Code != http.StatusConflict {
		t.Fatalf("old request was not invalidated before authenticating: %d %s", rec.Code, rec.Body)
	}
}
