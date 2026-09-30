package gui

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/app"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func localDeviceName(state model.State) string {
	if state.DeviceName != "" {
		return state.DeviceName
	}
	return app.DefaultDeviceName()
}

func (server *Server) renameDevice(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPatch {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	// Bind the request before waiting for account serialization. A queued rename
	// must never become a rename of an account signed in while it was waiting.
	server.remoteMu.Lock()
	generation := server.accountGeneration
	blocked := server.remoteBlocked
	server.remoteMu.Unlock()
	if blocked {
		writeError(writer, http.StatusConflict, "Account operation in progress")
		return
	}
	var body struct {
		Name string `json:"name"`
	}
	defer request.Body.Close()
	decoder := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 2048))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid device name")
		return
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		writeError(writer, http.StatusBadRequest, "Invalid device name")
		return
	}
	name, err := model.NormalizeDeviceName(body.Name)
	if err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}

	server.accountMu.Lock()
	defer server.accountMu.Unlock()
	if !server.currentAccountChange(request.Context(), generation) {
		writeError(writer, http.StatusConflict, "Account operation superseded")
		return
	}
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, "Sign in before renaming this device")
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	defer func() {
		closeCtx, closeCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer closeCancel()
		_ = client.CloseSession(closeCtx)
	}()
	if !server.currentAccountChange(ctx, generation) {
		writeError(writer, http.StatusConflict, "Account operation superseded")
		return
	}
	canonical, err := client.RenameCurrentDevice(ctx, name)
	if err != nil {
		writeClientError(writer, err)
		return
	}
	server.remoteMu.Lock()
	if ctx.Err() != nil || server.accountGeneration != generation {
		err = statepkg.ErrEnrollmentChanged
	} else {
		err = (statepkg.Store{Path: server.options.StatePath}).SetDeviceName(state, canonical)
	}
	server.remoteMu.Unlock()
	if errors.Is(err, statepkg.ErrEnrollmentChanged) {
		writeError(writer, http.StatusConflict, "Account operation superseded")
		return
	}
	if err != nil {
		writeError(writer, http.StatusInternalServerError, "Name changed on the server; refresh devices to save it locally")
		return
	}
	writeJSON(writer, map[string]string{"device_name": canonical})
}

// Reconcile legacy state and uncertain network results from the server's
// authoritative device list. Rechecking enrollment prevents cross-account writes.
func (server *Server) reconcileDeviceName(state model.State, devices []model.Device) {
	for _, device := range devices {
		if device.ID != state.DeviceID {
			continue
		}
		server.remoteMu.Lock()
		if !server.remoteBlocked {
			_ = (statepkg.Store{Path: server.options.StatePath}).RefreshDeviceName(state, device.Name)
		}
		server.remoteMu.Unlock()
		return
	}
}
