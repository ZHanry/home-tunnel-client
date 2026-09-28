package remotehost

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

func (s *Service) serverSTUN(ctx context.Context) ([]string, error) {
	request, e := http.NewRequestWithContext(ctx, "GET", s.origin+"/api/v1/public/capabilities", nil)
	if e != nil {
		return nil, e
	}
	response, e := s.http.Do(request)
	if e != nil {
		return nil, e
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, ErrUnavailable
	}
	raw, e := io.ReadAll(io.LimitReader(response.Body, 65537))
	if e != nil || len(raw) > 65536 {
		return nil, ErrAuthorization
	}
	var capabilities struct {
		Features []string `json:"features"`
		Remote   struct {
			Enabled  bool `json:"enabled"`
			Protocol struct {
				Major int `json:"major"`
			} `json:"protocol"`
			SignalPath  string   `json:"signal_path"`
			UDPOnly     bool     `json:"udp_only"`
			AllowTURN   bool     `json:"allow_turn"`
			AllowICETCP bool     `json:"allow_ice_tcp"`
			STUNURLs    []string `json:"stun_urls"`
			Relay       *struct {
				Enabled  bool   `json:"enabled"`
				Protocol string `json:"protocol"`
				Path     string `json:"ice_servers_path"`
			} `json:"relay"`
		} `json:"remote_desktop"`
	}
	if strictDecode(raw, &capabilities, false) != nil {
		return nil, ErrAuthorization
	}
	c := capabilities.Remote
	if !c.Enabled || c.Protocol.Major != 1 || c.SignalPath != "/api/v1/rd/signal" || !c.UDPOnly || c.AllowTURN || c.AllowICETCP || len(c.STUNURLs) > 4 {
		return nil, ErrAuthorization
	}
	for _, value := range c.STUNURLs {
		if !validSTUN(value) {
			return nil, ErrAuthorization
		}
	}
	relay := false
	for _, feature := range capabilities.Features {
		if feature == "rd_discovered_capabilities" {
			s.discovered.Store(true)
		}
		if feature == "rd_udp_relay" {
			relay = c.Relay != nil && c.Relay.Enabled && c.Relay.Protocol == "udp" && c.Relay.Path == "/api/v1/rd/sessions/{session_id}/ice-servers"
		}
	}
	s.relay.Store(relay)
	return append([]string{}, c.STUNURLs...), nil
}

// iceServers returns STUN plus short-lived UDP TURN credentials when the server
// offers relay for this session. Only UDP TURN and STUN URLs reach the engine.
func (s *Service) iceServers(ctx context.Context, sessionID string, stunURLs []string) ([]ICEServer, bool, error) {
	fallback := make([]ICEServer, 0, 1)
	if len(stunURLs) > 0 {
		fallback = append(fallback, ICEServer{URLs: append([]string{}, stunURLs...)})
	}
	if !s.relay.Load() {
		return fallback, false, nil
	}
	var answer struct {
		SessionID    string `json:"session_id"`
		RelayAllowed bool   `json:"relay_allowed"`
		Servers      []struct {
			URLs       []string `json:"urls"`
			Username   string   `json:"username"`
			Credential string   `json:"credential"`
		} `json:"ice_servers"`
	}
	if e := s.request(ctx, "GET", "/sessions/"+url.PathEscape(sessionID)+"/ice-servers", nil, "dpop", &answer); e != nil {
		return nil, false, e
	}
	if answer.SessionID != sessionID || len(answer.Servers) > 2 {
		return nil, false, ErrAuthorization
	}
	servers := make([]ICEServer, 0, len(answer.Servers))
	relay := false
	for _, server := range answer.Servers {
		if len(server.URLs) == 0 || len(server.URLs) > 4 {
			return nil, false, ErrAuthorization
		}
		stun, turn := true, true
		for _, value := range server.URLs {
			stun = stun && validSTUN(value)
			turn = turn && validTURN(value)
		}
		switch {
		case stun && server.Username == "" && server.Credential == "":
			servers = append(servers, ICEServer{URLs: server.URLs})
		case turn && answer.RelayAllowed && server.Username != "" && server.Credential != "" && len(server.Username) <= 256 && len(server.Credential) <= 256 && !strings.ContainsAny(server.Username+server.Credential, "\r\n\x00"):
			servers = append(servers, ICEServer{URLs: server.URLs, Username: server.Username, Credential: server.Credential})
			relay = true
		default:
			return nil, false, ErrAuthorization
		}
	}
	return servers, relay, nil
}
func validTURN(value string) bool {
	rest, ok := strings.CutSuffix(value, "?transport=udp")
	if !ok || !strings.HasPrefix(rest, "turn:") {
		return false
	}
	return validSTUN("stun:" + strings.TrimPrefix(rest, "turn:"))
}
func validSTUN(value string) bool {
	if !strings.HasPrefix(value, "stun:") {
		return false
	}
	host, port, e := net.SplitHostPort(strings.TrimPrefix(value, "stun:"))
	if e != nil {
		return false
	}
	number, e := strconv.Atoi(port)
	if e != nil || number < 1 || number > 65535 {
		return false
	}
	for _, c := range port {
		if c < '0' || c > '9' {
			return false
		}
	}
	if net.ParseIP(host) != nil {
		return true
	}
	if len(host) > 253 {
		return false
	}
	for _, label := range strings.Split(strings.ToLower(host), ".") {
		if len(label) < 1 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, c := range label {
			if (c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '-' {
				return false
			}
		}
	}
	return true
}
