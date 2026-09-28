package gui

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

var popupNow = time.Date(2026, 9, 28, 12, 0, 0, 0, time.UTC)

func popupStatus() remotehost.Status {
	return remotehost.Status{
		AccessRequests: []remotehost.AccessRequest{
			{ID: "a1", ControllerEndpointID: "ctl-1", ExpiresAt: popupNow.Add(30 * time.Second)},
			{ID: "old", ControllerEndpointID: "ctl-2", ExpiresAt: popupNow.Add(-time.Second)},
			{ID: "", ControllerEndpointID: "ctl-3", ExpiresAt: popupNow.Add(time.Minute)},
		},
		Pending: []remotehost.ApprovalEvent{
			{Kind: "pairing", ID: "p1", ExpiresAt: popupNow.Add(time.Minute)},
			{Kind: "pairing", ID: "p2", DisplayCode: "123456", ExpiresAt: popupNow.Add(time.Minute)},
			{Kind: "pairing_display", ID: "p3", DisplayCode: "654321", ExpiresAt: popupNow.Add(time.Minute)},
			{Kind: "session", ID: "s1", ExpiresAt: popupNow.Add(time.Minute)},
			{Kind: "session", ID: "s-expired", ExpiresAt: popupNow},
			{Kind: "pairing_complete", ID: "p4", ExpiresAt: popupNow.Add(time.Minute)},
		},
	}
}

func TestPendingApprovalsListOnlyLiveHostRequests(t *testing.T) {
	items := pendingApprovals(popupStatus(), popupNow)
	got := map[string]bool{}
	for _, item := range items {
		got[item.Key] = item.Decidable
	}
	want := map[string]bool{"access:a1": true, "pairing:p1": true, "pairing:p2": false, "pairing_display:p3": false, "session:s1": true}
	if len(got) != len(want) {
		t.Fatalf("unexpected items: %#v", got)
	}
	for key, decidable := range want {
		if value, ok := got[key]; !ok || value != decidable {
			t.Fatalf("item %s: got %v (present %v), want decidable %v", key, value, ok, decidable)
		}
	}
	if len(pendingApprovals(remotehost.Status{}, popupNow)) != 0 {
		t.Fatal("an empty status produced requests")
	}
}

func TestApprovalTrackerAnnouncesEachRequestOnce(t *testing.T) {
	tracker := newApprovalTracker()
	status := remotehost.Status{AccessRequests: []remotehost.AccessRequest{{ID: "a1", ExpiresAt: popupNow.Add(30 * time.Second)}}}
	if mode, attention := tracker.update(status, popupNow); mode != PopupRequest || !attention {
		t.Fatalf("first request: mode %q attention %v", mode, attention)
	}
	if mode, attention := tracker.update(status, popupNow.Add(time.Second)); mode != PopupRequest || attention {
		t.Fatalf("repeat request: mode %q attention %v", mode, attention)
	}
	status.Pending = []remotehost.ApprovalEvent{{Kind: "session", ID: "s1", ExpiresAt: popupNow.Add(time.Minute)}}
	if _, attention := tracker.update(status, popupNow.Add(2*time.Second)); !attention {
		t.Fatal("a second queued request did not ask for attention")
	}
	// Expiry drops the request and forgets it.
	if mode, _ := tracker.update(remotehost.Status{}, popupNow.Add(time.Minute)); mode != PopupHidden {
		t.Fatalf("expired requests kept the popup: %q", mode)
	}
	if len(tracker.seen) != 0 || len(tracker.current) != 0 {
		t.Fatal("tracker kept state for requests the host no longer lists")
	}
	// The same ID appearing again later is a new request.
	if _, attention := tracker.update(remotehost.Status{AccessRequests: []remotehost.AccessRequest{{ID: "a1", ExpiresAt: popupNow.Add(2 * time.Minute)}}}, popupNow.Add(time.Minute)); !attention {
		t.Fatal("a re-sent request was not announced")
	}
}

func TestApprovalTrackerModes(t *testing.T) {
	tracker := newApprovalTracker()
	display := remotehost.Status{Pending: []remotehost.ApprovalEvent{{Kind: "pairing_display", ID: "p1", DisplayCode: "123456", ExpiresAt: popupNow.Add(time.Minute)}}}
	// A code the user produced from the main window does not open a popup.
	if mode, attention := tracker.update(display, popupNow); mode != PopupHidden || attention {
		t.Fatalf("display-only notice opened the popup: %q %v", mode, attention)
	}
	// Accepting a pairing in the popup keeps it open to show the code.
	tracker = newApprovalTracker()
	pairing := remotehost.Status{Pending: []remotehost.ApprovalEvent{{Kind: "pairing", ID: "p1", ExpiresAt: popupNow.Add(time.Minute)}}}
	if mode, _ := tracker.update(pairing, popupNow); mode != PopupRequest {
		t.Fatalf("pairing did not open the popup: %q", mode)
	}
	if mode, attention := tracker.update(display, popupNow); mode != PopupRequest || attention {
		t.Fatalf("compare code after accept: %q %v", mode, attention)
	}
	if !tracker.acknowledge("pairing_display:p1") || tracker.acknowledge("pairing:unknown") {
		t.Fatal("acknowledge accepted an unknown key or refused a listed one")
	}
	if mode, _ := tracker.update(display, popupNow); mode != PopupHidden {
		t.Fatalf("acknowledged notice kept the popup: %q", mode)
	}
	// An active session shows the indicator; a new request takes precedence.
	session := remotehost.Status{ActiveSessionID: "live"}
	if mode, _ := tracker.update(session, popupNow); mode != PopupSession {
		t.Fatalf("active session: %q", mode)
	}
	session.AccessRequests = []remotehost.AccessRequest{{ID: "a9", ExpiresAt: popupNow.Add(time.Minute)}}
	if mode, attention := tracker.update(session, popupNow); mode != PopupRequest || !attention {
		t.Fatalf("request during session: %q %v", mode, attention)
	}
}

