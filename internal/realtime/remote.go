package realtime

import (
	"context"
	"crypto/tls"
	"errors"
	"net"
	"net/url"
	"unicode/utf8"
)

// DialRemote authenticates inside the RD subprotocol, never in a query string
// or upgrade header. The caller must already have pinned this HTTPS origin.
func DialRemote(ctx context.Context, origin string, tlsConfig *tls.Config) (*Conn, error) {
	endpoint, e := url.Parse(origin)
	if e != nil || endpoint.Host == "" || endpoint.User != nil || endpoint.RawQuery != "" || endpoint.Fragment != "" || (endpoint.Scheme != "https" && endpoint.Scheme != "http") {
		return nil, errors.New("invalid RD signaling origin")
	}
	secure := endpoint.Scheme == "https"
	if !secure {
		ip := net.ParseIP(endpoint.Hostname())
		if ip == nil || !ip.IsLoopback() {
			return nil, errors.New("RD signaling requires TLS")
		}
	}
	endpoint.Path = "/api/v1/rd/signal"
	dialer := &net.Dialer{Timeout: handshakeTimeout}
	var socket net.Conn
	if secure {
		socket, e = (&tls.Dialer{NetDialer: dialer, Config: tlsConfig}).DialContext(ctx, "tcp", dialAddress(endpoint, true))
	} else {
		socket, e = dialer.DialContext(ctx, "tcp", dialAddress(endpoint, false))
	}
	if e != nil {
		return nil, e
	}
	connection, e := completeHandshake(ctx, socket, endpoint, "", "ht.rd.signal.v1")
	if e != nil {
		_ = socket.Close()
		return nil, e
	}
	return connection, nil
}
func (c *Conn) WriteEvent(payload []byte) error {
	if len(payload) == 0 || len(payload) > maximumFramePayload || !utf8.Valid(payload) {
		return errors.New("invalid bounded WebSocket JSON message")
	}
	return c.writeFrame(opcodeText, payload)
}
