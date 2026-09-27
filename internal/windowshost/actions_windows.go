//go:build windows

package windowshost

import (
	"context"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"golang.org/x/sys/windows"
	"time"
)

func (s *Supervisor) hostAction(ctx context.Context, peer controlPeer, host *remotehost.Service, action RemoteAction, response *ControlResponse) error {
	// Emergency controls bypass the ordinary mutation queue.
	if action.Action == "stop" {
		return host.Stop(ctx, "RD_LOCAL_STOP")
	}
	if action.Action == "disable" {
		s.NotifySession()
		return host.DisableLocally(ctx)
	}
	if action.Action == "disable_unattended" {
		return host.SetUnattendedEnabled(ctx, false)
	}
	if peer.Session != windows.WTSGetActiveConsoleSessionId() {
		return ErrRejected
	}
	if !s.mutation.TryLock() {
		return ErrUnavailable
	}
	defer s.mutation.Unlock()
	switch action.Action {
	case "enable":
		return host.SetEnabled(ctx, true)
	case "disable_unattended":
		return host.SetUnattendedEnabled(ctx, false)
	case "enable_unattended":
		// Normal tray IPC never makes an elevated process stand in for the
		// local administrator. The UAC helper calls the dedicated operation.
		return ErrAdmin
	case "approve", "reject":
		if action.Kind == "pairing" {
			if action.Action == "reject" {
				return host.RejectPairing(ctx, action.ID)
			}
			expiry := time.Now().Add(10 * time.Minute)
			if action.Mode == "persistent" {
				expiry = time.Now().Add(30 * 24 * time.Hour)
			}
			return host.ApprovePairing(ctx, action.ID, action.Permissions, action.Mode, expiry)
		}
		if action.Kind == "session" {
			if action.Action == "approve" {
				return host.ApproveSessionExpected(ctx, action.ID, action.ConnectionEpoch, action.StateVersion)
			}
			return host.RejectSessionExpected(ctx, action.ID, action.ConnectionEpoch, action.StateVersion)
		}
	case "revoke":
		return host.RevokeGrant(ctx, action.ID)
	case "create_invite":
		value, err := host.CreateAssistInvite(ctx)
		if err == nil {
			response.Invite = &value
		}
		return err
	case "revoke_invite":
		return host.RevokeAssistInvite(ctx, action.ID)
	case "create_access_profile":
		value, err := host.AccessProfile(ctx, true)
		if err == nil {
			response.Profile = &value
		}
		return err
	case "set_fixed_password":
		value, err := host.SetFixedPassword(ctx, action.FixedPassword)
		if err == nil {
			response.Profile = &value
		}
		return err
	case "disable_fixed_password":
		return host.DisableFixedPassword(ctx)
	case "approve_access_request", "reject_access_request":
		return host.DecideAccessRequest(ctx, action.ID, action.Action == "approve_access_request")
	case "set_emergency_hotkey":
		return host.SetEmergencyKey(action.EmergencyKey)
	}
	return ErrRejected
}
func hostFileAction(ctx context.Context, host *remotehost.Service, action FileAction, response *ControlResponse) error {
	if action.Action == "valid" {
		response.Valid = host.FileSessionValid(action.SessionRef)
		return nil
	}
	if !host.FileSessionValid(action.SessionRef) {
		return remotehost.ErrAuthorization
	}
	switch action.Action {
	case "cancel":
		return host.CancelFile(ctx, action.SessionRef, action.ID)
	case "send":
		if len(action.Paths) == 0 || len(action.Paths) > 128 {
			return ErrRejected
		}
		return host.SelectFiles(ctx, action.SessionRef, func(context.Context) ([]string, error) { return action.Paths, nil })
	case "receive":
		if action.Destination == "" || len(action.Destination) > 32767 {
			return ErrRejected
		}
		return host.SelectDestination(ctx, action.SessionRef, action.ID, func(context.Context, string) (string, error) { return action.Destination, nil })
	}
	return ErrRejected
}
