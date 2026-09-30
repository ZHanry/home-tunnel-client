package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestRemoteHandoffCanonicalOriginAndResponseValidation(t *testing.T) {
	for _, test := range []struct{ api, public, origin string }{{"https://CONSOLE.example:443/api/v1/", "https://CONSOLE.example:443/", "https://console.example"}, {"https://[2001:0DB8:0:0::1]:443/api/v1/", "https://[2001:db8::1]/", "https://[2001:db8::1]"}} {
		transport := &http.Client{Transport: securityTransport(func(request *http.Request) (*http.Response, error) {
			if request.URL.RawQuery != "" || strings.Contains(request.URL.String(), "sample-access") {
				t.Fatal("credential entered request URL")
			}
			var body struct {
				Origin string `json:"origin"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body.Origin != test.origin {
				t.Errorf("origin=%s", body.Origin)
			}
			payload, _ := json.Marshal(map[string]any{"code": strings.Repeat("S", 43), "window_id": "12345678-1234-1234-1234-123456789abc", "expires_at": time.Now().Add(30 * time.Second)})
			return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader(string(payload)))}, nil
		})}
		client, err := New(test.api, transport)
		if err != nil {
			t.Fatal(err)
		}
		client.setSession("sample-access", "sample-refresh", time.Now().Add(time.Hour))
		if _, err = client.CreateRemoteHandoff(context.Background(), test.public); err != nil {
			t.Fatal(err)
		}
		if _, err = client.CreateRemoteHandoff(context.Background(), "https://attacker.test"); err == nil {
			t.Fatal("cross-origin handoff accepted")
		}
	}
	for _, status := range []int{404, 405} {
		client, _ := New("https://console.example/api/v1/", &http.Client{Transport: securityTransport(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: status, Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader(`{"error_code":"NOT_FOUND"}`))}, nil
		})})
		client.setSession("sample-access", "sample-refresh", time.Now().Add(time.Hour))
		if _, err := client.CreateRemoteHandoff(context.Background(), "https://console.example"); !errors.Is(err, ErrRemoteHandoffUnsupported) {
			t.Errorf("status%d: %v", status, err)
		}
	}
}
