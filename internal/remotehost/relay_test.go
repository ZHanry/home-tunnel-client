package remotehost

import "testing"

func TestRelayCandidatesNeedNegotiatedRelay(t *testing.T) {
	relay := "candidate:2 1 udp 41885439 158.180.81.141 49170 typ relay raddr 0.0.0.0 rport 0"
	if peerCandidate(relay, false) {
		t.Fatal("relay candidate accepted without negotiated relay")
	}
	if !peerCandidate(relay, true) {
		t.Fatal("UDP relay candidate rejected in a relay session")
	}
	for _, candidate := range []string{
		"candidate:2 1 tcp 41885439 158.180.81.141 49170 typ relay",
		"candidate:2 1 udp 41885439 158.180.81.141 49170 typ relay tcptype passive",
		"candidate:2 1 udp 41885439 127.0.0.1 49170 typ relay",
		"candidate:2 1 udp 41885439 relay.local 49170 typ relay",
		"candidate:2 1 udp 41885439 158.180.81.141 0 typ relay",
	} {
		if peerCandidate(candidate, true) {
			t.Fatalf("accepted %q", candidate)
		}
	}
	if !peerCandidate("candidate:1 1 udp 123 192.168.1.2 5000 typ host", true) {
		t.Fatal("direct candidate rejected in a relay session")
	}
}

func TestTURNURLsAreUDPOnly(t *testing.T) {
	for value, want := range map[string]bool{
		"turn:158.180.81.141:3479?transport=udp":    true,
		"turn:relay.example.com:3479?transport=udp": true,
		"turn:158.180.81.141:3479":                  false,
		"turn:158.180.81.141:3479?transport=tcp":    false,
		"turns:158.180.81.141:5349?transport=udp":   false,
		"stun:158.180.81.141:3478":                  false,
	} {
		if validTURN(value) != want {
			t.Fatalf("validTURN(%q) != %v", value, want)
		}
	}
}

func TestRelayWireOnlyWhenServerOffersRelay(t *testing.T) {
	ready := func() map[string]any { return map[string]any{"status": "ready"} }
	if _, ok := relayWire(ready(), false)["transports"]; ok {
		t.Fatal("transports advertised to a server without relay")
	}
	if got := relayWire(ready(), true)["transports"]; got == nil {
		t.Fatal("relay not advertised")
	}
	if _, ok := relayWire(map[string]any{"status": "unavailable"}, true)["transports"]; ok {
		t.Fatal("transports advertised while unavailable")
	}
}
