package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestEnrollmentInstallsDeviceScopedSessionAndBatchKeepsVersions(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			return
		}
		switch r.URL.Path {
		case "/api/v1/auth/enroll":
			if body["code"] != strings.Repeat("x", 32) || body["client_type"] != clientType() || body["install_id"] != "install-identity" || body["fingerprint_hash"] != strings.Repeat("a", 64) {
				t.Error("incorrect enrollment payload")
			}
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(map[string]any{"device_id": "device-local", "device_credential": "test-device-value", "config_version": 1, "access_token": "test-session-value", "refresh_token": "test-refresh-value", "access_expires_at": time.Now().Add(time.Hour).UTC().Format(time.RFC3339)})
		case "/api/v1/client/connections/batch":
			if r.Header.Get("Authorization") != "Bearer test-session-value" {
				t.Error("enrollment session missing")
			}
			items := body["items"].([]any)
			if body["enabled"] != false || items[0].(map[string]any)["expected_version"] != float64(7) {
				t.Error("batch lost the reviewed version")
			}
			_, _ = w.Write([]byte(`{"results":[{"id":"c","status":409,"error_code":"VERSION_CONFLICT"}]}`))
		default:
			t.Errorf("unexpected request %s", r.URL.Path)
		}
	}))
	defer server.Close()
	client, err := New(server.URL+"/api/v1/", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	registration, err := client.EnrollWithCode(context.Background(), strings.Repeat("x", 32), "Home NAS", "install-identity", strings.Repeat("a", 64))
	if err != nil || registration.DeviceID != "device-local" || client.deviceID != "device-local" {
		t.Fatalf("enrollment failed: %v", err)
	}
	results, err := client.BatchConnections(context.Background(), []BatchItem{{ID: "c", ExpectedVersion: 7}}, false)
	if err != nil || len(results) != 1 || results[0].Status != 409 || results[0].ErrorCode != "VERSION_CONFLICT" {
		t.Fatalf("batch result lost: %v", err)
	}
}
