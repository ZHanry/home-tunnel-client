package gui

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func TestConsoleURLStaysOnConfiguredOrigin(t *testing.T) {
	for _, test := range []struct{ base, section, want string }{
		{"https://console.example.com", "", "https://console.example.com/"},
		{"https://Console.Example.com:8443/prefix/?next=https://evil.example#frag", "", "https://console.example.com:8443/"},
		{"http://192.168.1.10:8080/", "remote", "http://192.168.1.10:8080/admin#remote"},
		{"https://[2001:db8::1]:443", "", "https://[2001:db8::1]:443/"},
	} {
		got, err := consoleURL(test.base, test.section)
		if err != nil || got != test.want {
			t.Fatalf("consoleURL(%q, %q) = %q, %v; want %q", test.base, test.section, got, err, test.want)
		}
	}
	for _, test := range []struct{ base, section string }{
		{"javascript:alert(1)", ""},
		{"file:///C:/Windows/System32/calc.exe", ""},
		{"ms-settings:display", ""},
		{"https://user:password@console.example.com", ""},
		{"//console.example.com", ""},
		{"https://", ""},
		{"https://console.example.com\" & calc.exe", ""},
		{"https://console.example.com^&calc", ""},
		{"https://console.example.com%26calc", ""},
		{"https://console.example.com", "https://evil.example"},
		{"https://console.example.com", "../../settings"},
		{"", ""},
	} {
		if got, err := consoleURL(test.base, test.section); err == nil {
			t.Fatalf("consoleURL(%q, %q) accepted %q", test.base, test.section, got)
		}
	}
}

func TestOpenConsoleUsesTheSignedInServerOnly(t *testing.T) {
	var opened []string
	previous := openBrowser
	openBrowser = func(address string) error { opened = append(opened, address); return nil }
	t.Cleanup(func() { openBrowser = previous })

	missing := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "missing.json")})
	recorder := httptest.NewRecorder()
	missing.Handler().ServeHTTP(recorder, trustedLocalRequest(http.MethodPost, "/local/console/open", strings.NewReader(`{}`)))
	if recorder.Code != http.StatusUnauthorized || len(opened) != 0 {
		t.Fatalf("signed-out console open: status=%d opened=%v", recorder.Code, opened)
	}

	path := filepath.Join(t.TempDir(), "state.json")
	state := model.State{InstallID: "install", DeviceID: "device", DeviceCredential: "credential", Profile: model.Profile{APIBaseURL: "https://console.example.com", PublicBaseURL: "https://console.example.com"}}
	if err := (statepkg.Store{Path: path}).Save(state); err != nil {
		t.Fatal(err)
	}
	if !state.Enrolled() {
		t.Fatal("fixture state is not enrolled")
	}
	server := New(Options{LocalToken: testLocalToken, StatePath: path})
	for _, test := range []struct {
		method, body string
		status       int
	}{
		{http.MethodGet, "", http.StatusMethodNotAllowed},
		{http.MethodPost, `{"section":"https://evil.example"}`, http.StatusBadRequest},
		{http.MethodPost, `{"url":"https://evil.example","section":"remote"}`, http.StatusOK},
		{http.MethodPost, `{}`, http.StatusOK},
	} {
		recorder := httptest.NewRecorder()
		server.Handler().ServeHTTP(recorder, trustedLocalRequest(test.method, "/local/console/open", strings.NewReader(test.body)))
		if recorder.Code != test.status {
			t.Fatalf("%s %s: status=%d body=%s", test.method, test.body, recorder.Code, recorder.Body)
		}
	}
	if strings.Join(opened, " ") != "https://console.example.com/admin#remote https://console.example.com/" {
		t.Fatalf("opened unexpected addresses: %v", opened)
	}
}
