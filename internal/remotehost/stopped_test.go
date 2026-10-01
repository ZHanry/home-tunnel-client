package remotehost

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type stoppedHostEngine struct {
	*fakeEngine
	failed      atomic.Bool
	wait        chan struct{}
	waitStarted chan struct{}
	waitErr     error
}

func (e *stoppedHostEngine) Close(ctx context.Context, ref SessionRef, reason string) error {
	if e.failed.Load() {
		return ErrUnavailable
	}
	return e.fakeEngine.Close(ctx, ref, reason)
}
func (e *stoppedHostEngine) WaitStopped(ctx context.Context) error {
	if !e.failed.Load() {
		return ErrUnavailable
	}
	if e.waitStarted != nil {
		select {
		case e.waitStarted <- struct{}{}:
		default:
		}
	}
	select {
	case <-e.wait:
		return e.waitErr
	default:
	}
	select {
	case <-e.wait:
		return e.waitErr
	case <-ctx.Done():
		return ctx.Err()
	}
}

func stoppedHostFixture(t *testing.T) (*Service, *runningSession, *stoppedHostEngine, *atomic.Int64) {
	t.Helper()
	s, r := approvalFixture(t)
	s.active = r
	s.pending[r.Session.SessionID] = r.Session
	e := &stoppedHostEngine{fakeEngine: &fakeEngine{available: true, events: make(chan EngineEvent, 8)}, wait: make(chan struct{}), waitStarted: make(chan struct{}, 4)}
	e.failed.Store(true)
	s.config.Engine = e
	acks := &atomic.Int64{}
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if strings.HasSuffix(request.URL.Path, "/close-ack") {
			var body struct {
				Epoch    int64  `json:"connection_epoch"`
				Sequence int64  `json:"lease_seq"`
				Proof    string `json:"signed_proof"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			proof, err := verifyJWS(body.Proof, jwk(&s.key.PublicKey), "ht-rd-session+jwt")
			if err != nil {
				t.Error("close proof invalid", err)
			}
			var claims struct {
				Type     string `json:"type"`
				ID       string `json:"session_id"`
				Epoch    int64  `json:"connection_epoch"`
				Sequence int64  `json:"lease_seq"`
				Stopped  bool   `json:"stopped"`
			}
			if err := json.Unmarshal(proof, &claims); err != nil || claims.Type != "session.close_ack" || claims.ID != r.Session.SessionID || claims.Epoch != r.Session.ConnectionEpoch || claims.Sequence != r.Session.LeaseSeq || !claims.Stopped || body.Epoch != claims.Epoch || body.Sequence != claims.Sequence {
				t.Error("close proof binding lost", err)
			}
			acks.Add(1)
		} else if !strings.HasSuffix(request.URL.Path, "/report") && !strings.HasSuffix(request.URL.Path, "/decision") {
			t.Error("unexpected request", request.URL.Path)
		}
		return fixtureResponse(map[string]any{}), nil
	})
	return s, r, e, acks
}

func TestStopAcknowledgesOnlyConfirmedProcessExit(t *testing.T) {
	s, r, engine, acks := stoppedHostFixture(t)
	result := make(chan error, 1)
	go func() { result <- s.Stop(context.Background(), "RD_BACKEND_UNAVAILABLE") }()
	<-engine.waitStarted
	if acks.Load() != 0 || s.State(context.Background()).ActiveSessionID != r.Session.SessionID {
		t.Fatal("unreaped process released local/server session")
	}
	close(engine.wait)
	if err := awaitResult(t, result); !errors.Is(err, ErrUnavailable) {
		t.Fatal("lost backend failure", err)
	}
	if acks.Load() != 1 || s.State(context.Background()).ActiveSessionID != "" || len(s.config.Store.closeAcks()) != 0 {
		t.Fatal("confirmed exit did not settle session")
	}
	if err := s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "closed"}, nil); err != nil {
		t.Fatal(err)
	}
	if err := s.Stop(context.Background(), "repeat"); err != nil || acks.Load() != 1 {
		t.Fatal("duplicate close acknowledged twice", err)
	}
}

func TestStopDoesNotAcknowledgeUnconfirmedExit(t *testing.T) {
	for _, failure := range []error{ErrUnavailable, context.DeadlineExceeded} {
		s, r, engine, acks := stoppedHostFixture(t)
		engine.waitErr = failure
		close(engine.wait)
		if err := s.Stop(context.Background(), "crash"); err == nil {
			t.Fatal("missing crash error")
		}
		if acks.Load() != 0 || s.State(context.Background()).ActiveSessionID != r.Session.SessionID {
			t.Fatal("unconfirmed stop released session")
		}
	}
}

func TestConfirmedOldProcessDoesNotAcknowledgeReplacement(t *testing.T) {
	s, r, engine, acks := stoppedHostFixture(t)
	result := make(chan error, 1)
	go func() { result <- s.Stop(context.Background(), "crash") }()
	<-engine.waitStarted
	next := *r
	next.Session.ConnectionEpoch++
	s.mu.Lock()
	s.active = &next
	s.mu.Unlock()
	close(engine.wait)
	_ = awaitResult(t, result)
	if acks.Load() != 0 || s.active != &next {
		t.Fatal("old process stop released replacement")
	}
}

func TestNativeCloseRetainsDebtOnTransientHTTPFailure(t *testing.T) {
	s, r, _, _ := stoppedHostFixture(t)
	var status atomic.Int64
	status.Store(http.StatusServiceUnavailable)
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		response := fixtureResponse(map[string]any{"error_code": "RD_TEMPORARY_FAILURE"})
		response.StatusCode = int(status.Load())
		return response, nil
	})
	if err := s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "closed"}, nil); err == nil {
		t.Fatal("HTTP failure hidden")
	}
	if s.active != nil || len(s.config.Store.closeAcks()) != 1 {
		t.Fatal("stopped local session or retry debt incorrect")
	}
	status.Store(http.StatusOK)
	if err := s.flushOwedAcks(context.Background()); err != nil || len(s.config.Store.closeAcks()) != 0 {
		t.Fatal("owed acknowledgment not retried", err)
	}
}

func TestCloseAckConflictReconcilesOnlyStoppedEpoch(t *testing.T) {
	for _, scenario := range []string{"renewed", "superseded", "terminal", "live", "older_epoch", "zero_lease"} {
		t.Run(scenario, func(t *testing.T) {
			s, r, _, _ := stoppedHostFixture(t)
			current := r.Session
			current.State = "active"
			switch scenario {
			case "renewed":
				current.LeaseSeq++
			case "superseded":
				current.ConnectionEpoch++
			case "terminal":
				current.State = "closed"
			case "older_epoch":
				r.Session.ConnectionEpoch++
				current.LeaseSeq++
			case "zero_lease":
				r.Session.LeaseSeq = 0
			}
			var posts atomic.Int64
			s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
				if request.Method == "GET" {
					return fixtureResponse(current), nil
				}
				count := posts.Add(1)
				if count == 2 && (scenario == "renewed" || scenario == "zero_lease") {
					var body struct {
						Epoch    int64 `json:"connection_epoch"`
						Sequence int64 `json:"lease_seq"`
					}
					if err := json.NewDecoder(request.Body).Decode(&body); err != nil || body.Epoch != r.Session.ConnectionEpoch || body.Sequence != current.LeaseSeq {
						t.Error("renewal acknowledgment escaped stopped epoch", err)
					}
					return fixtureResponse(map[string]any{}), nil
				}
				response := fixtureResponse(map[string]any{"error_code": "RD_STATE_CONFLICT"})
				response.StatusCode = http.StatusConflict
				return response, nil
			})
			err := s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "closed"}, nil)
			if scenario == "live" || scenario == "older_epoch" {
				if err == nil || len(s.config.Store.closeAcks()) != 1 {
					t.Fatal("live conflicting session debt discarded", err)
				}
			} else if err != nil || len(s.config.Store.closeAcks()) != 0 {
				t.Fatal("settled session retained debt", err)
			}
			want := int64(1)
			if scenario == "renewed" || scenario == "zero_lease" {
				want = 2
			}
			if posts.Load() != want {
				t.Fatal("unexpected close acknowledgment count", posts.Load())
			}
		})
	}
}

func TestConfirmedStopWaitIsBoundedByCaller(t *testing.T) {
	s, r, _, acks := stoppedHostFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_ = s.Stop(ctx, "crash")
	if acks.Load() != 0 || s.State(context.Background()).ActiveSessionID != r.Session.SessionID {
		t.Fatal("timeout falsely confirmed stop")
	}
}

func TestStoppedDebtSurvivesReplacementService(t *testing.T) {
	for _, failure := range []string{"429", "503", "network", "disk"} {
		t.Run(failure, func(t *testing.T) {
			s, r, _, _ := stoppedHostFixture(t)
			backend := s.config.Store.backend.(*memoryBackend)
			backend.fail = failure == "disk"
			s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
				if failure == "network" || failure == "disk" {
					return nil, errors.New("fixture offline")
				}
				response := fixtureResponse(map[string]any{"error_code": "RD_TEMPORARY_FAILURE"})
				response.StatusCode = http.StatusServiceUnavailable
				if failure == "429" {
					response.StatusCode = http.StatusTooManyRequests
				}
				return response, nil
			})
			if err := s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "closed"}, nil); err == nil {
				t.Fatal("lost failure")
			}
			owed := s.config.Store.closeAcks()
			if len(owed) != 1 || s.active != nil {
				t.Fatal("stopped debt lost")
			}
			config := s.config
			backend.fail = false
			if failure != "disk" {
				var err error
				config.Store, err = openStore(backend)
				if err != nil {
					t.Fatal("could not reload protected debt", err)
				}
			}
			config.Engine = &fakeEngine{available: true, events: make(chan EngineEvent, 8)}
			next, err := New(config)
			if err != nil {
				t.Fatal(err)
			}
			next.token = s.token
			nextSession := *r
			nextSession.Session.ConnectionEpoch++
			nextSession.Stopped = false
			next.active = &nextSession
			next.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
				if !strings.HasSuffix(request.URL.Path, "/close-ack") {
					t.Error("unexpected request", request.URL.Path)
				}
				var body struct {
					Proof    string `json:"signed_proof"`
					Epoch    int64  `json:"connection_epoch"`
					Sequence int64  `json:"lease_seq"`
				}
				if err := json.NewDecoder(request.Body).Decode(&body); err != nil || body.Proof != owed[0].SignedProof || body.Epoch != owed[0].ConnectionEpoch || body.Sequence != owed[0].LeaseSeq {
					t.Error("replacement changed the old stopped proof", err)
				}
				return fixtureResponse(map[string]any{}), nil
			})
			if err = next.flushOwedAcks(context.Background()); err != nil || len(config.Store.closeAcks()) != 0 {
				t.Fatal("replacement did not settle debt", err)
			}
			if next.active != &nextSession || nextSession.Stopped {
				t.Fatal("old debt stopped new worker session")
			}
			reloaded, err := openStore(backend)
			if err != nil || len(reloaded.closeAcks()) != 0 {
				t.Fatal("settled debt remained on disk", err)
			}
			if strings.Contains(string(backend.data), `"close_acks"`) {
				t.Fatal("empty debt changed legacy store schema")
			}
		})
	}
}

func TestConfirmedStopNeverIssuesUnboundClose(t *testing.T) {
	for _, success := range []bool{true, false} {
		s, r, engine, _ := stoppedHostFixture(t)
		close(engine.wait)
		var posts atomic.Int64
		s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
			if strings.HasSuffix(request.URL.Path, "/close") {
				t.Error("old Stop issued epoch-unbound close after recording stopped proof")
				<-request.Context().Done()
				return nil, request.Context().Err()
			}
			if !strings.HasSuffix(request.URL.Path, "/close-ack") {
				t.Error("unexpected request")
			}
			posts.Add(1)
			if success {
				// Model a same-ID reconnect immediately after the exact old ack.
				next := *r
				next.Stopped = false
				next.Session.ConnectionEpoch++
				s.mu.Lock()
				s.active = &next
				s.mu.Unlock()
				return fixtureResponse(map[string]any{}), nil
			}
			response := fixtureResponse(map[string]any{"error_code": "RD_TEMPORARY_FAILURE"})
			response.StatusCode = http.StatusServiceUnavailable
			return response, nil
		})
		ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
		_ = s.Stop(ctx, "crash")
		if ctx.Err() != nil {
			t.Fatal("HTTP close consumed the shutdown deadline")
		}
		cancel()
		if posts.Load() != 1 {
			t.Fatal("missing exact ack")
		}
		if success && (s.active == nil || s.active.Session.ConnectionEpoch != r.Session.ConnectionEpoch+1) {
			t.Fatal("old Stop cleared replacement")
		}
		if !success && len(s.config.Store.closeAcks()) != 1 {
			t.Fatal("failed ack lost debt")
		}
	}
}

func TestStoppedDebtRejectsTamperingAndKeepsEpochsSeparate(t *testing.T) {
	s, r, _, _ := stoppedHostFixture(t)
	old, err := s.makeCloseAck(r.Session.SessionRef, r.Session.LeaseSeq)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.config.Store.rememberCloseAck(old); err != nil {
		t.Fatal(err)
	}
	nextRef := r.Session.SessionRef
	nextRef.ConnectionEpoch++
	next, err := s.makeCloseAck(nextRef, r.Session.LeaseSeq)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.config.Store.rememberCloseAck(next); err != nil {
		t.Fatal(err)
	}
	if _, err = s.config.Store.changeCloseAck(old, nil); err != nil {
		t.Fatal(err)
	}
	owed := s.config.Store.closeAcks()
	if len(owed) != 1 || owed[0] != next {
		t.Fatal("old proof removed another epoch")
	}
	backend := s.config.Store.backend.(*memoryBackend)
	var state diskState
	if err = json.Unmarshal(backend.data, &state); err != nil {
		t.Fatal(err)
	}
	bad := next
	bad.LeaseSeq++
	state.CloseAcks[next.key()] = bad
	backend.data, _ = json.Marshal(state)
	if _, err = openStore(backend); err == nil {
		t.Fatal("tampered stop metadata accepted")
	}
}

func TestStopReportAndNativeAckAreSerialized(t *testing.T) {
	for _, closeFirst := range []bool{false, true} {
		s, r, engine, _ := stoppedHostFixture(t)
		engine.failed.Store(false)
		r.Session.State = "active"
		entered, release := make(chan struct{}), make(chan struct{})
		var ackPosts, closePosts atomic.Int64
		s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
			if strings.HasSuffix(request.URL.Path, "/report") {
				closePosts.Add(1)
				if !closeFirst {
					t.Error("failure report sent after native stop was recorded")
				} else {
					close(entered)
					<-release
				}
			} else if strings.HasSuffix(request.URL.Path, "/close-ack") {
				ackPosts.Add(1)
			} else {
				t.Error("unexpected request", request.URL.Path)
			}
			return fixtureResponse(map[string]any{}), nil
		})
		gateDone := make(chan error, 1)
		if !closeFirst {
			go func() {
				gateDone <- s.config.Store.withCloseRequest(context.Background(), func() error {
					close(entered)
					<-release
					return nil
				})
			}()
			<-entered
		}
		stopped := make(chan error, 1)
		go func() { stopped <- s.Stop(context.Background(), "normal-close") }()
		if closeFirst {
			<-entered
		} else {
			deadline := time.After(time.Second)
			for {
				s.mu.Lock()
				closing := r.Closing
				s.mu.Unlock()
				if closing {
					break
				}
				select {
				case <-deadline:
					t.Fatal("Stop did not latch")
				default:
					time.Sleep(time.Millisecond)
				}
			}
		}
		acknowledged := make(chan error, 1)
		go func() {
			acknowledged <- s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "closed"}, nil)
		}()
		deadline := time.After(time.Second)
		for len(s.config.Store.closeAcks()) == 0 {
			select {
			case <-deadline:
				t.Fatal("native stop was not saved ahead of network wait")
			default:
				time.Sleep(time.Millisecond)
			}
		}
		if ackPosts.Load() != 0 {
			t.Fatal("ack overtook in-flight failure report")
		}
		close(release)
		if !closeFirst {
			if err := awaitResult(t, gateDone); err != nil {
				t.Fatal(err)
			}
		}
		if err := awaitResult(t, stopped); err != nil {
			t.Fatal(err)
		}
		if err := awaitResult(t, acknowledged); err != nil {
			t.Fatal(err)
		}
		wantCloses := int64(0)
		if closeFirst {
			wantCloses = 1
		}
		if ackPosts.Load() != 1 || closePosts.Load() != wantCloses {
			t.Fatal("wrong close ordering/count")
		}
	}
}

func TestStoppedProofSurvivesCloseGateDeadline(t *testing.T) {
	s, r, engine, _ := stoppedHostFixture(t)
	close(engine.wait)
	entered, release := make(chan struct{}), make(chan struct{})
	gateDone := make(chan error, 1)
	go func() {
		gateDone <- s.config.Store.withCloseRequest(context.Background(), func() error {
			close(entered)
			<-release
			return nil
		})
	}()
	<-entered
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_ = s.Stop(ctx, "crash")
	if s.active != nil || len(s.config.Store.closeAcks()) != 1 {
		t.Fatal("blocked HTTP gate lost stopped proof")
	}
	close(release)
	if err := awaitResult(t, gateDone); err != nil {
		t.Fatal(err)
	}
	if err := s.flushOwedAcks(context.Background()); err != nil {
		t.Fatal(err)
	}
	if r.Stopped != true || len(s.config.Store.closeAcks()) != 0 {
		t.Fatal("deferred stopped proof not settled")
	}
}

func TestConfirmedStopDuringDecisionReconcilesZeroLease(t *testing.T) {
	s, fixture := approvalFixture(t)
	pending := fixture.Session
	pending.LeaseSeq = 0
	authorized := fixture.Session
	authorized.State, authorized.StateVersion = "authorized", 2
	engine := &stoppedHostEngine{fakeEngine: s.config.Engine.(*fakeEngine), wait: make(chan struct{})}
	s.config.Engine = engine
	entered, release := make(chan struct{}), make(chan struct{})
	var committed atomic.Bool
	var ackPosts atomic.Int64
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if request.Method == "GET" {
			if committed.Load() {
				return fixtureResponse(authorized), nil
			}
			return fixtureResponse(pending), nil
		}
		if strings.HasSuffix(request.URL.Path, "/decision") {
			committed.Store(true)
			close(entered)
			<-release
			return fixtureResponse(authorized), nil
		}
		if !strings.HasSuffix(request.URL.Path, "/close-ack") {
			t.Error("unexpected shutdown mutation", request.URL.Path)
		}
		var body struct {
			Epoch    int64 `json:"connection_epoch"`
			Sequence int64 `json:"lease_seq"`
		}
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		count := ackPosts.Add(1)
		if body.Epoch != pending.ConnectionEpoch || body.Sequence != count-1 {
			t.Error("wrong in-flight decision proof binding", body, count)
		}
		if count == 1 {
			response := fixtureResponse(map[string]any{"error_code": "RD_STATE_CONFLICT"})
			response.StatusCode = http.StatusConflict
			return response, nil
		}
		return fixtureResponse(map[string]any{}), nil
	})
	approval := make(chan error, 1)
	go func() { approval <- s.ApproveSession(context.Background(), pending.SessionID) }()
	<-entered
	engine.failed.Store(true)
	close(engine.wait)
	if err := s.Stop(context.Background(), "crash"); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	if ackPosts.Load() != 2 || s.active != nil || len(s.config.Store.closeAcks()) != 0 {
		t.Fatal("in-flight authorized lease did not settle")
	}
	close(release)
	if err := awaitResult(t, approval); err == nil {
		t.Fatal("stopped approval succeeded")
	}
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if len(engine.started) != 0 {
		t.Fatal("dead producer started after late decision response")
	}
}

func TestShutdownFallbackRetriesOnlyExactEpoch(t *testing.T) {
	for _, scenario := range []string{"authorized", "pending", "replacement"} {
		t.Run(scenario, func(t *testing.T) {
			s, r, engine, _ := stoppedHostFixture(t)
			engine.failed.Store(false)
			if scenario != "pending" {
				r.Session.State = "active"
			}
			current := r.Session
			current.State, current.StateVersion = "authorized", r.Session.StateVersion+1
			if scenario == "replacement" {
				current.ConnectionEpoch++
			}
			var posts atomic.Int64
			s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
				if request.Method == "GET" {
					return fixtureResponse(current), nil
				}
				count := posts.Add(1)
				var body struct {
					Phase    string `json:"phase"`
					Decision string `json:"decision"`
					Epoch    int64  `json:"connection_epoch"`
					Version  int64  `json:"expected_version"`
					Proof    string `json:"signed_proof"`
				}
				if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if scenario == "pending" && count == 1 {
					if !strings.HasSuffix(request.URL.Path, "/decision") || body.Decision != "reject" {
						t.Error("pending stop was not rejected")
					}
					raw, err := verifyJWS(body.Proof, jwk(&s.key.PublicKey), "ht-rd-session+jwt")
					var claims struct {
						SessionRef
						Decision string `json:"decision"`
					}
					if err != nil || json.Unmarshal(raw, &claims) != nil || claims.SessionRef != r.Session.SessionRef || claims.Decision != "reject" {
						t.Error("rejection lost exact epoch", err)
					}
				} else if !strings.HasSuffix(request.URL.Path, "/report") || body.Epoch != r.Session.ConnectionEpoch || body.Phase != "failed" {
					t.Error("stop report lost exact epoch")
				}
				if body.Version != r.Session.StateVersion+count-1 {
					t.Error("wrong state version")
				}
				if count == 1 {
					response := fixtureResponse(map[string]any{"error_code": "RD_STATE_CONFLICT"})
					response.StatusCode = http.StatusConflict
					return response, nil
				}
				return fixtureResponse(map[string]any{}), nil
			})
			if err := s.Stop(context.Background(), "stop"); err != nil {
				t.Fatal(err)
			}
			want := int64(2)
			if scenario == "replacement" {
				want = 1
			}
			if posts.Load() != want {
				t.Fatal("wrong bounded retry count", posts.Load())
			}
		})
	}
}

func TestFailedDisablePersistenceRetainsConfirmedStopLocally(t *testing.T) {
	s, _, engine, _ := stoppedHostFixture(t)
	close(engine.wait)
	backend := s.config.Store.backend.(*memoryBackend)
	backend.fail = true
	s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		t.Error("failed disable started network request", request.URL.Path)
		return nil, errors.New("unexpected request")
	})
	if err := s.SetEnabled(context.Background(), false); err == nil {
		t.Fatal("disk failure hidden")
	}
	if s.active != nil || len(s.config.Store.closeAcks()) != 1 {
		t.Fatal("failed disable lost verified stop debt")
	}
	backend.fail = false
	next, err := New(s.config)
	if err != nil || len(next.config.Store.closeAcks()) != 1 {
		t.Fatal("replacement lost locally retained proof", err)
	}
}

func TestVisibleRejectionCannotMutateReplacement(t *testing.T) {
	for _, serverReplaced := range []bool{false, true} {
		s, r := approvalFixture(t)
		s.pending[r.Session.SessionID] = r.Session
		entered, release := make(chan struct{}), make(chan struct{})
		var mutations atomic.Int64
		s.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
			if request.Method == "GET" {
				return fixtureResponse(r.Session), nil
			}
			if !strings.HasSuffix(request.URL.Path, "/decision") {
				t.Error("visible rejection used unbound endpoint", request.URL.Path)
			}
			var body struct {
				Decision string `json:"decision"`
				Version  int64  `json:"expected_version"`
				Proof    string `json:"signed_proof"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			raw, err := verifyJWS(body.Proof, jwk(&s.key.PublicKey), "ht-rd-session+jwt")
			var claims struct {
				SessionRef
				Decision string `json:"decision"`
				Version  int64  `json:"expected_version"`
			}
			if err != nil || json.Unmarshal(raw, &claims) != nil || claims.SessionRef != r.Session.SessionRef || claims.Decision != "reject" || claims.Version != r.Session.StateVersion || body.Decision != "reject" || body.Version != claims.Version {
				t.Error("visible rejection lost signed epoch/revision binding", err)
			}
			close(entered)
			<-release
			if serverReplaced {
				response := fixtureResponse(map[string]any{"error_code": "RD_VERSION_CONFLICT"})
				response.StatusCode = http.StatusConflict
				return response, nil
			}
			mutations.Add(1)
			return fixtureResponse(map[string]any{}), nil
		})
		result := make(chan error, 1)
		go func() {
			result <- s.RejectSessionExpected(context.Background(), r.Session.SessionID, r.Session.ConnectionEpoch, r.Session.StateVersion)
		}()
		<-entered
		next := r.Session
		next.ConnectionEpoch++
		next.StateVersion++
		s.mu.Lock()
		s.pending[next.SessionID] = next
		s.mu.Unlock()
		close(release)
		err := awaitResult(t, result)
		if serverReplaced != (err != nil) {
			t.Fatal("wrong stale decision result", err)
		}
		if serverReplaced && mutations.Load() != 0 {
			t.Fatal("stale rejection mutated server replacement")
		}
		if s.pending[next.SessionID].SessionRef != next.SessionRef {
			t.Fatal("late rejection cleared newer local approval")
		}
	}
}
