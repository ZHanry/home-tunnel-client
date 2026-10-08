//go:build windows

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestDirectoryPublicationUsesBoundBearerAndIsThrottled(t *testing.T) {
	var requests atomic.Int32
	received := make(chan map[string]string, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Method != "PUT" || r.URL.Path != "/api/v1/homedesk/devices/current" || r.Header.Get("Authorization") != "Bearer fixture-device-session" {
			t.Error("invalid publication route or identity")
		}
		var body map[string]string
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			t.Error("invalid body")
		}
		received <- body
		w.WriteHeader(200)
	}))
	defer server.Close()
	root, _ := url.Parse(server.URL)
	p := newDirectoryPublisher(root, http.DefaultTransport, "20000000-0000-4000-8000-000000000001", "123456789", "relay.example.com", strings.Repeat("a", 64))
	p.publish("Bearer fixture-device-session")
	p.publish("Bearer fixture-device-session")
	select {
	case body := <-received:
		if body["access_token"] != "" || body["device_credential"] != "" || body["remote_id"] != "123456789" || body["server"] != "relay.example.com:21116" || body["device_id"] == "" {
			t.Fatal("metadata mismatch")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("publication missing")
	}
	if requests.Load() != 1 {
		t.Fatal("publication was not throttled")
	}
}

func TestDirectoryPublisherRejectsTargetsAndDoesNotFollowRedirect(t *testing.T) {
	var otherRequests atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { otherRequests.Add(1) }))
	defer other.Close()
	called := make(chan struct{}, 1)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, other.URL, 302)
		called <- struct{}{}
	}))
	defer origin.Close()
	root, _ := url.Parse(origin.URL)
	if newDirectoryPublisher(root, http.DefaultTransport, "device", "127.0.0.1:22", "relay.example.com", strings.Repeat("a", 64)) != nil {
		t.Fatal("direct address was accepted as ID")
	}
	p := newDirectoryPublisher(root, http.DefaultTransport, "device", "123456789", "relay.example.com", strings.Repeat("a", 64))
	p.publish("Bearer fixture-device-session")
	select {
	case <-called:
	case <-time.After(2 * time.Second):
		t.Fatal("request missing")
	}
	// 等待响应处理结束，确认目标没有收到第二个请求。
	time.Sleep(50 * time.Millisecond)
	if otherRequests.Load() != 0 {
		t.Fatal("redirect was followed")
	}
}
