package gui

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/diagnostics"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

func (server *Server) connectionCheck(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	server.mu.Lock()
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	server.mu.Unlock()
	if err != nil || !state.Enrolled() {
		writeError(writer, http.StatusUnauthorized, "Sign in before checking a local service")
		return
	}
	var body struct {
		ProxyType   string `json:"proxy_type"`
		LocalHost   string `json:"local_host"`
		LocalPort   int    `json:"local_port"`
		LocalScheme string `json:"local_scheme"`
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 4096)
	defer request.Body.Close()
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if decoder.Decode(&body) != nil || decoder.Decode(&struct{}{}) != io.EOF ||
		body.LocalPort < 1 || body.LocalPort > 65535 ||
		(body.ProxyType != "http" && body.ProxyType != "tcp" && body.ProxyType != "udp") ||
		(body.ProxyType == "http" && body.LocalScheme != "http" && body.LocalScheme != "https") ||
		!validProbeHost(body.LocalHost) {
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusBadRequest)
		writeJSON(writer, map[string]string{"error_code": "TARGET_INVALID", "message": "Enter a host and port; URLs and credentials are not accepted"})
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 4*time.Second)
	defer cancel()
	writeJSON(writer, diagnostics.ProbeTarget(ctx, model.Connection{
		ProxyType: body.ProxyType, LocalHost: body.LocalHost,
		LocalPort: body.LocalPort, LocalScheme: body.LocalScheme,
	}))
}

func validProbeHost(host string) bool {
	if net.ParseIP(host) != nil {
		return true
	}
	if len(host) == 0 || len(host) > 253 || strings.TrimSpace(host) != host {
		return false
	}
	for _, label := range strings.Split(strings.TrimSuffix(host, "."), ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, char := range label {
			if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || char == '-') {
				return false
			}
		}
	}
	return true
}
