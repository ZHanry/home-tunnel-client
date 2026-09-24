package remotehost

import (
	"context"
	"errors"
	"net/url"
	"time"
)

type AssistInvite struct {
	ID                string    `json:"id"`
	DeviceID          string    `json:"device_id"`
	TemporaryPassword string    `json:"temporary_password,omitempty"`
	State             string    `json:"state,omitempty"`
	ExpiresAt         time.Time `json:"expires_at"`
	CreatedAt         time.Time `json:"created_at,omitempty"`
	RedeemedAt        time.Time `json:"redeemed_at,omitempty"`
}

func (s *Service) CreateAssistInvite(ctx context.Context) (AssistInvite, error) {
	d := s.config.Store.snapshot()
	s.mu.Lock()
	running := s.running && !s.disabled
	generation := s.generation
	s.mu.Unlock()
	if !d.Enabled || d.EndpointID == "" || !running {
		return AssistInvite{}, ErrLocalApproval
	}
	var invite AssistInvite
	if err := s.request(ctx, "POST", "/assist-invites", nil, "dpop", &invite); err != nil {
		return AssistInvite{}, err
	}
	if invite.ID == "" || len(invite.DeviceID) != 9 || len(invite.TemporaryPassword) != 12 || !invite.ExpiresAt.After(time.Now()) {
		return AssistInvite{}, ErrAuthorization
	}
	for _, digit := range invite.DeviceID {
		if digit < '0' || digit > '9' {
			return AssistInvite{}, ErrAuthorization
		}
	}
	s.mu.Lock()
	if s.disabled || !s.running || s.generation != generation {
		s.mu.Unlock()
		_ = s.request(ctx, "DELETE", "/assist-invites/"+url.PathEscape(invite.ID), nil, "dpop", nil)
		return AssistInvite{}, ErrLocalApproval
	}
	err := s.config.Store.update(func(state *diskState) error {
		if !state.Enabled {
			return ErrLocalApproval
		}
		if state.AssistInvites == nil {
			state.AssistInvites = map[string]time.Time{}
		}
		for id, expiry := range state.AssistInvites {
			if !expiry.After(time.Now()) {
				delete(state.AssistInvites, id)
			}
		}
		state.AssistInvites[invite.ID] = invite.ExpiresAt
		return nil
	})
	if err == nil {
		for id, expiry := range s.assistInvites {
			if !expiry.After(time.Now()) {
				delete(s.assistInvites, id)
			}
		}
		s.assistInvites[invite.ID] = invite.ExpiresAt
		delete(s.assistRevoked, invite.ID)
	}
	s.mu.Unlock()
	if err != nil {
		_ = s.request(ctx, "DELETE", "/assist-invites/"+url.PathEscape(invite.ID), nil, "dpop", nil)
		return AssistInvite{}, err
	}
	return invite, nil
}

func (s *Service) ListAssistInvites(ctx context.Context) ([]AssistInvite, error) {
	d := s.config.Store.snapshot()
	if !d.Enabled || d.EndpointID == "" {
		return nil, ErrLocalApproval
	}
	var response struct {
		Items []AssistInvite `json:"items"`
	}
	if err := s.request(ctx, "GET", "/assist-invites", nil, "dpop", &response); err != nil {
		return nil, err
	}
	if len(response.Items) > 30 {
		return nil, ErrAuthorization
	}
	return response.Items, nil
}

func (s *Service) RevokeAssistInvite(ctx context.Context, id string) error {
	if id == "" || len(id) > 128 {
		return errors.New("RD_ACTION_INVALID")
	}
	s.mu.Lock()
	s.assistRevoked[id] = true
	delete(s.assistInvites, id)
	err := s.config.Store.RevokeAssistGrants(id)
	stop := s.active != nil && s.active.Grant.AssistInviteID == id
	s.mu.Unlock()
	if err != nil {
		return err
	}
	if stop {
		_ = s.Stop(ctx, "RD_INVITE_REVOKED")
	}
	return s.request(ctx, "DELETE", "/assist-invites/"+url.PathEscape(id), nil, "dpop", nil)
}
