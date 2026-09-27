package remotehost

import (
	"context"
	"encoding/json"
	"errors"
)

var ErrServiceManaged = errors.New("RD_SYSTEM_SERVICE_MANAGED")

// ExportForService disables the old host and persists ownership BEFORE sending
// the identity to the privileged service. A lost IPC reply cannot resurrect
// an independent tray copy. The protected backup retains revocation tombstones.
func (s *Service) ExportForService(ctx context.Context) ([]byte, error) {
	if s.config.ServiceOwned {
		return nil, ErrLocalApproval
	}
	if s.config.Store.snapshot().ServiceManaged {
		return s.config.Store.PendingServiceTransfer()
	}
	if err := s.SetEnabled(ctx, false); err != nil {
		return nil, err
	}
	if err := s.config.Store.update(func(state *diskState) error {
		if state.EndpointID == "" || state.Origin == "" {
			return ErrLocalApproval
		}
		state.ServiceManaged = true
		return nil
	}); err != nil {
		return nil, err
	}
	return json.Marshal(s.config.Store.snapshot())
}

func (s *Store) PendingServiceTransfer() ([]byte, error) {
	data := s.snapshot()
	if !data.ServiceManaged || data.Enabled || data.UnattendedEnabled {
		return nil, ErrLocalApproval
	}
	return json.Marshal(data)
}

// Retry acknowledgements never replace newer service state or tombstones.
func SameServiceIdentity(existing, incoming []byte) bool {
	var a, b diskState
	return strictDecode(existing, &a, true) == nil && strictDecode(incoming, &b, true) == nil &&
		a.EndpointID != "" && a.EndpointID == b.EndpointID && a.Origin == b.Origin &&
		a.KeyPKCS8 != "" && a.KeyPKCS8 == b.KeyPKCS8 && a.OwnerUserID == b.OwnerUserID
}

// ValidateServiceTransfer verifies the envelope before a protected machine
// store is created. Server trust chains and every live grant are subsequently
// checked by the normal remotehost/native authorization paths.
func ValidateServiceTransfer(raw []byte, origin string) error {
	if len(raw) == 0 || len(raw) > 512<<10 {
		return ErrAuthorization
	}
	var data diskState
	if strictDecode(raw, &data, true) != nil || !data.ServiceManaged ||
		data.Enabled || data.UnattendedEnabled || data.Origin != origin ||
		!validBindingID(data.EndpointID) || data.OwnerUserID == "" ||
		len(data.InitialTrust) == 0 || len(data.Keyset) == 0 || data.CapabilityVersion < 1 {
		return ErrAuthorization
	}
	for _, grant := range data.Grants {
		if grant.Mode == "persistent" && !grant.Revoked {
			return ErrAuthorization
		}
	}
	store := &Store{data: data}
	_, err := store.privateKey()
	return err
}

// Identity is non-secret metadata used to bind service IPC to one endpoint.
func (s *Store) Identity() (origin, endpoint string, managed, enabled bool) {
	data := s.snapshot()
	return data.Origin, data.EndpointID, data.ServiceManaged, data.Enabled
}
func (s *Store) UnattendedBinding() (enabled bool, controllerID, thumbprint string) {
	data := s.snapshot()
	return data.Enabled && data.UnattendedEnabled, data.UnattendedControllerID, data.UnattendedControllerJKT
}

// DisableLocally is the durable emergency path, including when no worker or
// network connection exists. A later service restart remains disabled.
func (s *Store) DisableLocally() error {
	return s.update(func(data *diskState) error {
		data.Enabled = false
		revokePersistentGrants(data)
		clear(data.AssistInvites)
		clear(data.FixedInvites)
		return nil
	})
}

func (s *Service) DisableLocally(ctx context.Context) error {
	s.mu.Lock()
	s.generation++
	s.disabled = true
	clear(s.assistInvites)
	s.mu.Unlock()
	_, _, engineErr := s.stopLocal(ctx, "RD_LOCAL_EMERGENCY")
	return errors.Join(engineErr, s.config.Store.DisableLocally())
}
