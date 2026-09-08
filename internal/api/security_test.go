package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestDiscoveryRejectsRedirectsWithAnInjectedTLSClient(t *testing.T) {
	var redirected atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/unexpected" {
			redirected.Add(1)
			writer.WriteHeader(http.StatusNoContent)
			return
		}
		http.Redirect(writer, request, "/unexpected", http.StatusFound)
	}))
	defer server.Close()
	provided := server.Client()
	_, err := Discover(context.Background(), server.URL, provided)
	if err == nil || redirected.Load() != 0 {
		t.Fatalf("discovery followed a redirect: calls=%d err=%v", redirected.Load(), err)
	}
	if provided.CheckRedirect != nil {
		t.Fatal("caller HTTP client was modified")
	}
}

func TestAPIRedirectCannotReplayCredentials(t *testing.T) {
	var redirected atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/unexpected" {
			redirected.Add(1)
			return
		}
		http.Redirect(writer, request, "/unexpected", http.StatusTemporaryRedirect)
	}))
	defer server.Close()
	client, err := New(server.URL+"/api/v1/", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Login(context.Background(), "test-user", "test-password")
	if err == nil || redirected.Load() != 0 {
		t.Fatalf("API credentials were replayed to a redirect: calls=%d err=%v", redirected.Load(), err)
	}
}

func TestAPIRequestCannotEscapeSelectedOriginOrPrefix(t *testing.T) {
	var requests atomic.Int32
	transport := &http.Client{Transport: securityTransport(func(*http.Request) (*http.Response, error) {
		requests.Add(1)
		return nil, errors.New("unexpected transport call")
	})}
	client, err := New("https://console.example.test/api/v1/", transport)
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"https://elsewhere.example.test/", "//elsewhere.example.test/", "../../internal/metrics", "client/../../../internal/metrics", "client/%2e%2e/%2e%2e/%2e%2e/internal/metrics"} {
		if _, err := client.sendJSON(context.Background(), http.MethodGet, path, nil, nil, "test-token"); err == nil {
			t.Errorf("accepted escaping API path: %s", path)
		}
	}
	for _, base := range []string{"https://user:password@console.example.test/api/v1/", "https://console.example.test/", "https://console.example.test/api/v1/?token=test"} {
		if _, err := New(base, nil); err == nil {
			t.Errorf("accepted invalid API base: %s", base)
		}
	}
	if requests.Load() != 0 {
		t.Fatal("an escaping path reached the HTTP transport")
	}
}

type securityTransport func(*http.Request) (*http.Response, error)

func (transport securityTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return transport(request)
}

func TestRemoteErrorStringDoesNotReflectSecrets(t *testing.T) {
	secret := strings.Repeat("private", 8)
	err := &Error{StatusCode: 401, Code: secret, Message: secret}
	if strings.Contains(err.Error(), secret) {
		t.Fatal("remote error content leaked through Error()")
	}
}

func TestMalformedResponseCannotLeakAServerReflectedPassword(t *testing.T) {
	secret := strings.Repeat("private", 8)
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(writer).Encode(map[string]string{"access_expires_at": secret})
	}))
	defer server.Close()
	client, err := New(server.URL+"/api/v1/", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Login(context.Background(), "test-user", secret)
	if err == nil || strings.Contains(err.Error(), secret) {
		t.Fatal("malformed response did not fail safely")
	}
}
