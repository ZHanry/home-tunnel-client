package gui

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/remote"
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
