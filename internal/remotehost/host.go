package remotehost

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type pairing struct {
	ID         string          `json:"id"`
	State      string          `json:"state"`
	ExpiresAt  time.Time       `json:"expires_at"`
	Transcript json.RawMessage `json:"transcript"`
}
type transcript struct {
	Domain            string    `json:"domain"`
	Instance          string    `json:"server_instance_id"`
	PairingID         string    `json:"pairing_id"`
	HostID            string    `json:"host_endpoint_id"`
	ControllerID      string    `json:"controller_endpoint_id"`
	AssistInviteID    string    `json:"assist_invite_id,omitempty"`
	HostOwnerID       string    `json:"host_owner_user_id,omitempty"`
	ControllerOwnerID string    `json:"controller_owner_user_id,omitempty"`
	HostJKT           string    `json:"host_jkt"`
	ControllerJKT     string    `json:"controller_jkt"`
	HostNonce         *string   `json:"nonce_host"`
	ControllerNonce   string    `json:"nonce_controller"`
	Scope             []string  `json:"scope"`
	Mode              string    `json:"mode"`
	RequestID         string    `json:"session_request_id"`
	ExpiresAt         time.Time `json:"expires_at"`
}
type authority struct {
	Iss           string   `json:"iss"`
	Aud           string   `json:"aud"`
	Instance      string   `json:"server_instance_id"`
	RestoreEpoch  int64    `json:"restore_epoch"`
	SessionID     string   `json:"session_id"`
	RequestID     string   `json:"session_request_id"`
	Epoch         int64    `json:"connection_epoch"`
	Owner         string   `json:"owner_user_id"`
	Host          string   `json:"host_endpoint_id"`
	Controller    string   `json:"controller_endpoint_id"`
	HostJKT       string   `json:"host_jkt"`
	ControllerJKT string   `json:"controller_jkt"`
	Permissions   []string `json:"permissions"`
	GrantID       string   `json:"grant_id"`
	GrantVersion  int64    `json:"grant_version"`
	UserVersion   int64    `json:"user_token_version"`
	Iat           int64    `json:"iat"`
	Nbf           int64    `json:"nbf"`
	Exp           int64    `json:"exp"`
	LeaseSeq      int64    `json:"lease_seq"`
	JTI           string   `json:"jti"`
}
type runningSession struct {
	Session      Session
	Prepared     PreparedSession
	Grant        LocalGrant
	Ticket       authority
	Deadline     time.Time
	LastRenew    time.Time
	Sequence     uint64
	PeerMaximum  uint64
	PeerSeen     map[uint64]bool
	PeerQueue    []queuedPeer
	PeerFlushing bool
	Proofs       map[string]bool
	OfferJWS     string
	AnswerJWS    string
	Started      bool
	Verified     bool
	Files        map[string]FileEvent
	FileOrder    []string
	Closing      bool
	Superseded   bool
	Cancel       context.CancelFunc
}
type queuedPeer struct {
	raw     json.RawMessage
	kind    string
	id      string
	epoch   int64
	compact string
}

func subset(have, want []string) bool {
	if len(want) == 0 {
		return false
	}
	set := map[string]bool{}
	for _, x := range have {
		set[x] = true
	}
	seen := map[string]bool{}
	for _, x := range want {
		if !set[x] || seen[x] {
			return false
		}
		seen[x] = true
	}
	return seen["view"]
}
func sameScopes(a, b []string) bool { return len(a) == len(b) && subset(a, b) }
func canAutoApprove(grant LocalGrant, session Session, unattendedEnabled bool) bool {
	if grant.Revoked || !grant.ExpiresAt.After(time.Now()) || !subset(grant.Permissions, session.Permissions) || grant.ControllerEndpointID != session.ControllerEndpointID {
		return false
	}
	if grant.Mode == "persistent" {
		return unattendedEnabled && grant.AssistInviteID == ""
	}
	return grant.Mode == "one_session" && grant.OneSessionRequestID == session.SessionRequestID &&
		(grant.SessionID == "" || grant.SessionID == session.SessionID)
}
func canAutoApproveAssist(inviteExpires time.Time, request transcript, now time.Time) bool {
	return request.AssistInviteID != "" && request.Mode == "one_session" && inviteExpires.After(now) &&
		subset([]string{"view", "input.keyboard", "input.pointer", "input.text", "clipboard.read", "clipboard.write"}, request.Scope)
}

func (s *Service) autoApprovePairing(ctx context.Context, request transcript, event ApprovalEvent) {
	approvalCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	err := s.ApprovePairing(approvalCtx, request.PairingID, request.Scope, request.Mode, time.Now().Add(10*time.Minute))
	s.mu.Lock()
	delete(s.autoPairing, request.PairingID)
	fallback := err != nil && ctx.Err() == nil && !s.disabled && !s.assistRevoked[request.AssistInviteID]
	s.mu.Unlock()
	if fallback {
		_ = s.emit(event)
	}
}

