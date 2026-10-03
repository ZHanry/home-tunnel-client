package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const userOne = "10000000-0000-4000-8000-000000000001"
const userTwo = "10000000-0000-4000-8000-000000000002"
const deviceOne = "20000000-0000-4000-8000-000000000001"
const deviceTwo = "20000000-0000-4000-8000-000000000002"

func fixture(t *testing.T) (*directory, *bool) {
	t.Helper()
	revoked := false
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		uid := userOne
		var device any
		switch token {
		case "Bearer fixture-account-one":
		case "Bearer fixture-device-one":
			device = deviceOne
		case "Bearer fixture-account-two":
			uid = userTwo
		case "Bearer fixture-device-two":
			uid = userTwo
			device = deviceTwo
		default:
			w.WriteHeader(401)
			return
		}
		if r.URL.Path == "/api/v1/auth/me" {
			reply(w, 200, map[string]any{"id": uid, "device_id": device})
			return
		}
		if r.URL.Path == "/api/v1/client/devices" {
			id := deviceOne
			if uid == userTwo {
				id = deviceTwo
			}
			status := "active"
			if revoked {
				status = "revoked"
			}
			reply(w, 200, map[string]any{"items": []map[string]string{{"id": id, "status": status}}, "total_pages": 1})
			return
		}
		w.WriteHeader(404)
	}))
	t.Cleanup(control.Close)
	d, err := newDirectory(control.URL, filepath.Join(t.TempDir(), "directory.json"))
	if err != nil {
		t.Fatal(err)
	}
	return d, &revoked
}
func request(d *directory, method, path, token string, value any) *httptest.ResponseRecorder {
	data, _ := json.Marshal(value)
	r := httptest.NewRequest(method, path, bytes.NewReader(data))
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	d.ServeHTTP(w, r)
	return w
}
func metadata(id, remote string) map[string]any {
	return map[string]any{"device_id": id, "remote_id": remote, "server": "relay.example.com:21116", "key_sha256": strings.Repeat("a", 64), "platform": "windows"}
}
func TestDeviceSessionOwnershipAndAccountIsolation(t *testing.T) {
	d, _ := fixture(t)
	if got := request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-account-one", metadata(deviceOne, "123456789")).Code; got != 403 {
		t.Fatal(got)
	}
	if got := request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-one", metadata(deviceTwo, "123456789")).Code; got != 400 {
		t.Fatal(got)
	}
	if got := request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-one", metadata(deviceOne, "123456789")).Code; got != 200 {
		t.Fatal(got)
	}
	if got := request(d, "GET", "/api/v1/homedesk/devices", "fixture-device-one", nil).Code; got != 403 {
		t.Fatal(got)
	}
	own := request(d, "GET", "/api/v1/homedesk/devices", "fixture-account-one", nil)
	if own.Code != 200 || !strings.Contains(own.Body.String(), "123456789") || strings.Contains(own.Body.String(), "user_id") {
		t.Fatal(own.Code)
	}
	other := request(d, "GET", "/api/v1/homedesk/devices", "fixture-account-two", nil)
	if other.Code != 200 || strings.Contains(other.Body.String(), "123456789") {
		t.Fatal(other.Code)
	}
}
func TestDuplicateRemoteIDAndRevocation(t *testing.T) {
	d, revoked := fixture(t)
	request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-one", metadata(deviceOne, "123456789"))
	if got := request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-two", metadata(deviceTwo, "123456789")).Code; got != 409 {
		t.Fatal(got)
	}
	*revoked = true
	body := request(d, "GET", "/api/v1/homedesk/devices", "fixture-account-one", nil).Body.String()
	if strings.Contains(body, "123456789") {
		t.Fatal("revoked device remained visible")
	}
}
func TestPersistencePresenceAndInvalidTargets(t *testing.T) {
	d, _ := fixture(t)
	for _, invalid := range []string{"127.0.0.1:3389", "https://example.com", "123\n456"} {
		if got := request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-one", metadata(deviceOne, invalid)).Code; got != 400 {
			t.Fatal(got)
		}
	}
	request(d, "PUT", "/api/v1/homedesk/devices/current", "fixture-device-one", metadata(deviceOne, "123456789"))
	loaded, err := newDirectory(d.control, d.file)
	if err != nil || loaded.records[deviceOne].RemoteID != "123456789" {
		t.Fatal("persistence failed")
	}
	e := loaded.records[deviceOne]
	e.LastSeen = time.Now().Add(-2 * time.Minute)
	loaded.records[deviceOne] = e
	response := request(loaded, "GET", "/api/v1/homedesk/devices", "fixture-account-one", nil)
	if strings.Contains(response.Body.String(), `"online":true`) {
		t.Fatal("expired presence stayed online")
	}
}
func TestAuthenticationRoutesAndRedirectFailClosed(t *testing.T) {
	d, _ := fixture(t)
	if request(d, "GET", "/api/v1/homedesk/devices", "", nil).Code != 401 {
		t.Fatal("missing auth accepted")
	}
	if request(d, "POST", "/api/v1/homedesk/devices", "fixture-account-one", nil).Code != 405 {
		t.Fatal("invalid method accepted")
	}
	if request(d, "GET", "/health", "", nil).Code != 200 {
		t.Fatal("health failed")
	}
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "https://example.com", 302) }))
	defer other.Close()
	redirected, err := newDirectory(other.URL, "")
	if err != nil {
		t.Fatal(err)
	}
	if request(redirected, "GET", "/api/v1/homedesk/devices", "fixture-account-one", nil).Code != 502 {
		t.Fatal("redirect was followed")
	}
}
