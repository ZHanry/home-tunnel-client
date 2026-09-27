package gui

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/diagnostics"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func probeServer(t *testing.T) *Server {
	t.Helper()
	path := filepath.Join(t.TempDir(), "state.json")
	if err := (statepkg.Store{Path: path}).Save(model.State{
		InstallID: "fixture-install", DeviceID: "fixture-device", DeviceCredential: "fixture-" + "credential",
		Profile: model.Profile{PublicBaseURL: "https://example.test", APIBaseURL: "https://example.test/api/v1"},
	}); err != nil {
		t.Fatal(err)
	}
	return New(Options{LocalToken: testLocalToken, StatePath: path})
}

func TestConnectionCheckRequiresLocalSessionAndEnrollment(t *testing.T) {
	server := probeServer(t)
	request := trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(`{}`))
	request.Header.Del("Authorization")
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated local session: %d", recorder.Code)
	}
	server.options.StatePath = filepath.Join(t.TempDir(), "missing.json")
	recorder = httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(`{}`)))
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("unenrolled device: %d", recorder.Code)
	}
}

func TestConnectionCheckRejectsInvalidTargetsAndUnknownFields(t *testing.T) {
	server := probeServer(t)
	for _, body := range []string{
		`{"proxy_type":"tcp","local_host":"http://127.0.0.1/","local_port":80}`,
		`{"proxy_type":"tcp","local_host":"user@localhost","local_port":80}`,
		`{"proxy_type":"udp","local_host":"localhost","local_port":0}`,
		`{"proxy_type":"http","local_host":"localhost","local_port":80,"local_scheme":"file"}`,
		`{"proxy_type":"tcp","local_host":"localhost","local_port":80,"credentials":"no"}`,
		`{"proxy_type":"tcp","local_host":"localhost","local_port":80} {}`,
		strings.Repeat(" ", 4096) + `{}`,
	} {
		recorder := httptest.NewRecorder()
		server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(body)))
		if recorder.Code != http.StatusBadRequest {
			t.Fatalf("invalid target accepted: %d", recorder.Code)
		}
	}
	for _, host := range []string{"localhost", "nas.home", "127.0.0.1", "::1", "2001:db8::1"} {
		if !validProbeHost(host) {
			t.Fatalf("valid host rejected: %s", host)
		}
	}
}

func TestConnectionCheckUsesUnauthenticatedHeadWithoutRedirects(t *testing.T) {
	observed := make(chan [2]string, 1)
	upstream := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		observed <- [2]string{request.Method, request.Header.Get("Authorization") + request.Header.Get("Cookie")}
		writer.Header().Set("Location", "http://redirect.invalid/")
		writer.WriteHeader(http.StatusFound)
	}))
	defer upstream.Close()
	host, rawPort, _ := net.SplitHostPort(strings.TrimPrefix(upstream.URL, "http://"))
	port, _ := strconv.Atoi(rawPort)
	body, _ := json.Marshal(map[string]any{"proxy_type": "http", "local_host": host, "local_port": port, "local_scheme": "http"})
	recorder := httptest.NewRecorder()
	probeServer(t).Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(string(body))))
	var result diagnostics.Check
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if recorder.Code != http.StatusOK || result.Code != "TARGET_HTTP_READY" {
		t.Fatalf("incomplete HTTP probe: %+v", result)
	}
	select {
	case request := <-observed:
		if request != [2]string{http.MethodHead, ""} {
			t.Fatalf("unsafe HTTP probe: %+v", request)
		}
	default:
		t.Fatal("target never received the probe")
	}
}

func TestConnectionCheckDoesNotInventUDPOrTLSSuccess(t *testing.T) {
	server := probeServer(t)
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(writer, "ok") }))
	defer upstream.Close()
	host, rawPort, _ := net.SplitHostPort(strings.TrimPrefix(upstream.URL, "https://"))
	port, _ := strconv.Atoi(rawPort)
	for _, item := range []struct{ protocol, status, code string }{{"udp", "manual", "UDP_MANUAL_CHECK"}, {"http", "fail", "TARGET_TLS_FAILED"}} {
		body, _ := json.Marshal(map[string]any{"proxy_type": item.protocol, "local_host": host, "local_port": port, "local_scheme": "https"})
		recorder := httptest.NewRecorder()
		server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(string(body))))
		var result diagnostics.Check
		if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if result.Code != item.code || result.Status != item.status {
			t.Fatalf("incorrect protocol claim: %+v", result)
		}
	}
}
