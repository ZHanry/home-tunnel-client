package main

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"os/exec"
	"testing"
	"time"

	"github.com/pion/webrtc/v4"
)

func TestHelperProcess(t *testing.T) {
	if os.Getenv("NESTLINK_TEST_HELPER") != "1" {
		return
	}
	main()
	os.Exit(0)
}

func TestEncryptedPeerFrameAndInput(t *testing.T) {
	helper := exec.Command(os.Args[0], "-test.run=^TestHelperProcess$")
	helper.Env = append(os.Environ(), "NESTLINK_TEST_HELPER=1")
	stdin, err := helper.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := helper.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = helper.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = stdin.Close(); _ = helper.Process.Kill(); _ = helper.Wait() })
	events := make(chan event, 32)
	go func() {
		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 65536), 131072)
		for scanner.Scan() {
			var message event
			if json.Unmarshal(scanner.Bytes(), &message) == nil {
				events <- message
			}
		}
		close(events)
	}()
	next := func(kind string) event {
		t.Helper()
		timeout := time.After(15 * time.Second)
		for {
			select {
			case message, ok := <-events:
				if !ok {
					t.Fatal("helper ended")
				}
				if message.Kind == kind {
					return message
				}
				if message.Kind == "failed" {
					t.Fatal("helper failed")
				}
			case <-timeout:
				t.Fatalf("missing %s event", kind)
			}
		}
	}
	engine := webrtc.SettingEngine{}
	engine.SetIncludeLoopbackCandidate(true)
	engine.SetNetworkTypes([]webrtc.NetworkType{webrtc.NetworkTypeUDP4})
	pc, err := webrtc.NewAPI(webrtc.WithSettingEngine(engine)).NewPeerConnection(webrtc.Configuration{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pc.Close() })
	frames, err := pc.CreateDataChannel("nestlink.frames.v1", &webrtc.DataChannelInit{Ordered: boolPtr(false), MaxRetransmits: u16Ptr(0)})
	if err != nil {
		t.Fatal(err)
	}
	input, err := pc.CreateDataChannel("nestlink.input.v1", nil)
	if err != nil {
		t.Fatal(err)
	}
	opened := make(chan struct{})
	input.OnOpen(func() { close(opened) })
	chunks := make(chan []byte, 128)
	frames.OnMessage(func(message webrtc.DataChannelMessage) { chunks <- append([]byte(nil), message.Data...) })
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	gathered := webrtc.GatheringCompletePromise(pc)
	if err = pc.SetLocalDescription(offer); err != nil {
		t.Fatal(err)
	}
	select {
	case <-gathered:
	case <-time.After(10 * time.Second):
		t.Fatal("ICE gathering timeout")
	}
	encoder := json.NewEncoder(stdin)
	id := "11111111-1111-4111-8111-111111111111"
	if err = encoder.Encode(command{Kind: "start", ID: id, Offer: pc.LocalDescription().SDP}); err != nil {
		t.Fatal(err)
	}
	answer := next("answer")
	if answer.ID != id {
		t.Fatal("wrong session")
	}
	if err = pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: answer.Answer}); err != nil {
		t.Fatal(err)
	}
	next("ready")
	select {
	case <-opened:
	case <-time.After(10 * time.Second):
		t.Fatal("data channel not opened")
	}
	if !direct(pc) || pc.SCTP().Transport().State() != webrtc.DTLSTransportStateConnected {
		t.Fatal("transport is not encrypted direct UDP")
	}
	screen := image.NewRGBA(image.Rect(0, 0, 640, 360))
	for y := 0; y < 360; y++ {
		for x := 0; x < 640; x++ {
			screen.Set(x, y, color.RGBA{uint8(x), uint8(y), uint8(x * y), 255})
		}
	}
	var jpegBytes bytes.Buffer
	if err = jpeg.Encode(&jpegBytes, screen, &jpeg.Options{Quality: 72}); err != nil {
		t.Fatal(err)
	}
	if jpegBytes.Len() <= chunkBytes {
		t.Fatal("fixture must exercise fragmentation")
	}
	if err = encoder.Encode(command{Kind: "frame", ID: id, Image: base64.StdEncoding.EncodeToString(jpegBytes.Bytes())}); err != nil {
		t.Fatal(err)
	}
	parts := map[int][]byte{}
	length, count := 0, 0
	timeout := time.After(10 * time.Second)
	for count == 0 || len(parts) < count {
		select {
		case data := <-chunks:
			if len(data) < 16 || binary.BigEndian.Uint32(data) != 0x4e4c4a31 {
				t.Fatal("invalid frame protocol")
			}
			if binary.BigEndian.Uint32(data[4:]) != 1 {
				t.Fatal("wrong frame sequence")
			}
			index := int(binary.BigEndian.Uint16(data[8:]))
			count = int(binary.BigEndian.Uint16(data[10:]))
			length = int(binary.BigEndian.Uint32(data[12:]))
			parts[index] = data[16:]
		case <-timeout:
			t.Fatal("JPEG not delivered")
		}
	}
	var received bytes.Buffer
	for i := 0; i < count; i++ {
		received.Write(parts[i])
	}
	if received.Len() != length || !bytes.Equal(received.Bytes(), jpegBytes.Bytes()) {
		t.Fatal("JPEG changed in encrypted transport")
	}
	expected := `{"kind":"key","key":"KeyA","down":true}`
	if err = input.SendText(expected); err != nil {
		t.Fatal(err)
	}
	actual := next("input")
	if actual.ID != id || string(actual.Input) != expected {
		t.Fatal("input changed or session mixed")
	}
	if err = encoder.Encode(command{Kind: "close", ID: id}); err != nil {
		t.Fatal(err)
	}
	next("closed")
	t.Logf("direct encrypted UDP: %d JPEG bytes in %d chunks; keyboard delivered; host close ended session", length, count)
}
func boolPtr(value bool) *bool    { return &value }
func u16Ptr(value uint16) *uint16 { return &value }

func TestRejectRelayAndInvalidCommands(t *testing.T) {
	for _, value := range []command{
		{ID: "invalid", Offer: "v=0"},
		{ID: "11111111-1111-4111-8111-111111111111", Offer: "v=0\r\na=candidate:1 1 udp 1 192.0.2.1 5000 typ relay\r\n"},
		{ID: "11111111-1111-4111-8111-111111111111", Offer: "v=0\r\na=candidate:1 1 tcp 1 192.0.2.1 5000 typ host\r\n"},
		{ID: "11111111-1111-4111-8111-111111111111", Offer: "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n", STUN: []string{"turn:example.com:3478"}},
	} {
		if start(value) == nil {
			t.Fatal("invalid or relay command was accepted")
		}
	}
}
