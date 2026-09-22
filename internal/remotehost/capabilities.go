package remotehost

import (
	"context"
	"io"
	"net"
	"net/http"
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
		Remote struct {
			Enabled  bool `json:"enabled"`
			Protocol struct {
				Major int `json:"major"`
			} `json:"protocol"`
			SignalPath  string   `json:"signal_path"`
			UDPOnly     bool     `json:"udp_only"`
			AllowTURN   bool     `json:"allow_turn"`
			AllowICETCP bool     `json:"allow_ice_tcp"`
			STUNURLs    []string `json:"stun_urls"`
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
	return append([]string{}, c.STUNURLs...), nil
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
