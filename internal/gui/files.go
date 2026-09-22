package gui

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/filedialog"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

func (server *Server) remoteFiles(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 2048)
	var body struct {
		remotehost.SessionRef
		Action string `json:"action"`
		ID     string `json:"id"`
	}
	// In particular, callers cannot provide path, file name or file contents.
	defer request.Body.Close()
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid local file action")
		return
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		writeError(writer, http.StatusBadRequest, "Invalid local file action")
		return
	}
	if body.Action != "send" && body.Action != "receive" && body.Action != "cancel" {
		remoteError(writer, errors.New("RD_ACTION_INVALID"))
		return
	}
	host, _, err := server.localRemote(request.Context())
	if err != nil {
		remoteError(writer, err)
		return
	}
	ctx, cancel := context.WithTimeout(host.ctx, 2*time.Minute)
	defer cancel()
	unregister := context.AfterFunc(request.Context(), cancel)
	defer unregister()
	if !host.service.FileSessionValid(body.SessionRef) {
		remoteError(writer, remotehost.ErrAuthorization)
		return
	}
	// A closed/replaced/expired session cancels the native dialog promptly. Its
	// eventual selection is checked again by SelectFiles/SelectDestination.
	go func() {
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if !host.service.FileSessionValid(body.SessionRef) {
					cancel()
					return
				}
			}
		}
	}()
	if body.Action == "cancel" {
		err = host.service.CancelFile(ctx, body.SessionRef, body.ID)
	} else {
		if !host.actions.TryLock() {
			remoteError(writer, errors.New("RD_ACTION_IN_PROGRESS"))
			return
		}
		defer host.actions.Unlock()
		picker := server.options.RemoteFilePicker
		if picker == nil {
			picker = filedialog.Native{}
		}
		if body.Action == "send" {
			err = host.service.SelectFiles(ctx, body.SessionRef, picker.Sources)
		} else {
			err = host.service.SelectDestination(ctx, body.SessionRef, body.ID, picker.Destination)
		}
	}
	if errors.Is(err, filedialog.ErrCancelled) {
		writeJSON(writer, map[string]bool{"ok": true, "cancelled": true})
		return
	}
	if err != nil {
		remoteError(writer, err)
		return
	}
	writeJSON(writer, map[string]bool{"ok": true})
}