type popupCall struct {
	mode      string
	attention bool
}

func TestApplyApprovalStateShowsHidesAndRetries(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken})
	var shows []popupCall
	hides, ready := 0, false
	server.SetApprovalPopup(func(mode string, attention bool) bool {
		shows = append(shows, popupCall{mode, attention})
		return ready
	}, func() { hides++ })
	request := remotehost.Status{AccessRequests: []remotehost.AccessRequest{{ID: "a1", ExpiresAt: popupNow.Add(time.Minute)}}}
	// The native window is not ready yet: the next tick must try again.
	server.applyApprovalState(request, popupNow)
	server.applyApprovalState(request, popupNow.Add(time.Second))
	ready = true
	server.applyApprovalState(request, popupNow.Add(2*time.Second))
	server.applyApprovalState(request, popupNow.Add(3*time.Second))
	// The flash is kept until a show succeeds.
	want := []popupCall{{PopupRequest, true}, {PopupRequest, true}, {PopupRequest, true}}
	if len(shows) != len(want) {
		t.Fatalf("show calls %#v, want %#v", shows, want)
	}
	for i := range want {
		if shows[i] != want[i] {
			t.Fatalf("show calls %#v, want %#v", shows, want)
		}
	}
	server.applyApprovalState(remotehost.Status{ActiveSessionID: "live"}, popupNow.Add(4*time.Second))
	if last := shows[len(shows)-1]; last != (popupCall{PopupSession, false}) {
		t.Fatalf("session indicator not shown: %#v", last)
	}
	server.applyApprovalState(remotehost.Status{}, popupNow.Add(5*time.Second))
	server.applyApprovalState(remotehost.Status{}, popupNow.Add(6*time.Second))
	if hides != 1 || server.popupMode != PopupHidden {
		t.Fatalf("hide calls %d, mode %q", hides, server.popupMode)
	}
}

func TestApprovalTickWithoutHostHidesPopup(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken, StatePath: t.TempDir() + "/state.json"})
	shown, hidden := 0, 0
	server.SetApprovalPopup(func(string, bool) bool { shown++; return true }, func() { hidden++ })
	server.popupMode = PopupRequest
	server.approvalTick(t.Context())
	if shown != 0 || hidden != 1 || server.popupMode != PopupHidden {
		t.Fatalf("signed-out tick: shown %d hidden %d mode %q", shown, hidden, server.popupMode)
	}
}

func TestPopupEndpointRequiresDesktopSessionAndKnownKeys(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken})
	server.popupTracker.update(remotehost.Status{Pending: []remotehost.ApprovalEvent{{Kind: "pairing_display", ID: "p1", DisplayCode: "1", ExpiresAt: time.Now().Add(time.Minute)}}}, time.Now())
	handler := server.Handler()
	call := func(body string, authorized bool) int {
		request := trustedLocalRequest(http.MethodPost, "/local/remote/popup", strings.NewReader(body))
		if !authorized {
			request.Header.Del("Authorization")
		}
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, request)
		return recorder.Code
	}
	if code := call(`{"action":"refresh"}`, false); code != http.StatusUnauthorized {
		t.Fatalf("popup endpoint without the desktop session: %d", code)
	}
	if code := call(`{"action":"refresh"}`, true); code != http.StatusOK {
		t.Fatalf("refresh: %d", code)
	}
	select {
	case <-server.popupPoke:
	default:
		t.Fatal("refresh did not wake the watcher")
	}
	if code := call(`{"action":"acknowledge","key":"access:unknown"}`, true); code != http.StatusNotFound {
		t.Fatalf("unknown key: %d", code)
	}
	if code := call(`{"action":"acknowledge","key":"pairing_display:p1"}`, true); code != http.StatusOK || !server.popupTracker.acknowledged["pairing_display:p1"] {
		t.Fatalf("acknowledge: %d", code)
	}
	// The popup cannot approve anything through its own endpoint.
	for _, body := range []string{`{"action":"approve","key":"pairing_display:p1"}`, `{"action":"show"}`, `not json`} {
		if code := call(body, true); code != http.StatusBadRequest {
			t.Fatalf("%s: %d", body, code)
		}
	}
	request := trustedLocalRequest(http.MethodGet, "/local/remote/popup", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET popup action: %d", recorder.Code)
	}
}

func TestPopupPageIsEmbeddedWithoutSecrets(t *testing.T) {
	server := New(Options{LocalToken: testLocalToken})
	handler := server.Handler()
	for _, path := range []string{"/popup.html", "/popup.js", "/popup.css"} {
		request := trustedLocalRequest(http.MethodGet, path, nil)
		request.Header.Del("Authorization")
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, request)
		body, _ := io.ReadAll(recorder.Body)
		if recorder.Code != http.StatusOK || len(body) == 0 {
			t.Fatalf("%s: %d", path, recorder.Code)
		}
		if strings.Contains(string(body), testLocalToken) {
			t.Fatalf("%s embeds the desktop session", path)
		}
		if recorder.Header().Get("X-Frame-Options") != "DENY" || recorder.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("%s is served without the local UI headers", path)
		}
	}
}
