package gui

import (
	"net/http"

	"github.com/ZHanry/home-tunnel-client/internal/remote"
)

// This endpoint deliberately reports unavailable until a usable media backend is
// shipped. RDP-over-TCP remains an independent existing connection preset.
func (server *Server) remoteCapabilities(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	writeJSON(writer, remote.Unavailable("RD_BACKEND_UNAVAILABLE"))
}
