package remotehost

import (
	"context"
	"net/url"
)

func (s *Service) SetUnattendedEnabled(ctx context.Context, enabled bool) error {
	if enabled {
		if s.config.LocalAdminCheck == nil || s.config.LocalAdminCheck(ctx) != nil {
			return ErrLocalApproval
		}
	} else {
		if err := s.config.Store.update(func(state *diskState) error {
			revokePersistentGrants(state)
			return nil
		}); err != nil {
			return err
		}
		s.mu.Lock()
		s.generation++
		activePersistent := s.active != nil && s.active.Grant.Mode == "persistent"
		s.mu.Unlock()
		if activePersistent {
			_ = s.Stop(ctx, "RD_UNATTENDED_REVOKED")
		}
	}
	s.capabilityMu.Lock()
	defer s.capabilityMu.Unlock()
	d := s.config.Store.snapshot()
	s.mu.Lock()
	generation := s.generation
	available := !s.disabled
	s.mu.Unlock()
	if !d.Enabled || !available {
		if enabled {
			return ErrLocalApproval
		}
		return nil
	}
	caps, err := s.config.Engine.Capabilities(ctx)
	if enabled && (err != nil || !caps.Available || caps.Status != "ready" || !caps.UnattendedEnabled) {
		return ErrUnavailable
	}
	if err != nil || !caps.Available {
		caps = Capabilities{Permissions: []string{"view"}, Status: "unavailable"}
	}
	caps.UnattendedEnabled = enabled && caps.UnattendedEnabled
	payload := map[string]any{
		"endpoint_id":        d.EndpointID,
		"local_enabled":      true,
		"capability_version": d.CapabilityVersion + 1,
		"capabilities":       map[string]any{"permissions": caps.Permissions, "unattended_enabled": caps.UnattendedEnabled, "displays": caps.Displays, "codecs": caps.Codecs, "status": caps.Status},
	}
	proof, err := signJWS(s.key, "ht-rd-capabilities+jwt", payload, false)
	if err != nil {
		return err
	}
	delete(payload, "endpoint_id")
	payload["signed_proof"] = proof
	if err = s.request(ctx, "PUT", "/endpoints/"+url.PathEscape(d.EndpointID)+"/capabilities", payload, "dpop", nil); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	stale := s.disabled || generation != s.generation
	err = s.config.Store.update(func(state *diskState) error {
		state.CapabilityVersion = d.CapabilityVersion + 1
		state.UnattendedEnabled = enabled && !stale && state.Enabled
		return nil
	})
	if err == nil && stale && enabled {
		return ErrLocalApproval
	}
	return err
}
