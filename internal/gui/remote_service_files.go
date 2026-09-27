package gui

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/filedialog"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"github.com/ZHanry/home-tunnel-client/internal/windowshost"
)

func (server *Server) serviceRemoteFiles(writer http.ResponseWriter, request *http.Request, action windowshost.FileAction) bool {
	probe, finish := context.WithTimeout(request.Context(), 2*time.Second)
	response, state, err := server.serviceState(probe)
	finish()
	if err != nil || !response.Managed {
		return false
	}
	ctx, cancel := context.WithTimeout(request.Context(), 2*time.Minute)
	defer cancel()
	current := func() bool {
		check, done := context.WithTimeout(ctx, time.Second)
		defer done()
		result, err := windowshost.Control(check, windowshost.ControlRequest{Operation: "file_action",
			Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID, File: &windowshost.FileAction{Action: "valid", SessionRef: action.SessionRef}})
		return err == nil && result.Valid
	}
	if !current() {
		remoteError(writer, remotehost.ErrAuthorization)
		return true
	}
	if action.Action != "cancel" {
		if !server.serviceActions.TryLock() {
			remoteError(writer, errors.New("RD_ACTION_IN_PROGRESS"))
			return true
		}
		defer server.serviceActions.Unlock()
		go func() {
			ticker := time.NewTicker(300 * time.Millisecond)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					if !current() {
						cancel()
						return
					}
				}
			}
		}()
		picker := server.options.RemoteFilePicker
		if picker == nil {
			picker = filedialog.Native{}
		}
		if action.Action == "send" {
			action.Paths, err = picker.Sources(ctx)
		} else {
			name := ""
			if response.State != nil {
				for _, item := range response.State.Files.Items {
					if item.ID == action.ID && !item.Outgoing && item.Event == "offer" {
						name = item.Name
						break
					}
				}
			}
			if name == "" {
				remoteError(writer, remotehost.ErrAuthorization)
				return true
			}
			action.Destination, err = picker.Destination(ctx, name)
		}
	}
	if errors.Is(err, filedialog.ErrCancelled) {
		writeJSON(writer, map[string]bool{"ok": true, "cancelled": true})
		return true
	}
	if err == nil {
		_, err = windowshost.Control(ctx, windowshost.ControlRequest{Operation: "file_action",
			Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID, File: &action})
	}
	if err != nil {
		remoteError(writer, serviceError(err))
	} else {
		writeJSON(writer, map[string]bool{"ok": true})
	}
	return true
}
