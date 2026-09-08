package gui

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestLocalUIRejectsUntrustedRequestsBeforeDispatch(t *testing.T) {
	cases := []struct {
		name   string
		change func(*http.Request)
		status int
	}{
		{"dns rebinding", func(r *http.Request) { r.Host = "attacker.example:8788" }, http.StatusForbidden},
		{"foreign origin", func(r *http.Request) { r.Header.Set("Origin", "https://attacker.example") }, http.StatusForbidden},
		{"other local origin", func(r *http.Request) { r.Header.Set("Origin", "http://127.0.0.1:9999") }, http.StatusForbidden},
		{"opaque origin", func(r *http.Request) { r.Header.Set("Origin", "null") }, http.StatusForbidden},
		{"cross-site fetch", func(r *http.Request) { r.Header.Set("Sec-Fetch-Site", "cross-site") }, http.StatusForbidden},
		{"remote peer", func(r *http.Request) { r.RemoteAddr = "192.0.2.10:40000" }, http.StatusForbidden},
		{"missing session", func(r *http.Request) { r.Header.Del("Authorization") }, http.StatusUnauthorized},
		{"other session", func(r *http.Request) { r.Header.Set("Authorization", "Bearer another-session") }, http.StatusUnauthorized},
		{"plain form", func(r *http.Request) { r.Header.Set("Content-Type", "text/plain") }, http.StatusUnsupportedMediaType},
		{"encoded form", func(r *http.Request) { r.Header.Set("Content-Type", "application/x-www-form-urlencoded") }, http.StatusUnsupportedMediaType},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			called := false
			handler := protectLocalUI(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }), testLocalToken)
			request := trustedLocalRequest(http.MethodPost, "/local/login", strings.NewReader(`{"server":"https://private.example"}`))
			tc.change(request)
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)
			if recorder.Code != tc.status || called {
				t.Fatalf("untrusted request dispatched: status=%d called=%t", recorder.Code, called)
			}
		})
	}
}

func TestLocalUIAllowsAuthorizedBrowserAndNativeRequests(t *testing.T) {
	for _, browser := range []bool{true, false} {
		request := trustedLocalRequest(http.MethodPost, "/local/show", nil)
		if !browser {
			request.Header.Del("Origin")
		}
		called := false
		handler := protectLocalUI(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
			called = true
			writer.WriteHeader(http.StatusNoContent)
		}), testLocalToken)
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, request)
		if !called || recorder.Code != http.StatusNoContent || recorder.Header().Get("X-Frame-Options") != "DENY" {
			t.Fatalf("authorized request rejected or frame protection absent: %d", recorder.Code)
		}
	}
}

func TestDesktopSessionIsPrivateAndDoesNotLeakThroughHTML(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "state.json")
	server := New(Options{StatePath: statePath})
	cleanup, err := server.PublishLocalSession()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	token, err := readLocalToken(statePath)
	if err != nil || token != server.LocalToken() || len(token) != 64 {
		t.Fatal("private session token could not be loaded")
	}
	if runtime.GOOS != "windows" {
		info, err := os.Stat(localSessionPath(statePath))
		if err != nil || info.Mode().Perm()&0o077 != 0 {
			t.Fatal("desktop session token has public file permissions")
		}
	}
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodGet, "/", nil))
	body, _ := io.ReadAll(recorder.Body)
	if recorder.Code != http.StatusOK || strings.Contains(string(body), token) {
		t.Fatal("public UI HTML leaked the private session")
	}
	other := New(Options{StatePath: statePath})
	otherCleanup, err := other.PublishLocalSession()
	if err != nil {
		t.Fatal(err)
	}
	defer otherCleanup()
	cleanup()
	if token, err := readLocalToken(statePath); err != nil || token != other.LocalToken() {
		t.Fatal("old session cleanup removed a newer session")
	}
	otherCleanup()
	if _, err := os.Stat(localSessionPath(statePath)); !os.IsNotExist(err) {
		t.Fatal("session token was not removed on shutdown")
	}
}
