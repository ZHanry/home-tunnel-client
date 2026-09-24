package gui

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
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
	assistance, err := remoteAssistanceURL("https://console.example.com")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err = url.Parse(assistance)
	if err != nil || parsed.Query().Get("remoteAssist") != "1" || parsed.Query().Has("remoteDevice") || parsed.Fragment != "remote" {
		t.Fatalf("unexpected assistance URL: %s", assistance)
	}
	for _, base := range []string{"javascript:alert(1)", "https://user:password@console.example.com", "//console.example.com"} {
		if _, err := remoteWindowURL(base, deviceID); err == nil {
			t.Fatalf("accepted unsafe base: %q", base)
		}
	}
}

func TestRemoteWindowRequiresValidDeviceAndLogin(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "missing.json")})
	server.SetOpenRemote(func(string) error { t.Fatal("remote window must not open"); return nil })
	for _, test := range []struct {
		body   string
		status int
	}{
		{`{"device_id":"https://attacker.example"}`, http.StatusBadRequest},
		{`{"device_id":"12345678-1234-1234-1234-123456789abc","assist":true}`, http.StatusBadRequest},
		{`{"device_id":"12345678-1234-1234-1234-123456789abc"}`, http.StatusUnauthorized},
		{`{"assist":true}`, http.StatusUnauthorized},
	} {
		recorder := httptest.NewRecorder()
		server.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/remote/window", strings.NewReader(test.body)))
		if recorder.Code != test.status {
			t.Fatalf("remote window status = %d, want %d", recorder.Code, test.status)
		}
	}
}