func (s *Service) autoApprove(ctx context.Context, session Session, event ApprovalEvent) {
	approvalCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	err := s.ApproveSessionExpected(approvalCtx, session.SessionID, session.ConnectionEpoch, session.StateVersion)
	s.mu.Lock()
	delete(s.autoApproving, session.SessionID)
	pending, exists := s.pending[session.SessionID]
	fallback := err != nil && ctx.Err() == nil && exists && pending.ConnectionEpoch == session.ConnectionEpoch && pending.StateVersion == session.StateVersion && !s.disabled
	s.mu.Unlock()
	if fallback {
		_ = s.emit(event)
	}
}
func (s *Service) emit(event ApprovalEvent) error {
	select {
	case s.approvals <- event:
		return nil
	default:
		return errors.New("RD_LOCAL_APPROVAL_QUEUE_FULL")
	}
}
func (s *Service) loadPairing(ctx context.Context, id string) (pairing, transcript, error) {
	var p pairing
	var t transcript
	e := s.request(ctx, "GET", "/pairings/"+url.PathEscape(id), nil, "dpop", &p)
	if e != nil {
		return p, t, e
	}
	if e = strictDecode(p.Transcript, &t, true); e != nil {
		return p, t, e
	}
	d := s.config.Store.snapshot()
	keys, e := parseKeyset(d.Keyset)
	if e != nil || p.ID != id || p.State != "pending" || !p.ExpiresAt.After(time.Now()) || t.Domain != "ht-rd-pairing-v1" || t.Instance != keys.ServerInstanceID || t.PairingID != id || t.HostID != d.EndpointID || t.HostJKT != jwk(&s.key.PublicKey).Thumbprint() || t.ControllerID == d.EndpointID || len(t.ControllerJKT) != 43 || len(t.ControllerNonce) != 43 || !t.ExpiresAt.Equal(p.ExpiresAt) || (t.Mode != "one_session" && t.Mode != "persistent") || (t.AssistInviteID == "" && (t.HostOwnerID != "" || t.ControllerOwnerID != "")) || (t.AssistInviteID != "" && (t.HostOwnerID != d.OwnerUserID || t.ControllerOwnerID == "" || t.ControllerOwnerID == d.OwnerUserID || t.Mode != "one_session")) {
		return p, t, ErrAuthorization
	}
	return p, t, nil
}

