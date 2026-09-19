package diagnostics

import (
	"archive/zip"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/state"
)

func TestDoctorProbesAndBundleRedaction(t *testing.T) {
	local := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(401) }))
	defer local.Close()
	host, portText, _ := net.SplitHostPort(strings.TrimPrefix(local.URL, "http://"))
	port, _ := strconv.Atoi(portText)
	var upstream *httptest.Server
	authenticated, closed := false, false
	upstream = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/v1/public/config":
			_ = json.NewEncoder(w).Encode(map[string]any{"public_base_url": upstream.URL, "tunnel_domain": "private.example.com", "frps_host": host, "frps_port": port})
		case "/api/v1/auth/device":
			authenticated = true
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "private-access-token", "refresh_token": "private-refresh-token", "access_expires_at": "2099-01-01T00:00:00Z"})
		case "/api/v1/client/connections":
			_, _ = io.WriteString(w, `{"items":[]}`)
		case "/api/v1/auth/session/close":
			closed = true
			w.WriteHeader(204)
		default:
			http.NotFound(w, r)
		}
	}))
	defer upstream.Close()
	path := filepath.Join(t.TempDir(), "state.json")
	input := model.State{InstallID: "private-install-id", DeviceID: "private-device-id", DeviceCredential: "private-device-credential", Profile: model.Profile{PublicBaseURL: upstream.URL, APIBaseURL: upstream.URL + "/api/v1/"}, CachedConnections: []model.Connection{{Name: "private-service-name", LocalHost: host, LocalPort: port, ProxyType: "http", LocalScheme: "http"}, {ProxyType: "udp"}}}
	if err := (state.Store{Path: path}).Save(input); err != nil {
		t.Fatal(err)
	}
	report := Run(context.Background(), Options{StatePath: path, HTTPClient: upstream.Client()})
	if !authenticated || !closed {
		t.Fatal("authentication was not tested and cleaned up")
	}
	checks := map[string]Check{}
	for _, c := range report.Checks {
		checks[c.Name] = c
	}
	if checks["local_target_1"].Status != "pass" || checks["local_target_2"].Status != "manual" {
		t.Fatalf("bad local probe results: %#v", checks)
	}
	bundle := filepath.Join(t.TempDir(), "support.zip")
	if err := WriteBundle(report, bundle); err != nil {
		t.Fatal(err)
	}
	archive, err := zip.OpenReader(bundle)
	if err != nil {
		t.Fatal(err)
	}
	defer archive.Close()
	for _, entry := range archive.File {
		reader, _ := entry.Open()
		body, _ := io.ReadAll(reader)
		reader.Close()
		for _, secret := range []string{"private-device", "private-service", "private-access", "private-refresh", upstream.URL, path} {
			if strings.Contains(string(body), secret) {
				t.Fatalf("bundle leaks %s", secret)
			}
		}
	}
	_ = (state.Store{Path: path}).Save(model.State{InstallID: input.InstallID})
}

func TestDoctorDoesNotSendCredentialsToAnotherOrigin(t *testing.T) {
	var upstream *httptest.Server
	upstream = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/public/config" {
			t.Error("sent credentials to different origin")
			http.Error(w, "unexpected", 500)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"public_base_url": upstream.URL, "tunnel_domain": "example.com", "frps_host": "127.0.0.1", "frps_port": 1})
	}))
	defer upstream.Close()
	path := filepath.Join(t.TempDir(), "state.json")
	if err := (state.Store{Path: path}).Save(model.State{InstallID: "test", DeviceID: "test", DeviceCredential: "private-credential", Profile: model.Profile{PublicBaseURL: "https://original.example.com/", APIBaseURL: "https://original.example.com/api/v1/"}}); err != nil {
		t.Fatal(err)
	}
	report := Run(context.Background(), Options{StatePath: path, Server: upstream.URL, HTTPClient: upstream.Client()})
	for _, check := range report.Checks {
		if check.Name == "authentication" && check.Status != "warning" {
			t.Fatal("cross-origin authentication was attempted")
		}
	}
	_ = (state.Store{Path: path}).Save(model.State{InstallID: "test"})
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
}
