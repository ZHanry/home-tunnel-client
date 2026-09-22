package remotehost

import (
	"context"
	"net/url"
	"time"
)

type Status struct {
	Enrolled        bool            `json:"enrolled"`
	Enabled         bool            `json:"enabled"`
	Running         bool            `json:"running"`
	EndpointID      string          `json:"endpoint_id"`
	OwnerUserID     string          `json:"owner_user_id"`
	Origin          string          `json:"origin"`
	Capabilities    Capabilities    `json:"capabilities"`
	ActiveSessionID string          `json:"active_session_id"`
	Pending         []ApprovalEvent `json:"pending"`
	Grants          []LocalGrant    `json:"grants"`
	ErrorCode       string          `json:"error_code,omitempty"`
	Files           FileState       `json:"files"`
}

func (s *Service) State(ctx context.Context) Status {
	d := s.config.Store.snapshot()
	caps, e := s.config.Engine.Capabilities(ctx)
	result := Status{Enrolled: d.EndpointID != "", Enabled: d.Enabled, EndpointID: d.EndpointID, OwnerUserID: d.OwnerUserID, Origin: s.origin, Capabilities: caps, Grants: s.config.Store.Grants(), Pending: []ApprovalEvent{}}
	if e != nil || !caps.Available {
		result.ErrorCode = "RD_BACKEND_UNAVAILABLE"
		result.Capabilities.Available = false
	}
	result.Files = s.FileState()
	s.mu.Lock()
	defer s.mu.Unlock()
	result.Running = s.running
	result.Enabled = result.Enabled && !s.disabled
	if s.active != nil {
		result.ActiveSessionID = s.active.Session.SessionID
	}
	for _, session := range s.pending {
		if !sessionApprovalExpiry(session).After(time.Now()) {
			continue
		}
		grant, err := s.grantFor(session)
		if err != nil {
			continue
		}
		result.Pending = append(result.Pending, ApprovalEvent{Kind: "session", ID: session.SessionID, ConnectionEpoch: session.ConnectionEpoch, StateVersion: session.StateVersion, ControllerEndpointID: session.ControllerEndpointID, ControllerThumbprint: grant.ControllerJKT, Mode: grant.Mode, Permissions: append([]string(nil), session.Permissions...), ExpiresAt: sessionApprovalExpiry(session)})
	}
	return result
}
func sessionApprovalExpiry(session Session) time.Time {
	if session.State == "reconnecting" && session.LeaseExpiresAt.After(session.ApprovalExpiresAt) {
		return session.LeaseExpiresAt
	}
	return session.ApprovalExpiresAt
}
func (s *Service) RejectSession(ctx context.Context, id string) error {
	return s.rejectSession(ctx, id, 0, 0)
}
func (s *Service) RejectSessionExpected(ctx context.Context, id string, epoch, version int64) error {
	if epoch < 1 || version < 1 {
		return ErrLocalApproval
	}
	return s.rejectSession(ctx, id, epoch, version)
}
func (s *Service) rejectSession(ctx context.Context, id string, epoch, version int64) error {
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
	e = s.request(ctx, "POST", "/sessions/"+url.PathEscape(id)+"/close", map[string]any{}, "dpop", nil)
	if e == nil {
		s.mu.Lock()
		delete(s.pending, id)
		s.mu.Unlock()
	}
	return e
}