// ApprovePairing is invoked by an explicit local UI decision over the displayed
// target, requested scopes and mode. Network messages never call this method.
func (s *Service) ApprovePairing(ctx context.Context, id string, selected []string, mode string, expires time.Time) error {
	pair, t, e := s.loadPairing(ctx, id)
	if e != nil {
		return e
	}
	d := s.config.Store.snapshot()
	if !d.Enabled || mode != t.Mode || !sameScopes(t.Scope, selected) {
		return ErrLocalApproval
	}
	if mode == "persistent" {
		if !d.UnattendedEnabled || s.config.LocalAdminCheck == nil || s.config.LocalAdminCheck(ctx) != nil {
			return ErrLocalApproval
		}
	}
	caps, e := s.config.Engine.Capabilities(ctx)
	if e != nil || !caps.Available || !subset(caps.Permissions, selected) || (mode == "persistent" && !caps.UnattendedEnabled) {
		return ErrUnavailable
	}
	if expires.IsZero() {
		expires = time.Now().Add(10 * time.Minute)
	}
	if !expires.After(time.Now()) || expires.After(time.Now().Add(30*24*time.Hour)) {
		return ErrLocalApproval
	}
	if old, exists := d.Grants[id]; exists && (old.Revoked || old.GrantJWS != "") {
		return ErrAuthorization
	}
	if len(d.Grants) >= 128 {
		return errors.New("local grant history is full")
	}
	hostNonce := nonce()
	t.HostNonce = &hostNonce
	var original map[string]json.RawMessage
	if e = strictDecode(pair.Transcript, &original, false); e != nil {
		return e
	}
	original["nonce_host"], _ = json.Marshal(hostNonce)
	raw, _ := json.Marshal(original)
	pairProof, e := signJWS(s.key, "ht-rd-pairing+jwt", json.RawMessage(raw), false)
	if e != nil {
		return e
	}
	var requestID any
	if mode == "one_session" {
		requestID = t.RequestID
	}
	payload := map[string]any{"id": id, "server_instance_id": t.Instance, "owner_user_id": d.OwnerUserID, "host_endpoint_id": d.EndpointID, "controller_endpoint_id": t.ControllerID, "host_jkt": t.HostJKT, "controller_jkt": t.ControllerJKT, "scope": t.Scope, "mode": mode, "one_session_request_id": requestID, "grant_version": 1, "expires_at": expires.UTC().Format("2006-01-02T15:04:05.000Z")}
	grantProof, e := signJWS(s.key, "ht-rd-grant+jwt", payload, false)
	if e != nil {
		return e
	}
	grant := LocalGrant{ID: id, AssistInviteID: t.AssistInviteID, ControllerEndpointID: t.ControllerID, ControllerJKT: t.ControllerJKT, Permissions: append([]string(nil), t.Scope...), Mode: mode, Version: 1, ExpiresAt: expires, GrantJWS: grantProof}
	if mode == "one_session" {
		grant.OneSessionRequestID = t.RequestID
	}
	s.mu.Lock()
	if t.AssistInviteID != "" && s.assistRevoked[t.AssistInviteID] {
		s.mu.Unlock()
		return ErrLocalApproval
	}
	e = s.config.Store.update(func(d *diskState) error {
		if _, exists := d.Grants[id]; exists || (mode == "persistent" && !d.UnattendedEnabled) {
			return ErrAuthorization
		}
		d.Grants[id] = grant
		return nil
	})
	s.mu.Unlock()
	if e != nil {
		return e
	}
	if e = s.request(ctx, "POST", "/pairings/"+url.PathEscape(id)+"/confirm", map[string]any{"nonce_host": hostNonce, "signed_proof": pairProof, "grant_jws": grantProof}, "dpop", nil); e != nil {
		_ = s.config.Store.RevokeGrant(id)
		return e
	}
	s.mu.Lock()
	revoked := t.AssistInviteID != "" && s.assistRevoked[t.AssistInviteID]
	s.mu.Unlock()
	if revoked {
		return ErrLocalApproval
	}
	return s.emit(pairingApproval(pairing{ID: id, Transcript: raw}, t, "pairing_display"))
}
func (s *Service) RejectPairing(ctx context.Context, id string) error {
	e := s.request(ctx, "POST", "/pairings/"+url.PathEscape(id)+"/reject", map[string]any{}, "dpop", nil)
	if e == nil {
		return s.emit(ApprovalEvent{Kind: "pairing_complete", ID: id})
	}
	return e
}
func pairingApproval(p pairing, t transcript, kind string) ApprovalEvent {
	event := ApprovalEvent{Kind: kind, ID: p.ID, ControllerEndpointID: t.ControllerID, ControllerThumbprint: t.ControllerJKT, Permissions: append([]string(nil), t.Scope...), Mode: t.Mode, ExpiresAt: t.ExpiresAt}
	if t.HostNonce != nil {
		var original map[string]json.RawMessage
		if strictDecode(p.Transcript, &original, false) == nil {
			canonical, _ := json.Marshal(original)
			hash := sha256.Sum256(canonical)
			hexCode := hex.EncodeToString(hash[:16])
			parts := make([]string, 0, 8)
			for i := 0; i < 32; i += 4 {
				parts = append(parts, hexCode[i:i+4])
			}
			event.DisplayCode = strings.Join(parts, "-")
		}
	}
	return event
}
func (s *Service) RevokeGrant(ctx context.Context, id string) error {
	if e := s.config.Store.RevokeGrant(id); e != nil {
		return e
	}
	s.mu.Lock()
	active := s.active
	stop := active != nil && active.Grant.ID == id
	s.mu.Unlock()
	if stop {
		_ = s.Stop(ctx, "RD_GRANT_REVOKED")
	}
	return s.request(ctx, "DELETE", "/grants/"+url.PathEscape(id), nil, "dpop", nil)
}
func (s *Service) loadSession(ctx context.Context, id string) (Session, error) {
	var session Session
	e := s.request(ctx, "GET", "/sessions/"+url.PathEscape(id), nil, "dpop", &session)
	if e != nil {
		return session, e
	}
	if session.SessionID != id || session.ID != id || session.HostEndpointID != s.config.Store.snapshot().EndpointID || session.ConnectionEpoch < 1 || session.ConnectionEpoch > 0xffffffff {
		return session, ErrAuthorization
	}
	return session, nil
}
func (s *Service) grantFor(session Session) (LocalGrant, error) {
	d := s.config.Store.snapshot()
	raw, e := verifyJWS(session.GrantJWS, jwk(&s.key.PublicKey), "ht-rd-grant+jwt")
	if e != nil {
		return LocalGrant{}, e
	}
	var claim struct {
		ID      string `json:"id"`
		Version int64  `json:"grant_version"`
	}
	if e = strictDecode(raw, &claim, false); e != nil {
		return LocalGrant{}, e
	}
	g, exists := d.Grants[claim.ID]
	if !exists || g.Revoked || g.Version != claim.Version || g.GrantJWS != session.GrantJWS || !g.ExpiresAt.After(time.Now()) || g.ControllerEndpointID != session.ControllerEndpointID || !subset(g.Permissions, session.Permissions) || (g.Mode == "persistent" && !d.UnattendedEnabled) || (g.Mode == "one_session" && (g.OneSessionRequestID != session.SessionRequestID || (g.SessionID != "" && g.SessionID != session.SessionID))) {
		return g, ErrAuthorization
	}
	return g, nil
}
func (s *Service) ApproveSession(ctx context.Context, id string) error {
	return s.approveSession(ctx, id, 0, 0)
}

