package remotehost

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

type fixtureTransport func(*http.Request) (*http.Response, error)

func (f fixtureTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if r.URL.Path == "/api/v1/public/capabilities" {
		return fixtureResponse(map[string]any{"remote_desktop": map[string]any{"enabled": true, "protocol": map[string]any{"major": 1}, "signal_path": "/api/v1/rd/signal", "udp_only": true, "allow_turn": false, "allow_ice_tcp": false, "stun_urls": []string{}}}), nil
	}
	return f(r)
}
func fixtureResponse(value any) *http.Response {
	raw, _ := json.Marshal(value)
	return &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(raw)), Header: make(http.Header)}
}
func approvalFixture(t *testing.T) (*Service, *runningSession) {
	t.Helper()
	s, r, _ := authorityFixture(t)
	r.Session.State = "pending_approval"
	r.Session.StateVersion = 1
	r.Session.ApprovalExpiresAt = time.Now().Add(time.Minute)
	proof, _ := signJWS(s.key, "ht-rd-grant+jwt", map[string]any{"id": r.Grant.ID, "grant_version": r.Grant.Version}, false)
	r.Grant.GrantJWS = proof
	r.Session.GrantJWS = proof
	if e := s.config.Store.update(func(d *diskState) error { d.Grants[r.Grant.ID] = r.Grant; return nil }); e != nil {
		t.Fatal(e)
	}
	s.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	return s, r
}
func awaitResult(t *testing.T, result <-chan error) error {
	t.Helper()
	select {
	case e := <-result:
		return e
	case <-time.After(5 * time.Second):
		t.Fatal("operation blocked")
		return nil
	}
}
func TestStopDuringDecisionCannotStartNative(t *testing.T) {
	s, r := approvalFixture(t)
	entered, release := make(chan struct{}), make(chan struct{})
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if strings.HasSuffix(request.URL.Path, "/decision") {
			close(entered)
			<-release
			return fixtureResponse(r.Session), nil
		}
		if request.Method == "GET" {
			return fixtureResponse(r.Session), nil
		}
		return fixtureResponse(nil), nil
	})
	result := make(chan error, 1)
	go func() { result <- s.ApproveSession(context.Background(), r.Session.SessionID) }()
	<-entered
	if e := s.Stop(context.Background(), "fixture-stop"); e != nil {
		t.Fatal(e)
	}
	close(release)
	if awaitResult(t, result) == nil {
		t.Fatal("stopped approval succeeded")
	}
	engine := s.config.Engine.(*fakeEngine)
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if len(engine.started) != 0 {
		t.Fatal("native started after stop won the decision race")
	}
}

type blockedStartEngine struct {
	*fakeEngine
	entered chan struct{}
	release chan struct{}
}

