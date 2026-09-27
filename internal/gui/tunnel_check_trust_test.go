package gui

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
)

type probeCountingListener struct {
	net.Listener
	accepted atomic.Int32
}

func (listener *probeCountingListener) Accept() (net.Conn, error) {
	connection, err := listener.Listener.Accept()
	if err == nil {
		listener.accepted.Add(1)
	}
	return connection, err
}

func TestConnectionCheckNetworkBoundary(t *testing.T) {
	target := httptest.NewUnstartedServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) { writer.WriteHeader(http.StatusNoContent) }))
	listener := &probeCountingListener{Listener: target.Listener}
	target.Listener = listener
	target.Start()
	defer target.Close()
	host, rawPort, _ := net.SplitHostPort(strings.TrimPrefix(target.URL, "http://"))
	port, _ := strconv.Atoi(rawPort)
	body, _ := json.Marshal(map[string]any{"proxy_type": "http", "local_host": host, "local_port": port, "local_scheme": "http"})
	server := probeServer(t)
	for _, item := range []struct {
		name   string
		change func(*http.Request)
		status int
	}{
		{"DNS rebinding", func(r *http.Request) { r.Host = "attacker.example:8788" }, http.StatusForbidden},
		{"remote client", func(r *http.Request) { r.RemoteAddr = "192.0.2.50:4000" }, http.StatusForbidden},
		{"foreign origin", func(r *http.Request) { r.Header.Set("Origin", "https://attacker.example") }, http.StatusForbidden},
		{"another local origin", func(r *http.Request) { r.Header.Set("Origin", "http://127.0.0.1:9999") }, http.StatusForbidden},
		{"opaque origin", func(r *http.Request) { r.Header.Set("Origin", "null") }, http.StatusForbidden},
		{"cross-site request", func(r *http.Request) { r.Header.Set("Sec-Fetch-Site", "cross-site") }, http.StatusForbidden},
		{"missing desktop session", func(r *http.Request) { r.Header.Del("Authorization") }, http.StatusUnauthorized},
		{"wrong desktop session", func(r *http.Request) { r.Header.Set("Authorization", "Bearer test-other-session") }, http.StatusUnauthorized},
		{"HTML form request", func(r *http.Request) { r.Header.Set("Content-Type", "application/x-www-form-urlencoded") }, http.StatusUnsupportedMediaType},
		{"GET request", func(r *http.Request) { r.Method = http.MethodGet }, http.StatusMethodNotAllowed},
	} {
		t.Run(item.name, func(t *testing.T) {
			request := trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(string(body)))
			item.change(request)
			recorder := httptest.NewRecorder()
			server.Handler().ServeHTTP(recorder, request)
			if recorder.Code != item.status || listener.accepted.Load() != 0 {
				t.Fatalf("untrusted probe reached the target: response=%d accepted=%d", recorder.Code, listener.accepted.Load())
			}
		})
	}
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/connection-check", strings.NewReader(string(body))))
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), "TARGET_HTTP_READY") || listener.accepted.Load() < 1 {
		t.Fatalf("authorized local user could not probe: %d %s", recorder.Code, recorder.Body.String())
	}
}
