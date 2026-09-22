package remoteengine

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

func TestPinnedExecutableAndStrictResponse(t *testing.T) {
	file := t.TempDir() + string(os.PathSeparator) + "native-host"
	if err := os.WriteFile(file, []byte("not an executable"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(context.Background(), Options{ExecutablePath: file, ExpectedSHA256: strings.Repeat("0", 64)}); err == nil {
		t.Fatal("mismatched executable digest accepted")
	}
	for _, body := range []string{
		`{"abi":1,"abi":1}`, `{"abi":1,"\u0061bi":1}`,
		`{"abi":1,"result":{"x":1,"x":2}}`, `{"abi":1} {}`,
		`{"abi":1,"unknown":true}`, `{"abi":1,"result":` + strings.Repeat("[", 30) + `0` + strings.Repeat("]", 30) + `}`,
	} {
		var result response
		if decode([]byte(body), &result) == nil {
			t.Fatalf("accepted malformed response %q", body)
		}
	}
}

func fileFixtureEvent(phase string, id int, offset uint64) remotehost.EngineEvent {
	value := remotehost.FileEvent{Event: phase, ID: fmt.Sprintf("f0000000-0000-4000-8000-%012d", id), Name: "中文-🙂.bin", Size: 8 << 30, Offset: offset, Outgoing: true}
	if phase == "complete" {
		value.Offset = value.Size
	}
	payload, _ := json.Marshal(value)
	// The native engine always includes offset, including zero.
	var fields map[string]any
	_ = json.Unmarshal(payload, &fields)
	fields["offset"] = value.Offset
	payload, _ = json.Marshal(fields)
	return remotehost.EngineEvent{SessionRef: remotehost.SessionRef{SessionID: "a0000000-0000-4000-8000-000000000001", ConnectionEpoch: 5}, Kind: "file", Payload: payload}
}

func TestFileEventsValidateTheCompleteLocalOnlyShape(t *testing.T) {
	for _, phase := range []string{"offer", "progress", "complete"} {
		if !validEvent(fileFixtureEvent(phase, 1, 0)) {
			t.Fatal("valid native event rejected", phase)
		}
	}
	base := fileFixtureEvent("offer", 1, 0)
	for name, change := range map[string]func(map[string]any){
		"caller path":               func(v map[string]any) { v["path"] = "C:/private.txt" },
		"missing direction":         func(v map[string]any) { delete(v, "outgoing") },
		"null direction":            func(v map[string]any) { v["outgoing"] = nil },
		"fractional bytes":          func(v map[string]any) { v["size"] = 1.5 },
		"negative bytes":            func(v map[string]any) { v["size"] = -1 },
		"oversize":                  func(v map[string]any) { v["size"] = uint64(8<<30) + 1 },
		"offset exceeds file":       func(v map[string]any) { v["offset"] = uint64(8<<30) + 1 },
		"offer already advanced":    func(v map[string]any) { v["offset"] = 1 },
		"unknown phase":             func(v map[string]any) { v["event"] = "accepted" },
		"false completion":          func(v map[string]any) { v["event"] = "complete" },
		"error without reason":      func(v map[string]any) { v["event"] = "error" },
		"unsafe name":               func(v map[string]any) { v["name"] = "../private.txt" },
		"device name":               func(v map[string]any) { v["name"] = "NUL.txt" },
		"NUL name":                  func(v map[string]any) { v["name"] = "before\x00after" },
		"long emoji":                func(v map[string]any) { v["name"] = strings.Repeat("🙂", 128) },
		"uncertainty before commit": func(v map[string]any) { v["may_be_saved"] = true },
	} {
		t.Run(name, func(t *testing.T) {
			var fields map[string]any
			_ = json.Unmarshal(base.Payload, &fields)
			change(fields)
			event := base
			event.Payload, _ = json.Marshal(fields)
			if validEvent(event) {
				t.Fatal("invalid file event accepted")
			}
		})
	}
	for _, text := range []string{`{"event":"offer","event":"progress"}`, `{"event":"error","error_code":"RD_FILE_LIMIT"}`, `{"event":"error","error_code":"RD_FILE_LIMIT","outgoing":false}`} {
		event := base
		event.Payload = []byte(text)
		if validEvent(event) {
			t.Fatal("invalid source batch error accepted")
		}
	}
	for _, text := range []string{`{"event":"error","error_code":"RD_FILE_LIMIT","outgoing":true}`, `{"event":"error","id":"f0000000-0000-4000-8000-000000000001","name":"saved.bin","size":0,"offset":0,"outgoing":false,"error_code":"RD_FILE_WRITE_FAILED","may_be_saved":true}`} {
		event := base
		event.Payload = []byte(text)
		if !validEvent(event) {
			t.Fatal("valid file failure rejected")
		}
	}
	for _, epoch := range []int64{1, 5, 0xffffffff} {
		event := base
		event.ConnectionEpoch = epoch
		if !validEvent(event) {
			t.Fatal("valid uint32 epoch rejected", epoch)
		}
	}
	for _, epoch := range []int64{-1, 0, 0x100000000} {
		event := base
		event.ConnectionEpoch = epoch
		if validEvent(event) {
			t.Fatal("invalid epoch accepted", epoch)
		}
	}
	for _, name := range []string{strings.Repeat("文", 200) + ".bin", strings.Repeat("🙂", 125) + ".bin"} {
		if !nativeFilename(name) {
			t.Fatal("valid Unicode filename rejected")
		}
	}
}

func mailboxFixture(t *testing.T) *Engine {
	t.Helper()
	e := &Engine{events: make(chan remotehost.EngineEvent), done: make(chan struct{}), eventWake: make(chan struct{}, 1), eventProgress: map[fileEventKey]*queuedEvent{}}
	go e.dispatchEvents()
	t.Cleanup(func() {
		close(e.done)
		select {
		case _, open := <-e.events:
			if open {
				for range e.events {
				}
			}
		case <-time.After(2 * time.Second):
			t.Error("blocked event dispatcher leaked on shutdown")
		}
	})
	return e
}

func TestSlowConsumerKeepsOffersAndTerminalEventsWhileCoalescingProgress(t *testing.T) {
	e := mailboxFixture(t)
	for id := 1; id <= 64; id++ {
		if err := e.enqueueEvent(fileFixtureEvent("offer", id, 0)); err != nil {
			t.Fatal(err)
		}
	}
	// A slow HTTP renewal consumer reads no events during this entire burst.
	for offset := uint64(1); offset <= 200; offset++ {
		for id := 1; id <= 64; id++ {
			if err := e.enqueueEvent(fileFixtureEvent("progress", id, offset)); err != nil {
				t.Fatal(err)
			}
		}
	}
	e.eventMu.Lock()
	critical, progress, queued := e.eventCritical, len(e.eventProgress), len(e.eventQueue)
	e.eventMu.Unlock()
	if critical != 64 || progress != 64 || queued != 128 {
		t.Fatalf("unbounded or lost queue: %d %d %d", critical, progress, queued)
	}
	for id := 1; id <= 64; id++ {
		if err := e.enqueueEvent(fileFixtureEvent("complete", id, 8<<30)); err != nil {
			t.Fatal(err)
		}
	}
	for index := 0; index < 128; index++ {
		select {
		case event := <-e.events:
			file, ok := nativeFileEvent(event)
			want := "offer"
			if index >= 64 {
				want = "complete"
			}
			if !ok || file.Event != want {
				t.Fatalf("important event lost/reordered: %d %+v", index, file)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("important event stalled")
		}
	}
}

func TestProgressMailboxPreservesLatestValueAndControlCapacity(t *testing.T) {
	e := mailboxFixture(t)
	for offset := uint64(1); offset <= 1000; offset++ {
		if err := e.enqueueEvent(fileFixtureEvent("progress", 1, offset)); err != nil {
			t.Fatal(err)
		}
	}
	// A captured old progress value may be sent once while a newer one replaces
	// it; any following terminal state is still ordered after that value.
	for id := 2; id <= 100; id++ {
		if err := e.enqueueEvent(fileFixtureEvent("progress", id, 1)); err != nil {
			t.Fatal(err)
		}
	}
	for index := 0; index < criticalEventLimit; index++ {
		event := fileFixtureEvent("offer", index+1000, 0)
		if err := e.enqueueEvent(event); err != nil {
			t.Fatal("progress consumed important capacity", err)
		}
	}
	if err := e.enqueueEvent(fileFixtureEvent("offer", 9999, 0)); err == nil {
		t.Fatal("important event limit was not bounded")
	}
	e.eventMu.Lock()
	latest, valid := nativeFileEvent(e.eventProgress[fileEventKey{SessionRef: fileFixtureEvent("progress", 1, 0).SessionRef, ID: "f0000000-0000-4000-8000-000000000001"}].event)
	if !valid || latest.Offset != 1000 {
		t.Error("latest pending progress was not retained")
	}
	if e.eventCritical != criticalEventLimit || len(e.eventProgress) != progressEventLimit || len(e.eventQueue) > criticalEventLimit+progressEventLimit {
		t.Error("mailbox exceeded independent bounds")
	}
	e.eventMu.Unlock()
}

func TestConcurrentProgressDeliveryCannotFollowItsTerminalState(t *testing.T) {
	e := mailboxFixture(t)
	produced := make(chan error, 1)
	go func() {
		if err := e.enqueueEvent(fileFixtureEvent("offer", 1, 0)); err != nil {
			produced <- err
			return
		}
		for offset := uint64(1); offset <= 1000; offset++ {
			if err := e.enqueueEvent(fileFixtureEvent("progress", 1, offset)); err != nil {
				produced <- err
				return
			}
		}
		if err := e.enqueueEvent(fileFixtureEvent("complete", 1, 8<<30)); err != nil {
			produced <- err
			return
		}
		marker := fileFixtureEvent("offer", 1, 0)
		marker.Kind = "closed"
		marker.Payload = nil
		produced <- e.enqueueEvent(marker)
	}()
	deadline := time.After(5 * time.Second)
	var offset uint64
	terminal, offer := false, false
	for {
		select {
		case event := <-e.events:
			if event.Kind == "closed" {
				if !offer || !terminal {
					t.Fatal("important state lost")
				}
				if err := <-produced; err != nil {
					t.Fatal(err)
				}
				return
			}
			file, ok := nativeFileEvent(event)
			if !ok {
				t.Fatal("malformed delivered event")
			}
			if file.Event == "offer" {
				offer = true
				continue
			}
			if terminal || !offer || file.Offset < offset {
				t.Fatal("progress reordered around offer/terminal")
			}
			offset = file.Offset
			terminal = file.Event == "complete"
		case <-deadline:
			t.Fatal("concurrent delivery stalled")
		}
	}
}

// TestMain provides a framed-IPC fixture child, not a media/authorization mock
// used to claim a working remote desktop. It deliberately emits more progress
// than the old queue held before replying to a command.
func TestMain(m *testing.M) {
	if len(os.Args) == 2 && os.Args[1] == "--host-inherited-pipe" {
		nativeMailboxFixtureProcess()
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func nativeMailboxFixtureProcess() {
	emit := func(value any) {
		body, err := json.Marshal(value)
		if err != nil {
			os.Exit(20)
		}
		var output bytes.Buffer
		_ = binary.Write(&output, binary.BigEndian, uint32(len(body)))
		output.Write(body)
		if _, err = output.WriteTo(os.Stdout); err != nil {
			os.Exit(21)
		}
	}
	for {
		var size uint32
		if binary.Read(os.Stdin, binary.BigEndian, &size) != nil {
			return
		}
		if size == 0 || size > maximumFrame {
			os.Exit(22)
		}
		body := make([]byte, size)
		if _, err := io.ReadFull(os.Stdin, body); err != nil {
			return
		}
		var request struct {
			ABI       int             `json:"abi"`
			ID        uint64          `json:"id"`
			Operation string          `json:"operation"`
			Payload   json.RawMessage `json:"payload"`
		}
		if json.Unmarshal(body, &request) != nil {
			os.Exit(23)
		}
		if request.Operation == "hello" {
			emit(map[string]any{"abi": 1, "id": request.ID, "ok": true, "result": map[string]any{"version": model.Version, "abi": 1, "max_frame_bytes": maximumFrame}})
			continue
		}
		if request.Operation != "test_progress_burst" {
			os.Exit(24)
		}
		for id := 1; id <= 64; id++ {
			emit(response{ABI: 1, Event: ptrEvent(fileFixtureEvent("offer", id, 0))})
		}
		for offset := uint64(1); offset <= 100; offset++ {
			for id := 1; id <= 64; id++ {
				emit(response{ABI: 1, Event: ptrEvent(fileFixtureEvent("progress", id, offset))})
			}
		}
		for id := 1; id <= 64; id++ {
			emit(response{ABI: 1, Event: ptrEvent(fileFixtureEvent("complete", id, 8<<30))})
		}
		emit(response{ABI: 1, ID: request.ID, OK: true})
	}
}

func ptrEvent(event remotehost.EngineEvent) *remotehost.EngineEvent { return &event }

func TestBlockedEventConsumerDoesNotBlockIPCRepliesOrKillWorker(t *testing.T) {
	path, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(body)
	e, err := New(context.Background(), Options{ExecutablePath: path, ExpectedSHA256: hex.EncodeToString(hash[:])})
	if err != nil {
		t.Fatal(err)
	}
	defer e.Shutdown()
	if err = e.call(context.Background(), "test_progress_burst", struct{}{}, nil); err != nil {
		t.Fatal("slow consumer prevented independent IPC reply", err)
	}
	for index := 0; index < 128; index++ {
		select {
		case event, open := <-e.Events():
			if !open {
				t.Fatal("worker died on progress")
			}
			file, _ := nativeFileEvent(event)
			want := "offer"
			if index >= 64 {
				want = "complete"
			}
			if file.Event != want {
				t.Fatalf("lost terminal/offer: %d %s", index, file.Event)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("pending event not delivered")
		}
	}
	if err = e.Shutdown(); err != nil {
		t.Fatal(err)
	}
}

func TestNativeHostProcess(t *testing.T) {
	path := os.Getenv("HT_REMOTE_HOST_TEST_EXE")
	if path == "" {
		t.Skip("requires explicitly built native WebRTC host")
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(body)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	engine, err := New(ctx, Options{ExecutablePath: path, ExpectedSHA256: hex.EncodeToString(hash[:])})
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown()
	capability, err := engine.Capabilities(ctx)
	if err != nil || !capability.Available || capability.Status != "ready" || len(capability.Displays) == 0 {
		t.Fatalf("native capability: %+v, %v", capability, err)
	}
	wantPermissions := []string{"view", "input.keyboard", "input.pointer", "input.text", "clipboard.read", "clipboard.write", "files.send", "files.receive"}
	if runtime.GOOS == "linux" {
		wantPermissions = []string{"view", "input.keyboard", "input.pointer"}
	}
	if !slices.Equal(capability.Permissions, wantPermissions) {
		t.Fatal("worker advertised unimplemented capabilities")
	}
	if !slices.Equal(capability.Codecs, []string{"H264", "VP8"}) {
		t.Fatalf("worker advertised an unexpected codec profile: %v", capability.Codecs)
	}
	ref := remotehost.SessionRef{SessionID: "a0000000-0000-4000-8000-000000000001", ConnectionEpoch: 1}
	prepared, err := engine.PrepareSession(ctx, ref)
	if err != nil || len(prepared.HostNonce) != 32 || len(prepared.DTLSFingerprintSHA256) != 95 || !json.Valid(prepared.EphemeralPublicJWK) {
		t.Fatalf("native preparation: %+v, %v", prepared, err)
	}
	if err = engine.Start(ctx, remotehost.StartRequest{SessionRef: ref, Prepared: prepared}); err == nil {
		t.Fatal("unsigned empty authorization started a capture session")
	}
	select {
	case event := <-engine.Events():
		if event.Kind != "closed" || event.SessionID != ref.SessionID {
			t.Fatalf("unexpected rejection event %+v", event)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("invalid authorization did not close native session")
	}
	if err = engine.Shutdown(); err != nil {
		t.Fatal(err)
	}
	if _, err = engine.Capabilities(ctx); err == nil {
		t.Fatal("worker survived shutdown")
	}
}
