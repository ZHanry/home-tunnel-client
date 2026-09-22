package remotehost

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestRealControlCenterInterop(t *testing.T) {
	if os.Getenv("HT_SERVER_ROOT") == "" {
		t.Skip("set HT_SERVER_ROOT to a built home-tunnel-server checkout for cross-repository integration")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "node", "testdata/fixture-server.mjs")
	var stderr bytes.Buffer
	command.Stderr = &stderr
	stdout, e := command.StdoutPipe()
	if e != nil {
		t.Fatal(e)
	}
	stdin, e := command.StdinPipe()
	if e != nil {
		t.Fatal(e)
	}
	if e = command.Start(); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = stdin.Close(); cancel(); _ = command.Wait() })
	lines := make(chan []byte, 8)
	go func() {
		defer close(lines)
		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 4096), 262144)
		for scanner.Scan() {
			if raw, found := strings.CutPrefix(scanner.Text(), "HT_FIXTURE "); found {
				select {
				case lines <- []byte(raw):
				case <-ctx.Done():
					return
				}
			}
		}
	}()
	read := func(target any) {
		t.Helper()
		select {
		case raw, open := <-lines:
			if !open {
				t.Fatalf("fixture exited: %s", stderr.String())
			}
			if e := strictDecode(raw, target, false); e != nil {
				t.Fatal(e)
			}
		case <-ctx.Done():
			t.Fatal("fixture timed out")
		}
	}
	var meta struct {
		Origin       string `json:"origin"`
		AccountToken string `json:"account_token"`
		DeviceID     string `json:"device_id"`
		ControllerID string `json:"controller_id"`
	}
	read(&meta)
	rpc := func(action string, fields map[string]any, target any) {
		t.Helper()
		if fields == nil {
			fields = map[string]any{}
		}
		fields["action"] = action
		raw, _ := json.Marshal(fields)
		if _, e := fmt.Fprintln(stdin, string(raw)); e != nil {
			t.Fatal(e)
		}
		var response struct {
			Result json.RawMessage `json:"result"`
			Error  string          `json:"error"`
		}
		read(&response)
		if response.Error != "" {
			t.Fatal(response.Error)
		}
		if target != nil {
			if e := strictDecode(response.Result, target, false); e != nil {
				t.Fatal(e)
			}
		}
	}
	engine := &fakeEngine{available: true, events: make(chan EngineEvent, 8)}
	service, e := New(Config{Origin: meta.Origin, Store: testStore(t), Engine: engine, AllowInsecureLoopback: true, AccountToken: func(context.Context) (string, error) { return meta.AccountToken, nil }, InitialTrust: func(context.Context, string, Keyset) error { return nil }})
	if e != nil {
		t.Fatal(e)
	}
	if e = service.Enroll(ctx, Enrollment{LinkedDeviceID: meta.DeviceID, Name: "Go host", Platform: "windows"}); e != nil {
		t.Fatal(e)
	}
	if e = service.SetEnabled(ctx, true); e != nil {
		t.Fatal(e)
	}
	runCtx, stopRun := context.WithCancel(ctx)
	defer stopRun()
	runResult := make(chan error, 1)
	go func() { runResult <- service.Run(runCtx) }()
	waitApproval := func(kind string) ApprovalEvent {
		t.Helper()
		for {
			select {
			case event := <-service.Approvals():
				if event.Kind == kind {
					return event
				}
			case e := <-runResult:
				t.Fatalf("host run failed: %v", e)
			case <-ctx.Done():
				t.Fatal("approval timed out")
			}
		}
	}
	var pair struct {
		ID        string `json:"id"`
		RequestID string `json:"request_id"`
	}
	rpc("pair", map[string]any{"host_id": service.State(ctx).EndpointID}, &pair)
	approval := waitApproval("pairing")
	if approval.ID != pair.ID || approval.ControllerEndpointID != meta.ControllerID {
		t.Fatal("pair identity lost")
	}
	if e = service.ApprovePairing(ctx, pair.ID, approval.Permissions, approval.Mode, time.Now().Add(10*time.Minute)); e != nil {
		t.Fatal(e)
	}
	display := waitApproval("pairing_display")
	var confirmed struct {
		Display string `json:"display_code"`
	}
	rpc("confirm", nil, &confirmed)
	if display.DisplayCode == "" || display.DisplayCode != confirmed.Display {
		t.Fatal("pairing canonical display mismatch")
	}
	var session Session
	rpc("create", nil, &session)
	request := waitApproval("session")
	if request.ID != session.ID {
		t.Fatal("session identity lost")
	}
	if e = service.ApproveSession(ctx, session.ID); e != nil {
		t.Fatal(e)
	}
	engine.mu.Lock()
	started := append([]StartRequest(nil), engine.started...)
	engine.mu.Unlock()
	if len(started) != 1 || started[0].SessionRequestID != pair.RequestID || started[0].DisplayID != "display-1" || started[0].TicketJWS == "" || started[0].GrantJWS == "" || started[0].LocalGrantRevoked {
		t.Fatal("native authorization lost bindings")
	}
	var offer struct {
		Compact string `json:"compact"`
	}
	rpc("offer", nil, &offer)
	waitUntil := func(check func() bool) {
		t.Helper()
		timer := time.NewTimer(5 * time.Second)
		defer timer.Stop()
		tick := time.NewTicker(10 * time.Millisecond)
		defer tick.Stop()
		for !check() {
			select {
			case <-tick.C:
			case e := <-runResult:
				t.Fatalf("host run failed: %v", e)
			case <-timer.C:
				t.Fatal("condition timed out")
			}
		}
	}
	waitUntil(func() bool {
		engine.mu.Lock()
		defer engine.mu.Unlock()
		for _, raw := range engine.signals {
			var outer struct {
				Payload string `json:"payload_jws"`
			}
			_ = json.Unmarshal(raw, &outer)
			if outer.Payload == offer.Compact {
				return true
			}
		}
		return false
	})
	payload, _ := json.Marshal(map[string]string{"type": "answer", "sdp": "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=fingerprint:sha-256 " + started[0].Prepared.DTLSFingerprintSHA256 + "\r\n"})
	engine.events <- EngineEvent{SessionRef: session.SessionRef, Kind: "outgoing_signal", SignalType: "peer.answer", Payload: payload}
	var answer struct {
		Compact string `json:"compact"`
	}
	rpc("answer", nil, &answer)
	if answer.Compact == "" {
		t.Fatal("missing signed answer")
	}
	rpc("ready", nil, nil)
	engine.events <- EngineEvent{SessionRef: session.SessionRef, Kind: "verified_ready"}
	waitUntil(func() bool {
		service.mu.Lock()
		defer service.mu.Unlock()
		return service.active != nil && service.active.Session.State == "active"
	})
	rpc("age_lease", nil, nil)
	service.mu.Lock()
	service.active.LastRenew = time.Now().Add(-241 * time.Second)
	service.mu.Unlock()
	if e = service.tick(ctx); e != nil {
		t.Fatal(e)
	}
	service.mu.Lock()
	leaseSequence := service.active.Session.LeaseSeq
	service.mu.Unlock()
	if leaseSequence != 2 {
		t.Fatal("renewal did not advance the native lease")
	}
	previous := session.SessionRef
	rpc("reconnect", nil, &session)
	if session.ConnectionEpoch != previous.ConnectionEpoch+1 {
		t.Fatal("reconnect epoch did not advance")
	}
	waitApproval("session")
	engine.events <- EngineEvent{SessionRef: previous, Kind: "closed"}
	waitUntil(func() bool { return service.State(ctx).ActiveSessionID == "" })
	if e = service.ApproveSession(ctx, session.ID); e != nil {
		t.Fatal(e)
	}
	engine.mu.Lock()
	startCount := len(engine.started)
	engine.mu.Unlock()
	if startCount != 2 {
		t.Fatal("reconnect did not receive a new independently prepared native session")
	}
	if e = service.Stop(ctx, "RD_CANCELLED"); e != nil {
		t.Fatal(e)
	}
	var state struct {
		State string `json:"state"`
		Slots int    `json:"slots"`
	}
	rpc("state", nil, &state)
	if state.State != "closing" || state.Slots == 0 {
		t.Fatal("slots released before native closed acknowledgment")
	}
	engine.events <- EngineEvent{SessionRef: session.SessionRef, Kind: "closed"}
	waitUntil(func() bool { return service.State(ctx).ActiveSessionID == "" })
	rpc("state", nil, &state)
	if state.State != "closed" || state.Slots != 0 {
		t.Fatalf("close acknowledgment failed: state=%s slots=%d", state.State, state.Slots)
	}
	stopRun()
	select {
	case <-runResult:
	case <-ctx.Done():
		t.Fatal("host did not stop")
	}
}
