package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestRenameCurrentDeviceUsesBoundSession(t *testing.T) {
	for _, wrongResponse := range []bool{false, true} {
		server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPatch || r.URL.Path != "/api/v1/devices/current/name" || r.Header.Get("Authorization") != "Bearer access" {
				t.Errorf("unexpected rename request: %s %s", r.Method, r.URL)
			}
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			if len(body) != 1 || body["name"] != "Office PC" {
				t.Errorf("unsafe rename payload: %#v", body)
			}
			id := "current-device"
			if wrongResponse {
				id = "another-device"
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"device_id": id, "device_name": "Office PC"})
		}))
		client, err := New(server.URL+"/api/v1/", server.Client())
		if err != nil {
			t.Fatal(err)
		}
		client.deviceID = "current-device"
		client.setSession("access", "refresh", time.Now().Add(time.Hour))
		name, err := client.RenameCurrentDevice(context.Background(), "  Office PC  ")
		server.Close()
		if wrongResponse {
			if err == nil {
				t.Fatal("accepted another device's response")
			}
		} else if err != nil || name != "Office PC" {
			t.Fatalf("rename failed: %q %v", name, err)
		}
	}
}

func TestRenameCurrentDeviceRejectsUnboundAccountSession(t *testing.T) {
	client, err := New("https://example.com/api/v1/", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.RenameCurrentDevice(context.Background(), "Office PC"); err == nil {
		t.Fatal("unbound session accepted")
	}
}
