package remotehost

import (
	"context"
	"net/url"
)

func (s *Service) SetUnattendedController(ctx context.Context, id, jkt string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if !validBindingID(id) || len(jkt) != 43 {
		return ErrLocalApproval
	}
	return s.config.Store.update(func(state *diskState) error {
		if state.UnattendedEnabled && (state.UnattendedControllerID != id || state.UnattendedControllerJKT != jkt) {
			return ErrLocalApproval
		}
		state.UnattendedControllerID = id
		state.UnattendedControllerJKT = jkt
		return nil
	})
}

func (s *Service) SetUnattendedEnabled(ctx context.Context, enabled bool) error {
	if enabled {
		if s.config.LocalAdminCheck == nil || s.config.LocalAdminCheck(ctx) != nil {
			return ErrLocalApproval
		}
	} else {
		if err := s.config.Store.update(func(state *diskState) error {
			revokePersistentGrants(state)
			state.UnattendedControllerID = ""
			state.UnattendedControllerJKT = ""
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
	if enabled && (!validBindingID(d.UnattendedControllerID) || len(d.UnattendedControllerJKT) != 43) {
		return ErrLocalApproval
	}
	if err != nil || !caps.Available {
		caps = Capabilities{Permissions: []string{"view"}, Status: "unavailable"}
	}
	caps.UnattendedEnabled = enabled && caps.UnattendedEnabled
	payload := map[string]any{
		"endpoint_id":        d.EndpointID,
		"local_enabled":      true,
		"capability_version": d.CapabilityVersion + 1,
		"capabilities":       relayWire(wireCapabilities(caps, true, s.discovered.Load()), s.relay.Load()),
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