// ApproveSessionExpected binds a visible local decision to its exact epoch and
// server state revision, so a replaced/reconnected request needs a new click.
func (s *Service) ApproveSessionExpected(ctx context.Context, id string, epoch, version int64) error {
	if epoch < 1 || version < 1 {
		return ErrLocalApproval
	}
	return s.approveSession(ctx, id, epoch, version)
}
func (s *Service) approveSession(ctx context.Context, id string, epoch, version int64) error {
	s.mu.Lock()
	generation := s.generation
	disabled := s.disabled
	s.mu.Unlock()
	d := s.config.Store.snapshot()
	if !d.Enabled || disabled {
		return ErrLocalApproval
	}
	session, e := s.loadSession(ctx, id)
	if e != nil {
		return e
	}
	if epoch != 0 && (session.ConnectionEpoch != epoch || session.StateVersion != version) {
		return ErrLocalApproval
	}
	if session.State != "pending_approval" && session.State != "reconnecting" {
		return ErrAuthorization
	}
	if !session.ApprovalExpiresAt.After(time.Now()) && session.State == "pending_approval" {
		return ErrAuthorization
	}
	grant, e := s.grantFor(session)
	if e != nil {
		return e
	}
	if grant.Mode == "persistent" {
		caps, capabilityError := s.config.Engine.Capabilities(ctx)
		if capabilityError != nil || !caps.Available || !caps.UnattendedEnabled {
			return ErrUnavailable
		}
	}
	stunURLs, e := s.serverSTUN(ctx)
	if e != nil {
		return e
	}
	s.mu.Lock()
	if s.active != nil {
		s.mu.Unlock()
		return errors.New("RD_HOST_BUSY")
	}
	if generation != s.generation || s.disabled {
		s.mu.Unlock()
		return ErrLocalApproval
	}
	startCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	running := &runningSession{Session: session, Grant: grant, PeerSeen: map[uint64]bool{}, Proofs: map[string]bool{}, Cancel: cancel}
	s.active = running
	s.mu.Unlock()
	succeeded := false
	defer func() {
		if !succeeded {
			stopCtx, stopCancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer stopCancel()
			_ = s.Stop(stopCtx, "RD_AUTHORIZATION_INVALID")
		}
	}()
	s.engineMu.Lock()
	s.mu.Lock()
	stale := s.active != running || running.Closing || generation != s.generation || s.disabled
	s.mu.Unlock()
	if stale {
		s.engineMu.Unlock()
		return ErrLocalApproval
	}
	prepared, e := s.config.Engine.PrepareSession(startCtx, session.SessionRef)
	s.engineMu.Unlock()
	if e != nil {
		return e
	}
	if len(prepared.HostNonce) != 32 || len(prepared.DTLSFingerprintSHA256) == 0 || len(prepared.EphemeralPublicJWK) == 0 {
		return ErrAuthorization
	}
	if e = s.config.Store.update(func(d *diskState) error {
		g := d.Grants[grant.ID]
		if !d.Enabled || g.Revoked || g.Version != grant.Version || (g.SessionID != "" && g.SessionID != id && g.Mode == "one_session") {
			return ErrAuthorization
		}
		if g.Mode == "one_session" {
			g.SessionID = id
		}
		d.Grants[g.ID] = g
		return nil
	}); e != nil {
		return e
	}
	payload := map[string]any{"type": "session.decision", "session_id": id, "connection_epoch": session.ConnectionEpoch, "decision": "accept", "grant_version": grant.Version, "permissions": session.Permissions, "expected_version": session.StateVersion}
	proof, e := signJWS(s.key, "ht-rd-session+jwt", payload, false)
	if e != nil {
		return e
	}
	delete(payload, "type")
	delete(payload, "session_id")
	delete(payload, "connection_epoch")
	payload["signed_proof"] = proof
	var authorized Session
	if e = s.request(startCtx, "POST", "/sessions/"+url.PathEscape(id)+"/decision", payload, "dpop", &authorized); e != nil {
		return e
	}
	checked := &runningSession{Session: authorized, Prepared: prepared, Grant: grant}
	if authorized.SessionRef != session.SessionRef || e != nil {
		return ErrAuthorization
	}
	if e = s.checkAuthority(checked); e != nil {
		return e
	}
	d = s.config.Store.snapshot()
	request := StartRequest{SessionRef: authorized.SessionRef, DisplayID: authorized.DisplayID, SessionRequestID: authorized.SessionRequestID, GrantID: grant.ID, GrantVersion: grant.Version, RestoreEpoch: checked.Ticket.RestoreEpoch, UserTokenVersion: checked.Ticket.UserVersion, Origin: s.origin, OwnerUserID: d.OwnerUserID, HostEndpointID: d.EndpointID, ControllerEndpointID: authorized.ControllerEndpointID, HostPublicJWK: authorized.HostPublicJWK, ControllerPublicJWK: authorized.ControllerPublicJWK, TicketJWS: authorized.TicketJWS, LeaseJWS: authorized.LeaseJWS, GrantJWS: authorized.GrantJWS, InitialTrustPin: d.InitialTrust, ServerKeyset: d.Keyset, LocalPermissions: append([]string(nil), grant.Permissions...), LocalGrantRevoked: d.Grants[grant.ID].Revoked, Prepared: prepared}
	request.STUNURLs = stunURLs
	s.engineMu.Lock()
	s.mu.Lock()
	stale = s.active != running || running.Closing || generation != s.generation || s.disabled
	if !stale {
		running.Session, running.Prepared, running.Ticket = authorized, prepared, checked.Ticket
		running.Deadline, running.LastRenew = checked.Deadline, checked.LastRenew
	}
	s.mu.Unlock()
	if stale {
		s.engineMu.Unlock()
		return ErrLocalApproval
	}
	e = s.config.Engine.Start(startCtx, request)
	s.mu.Lock()
	stale = s.active != running || running.Closing || generation != s.generation || s.disabled
	if e == nil && !stale {
		running.Started = true
		running.PeerFlushing = true
		delete(s.pending, id)
	}
	s.mu.Unlock()
	s.engineMu.Unlock()
	if e != nil {
		return e
	}
	if stale {
		return ErrLocalApproval
	}
	if e = s.flushPeer(startCtx, running); e != nil {
		return e
	}
	succeeded = true
	return nil
}
func (s *Service) flushPeer(ctx context.Context, running *runningSession) error {
	for {
		s.mu.Lock()
		if s.active != running || running.Closing {
			s.mu.Unlock()
			return ErrAuthorization
		}
		if len(running.PeerQueue) == 0 {
			running.PeerFlushing = false
			s.mu.Unlock()
			return nil
		}
		peer := running.PeerQueue[0]
		running.PeerQueue = running.PeerQueue[1:]
		s.mu.Unlock()
		if err := s.handlePeer(ctx, peer.raw, peer.kind, peer.id, peer.epoch, peer.compact, true); err != nil {
			return err
		}
	}
}
func (s *Service) checkAuthority(r *runningSession) error {
	d := s.config.Store.snapshot()
	local, exists := d.Grants[r.Grant.ID]
	if !d.Enabled || !exists || local.Revoked || local.Version != r.Grant.Version || local.GrantJWS != r.Grant.GrantJWS || !local.ExpiresAt.After(time.Now()) || (local.Mode == "persistent" && !d.UnattendedEnabled) {
		return ErrAuthorization
	}
	keys, e := parseKeyset(d.Keyset)
	if e != nil {
		return e
	}
	var controller PublicJWK
	if e = strictDecode(r.Session.ControllerPublicJWK, &controller, true); e != nil || controller.Thumbprint() != r.Grant.ControllerJKT {
		return ErrAuthorization
	}
	var host PublicJWK
	if e = strictDecode(r.Session.HostPublicJWK, &host, true); e != nil || host.Thumbprint() != jwk(&s.key.PublicKey).Thumbprint() {
		return ErrAuthorization
	}
	var ticket, lease authority
	for _, item := range []struct {
		compact, typ, aud string
		target            *authority
	}{{r.Session.TicketJWS, "ht-rd-ticket+jwt", "ht-rd-start", &ticket}, {r.Session.LeaseJWS, "ht-rd-lease+jwt", "ht-rd-use", &lease}} {
		raw, e := verifyServerJWS(item.compact, item.typ, keys)
		if e != nil {
			return e
		}
		if e = strictDecode(raw, item.target, true); e != nil {
			return e
		}
		a := item.target
		now := time.Now().Unix()
		if a.Iss != s.origin || a.Aud != item.aud || a.Instance != keys.ServerInstanceID || a.RestoreEpoch != keys.RestoreEpoch || a.SessionID != r.Session.SessionID || a.RequestID != r.Session.SessionRequestID || a.Epoch != r.Session.ConnectionEpoch || a.Owner != d.OwnerUserID || a.Host != d.EndpointID || a.Controller != r.Grant.ControllerEndpointID || a.HostJKT != host.Thumbprint() || a.ControllerJKT != controller.Thumbprint() || a.GrantID != r.Grant.ID || a.GrantVersion != r.Grant.Version || !sameScopes(a.Permissions, r.Session.Permissions) || !subset(r.Grant.Permissions, a.Permissions) || a.Iat > now+60 || a.Nbf > now+60 || (a.Exp <= now && !(item.typ == "ht-rd-ticket+jwt" && r.Started)) || a.Exp-a.Iat > 900 || a.Exp <= a.Iat || a.JTI == "" {
			return ErrAuthorization
		}
		if r.Grant.Mode == "one_session" && a.RequestID != r.Grant.OneSessionRequestID {
			return ErrAuthorization
		}
	}
	if ticket.Exp-ticket.Iat > 60 || lease.LeaseSeq != r.Session.LeaseSeq || lease.LeaseSeq < 1 || ticket.UserVersion < 0 || ticket.UserVersion != lease.UserVersion {
		return ErrAuthorization
	}
	r.Ticket = ticket
	r.Deadline = time.Now().Add(time.Until(time.Unix(lease.Exp, 0)))
	r.LastRenew = time.Now()
	return nil
}
func (s *Service) Stop(ctx context.Context, reason string) error {
	session, present, engineError := s.stopLocal(ctx, reason)
	if !present {
		return engineError
	}
	networkError := s.request(ctx, "POST", "/sessions/"+url.PathEscape(session.SessionID)+"/close", map[string]any{}, "dpop", nil)
	// Only a subsequent native closed event may produce close_ack and release slots.
	if engineError != nil {
		return engineError
	}
	return networkError
}
func (s *Service) stopLocal(ctx context.Context, reason string) (Session, bool, error) {
	s.mu.Lock()
	s.generation++
	r := s.active
	var session Session
	if r != nil {
		r.Closing = true
		if r.Cancel != nil {
			r.Cancel()
		}
		session = r.Session
	}
	s.mu.Unlock()
	if r == nil {
		return Session{}, false, nil
	}
	s.engineMu.Lock()
	engineError := s.config.Engine.Close(ctx, session.SessionRef, reason)
	s.engineMu.Unlock()
	return session, true, engineError
}
func (s *Service) handleServer(ctx context.Context, raw json.RawMessage) error {
	var message struct {
		V          int             `json:"v"`
		Type       string          `json:"type"`
		SessionID  string          `json:"session_id"`
		Epoch      int64           `json:"connection_epoch"`
		Payload    json.RawMessage `json:"payload"`
		PayloadJWS string          `json:"payload_jws"`
	}
	if e := strictDecode(raw, &message, false); e != nil {
		return e
	}
	if message.V != 1 {
		return ErrAuthorization
	}
	if message.Type == "pairing.updated" {
		var p pairing
		if e := strictDecode(message.Payload, &p, false); e != nil {
			return e
		}
		if p.State != "pending" {
			s.mu.Lock()
			delete(s.autoPairing, p.ID)
			delete(s.autoPairAttempted, p.ID)
			s.mu.Unlock()
			return s.emit(ApprovalEvent{Kind: "pairing_complete", ID: p.ID})
		}
		p, t, e := s.loadPairing(ctx, p.ID)
		if e != nil {
			return e
		}
		if t.HostNonce != nil {
			return s.emit(pairingApproval(p, t, "pairing_display"))
		}
		event := pairingApproval(p, t, "pairing")
		if t.AssistInviteID != "" {
			if e := s.loadFixedAccessAuthorization(ctx, t.AssistInviteID); e != nil {
				var apiError *APIError
				if !errors.As(e, &apiError) || apiError.Status != 404 {
					return e
				}
			}
		}
		s.mu.Lock()
		inviteExpires, trusted := s.assistInvites[t.AssistInviteID]
		auto := trusted && !s.disabled && !s.assistRevoked[t.AssistInviteID] && !s.autoPairAttempted[p.ID] && canAutoApproveAssist(inviteExpires, t, time.Now())
		if auto {
			s.autoPairAttempted[p.ID] = true
			s.autoPairing[p.ID] = true
		}
		pending := s.autoPairing[p.ID]
		s.mu.Unlock()
		if auto {
			go s.autoApprovePairing(ctx, t, event)
			return nil
		}
		if pending {
			return nil
		}
		return s.emit(event)
	}
	if strings.HasPrefix(message.Type, "peer.") {
		return s.incomingPeer(ctx, raw, message.Type, message.SessionID, message.Epoch, message.PayloadJWS)
	}
	if !strings.HasPrefix(message.Type, "session.") {
		return nil
	}
	var session Session
	if e := strictDecode(message.Payload, &session, false); e != nil {
		return e
	}
	if session.SessionID != message.SessionID || session.ConnectionEpoch != message.Epoch {
		return ErrAuthorization
	}
	if session.State == "closing" || session.State == "closed" || session.State == "expired" || session.State == "failed" {
		s.mu.Lock()
		matches := s.active != nil && s.active.Session.SessionRef == session.SessionRef
		delete(s.pending, session.SessionID)
		delete(s.autoApproving, session.SessionID)
		delete(s.autoAttempted, session.SessionID)
		s.mu.Unlock()
		if matches {
			return s.Stop(ctx, "RD_SERVER_REVOKED")
		}
		return nil
	}
	if session.State == "pending_approval" || session.State == "reconnecting" {
		if session.HostEndpointID != s.config.Store.snapshot().EndpointID {
			return ErrAuthorization
		}
		grant, e := s.grantFor(session)
		if e != nil {
			return e
		}
		s.mu.Lock()
		old := s.active
		var oldRef SessionRef
		superseded := old != nil && old.Session.SessionID == session.SessionID && old.Session.ConnectionEpoch < session.ConnectionEpoch
		if superseded {
			s.generation++
			old.Closing, old.Superseded = true, true
			if old.Cancel != nil {
				old.Cancel()
			}
			oldRef = old.Session.SessionRef
		}
		s.pending[session.SessionID] = session
		s.mu.Unlock()
		if superseded {
			s.engineMu.Lock()
			e = s.config.Engine.Close(ctx, oldRef, "RD_RECONNECTING")
			s.engineMu.Unlock()
			if e != nil {
				return e
			}
		}
		event := ApprovalEvent{Kind: "session", ID: session.SessionID, ConnectionEpoch: session.ConnectionEpoch, StateVersion: session.StateVersion, ControllerEndpointID: grant.ControllerEndpointID, ControllerThumbprint: grant.ControllerJKT, Permissions: append([]string(nil), session.Permissions...), Mode: grant.Mode, ExpiresAt: sessionApprovalExpiry(session)}
		unattendedEnabled := s.config.Store.snapshot().UnattendedEnabled
		s.mu.Lock()
		auto := canAutoApprove(grant, session, unattendedEnabled) && s.autoAttempted[session.SessionID] != session.ConnectionEpoch && s.active == nil
		if auto {
			s.autoAttempted[session.SessionID] = session.ConnectionEpoch
			s.autoApproving[session.SessionID] = session.ConnectionEpoch
		}
		s.mu.Unlock()
		if auto {
			go s.autoApprove(ctx, session, event)
			return nil
		}
		return s.emit(event)
	}
	s.mu.Lock()
	if pending, exists := s.pending[session.SessionID]; exists && pending.ConnectionEpoch <= session.ConnectionEpoch {
		delete(s.pending, session.SessionID)
	}
	r := s.active
	if r != nil && r.Session.SessionID == session.SessionID && r.Session.ConnectionEpoch == session.ConnectionEpoch && session.StateVersion > r.Session.StateVersion {
		r.Session.State = session.State
		r.Session.StateVersion = session.StateVersion
	}
	s.mu.Unlock()
	return nil
}
func (s *Service) incomingPeer(ctx context.Context, raw json.RawMessage, kind, id string, epoch int64, compact string) error {
	return s.handlePeer(ctx, raw, kind, id, epoch, compact, false)
}
func (s *Service) handlePeer(ctx context.Context, raw json.RawMessage, kind, id string, epoch int64, compact string, flushing bool) error {
	s.mu.Lock()
	r := s.active
	if r == nil || r.Closing || r.Session.SessionID != id || r.Session.ConnectionEpoch != epoch {
		s.mu.Unlock()
		return fmt.Errorf("peer session unavailable: %w", ErrAuthorization)
	}
	if !r.Started || (r.PeerFlushing && !flushing) {
		if flushing || len(raw) > 65536 || len(r.PeerQueue) >= 32 {
			s.mu.Unlock()
			return ErrAuthorization
		}
		r.PeerQueue = append(r.PeerQueue, queuedPeer{raw: append(json.RawMessage(nil), raw...), kind: kind, id: id, epoch: epoch, compact: compact})
		s.mu.Unlock()
		return nil
	}
	publicRaw := append([]byte(nil), r.Session.ControllerPublicJWK...)
	snapshot := *r
	s.mu.Unlock()
	var public PublicJWK
	if e := strictDecode(publicRaw, &public, true); e != nil {
		return e
	}
	payload, e := verifyJWS(compact, public, "ht-rd-peer+jwt")
	if e != nil {
		return fmt.Errorf("peer signature: %w", e)
	}
	var inner struct {
		V         int             `json:"v"`
		Type      string          `json:"type"`
		SessionID string          `json:"session_id"`
		Epoch     int64           `json:"connection_epoch"`
		From      string          `json:"from_endpoint_id"`
		To        string          `json:"to_endpoint_id"`
		Seq       string          `json:"seq"`
		TicketJTI string          `json:"ticket_jti"`
		Created   time.Time       `json:"created_at"`
		Payload   json.RawMessage `json:"payload"`
	}
	if e = strictDecode(payload, &inner, true); e != nil {
		return fmt.Errorf("peer payload: %w", e)
	}
	seq, e := strconv.ParseUint(inner.Seq, 10, 64)
	if e != nil || strconv.FormatUint(seq, 10) != inner.Seq || inner.V != 1 || inner.Type != kind || inner.SessionID != id || inner.Epoch != epoch || inner.From != snapshot.Session.ControllerEndpointID || inner.To != snapshot.Session.HostEndpointID || inner.TicketJTI != snapshot.Ticket.JTI || time.Since(inner.Created) > time.Minute || time.Until(inner.Created) > time.Minute || (kind != "peer.offer" && kind != "peer.candidates" && kind != "peer.candidates_done") {
		return fmt.Errorf("peer binding: %w", ErrAuthorization)
	}
	s.mu.Lock()
	if s.active != r || r.Closing || r.PeerSeen[seq] || (seq < r.PeerMaximum && r.PeerMaximum-seq >= 32) || (kind == "peer.offer" && r.OfferJWS != "") {
		s.mu.Unlock()
		return ErrAuthorization
	}
	r.PeerSeen[seq] = true
	if seq > r.PeerMaximum {
		r.PeerMaximum = seq
	}
	for n := range r.PeerSeen {
		if n < r.PeerMaximum && r.PeerMaximum-n >= 32 {
			delete(r.PeerSeen, n)
		}
	}
	if kind == "peer.offer" {
		r.OfferJWS = compact
	}
	s.mu.Unlock()
	return s.config.Engine.OnSignal(ctx, snapshot.Session.SessionRef, raw)
}
func (s *Service) signPeerProof(ctx context.Context, r *runningSession, event EngineEvent) error {
	s.mu.Lock()
	if s.active != r || r.Closing {
		s.mu.Unlock()
		return ErrAuthorization
	}
	snapshot := *r
	s.mu.Unlock()
	data := event.Transcript
	if len(data) != 222 || event.RequestID == "" || len(event.RequestID) > 128 {
		return ErrAuthorization
	}
	offset := 0
	part := func(size int) []byte {
		if offset+4+size > len(data) || int(binary.BigEndian.Uint32(data[offset:])) != size {
			return nil
		}
		offset += 4
		p := data[offset : offset+size]
		offset += size
		return p
	}
	if string(part(14)) != "ht-rd-proof-v1" {
		return ErrAuthorization
	}
	sessionBytes, e := hex.DecodeString(strings.ReplaceAll(snapshot.Session.SessionID, "-", ""))
	if e != nil || !bytes.Equal(part(16), sessionBytes) {
		return ErrAuthorization
	}
	if offset+4 > len(data) || int64(binary.BigEndian.Uint32(data[offset:])) != snapshot.Session.ConnectionEpoch {
		return ErrAuthorization
	}
	offset += 4
	if len(part(32)) != 32 || !bytes.Equal(part(32), snapshot.Prepared.HostNonce) {
		return ErrAuthorization
	}
	for _, text := range []string{snapshot.OfferJWS, snapshot.AnswerJWS, snapshot.Session.TicketJWS} {
		if text == "" {
			return ErrAuthorization
		}
		h := sha256.Sum256([]byte(text))
		if !bytes.Equal(part(32), h[:]) {
			return ErrAuthorization
		}
	}
	s.mu.Lock()
	if s.active != r || r.Closing || r.Proofs[event.RequestID] || len(r.Proofs) >= 8 {
		s.mu.Unlock()
		return ErrAuthorization
	}
	r.Proofs[event.RequestID] = true
	s.mu.Unlock()
	sig, e := rawSignature(s.key, data)
	if e != nil {
		return e
	}
	return s.config.Engine.RespondProof(ctx, snapshot.Session.SessionRef, event.RequestID, sig)
}
