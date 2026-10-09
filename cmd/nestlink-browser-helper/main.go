// nestlink-browser-helper is private GUI transport. It has no account/login CLI.
// The native core separately verifies server grants before screen capture or input.
package main

import (
	"bufio"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/pion/webrtc/v4"
)

const chunkBytes = 16384

type command struct {
	Kind  string   `json:"kind"`
	ID    string   `json:"id"`
	Offer string   `json:"offer"`
	Image string   `json:"image"`
	STUN  []string `json:"stun_urls"`
}
type event struct {
	Kind   string          `json:"kind"`
	ID     string          `json:"id,omitempty"`
	Answer string          `json:"answer,omitempty"`
	Input  json.RawMessage `json:"input,omitempty"`
}
type transport struct {
	id     string
	pc     *webrtc.PeerConnection
	frames *webrtc.DataChannel
	frame  uint32
	ready  bool
}

var outputMu sync.Mutex
var stateMu sync.Mutex
var current *transport

func emit(value event) {
	outputMu.Lock()
	defer outputMu.Unlock()
	if err := json.NewEncoder(os.Stdout).Encode(value); err != nil {
		os.Exit(1)
	}
}
func direct(pc *webrtc.PeerConnection) bool {
	if pc.SCTP() == nil || pc.SCTP().Transport() == nil {
		return false
	}
	pair, err := pc.SCTP().Transport().ICETransport().GetSelectedCandidatePair()
	if err != nil || pair == nil {
		return false
	}
	for _, candidate := range []*webrtc.ICECandidate{pair.Local, pair.Remote} {
		if candidate == nil || candidate.Protocol != webrtc.ICEProtocolUDP ||
			(candidate.Typ != webrtc.ICECandidateTypeHost && candidate.Typ != webrtc.ICECandidateTypeSrflx && candidate.Typ != webrtc.ICECandidateTypePrflx) {
			return false
		}
	}
	return true
}
func stop(id string) {
	stateMu.Lock()
	peer := current
	if peer == nil || id != "" && peer.id != id {
		stateMu.Unlock()
		return
	}
	current = nil
	peer.ready = false
	stateMu.Unlock()
	_ = peer.pc.Close()
	emit(event{Kind: "closed", ID: peer.id})
}
func start(value command) error {
	if len(value.ID) != 36 || len(value.Offer) < 32 || len(value.Offer) > 32768 {
		return errors.New("invalid offer")
	}
	for _, line := range strings.Split(value.Offer, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "m=") && !strings.HasPrefix(line, "m=application 9 UDP/DTLS/SCTP ") &&
			!regexp.MustCompile(`^m=application [0-9]+ UDP/DTLS/SCTP `).MatchString(line) {
			return errors.New("only a DTLS/SCTP data channel is supported")
		}
		if strings.HasPrefix(line, "a=candidate:") {
			fields := strings.Fields(line)
			if len(fields) < 8 || !strings.EqualFold(fields[2], "udp") || fields[6] != "typ" ||
				(fields[7] != "host" && fields[7] != "srflx" && fields[7] != "prflx") {
				return errors.New("only direct UDP candidates are supported")
			}
		}
	}
	stateMu.Lock()
	occupied := current != nil
	stateMu.Unlock()
	if occupied {
		return errors.New("occupied")
	}
	if len(value.STUN) > 4 {
		return errors.New("invalid STUN configuration")
	}
	for _, url := range value.STUN {
		if !regexp.MustCompile(`^stun:([a-zA-Z0-9.-]+|\[[a-fA-F0-9:]+\]):[0-9]{1,5}$`).MatchString(url) {
			return errors.New("only explicit self-hosted STUN URLs are supported")
		}
	}
	engine := webrtc.SettingEngine{}
	engine.SetNetworkTypes([]webrtc.NetworkType{webrtc.NetworkTypeUDP4, webrtc.NetworkTypeUDP6})
	api := webrtc.NewAPI(webrtc.WithSettingEngine(engine))
	configuration := webrtc.Configuration{}
	if len(value.STUN) > 0 {
		configuration.ICEServers = []webrtc.ICEServer{{URLs: value.STUN}}
	}
	pc, err := api.NewPeerConnection(configuration)
	if err != nil {
		return err
	}
	peer := &transport{id: value.ID, pc: pc}
	stateMu.Lock()
	current = peer
	stateMu.Unlock()
	pc.OnConnectionStateChange(func(status webrtc.PeerConnectionState) {
		if status == webrtc.PeerConnectionStateConnected {
			if !direct(pc) {
				stop(peer.id)
				return
			}
			stateMu.Lock()
			if current == peer {
				peer.ready = true
			}
			stateMu.Unlock()
			emit(event{Kind: "ready", ID: peer.id})
		} else if status == webrtc.PeerConnectionStateFailed || status == webrtc.PeerConnectionStateDisconnected {
			stop(peer.id)
		}
	})
	pc.OnDataChannel(func(channel *webrtc.DataChannel) {
		switch channel.Label() {
		case "nestlink.frames.v1":
			stateMu.Lock()
			if current == peer {
				peer.frames = channel
			}
			stateMu.Unlock()
		case "nestlink.input.v1":
			var window time.Time
			var messages int
			channel.OnMessage(func(message webrtc.DataChannelMessage) {
				if !message.IsString || len(message.Data) > 8192 || !json.Valid(message.Data) {
					stop(peer.id)
					return
				}
				stateMu.Lock()
				ready := current == peer && peer.ready
				stateMu.Unlock()
				if !ready || !direct(pc) {
					return
				}
				now := time.Now()
				if now.Sub(window) >= time.Second {
					window = now
					messages = 0
				}
				messages++
				if messages > 240 {
					stop(peer.id)
					return
				}
				emit(event{Kind: "input", ID: peer.id, Input: message.Data})
			})
		default:
			_ = channel.Close()
		}
	})
	if err = pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: value.Offer}); err != nil {
		stop(peer.id)
		return err
	}
	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		stop(peer.id)
		return err
	}
	gathered := webrtc.GatheringCompletePromise(pc)
	if err = pc.SetLocalDescription(answer); err != nil {
		stop(peer.id)
		return err
	}
	select {
	case <-gathered:
	case <-time.After(8 * time.Second):
		stop(peer.id)
		return errors.New("gather timeout")
	}
	emit(event{Kind: "answer", ID: peer.id, Answer: pc.LocalDescription().SDP})
	return nil
}
func frame(value command) {
	stateMu.Lock()
	peer := current
	if peer == nil || peer.id != value.ID || !peer.ready || peer.frames == nil {
		stateMu.Unlock()
		return
	}
	channel := peer.frames
	peer.frame++
	sequence := peer.frame
	stateMu.Unlock()
	if channel.ReadyState() != webrtc.DataChannelStateOpen || channel.BufferedAmount() > 262144 || !direct(peer.pc) {
		return
	}
	image, err := base64.StdEncoding.DecodeString(value.Image)
	if err != nil || len(image) < 4 || len(image) > 2097152 || image[0] != 255 || image[1] != 216 {
		stop(peer.id)
		return
	}
	count := (len(image) + chunkBytes - 1) / chunkBytes
	for index := 0; index < count; index++ {
		first := index * chunkBytes
		last := first + chunkBytes
		if last > len(image) {
			last = len(image)
		}
		chunk := make([]byte, 16+last-first)
		binary.BigEndian.PutUint32(chunk[0:4], 0x4e4c4a31)
		binary.BigEndian.PutUint32(chunk[4:8], sequence)
		binary.BigEndian.PutUint16(chunk[8:10], uint16(index))
		binary.BigEndian.PutUint16(chunk[10:12], uint16(count))
		binary.BigEndian.PutUint32(chunk[12:16], uint32(len(image)))
		copy(chunk[16:], image[first:last])
		if err = channel.Send(chunk); err != nil {
			stop(peer.id)
			return
		}
	}
}
func main() {
	defer stop("")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 65536), 4*1024*1024)
	for scanner.Scan() {
		var value command
		if json.Unmarshal(scanner.Bytes(), &value) != nil {
			break
		}
		switch value.Kind {
		case "start":
			if start(value) != nil {
				emit(event{Kind: "failed", ID: value.ID})
			}
		case "frame":
			frame(value)
		case "close":
			stop(value.ID)
		default:
			return
		}
	}
}