func (e *blockedStartEngine) Start(ctx context.Context, r StartRequest) error {
	close(e.entered)
	<-e.release
	return e.fakeEngine.Start(ctx, r)
}
func TestStopWaitsOnlyForNativeStartThenCloses(t *testing.T) {
	s, r := approvalFixture(t)
	engine := &blockedStartEngine{fakeEngine: s.config.Engine.(*fakeEngine), entered: make(chan struct{}), release: make(chan struct{})}
	s.config.Engine = engine
	s.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) { return fixtureResponse(r.Session), nil })
	approval := make(chan error, 1)
	go func() { approval <- s.ApproveSession(context.Background(), r.Session.SessionID) }()
	<-engine.entered
	stop := make(chan error, 1)
	go func() { stop <- s.Stop(context.Background(), "fixture-stop") }()
	deadline := time.After(5 * time.Second)
	for {
		s.mu.Lock()
		closing := s.active != nil && s.active.Closing
		s.mu.Unlock()
		if closing {
			break
		}
		select {
		case <-deadline:
			t.Fatal("stop did not latch")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	close(engine.release)
	if awaitResult(t, approval) == nil {
		t.Fatal("closed native start became active")
	}
	if e := awaitResult(t, stop); e != nil {
		t.Fatal(e)
	}
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if len(engine.started) != 1 || engine.closed < 1 {
		t.Fatal("late native start was not closed")
	}
}
func TestDisableWinsInFlightEnable(t *testing.T) {
	s, _ := approvalFixture(t)
	entered, release := make(chan struct{}), make(chan struct{})
	var mu sync.Mutex
	var revisions []int64
	s.http.Transport = fixtureTransport(func(r *http.Request) (*http.Response, error) {
		var body struct {
			Enabled bool  `json:"local_enabled"`
			Version int64 `json:"capability_version"`
		}
		if e := json.NewDecoder(r.Body).Decode(&body); e != nil {
			return nil, e
		}
		mu.Lock()
		revisions = append(revisions, body.Version)
		mu.Unlock()
		if body.Enabled {
			close(entered)
			<-release
		}
		return fixtureResponse(nil), nil
	})
	enable := make(chan error, 1)
	go func() { enable <- s.SetEnabled(context.Background(), true) }()
	<-entered
	disable := make(chan error, 1)
	go func() { disable <- s.SetEnabled(context.Background(), false) }()
	deadline := time.After(5 * time.Second)
	for {
		s.mu.Lock()
		stopped := s.disabled && s.generation > 0
		s.mu.Unlock()
		if stopped {
			break
		}
		select {
		case <-deadline:
			t.Fatal("disable did not latch")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	close(release)
	if !errors.Is(awaitResult(t, enable), ErrLocalApproval) {
		t.Fatal("late enable did not fail")
	}
	if e := awaitResult(t, disable); e != nil {
		t.Fatal(e)
	}
	if s.State(context.Background()).Enabled || s.config.Store.snapshot().Enabled {
		t.Fatal("disable was overwritten")
	}
	mu.Lock()
	defer mu.Unlock()
	if len(revisions) != 2 || revisions[1] != revisions[0]+1 {
		t.Fatal("capability revisions were reused")
	}
}
func TestForeignSessionCloseDoesNotStopActiveHost(t *testing.T) {
	s, r := approvalFixture(t)
	s.active = r
	other := r.Session
	other.SessionID = randomID()
	other.ID = other.SessionID
	other.State = "closed"
	raw, _ := json.Marshal(map[string]any{"v": 1, "type": "session.updated", "session_id": other.SessionID, "connection_epoch": other.ConnectionEpoch, "payload": other})
	if e := s.handleServer(context.Background(), raw); e != nil {
		t.Fatal(e)
	}
	if r.Closing {
		t.Fatal("another session closed active capture")
	}
}
func TestVisibleApprovalIsBoundToEpochAndRevision(t *testing.T) {
	s, r := approvalFixture(t)
	s.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) { return fixtureResponse(r.Session), nil })
	if s.ApproveSessionExpected(context.Background(), r.Session.SessionID, r.Session.ConnectionEpoch+1, r.Session.StateVersion) == nil {
		t.Fatal("changed epoch approved")
	}
	if s.ApproveSessionExpected(context.Background(), r.Session.SessionID, r.Session.ConnectionEpoch, r.Session.StateVersion+1) == nil {
		t.Fatal("changed revision approved")
	}
	if s.RejectSessionExpected(context.Background(), r.Session.SessionID, r.Session.ConnectionEpoch+1, r.Session.StateVersion) == nil {
		t.Fatal("changed epoch rejected through stale UI")
	}
	s.pending[r.Session.SessionID] = r.Session
	status := s.State(context.Background())
	if len(status.Pending) != 1 || status.Pending[0].ControllerThumbprint != r.Grant.ControllerJKT || status.Pending[0].Mode != r.Grant.Mode || status.Pending[0].ConnectionEpoch != r.Session.ConnectionEpoch || status.Pending[0].StateVersion != r.Session.StateVersion {
		t.Fatal("approval UI lost authenticated context")
	}
}
func TestSTUNURLsForbidRelayCredentialsAndUnboundedPorts(t *testing.T) {
	for _, value := range []string{"turn:example.com:3478", "stuns:example.com:5349", "stun:user:password@example.com:3478", "stun:example.com:3478?transport=tcp", "stun:example.com:0", "stun:example.com:65536", "stun:-example.com:3478", "stun:example.com:+3478"} {
		if validSTUN(value) {
			t.Fatalf("accepted %q", value)
		}
	}
	for _, value := range []string{"stun:example.com:3478", "stun:192.168.1.5:3478", "stun:[2001:db8::1]:3478"} {
		if !validSTUN(value) {
			t.Fatalf("rejected %q", value)
		}
	}
}
func TestDisablePersistsBeforeCloseNetworkWait(t *testing.T) {
	s, r := approvalFixture(t)
	s.active = r
	entered, release := make(chan struct{}), make(chan struct{})
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if strings.HasSuffix(request.URL.Path, "/close") {
			close(entered)
			<-release
		}
		return fixtureResponse(nil), nil
	})
	result := make(chan error, 1)
	go func() { result <- s.SetEnabled(context.Background(), false) }()
	<-entered
	if s.config.Store.snapshot().Enabled {
		t.Fatal("network wait preceded durable disable")
	}
	engine := s.config.Engine.(*fakeEngine)
	engine.mu.Lock()
	closed := engine.closed
	engine.mu.Unlock()
	if closed == 0 {
		t.Fatal("network wait preceded native close")
	}
	close(release)
	if e := awaitResult(t, result); e != nil {
		t.Fatal(e)
	}
}
func TestFailedDisablePersistenceStillClosesNative(t *testing.T) {
	s, r := approvalFixture(t)
	s.active = r
	s.config.Store.backend.(*memoryBackend).fail = true
	s.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		t.Fatal("storage failure should return before network wait")
		return nil, errors.New("unexpected request")
	})
	if s.SetEnabled(context.Background(), false) == nil {
		t.Fatal("storage failure lost")
	}
	engine := s.config.Engine.(*fakeEngine)
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if engine.closed == 0 {
		t.Fatal("storage failure skipped native close")
	}
	if s.State(context.Background()).Enabled {
		t.Fatal("storage failure released disabled latch")
	}
}
