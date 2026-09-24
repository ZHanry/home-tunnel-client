package remotehost

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/realtime"
)

func (s *Service) Run(ctx context.Context) error {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return errors.New("remote host already online")
	}
	s.running = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.running = false
		s.mu.Unlock()
		stop, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = s.Stop(stop, "RD_SIGNAL_DISCONNECTED")
	}()
	d := s.config.Store.snapshot()
	if !d.Enabled || d.EndpointID == "" {
		return ErrLocalApproval
	}
	caps, e := s.config.Engine.Capabilities(ctx)
	if e != nil || !caps.Available || caps.Status != "ready" {
		return ErrUnavailable
	}
	changed, e := s.RefreshKeys(ctx)
	if e != nil {
		return e
	}
	if changed {
		return ErrLocalApproval
	}
	connection, e := realtime.DialRemote(ctx, s.origin, s.config.TLSConfig)
	if e != nil {
		return e
	}
	defer connection.Close()
	send := func(value any) error {
		raw, e := json.Marshal(value)
		if e != nil {
			return e
		}
		return connection.WriteEvent(raw)
	}
	raw, e := connection.ReadEvent(ctx)
	if e != nil {
		return e
	}
	var challenge struct {
		V            int    `json:"v"`
		Type         string `json:"type"`
		ConnectionID string `json:"connection_id"`
		Nonce        string `json:"nonce"`
	}
	if e = strictDecode(raw, &challenge, true); e != nil || challenge.V != 1 || challenge.Type != "auth.challenge" || challenge.ConnectionID == "" || len(challenge.Nonce) != 43 {
		return ErrAuthorization
	}
	authenticate := func(kind, connectionID, serverNonce string) error {
		purpose := "connect"
		if kind == "auth.reauth" {
			purpose = "reauth"
			s.tokenMu.Lock()
			s.token = onlineToken{}
			s.tokenMu.Unlock()
		}
		var ticket struct {
			Ticket      string `json:"ticket"`
			SignalPath  string `json:"signal_path"`
			Subprotocol string `json:"subprotocol"`
		}
		if e := s.request(ctx, "POST", "/signal-tickets", map[string]any{"purpose": purpose}, "dpop", &ticket); e != nil {
			return e
		}
		if ticket.SignalPath != "/api/v1/rd/signal" || ticket.Subprotocol != "ht.rd.signal.v1" {
			return ErrAuthorization
		}
		proof, e := signJWS(s.key, "ht-rd-signal+jwt", map[string]any{"connection_id": connectionID, "nonce": serverNonce, "ticket_hash": digest([]byte(ticket.Ticket)), "endpoint_id": d.EndpointID}, false)
		if e != nil {
			return e
		}
		return send(map[string]any{"v": 1, "type": kind, "ticket": ticket.Ticket, "proof": proof})
	}
	if e = authenticate("auth", challenge.ConnectionID, challenge.Nonce); e != nil {
		return e
	}
	readCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	incoming := make(chan json.RawMessage, 8)
	failures := make(chan error, 1)
	go func() {
		for {
			raw, e := connection.ReadEvent(readCtx)
			if e != nil {
				select {
				case failures <- e:
				case <-readCtx.Done():
				}
				return
			}
			select {
			case incoming <- raw:
			case <-readCtx.Done():
				return
			default:
				select {
				case failures <- errors.New("RD signaling queue full"):
				default:
				}
				_ = connection.Close()
				return
			}
		}
	}()
	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	heartbeat := time.NewTicker(60 * time.Second)
	defer heartbeat.Stop()
	authenticated := false
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case e := <-failures:
			return e
		case raw := <-incoming:
			var header struct {
				V            int    `json:"v"`
				Type         string `json:"type"`
				EndpointID   string `json:"endpoint_id"`
				ConnectionID string `json:"connection_id"`
				Nonce        string `json:"nonce"`
				ErrorCode    string `json:"error_code"`
			}
			if e = strictDecode(raw, &header, false); e != nil || header.V != 1 {
				return ErrAuthorization
			}
			switch header.Type {
			case "auth.ok", "auth.renewed":
				if header.EndpointID != d.EndpointID || header.ConnectionID != challenge.ConnectionID {
					return ErrAuthorization
				}
				authenticated = true
			case "auth.reauth_required":
				if !authenticated || header.ConnectionID != challenge.ConnectionID || len(header.Nonce) != 43 {
					return ErrAuthorization
				}
				if e = authenticate("auth.reauth", header.ConnectionID, header.Nonce); e != nil {
					return e
				}
			case "error":
				return &APIError{Status: 401, Code: "RD_SIGNAL_REJECTED"}
			default:
				if !authenticated {
					return ErrAuthorization
				}
				if e = s.handleServer(ctx, raw); e != nil {
					eventKind := "other"
					switch header.Type {
					case "peer.offer", "peer.answer", "peer.candidates", "peer.candidates_done", "session.authorized", "session.state", "session.lease_updated", "pairing.updated":
						eventKind = header.Type
					}
					return fmt.Errorf("server event %s: %w", eventKind, e)
				}
			}
		case event, open := <-s.config.Engine.Events():
			if !open {
				return ErrUnavailable
			}
			if !authenticated {
				return ErrAuthorization
			}
			if e = s.handleEngine(ctx, event, send); e != nil {
				return fmt.Errorf("engine event: %w", e)
			}
		case <-heartbeat.C:
			if authenticated {
				if e = send(map[string]any{"v": 1, "type": "ping"}); e != nil {
					return e
				}
			}
		case <-tick.C:
			if authenticated {
				if e = s.tick(ctx); e != nil {
					return e
				}
			}
		}
	}
}
func (s *Service) tick(ctx context.Context) error {
	s.mu.Lock()
	r := s.active
	if r == nil {
		s.mu.Unlock()
		return nil
	}
	expired := !r.Deadline.IsZero() && !time.Now().Before(r.Deadline)
	renew := r.Started && !r.Closing && time.Since(r.LastRenew) >= 240*time.Second
	snapshot := *r
	s.mu.Unlock()
	if expired {
		return s.Stop(ctx, "RD_LEASE_EXPIRED")
	}
	if !renew {
		return nil
	}
	changed, e := s.RefreshKeys(ctx)
	if e != nil {
		return e
	}
	if changed {
		return s.Stop(ctx, "RD_RESTORE_INVALIDATED")
	}
	proof, e := signJWS(s.key, "ht-rd-session+jwt", map[string]any{"type": "session.renew", "session_id": snapshot.Session.SessionID, "connection_epoch": snapshot.Session.ConnectionEpoch, "last_lease_seq": snapshot.Session.LeaseSeq, "grant_id": snapshot.Grant.ID, "grant_version": snapshot.Grant.Version}, false)
	if e != nil {
		return e
	}
	var renewed Session
	if e = s.request(ctx, "POST", "/sessions/"+url.PathEscape(snapshot.Session.SessionID)+"/renew", map[string]any{"current_epoch": snapshot.Session.ConnectionEpoch, "last_lease_seq": snapshot.Session.LeaseSeq, "signed_proof": proof}, "dpop", &renewed); e != nil {
		return e
	}
	if renewed.SessionID != snapshot.Session.SessionID || renewed.ConnectionEpoch != snapshot.Session.ConnectionEpoch || renewed.TicketJWS != snapshot.Session.TicketJWS || renewed.LeaseSeq <= snapshot.Session.LeaseSeq {
		return ErrAuthorization
	}
	next := snapshot
	next.Session = renewed
	if e = s.checkAuthority(&next); e != nil {
		return e
	}
	raw, _ := json.Marshal(map[string]any{"v": 1, "type": "session.lease", "session_id": renewed.SessionID, "connection_epoch": renewed.ConnectionEpoch, "lease_jws": renewed.LeaseJWS, "server_keyset": json.RawMessage(s.config.Store.snapshot().Keyset)})
	if e = s.config.Engine.OnSignal(ctx, snapshot.Session.SessionRef, raw); e != nil {
		return e
	}
	s.mu.Lock()
	if s.active == r && !r.Closing {
		r.Session = renewed
		r.Deadline = next.Deadline
		r.LastRenew = next.LastRenew
	}
	s.mu.Unlock()
	return nil
}
func (s *Service) handleEngine(ctx context.Context, event EngineEvent, send func(any) error) error {
	s.mu.Lock()
	r := s.active
	if r == nil || event.SessionID != r.Session.SessionID || event.ConnectionEpoch != r.Session.ConnectionEpoch {
		s.mu.Unlock()
		return ErrAuthorization
	}
	closing := r.Closing
	snapshot := *r
	s.mu.Unlock()
	if event.Kind == "closed" {
		if snapshot.Session.LeaseSeq > 0 && !snapshot.Superseded {
			proof, e := signJWS(s.key, "ht-rd-session+jwt", map[string]any{"type": "session.close_ack", "session_id": snapshot.Session.SessionID, "connection_epoch": snapshot.Session.ConnectionEpoch, "lease_seq": snapshot.Session.LeaseSeq, "stopped": true}, false)
			if e != nil {
				return e
			}
			if e = s.request(ctx, "POST", "/sessions/"+url.PathEscape(snapshot.Session.SessionID)+"/close-ack", map[string]any{"connection_epoch": snapshot.Session.ConnectionEpoch, "lease_seq": snapshot.Session.LeaseSeq, "signed_proof": proof}, "dpop", nil); e != nil {
				return e
			}
		}
		s.mu.Lock()
		if s.active == r {
			s.active = nil
		}
		if !snapshot.Superseded {
			delete(s.pending, snapshot.Session.SessionID)
		}
		s.mu.Unlock()
		return nil
	}
	if closing {
		return nil
	}
	switch event.Kind {
	case "file":
		var value FileEvent
		if err := strictDecode(event.Payload, &value, true); err != nil {
			return ErrAuthorization
		}
		return s.fileEvent(event.SessionRef, value)
	case "sign_peer_proof":
		return s.signPeerProof(ctx, r, event)
	case "verified_ready":
		s.mu.Lock()
		if s.active == r && !r.Closing {
			r.Verified = true
		}
		s.mu.Unlock()
		for attempt := 0; attempt < 2; attempt++ {
			current, e := s.loadSession(ctx, snapshot.Session.SessionID)
			if e != nil {
				return e
			}
			if current.ConnectionEpoch != snapshot.Session.ConnectionEpoch {
				return ErrAuthorization
			}
			var updated Session
			e = s.request(ctx, "POST", "/sessions/"+url.PathEscape(current.SessionID)+"/report", map[string]any{"phase": "ready", "connection_epoch": current.ConnectionEpoch, "expected_version": current.StateVersion, "path_verified": true}, "dpop", &updated)
			if e == nil {
				s.mu.Lock()
				if s.active == r {
					r.Session.State = updated.State
					r.Session.StateVersion = updated.StateVersion
				}
				s.mu.Unlock()
				return nil
			}
			var apiError *APIError
			if !errors.As(e, &apiError) || apiError.Code != "RD_VERSION_CONFLICT" {
				return e
			}
		}
		return ErrAuthorization
	case "outgoing_signal":
		if event.SignalType != "peer.answer" && event.SignalType != "peer.candidates" && event.SignalType != "peer.candidates_done" {
			return ErrAuthorization
		}
		if e := validateSignalPayload(event.SignalType, event.Payload, snapshot.Prepared.DTLSFingerprintSHA256); e != nil {
			return e
		}
		s.mu.Lock()
		if s.active != r || r.Closing || (event.SignalType == "peer.answer" && (r.OfferJWS == "" || r.AnswerJWS != "")) {
			s.mu.Unlock()
			return ErrAuthorization
		}
		r.Sequence++
		seq := r.Sequence
		s.mu.Unlock()
		inner := map[string]any{"v": 1, "type": event.SignalType, "session_id": snapshot.Session.SessionID, "connection_epoch": snapshot.Session.ConnectionEpoch, "from_endpoint_id": snapshot.Session.HostEndpointID, "to_endpoint_id": snapshot.Session.ControllerEndpointID, "seq": strconv.FormatUint(seq, 10), "ticket_jti": snapshot.Ticket.JTI, "created_at": time.Now().UTC().Format(time.RFC3339Nano), "payload": event.Payload}
		compact, e := signJWS(s.key, "ht-rd-peer+jwt", inner, false)
		if e != nil {
			return e
		}
		outer := map[string]any{"v": 1, "type": event.SignalType, "request_id": randomID(), "session_id": snapshot.Session.SessionID, "connection_epoch": snapshot.Session.ConnectionEpoch, "payload_jws": compact}
		if e = send(outer); e != nil {
			return e
		}
		s.mu.Lock()
		if s.active == r && event.SignalType == "peer.answer" {
			r.AnswerJWS = compact
		}
		s.mu.Unlock()
		echo, _ := json.Marshal(map[string]any{"v": 1, "type": "local.signed_signal", "envelope": outer})
		return s.config.Engine.OnSignal(ctx, snapshot.Session.SessionRef, echo)
	case "failed":
		return s.Stop(ctx, "RD_MEDIA_FAILED")
	default:
		return ErrAuthorization
	}
}
func validateSignalPayload(kind string, raw json.RawMessage, fingerprint string) error {
	if len(raw) > 32768 {
		return ErrAuthorization
	}
	if kind == "peer.candidates_done" {
		var empty struct{}
		return strictDecode(raw, &empty, true)
	}
	if kind == "peer.answer" {
		var payload struct {
			Type string `json:"type"`
			SDP  string `json:"sdp"`
		}
		if e := strictDecode(raw, &payload, true); e != nil || payload.Type != "answer" || len(payload.SDP) > 24576 || strings.ContainsRune(payload.SDP, 0) {
			return ErrAuthorization
		}
		found := false
		for _, line := range strings.Split(strings.ReplaceAll(payload.SDP, "\r\n", "\n"), "\n") {
			if strings.HasPrefix(line, "a=candidate:") && !directCandidate(strings.TrimPrefix(line, "a=")) {
				return ErrAuthorization
			}
			if strings.HasPrefix(line, "m=") {
				parts := strings.Fields(line)
				if len(parts) < 3 || (parts[2] != "UDP/TLS/RTP/SAVPF" && parts[2] != "UDP/DTLS/SCTP") {
					return ErrAuthorization
				}
			}
			if strings.HasPrefix(line, "a=fingerprint:") {
				parts := strings.Fields(strings.TrimPrefix(line, "a=fingerprint:"))
				if len(parts) != 2 || !strings.EqualFold(parts[0], "sha-256") || !strings.EqualFold(strings.ReplaceAll(parts[1], ":", ""), strings.ReplaceAll(fingerprint, ":", "")) {
					return ErrAuthorization
				}
				found = true
			}
		}
		if !found {
			return ErrAuthorization
		}
		return nil
	}
	var payload struct {
		Candidates []struct {
			Candidate string  `json:"candidate"`
			Mid       *string `json:"sdpMid"`
			Line      *int    `json:"sdpMLineIndex"`
			Username  *string `json:"usernameFragment,omitempty"`
		} `json:"candidates"`
	}
	if e := strictDecode(raw, &payload, true); e != nil || len(payload.Candidates) > 32 {
		return ErrAuthorization
	}
	for _, candidate := range payload.Candidates {
		if len(candidate.Candidate) > 1024 || !directCandidate(candidate.Candidate) {
			return ErrAuthorization
		}
	}
	return nil
}
func directCandidate(candidate string) bool {
	if candidate == "" {
		return true
	}
	parts := strings.Fields(candidate)
	if len(parts) < 8 || !strings.HasPrefix(parts[0], "candidate:") || !strings.EqualFold(parts[2], "udp") || parts[6] != "typ" || (parts[7] != "host" && parts[7] != "srflx" && parts[7] != "prflx") {
		return false
	}
	port, e := strconv.Atoi(parts[5])
	if e != nil || port < 1 || port > 65535 {
		return false
	}
	ip := net.ParseIP(parts[4])
	if ip != nil {
		return !ip.IsLoopback() && !ip.IsUnspecified() && !ip.IsMulticast() && !ip.IsLinkLocalUnicast() && parts[4] != "255.255.255.255"
	}
	name := strings.ToLower(parts[4])
	if !strings.HasSuffix(name, ".local") {
		return false
	}
	label := strings.TrimSuffix(name, ".local")
	if len(label) < 1 || len(label) > 63 {
		return false
	}
	for _, r := range label {
		if (r < 'a' || r > 'z') && (r < '0' || r > '9') && r != '-' {
			return false
		}
	}
	return true
}
