package gui

import (
	"context"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/api"
)

func (server *Server) deviceMetadata(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet && request.Method != http.MethodPatch {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	client, state, err := server.client()
	if err != nil {
		writeClientError(writer, err)
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	defer client.CloseSession(ctx)
	if request.Method == http.MethodGet {
		items, err := client.ListDevices(ctx)
		if err != nil {
			writeClientError(writer, err)
			return
		}
		for _, device := range items {
			if device.ID == state.DeviceID {
				writeJSON(writer, device)
				return
			}
		}
		writeError(writer, http.StatusNotFound, "Device unavailable")
		return
	}
	var body struct {
		Tags     []string `json:"tags"`
		Favorite bool     `json:"favorite"`
		Version  int64    `json:"expected_metadata_version"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid metadata")
		return
	}
	if body.Tags == nil {
		body.Tags = []string{}
	}
	if err := client.SetDeviceMetadata(ctx, state.DeviceID, body.Tags, body.Favorite, body.Version); err != nil {
		writeClientError(writer, err)
		return
	}
	writeJSON(writer, map[string]bool{"ok": true})
}

func (server *Server) batchConnections(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Items   []api.BatchItem `json:"items"`
		Enabled bool            `json:"enabled"`
	}
	if err := readJSON(request, &body); err != nil || len(body.Items) < 1 || len(body.Items) > 50 {
		writeError(writer, http.StatusBadRequest, "Select 1–50 local connections")
		return
	}
	client, _, err := server.client()
	if err != nil {
		writeClientError(writer, err)
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 45*time.Second)
	defer cancel()
	defer client.CloseSession(ctx)
	results, err := client.BatchConnections(ctx, body.Items, body.Enabled)
	if err != nil {
		writeClientError(writer, err)
		return
	}
	writeJSON(writer, map[string]any{"results": results})
}
