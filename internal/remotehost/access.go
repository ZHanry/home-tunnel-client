package remotehost

import (
	"context"
	"net/url"
	"time"
)

type AccessProfile struct {
	DeviceID             string `json:"device_id"`
	FixedPasswordEnabled bool   `json:"fixed_password_enabled"`
	Revision             int64  `json:"revision"`
}

type AccessRequest struct {
	ID                   string    `json:"id"`
	ControllerEndpointID string    `json:"controller_endpoint_id"`
	ExpiresAt            time.Time `json:"expires_at"`
}

type AccessDecision struct {
	ID        string    `json:"id"`
	State     string    `json:"state"`
	InviteID  string    `json:"invite_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (s *Service) AccessProfile(ctx context.Context, create bool) (AccessProfile, error) {
	method := "GET"
	if create {
		method = "POST"
	}
	var profile AccessProfile
	err := s.request(ctx, method, "/access-profile", nil, "dpop", &profile)
	if err != nil {
		return AccessProfile{}, err
	}
	if profile.DeviceID != "" && len(profile.DeviceID) != 9 {
		return AccessProfile{}, ErrAuthorization
	}
	if create && profile.DeviceID == "" {
		return AccessProfile{}, ErrAuthorization
	}
	return profile, nil
}

func (s *Service) SetFixedPassword(ctx context.Context, password string) (AccessProfile, error) {
	if len(password) < 12 || len(password) > 128 {
		return AccessProfile{}, ErrLocalApproval
	}
	d := s.config.Store.snapshot()
	s.mu.Lock()
	ready := s.running && !s.disabled
	s.mu.Unlock()
	if !d.Enabled || !ready {
		return AccessProfile{}, ErrLocalApproval
	}
	current, err := s.AccessProfile(ctx, true)
	if err != nil {
		return AccessProfile{}, err
	}
	if err := s.disableFixedLocally(ctx); err != nil {
		return AccessProfile{}, err
	}
	expectedRevision := current.Revision + 1
	if err := s.config.Store.update(func(state *diskState) error {
		if !state.Enabled {
			return ErrLocalApproval
		}
		state.FixedRevision = expectedRevision
		return nil
	}); err != nil {
		return AccessProfile{}, err
	}
	var profile AccessProfile
	if err := s.request(ctx, "PUT", "/access-profile/password", map[string]any{"password": password}, "dpop", &profile); err != nil {
		return AccessProfile{}, err
	}
	if !profile.FixedPasswordEnabled || profile.Revision != expectedRevision || profile.DeviceID != current.DeviceID {
		return AccessProfile{}, ErrAuthorization
	}
	return profile, nil
}

func (s *Service) DisableFixedPassword(ctx context.Context) error {
	if err := s.disableFixedLocally(ctx); err != nil {
		return err
	}
	return s.request(ctx, "DELETE", "/access-profile/password", nil, "dpop", nil)
}

func (s *Service) disableFixedLocally(ctx context.Context) error {
	previous := s.config.Store.snapshot().FixedInvites
	s.mu.Lock()
	active := s.active
	fixed := false
	if active != nil {
		_, fixed = previous[active.Grant.AssistInviteID]
	}
	s.mu.Unlock()
	if err := s.config.Store.RevokeFixedGrants(); err != nil {
		return err
	}
	s.mu.Lock()
	for id := range previous {
		delete(s.assistInvites, id)
	}
	s.mu.Unlock()
	if fixed {
		_ = s.Stop(ctx, "RD_FIXED_PASSWORD_REVOKED")
	}
	return nil
}

func (s *Service) ListAccessRequests(ctx context.Context) ([]AccessRequest, error) {
	var response struct {
		Items []AccessRequest `json:"items"`
	}
	if err := s.request(ctx, "GET", "/access/requests", nil, "dpop", &response); err != nil {
		return nil, err
	}
	if len(response.Items) > 5 {
		return nil, ErrAuthorization
	}
	return response.Items, nil
}

func (s *Service) DecideAccessRequest(ctx context.Context, id string, approve bool) error {
	if id == "" || len(id) > 128 {
		return ErrLocalApproval
	}
	decision := "reject"
	if approve {
		decision = "approve"
	}
	var result AccessDecision
	if err := s.request(ctx, "POST", "/access/requests/"+url.PathEscape(id)+"/decision", map[string]any{"decision": decision}, "dpop", &result); err != nil {
		return err
	}
	if !approve {
		if result.ID != id || result.State != "rejected" {
			return ErrAuthorization
		}
		return nil
	}
	if result.ID != id || result.State != "preparing" || result.InviteID == "" || !result.ExpiresAt.After(time.Now()) {
		return ErrAuthorization
	}
	if err := s.trustAccessInvite(result.InviteID, result.ExpiresAt, 0); err != nil {
		return err
	}
	var activated AccessDecision
	if err := s.request(ctx, "POST", "/access/requests/"+url.PathEscape(id)+"/activate", nil, "dpop", &activated); err != nil {
		return err
	}
	if activated.ID != id || activated.State != "approved" {
		return ErrAuthorization
	}
	return nil
}

func (s *Service) trustAccessInvite(id string, expires time.Time, fixedRevision int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.disabled || !expires.After(time.Now()) {
		return ErrLocalApproval
	}
	if err := s.config.Store.update(func(state *diskState) error {
		if !state.Enabled || fixedRevision > 0 && state.FixedRevision != fixedRevision {
			return ErrLocalApproval
		}
		if state.AssistInvites == nil {
			state.AssistInvites = map[string]time.Time{}
		}
		state.AssistInvites[id] = expires
		if fixedRevision > 0 {
			if state.FixedInvites == nil {
				state.FixedInvites = map[string]time.Time{}
			}
			state.FixedInvites[id] = expires
		}
		return nil
	}); err != nil {
		return err
	}
	s.assistInvites[id] = expires
	return nil
}

func (s *Service) loadFixedAccessAuthorization(ctx context.Context, id string) error {
	s.mu.Lock()
	_, known := s.assistInvites[id]
	s.mu.Unlock()
	if known || s.config.Store.snapshot().FixedRevision == 0 {
		return nil
	}
	var authorization struct {
		InviteID       string    `json:"invite_id"`
		AccessKind     string    `json:"access_kind"`
		ProfileVersion int64     `json:"profile_revision"`
		ExpiresAt      time.Time `json:"expires_at"`
	}
	if err := s.request(ctx, "GET", "/access/invites/"+url.PathEscape(id)+"/authorization", nil, "dpop", &authorization); err != nil {
		return err
	}
	if authorization.InviteID != id || authorization.AccessKind != "fixed_password" ||
		authorization.ProfileVersion != s.config.Store.snapshot().FixedRevision {
		return nil
	}
	return s.trustAccessInvite(id, authorization.ExpiresAt, authorization.ProfileVersion)
}
