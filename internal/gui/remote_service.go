package gui

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"path/filepath"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
	"github.com/ZHanry/home-tunnel-client/internal/windowshost"
)

func (server *Server) serviceState(ctx context.Context) (windowshost.ControlResponse, model.State, error) {
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	if err != nil || !state.Enrolled() {
		return windowshost.ControlResponse{}, state, remotehost.ErrLocalApproval
	}
	response, err := windowshost.Control(ctx, windowshost.ControlRequest{Operation: "status", Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID})
	return response, state, err
}
func (server *Server) serviceRemoteState(ctx context.Context) (remotehost.Status, bool) {
	response, _, err := server.serviceState(ctx)
	if err != nil || !response.Managed || response.State == nil {
		return remotehost.Status{}, false
	}
	status := *response.State
	if remotehost.ValidEmergencyKey(status.EmergencyKey) {
		server.mu.Lock()
		set, key := server.setEmergencyHotkey, server.serviceEmergencyKey
		server.mu.Unlock()
		if set != nil && key != status.EmergencyKey {
			if set(status.EmergencyKey) == nil {
				server.mu.Lock()
				server.serviceEmergencyKey = status.EmergencyKey
				server.mu.Unlock()
			}
		}
	}
	surface := response.Surface
	status.Service = remotehost.ServiceSurface{Installed: surface.Installed, Running: surface.Running,
		UnattendedEnabled: surface.UnattendedEnabled, SecureDesktop: surface.SecureDesktop, Detail: surface.Detail}
	return status, true
}
func serviceError(err error) error {
	if errors.Is(err, windowshost.ErrAdmin) || errors.Is(err, windowshost.ErrIdentity) {
		return remotehost.ErrLocalApproval
	}
	if errors.Is(err, windowshost.ErrNotInstalled) || errors.Is(err, windowshost.ErrUnavailable) {
		return remotehost.ErrUnavailable
	}
	return err
}
func (server *Server) serviceRemoteAction(writer http.ResponseWriter, request *http.Request, action windowshost.RemoteAction) bool {
	probe, cancel := context.WithTimeout(request.Context(), 2*time.Second)
	response, state, err := server.serviceState(probe)
	cancel()
	if err != nil || !response.Managed {
		return false
	}
	ctx, done := context.WithTimeout(request.Context(), 35*time.Second)
	defer done()
	if action.Action != "stop" && action.Action != "disable" && action.Action != "disable_unattended" {
		if !server.serviceActions.TryLock() {
			remoteError(writer, errors.New("RD_ACTION_IN_PROGRESS"))
			return true
		}
		defer server.serviceActions.Unlock()
	}
	if action.Action == "set_emergency_hotkey" {
		if !remotehost.ValidEmergencyKey(action.EmergencyKey) {
			remoteError(writer, remotehost.ErrLocalApproval)
			return true
		}
		server.mu.Lock()
		set := server.setEmergencyHotkey
		server.mu.Unlock()
		if set == nil {
			remoteError(writer, remotehost.ErrUnavailable)
			return true
		}
		if err = set(action.EmergencyKey); err != nil {
			remoteError(writer, err)
			return true
		}
	}
	result, err := windowshost.Control(ctx, windowshost.ControlRequest{
		Operation: "host_action", Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID, Action: &action})
	if err != nil {
		if action.Action == "set_emergency_hotkey" && response.State != nil {
			server.mu.Lock()
			set := server.setEmergencyHotkey
			server.mu.Unlock()
			if set != nil {
				_ = set(response.State.EmergencyKey)
			}
		}
		remoteError(writer, serviceError(err))
		return true
	}
	writer.Header().Set("cache-control", "no-store")
	if result.Invite != nil {
		writeJSON(writer, result.Invite)
	} else if result.Profile != nil {
		writeJSON(writer, result.Profile)
	} else {
		writeJSON(writer, map[string]bool{"ok": true})
	}
	return true
}
func (server *Server) pendingServiceTransfer(state model.State) ([]byte, error) {
	store, err := server.handoffStore(state)
	if err != nil {
		return nil, err
	}
	return store.PendingServiceTransfer()
}
func (server *Server) handoffStore(state model.State) (*remotehost.Store, error) {
	digest := sha256.Sum256([]byte(remoteIdentity(state)))
	path, err := filepath.Abs(filepath.Join(filepath.Dir(server.options.StatePath), "remote-host-"+hex.EncodeToString(digest[:16])+".json"))
	if err != nil {
		return nil, err
	}
	store, err := remotehost.OpenStore(path)
	if err != nil {
		return nil, err
	}
	return store, nil
}
func (server *Server) pendingServiceState(ctx context.Context, state model.State) (remotehost.Status, error) {
	store, err := server.handoffStore(state)
	if err != nil {
		return remotehost.Status{}, err
	}
	origin, endpoint, managed, _ := store.Identity()
	if !managed {
		return remotehost.Status{}, remotehost.ErrLocalApproval
	}
	surface := windowshost.Inspect(ctx)
	return remotehost.Status{Origin: origin, EndpointID: endpoint, Enrolled: true, Enabled: false,
		ErrorCode: "RD_SERVICE_SETUP_INCOMPLETE", Capabilities: remotehost.Capabilities{Status: "unavailable"},
		Service: remotehost.ServiceSurface{Installed: surface.Installed, Running: surface.Running, SecureDesktop: surface.SecureDesktop, Detail: surface.Detail}}, nil
}
func (server *Server) enableServiceRemote(parent context.Context, action windowshost.RemoteAction) error {
	if !server.serviceActions.TryLock() {
		return errors.New("RD_ACTION_IN_PROGRESS")
	}
	defer server.serviceActions.Unlock()
	if !windowshost.ValidEndpointID(action.ControllerEndpointID) || !windowshost.ValidThumbprint(action.ControllerThumbprint) {
		return remotehost.ErrLocalApproval
	}
	ctx, cancel := context.WithTimeout(parent, 100*time.Second)
	defer cancel()
	response, state, probeErr := server.serviceState(ctx)
	if probeErr != nil && !errors.Is(probeErr, windowshost.ErrUnavailable) {
		return serviceError(probeErr)
	}
	request := windowshost.ControlRequest{Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID,
		ControllerID: action.ControllerEndpointID, Thumbprint: action.ControllerThumbprint}
	if !response.Managed {
		host, _, err := server.localRemote(ctx)
		if errors.Is(err, remotehost.ErrServiceManaged) {
			request.State, err = server.pendingServiceTransfer(state)
		} else if err == nil {
			if !host.actions.TryLock() {
				return errors.New("RD_ACTION_IN_PROGRESS")
			}
			request.State, err = host.service.ExportForService(ctx)
			host.actions.Unlock()
			if err == nil {
				host.cancel()
				server.remoteMu.Lock()
				if server.remoteHost == host {
					server.remoteHost = nil
				}
				server.remoteMu.Unlock()
			}
		}
		if err != nil {
			return err
		}
	}
	return serviceError(windowshost.EnableWithApproval(ctx, request))
}
