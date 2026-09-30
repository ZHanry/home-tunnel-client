// Package origin canonicalizes trusted HTTPS addresses the same way browser
// origin comparisons do, before they are used for native authorization handoff.
package origin

import (
	"errors"
	"net/netip"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var hostname = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9.-]*[a-z0-9.])?$`)
var numericHost = regexp.MustCompile(`^[0-9.]+$`)

func HTTPS(value string) (*url.URL, error) {
	address, err := url.Parse(value)
	if err != nil || address.Scheme != "https" || address.Host == "" || address.User != nil || address.Opaque != "" || address.RawPath != "" || strings.HasSuffix(address.Host, ":") {
		return nil, errors.New("invalid HTTPS address")
	}
	host := strings.ToLower(address.Hostname())
	if ip, parseErr := netip.ParseAddr(host); parseErr == nil {
		if ip.Zone() != "" {
			return nil, errors.New("invalid HTTPS host")
		}
		host = ip.String()
		if ip.Is6() {
			host = "[" + host + "]"
		}
	} else if !hostname.MatchString(host) || numericHost.MatchString(host) {
		return nil, errors.New("invalid HTTPS host")
	}
	port := address.Port()
	if port != "" {
		number, err := strconv.Atoi(port)
		if err != nil || number < 1 || number > 65535 {
			return nil, errors.New("invalid HTTPS port")
		}
		if number != 443 {
			host += ":" + strconv.Itoa(number)
		}
	}
	address.Host = host
	return address, nil
}
