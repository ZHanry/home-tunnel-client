// Package remoteengine adapts the hash-pinned native host's private IPC to the
// desktop host control plane. Browser requests never choose executables or keys.
package remoteengine

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

const maximumFrame = 262144

type Options struct {
	ExecutablePath string
	ExpectedSHA256 string
	// InputTargetProcessID narrows integration-test injection to a dedicated
	// foreground process. It is installation/test configuration, never HTTP input.
	InputTargetProcessID uint32
}

type response struct {
	ABI       int                     `json:"abi"`
	ID        uint64                  `json:"id,omitempty"`
	OK        bool                    `json:"ok,omitempty"`
	Result    json.RawMessage         `json:"result,omitempty"`
	ErrorCode string                  `json:"error_code,omitempty"`
	Event     *remotehost.EngineEvent `json:"event,omitempty"`
}

type Engine struct {
	command *exec.Cmd
	input   io.WriteCloser
	output  io.ReadCloser
	events  chan remotehost.EngineEvent
	done    chan struct{}
	stopped chan struct{}
	writeMu sync.Mutex
	mu      sync.Mutex
	next    uint64
	pending map[uint64]chan response
	err     error
	once    sync.Once
}

var _ remotehost.HostEngine = (*Engine)(nil)

// New accepts installation metadata from the verified local release manifest.
func New(parent context.Context, options Options) (*Engine, error) {
	if err := verifyExecutable(options); err != nil {
		return nil, err
	}
	arguments := []string{"--host-inherited-pipe"}
	if options.InputTargetProcessID != 0 {
		arguments = append(arguments, "--input-target-pid="+strconv.FormatUint(uint64(options.InputTargetProcessID), 10))
	}
	command := exec.Command(options.ExecutablePath, arguments...)
	configure(command)
	command.Dir = filepath.Dir(options.ExecutablePath)
	command.Env = environment()
	command.Stderr = io.Discard
	input, err := command.StdinPipe()
	if err != nil {
		return nil, err
	}
	output, err := command.StdoutPipe()
	if err != nil {
		_ = input.Close()
		return nil, err
	}
	if err = command.Start(); err != nil {
		_ = input.Close()
		_ = output.Close()
		return nil, err
	}
	engine := &Engine{command: command, input: input, output: output, events: make(chan remotehost.EngineEvent, 64), done: make(chan struct{}), stopped: make(chan struct{}), pending: map[uint64]chan response{}}
	go engine.read()
	go func() {
		select {
		case <-parent.Done():
			engine.fail(parent.Err())
		case <-engine.stopped:
		}
	}()
	var hello struct {
		Version       string `json:"version"`
		ABI           int    `json:"abi"`
		MaxFrameBytes int    `json:"max_frame_bytes"`
	}
	if err = engine.call(parent, "hello", struct{}{}, &hello); err != nil || hello.Version != model.Version || hello.ABI != 1 || hello.MaxFrameBytes != maximumFrame {
		_ = engine.Shutdown()
		return nil, errors.New("native host version/ABI does not match this application")
	}
	return engine, nil
}

func verifyExecutable(options Options) error {
	if !filepath.IsAbs(options.ExecutablePath) || len(options.ExpectedSHA256) != 64 {
		return errors.New("native host requires an absolute installation path and pinned SHA256")
	}
	want, err := hex.DecodeString(options.ExpectedSHA256)
	if err != nil || len(want) != sha256.Size {
		return errors.New("invalid native host digest")
	}
	file, err := os.Open(options.ExecutablePath)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > 256<<20 {
		return errors.New("invalid native host executable")
	}
	hash := sha256.New()
	if _, err = io.Copy(hash, file); err != nil {
		return err
	}
	if !bytes.Equal(hash.Sum(nil), want) {
		return errors.New("native host digest mismatch")
	}
	return nil
}

func environment() []string {
	allowed := map[string]bool{"SYSTEMROOT": true, "WINDIR": true, "TEMP": true, "TMP": true, "USERPROFILE": true, "HOME": true, "LANG": true, "LC_ALL": true}
	var values []string
	for _, value := range os.Environ() {
		key, _, _ := strings.Cut(value, "=")
		if allowed[strings.ToUpper(key)] {
			values = append(values, value)
		}
	}
	return values
}

func (e *Engine) fail(err error) {
	e.once.Do(func() {
		e.mu.Lock()
		e.err = err
		e.mu.Unlock()
		// EOF asks the native command loop to release this session's injected
		// keys/buttons before exiting. CommandContext would terminate it first.
		_ = e.input.Close()
		close(e.done)
		go func() {
			select {
			case <-e.stopped:
			case <-time.After(4 * time.Second):
				_ = e.command.Process.Kill()
			}
		}()
	})
}

func (e *Engine) read() {
	defer close(e.stopped)
	defer close(e.events)
	defer func() {
		// Continue consuming shutdown events so the worker cannot block while
		// releasing input. The fail deadline still bounds a malformed worker.
		_, _ = io.Copy(io.Discard, e.output)
		_ = e.output.Close()
		_ = e.command.Wait()
	}()
	for {
		var size uint32
		if err := binary.Read(e.output, binary.BigEndian, &size); err != nil {
			e.fail(fmt.Errorf("native host stopped: %w", err))
			return
		}
		if size == 0 || size > maximumFrame {
			e.fail(errors.New("native host response exceeds bound"))
			return
		}
		body := make([]byte, size)
		if _, err := io.ReadFull(e.output, body); err != nil {
			e.fail(err)
			return
		}
		var reply response
		if err := decode(body, &reply); err != nil || reply.ABI != 1 {
			e.fail(errors.New("invalid native host response"))
			return
		}
		if reply.Event != nil {
			if reply.ID != 0 || reply.OK || len(reply.Result) != 0 || reply.ErrorCode != "" || !validEvent(*reply.Event) {
				e.fail(errors.New("invalid native host event"))
				return
			}
			select {
			case e.events <- *reply.Event:
			default:
				e.fail(errors.New("native host event queue exceeded"))
				return
			}
			continue
		}
		e.mu.Lock()
		pending := e.pending[reply.ID]
		delete(e.pending, reply.ID)
		e.mu.Unlock()
		if pending == nil || (reply.OK && reply.ErrorCode != "") || (!reply.OK && reply.ErrorCode == "") {
			e.fail(errors.New("unsolicited native host response"))
			return
		}
		pending <- reply
	}
}

func validEvent(event remotehost.EngineEvent) bool {
	if event.SessionID == "" || event.ConnectionEpoch < 1 || event.ConnectionEpoch > 0xffffffff || len(event.Payload) > 32768 {
		return false
	}
	switch event.Kind {
	case "outgoing_signal":
		return len(event.Transcript) == 0 && (event.SignalType == "peer.answer" || event.SignalType == "peer.candidates" || event.SignalType == "peer.candidates_done")
	case "sign_peer_proof":
		return len(event.Transcript) == 222 && event.RequestID != "" && len(event.RequestID) <= 128 && len(event.Payload) == 0
	case "verified_ready", "closed", "failed":
		return len(event.Transcript) == 0
	}
	return false
}

func (e *Engine) call(parent context.Context, operation string, payload any, result any) error {
	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()
	stopCancellation := context.AfterFunc(ctx, func() { e.fail(ctx.Err()) })
	defer stopCancellation()
	e.writeMu.Lock()
	e.mu.Lock()
	if e.err != nil {
		err := e.err
		e.mu.Unlock()
		e.writeMu.Unlock()
		return err
	}
	if len(e.pending) >= 32 {
		e.mu.Unlock()
		e.writeMu.Unlock()
		return errors.New("native host concurrent request limit exceeded")
	}
	e.next++
	id := e.next
	pending := make(chan response, 1)
	e.pending[id] = pending
	e.mu.Unlock()
	body, err := json.Marshal(struct {
		ABI       int    `json:"abi"`
		ID        uint64 `json:"id"`
		Operation string `json:"operation"`
		Payload   any    `json:"payload"`
	}{1, id, operation, payload})
	if err == nil && (len(body) == 0 || len(body) > maximumFrame) {
		err = errors.New("native host request exceeds bound")
	}
	if err == nil {
		var frame bytes.Buffer
		_ = binary.Write(&frame, binary.BigEndian, uint32(len(body)))
		frame.Write(body)
		_, err = io.Copy(e.input, &frame)
	}
	e.writeMu.Unlock()
	if err != nil {
		e.fail(err)
		return err
	}
	select {
	case reply := <-pending:
		if !reply.OK {
			return fmt.Errorf("native host rejected operation: %s", reply.ErrorCode)
		}
		if result != nil {
			if err = decode(reply.Result, result); err != nil {
				e.fail(err)
				return err
			}
		}
		return nil
	case <-ctx.Done():
		e.fail(ctx.Err())
		return ctx.Err()
	case <-e.done:
		e.mu.Lock()
		defer e.mu.Unlock()
		return e.err
	}
}

func (e *Engine) Capabilities(ctx context.Context) (remotehost.Capabilities, error) {
	var result remotehost.Capabilities
	err := e.call(ctx, "capabilities", struct{}{}, &result)
	if err == nil && (len(result.Permissions) > 10 || len(result.Displays) > 16 || len(result.Codecs) > 16) {
		err = errors.New("native host capability exceeds bound")
		e.fail(err)
	}
	return result, err
}
func (e *Engine) PrepareSession(ctx context.Context, ref remotehost.SessionRef) (remotehost.PreparedSession, error) {
	var result remotehost.PreparedSession
	err := e.call(ctx, "prepare", ref, &result)
	if err == nil && (len(result.HostNonce) != 32 || len(result.DTLSFingerprintSHA256) != 95 || len(result.EphemeralPublicJWK) > 1024) {
		err = errors.New("native host returned invalid prepared identity")
		e.fail(err)
	}
	return result, err
}
func (e *Engine) Start(ctx context.Context, request remotehost.StartRequest) error {
	return e.call(ctx, "start", request, nil)
}
func (e *Engine) OnSignal(ctx context.Context, ref remotehost.SessionRef, signal json.RawMessage) error {
	return e.call(ctx, "signal", struct {
		remotehost.SessionRef
		Signal json.RawMessage `json:"signal"`
	}{ref, signal}, nil)
}
func (e *Engine) RespondProof(ctx context.Context, ref remotehost.SessionRef, request string, signature []byte) error {
	if len(signature) != 64 || request == "" || len(request) > 128 {
		return remotehost.ErrAuthorization
	}
	return e.call(ctx, "proof", struct {
		remotehost.SessionRef
		RequestID string `json:"request_id"`
		Signature []byte `json:"signature"`
	}{ref, request, signature}, nil)
}
func (e *Engine) Events() <-chan remotehost.EngineEvent { return e.events }

// ProcessID identifies this instance's worker for local lifecycle diagnostics.
// It is never exposed to a browser or accepted as a remote command target.
func (e *Engine) ProcessID() int { return e.command.Process.Pid }

// Diagnostics reports bounded counters, never injected input values or content.
func (e *Engine) Diagnostics(ctx context.Context) (map[string]json.RawMessage, error) {
	var result map[string]json.RawMessage
	err := e.call(ctx, "diagnostics", struct{}{}, &result)
	return result, err
}
func (e *Engine) Close(ctx context.Context, ref remotehost.SessionRef, reason string) error {
	return e.call(ctx, "close", struct {
		remotehost.SessionRef
		Reason string `json:"reason"`
	}{ref, reason}, nil)
}
func (e *Engine) Shutdown() error {
	e.fail(context.Canceled)
	select {
	case <-e.stopped:
		return nil
	case <-time.After(5 * time.Second):
		return errors.New("native host did not stop within deadline")
	}
}

func decode(body []byte, value any) error {
	if len(body) == 0 || len(body) > maximumFrame || !utf8.Valid(body) || !json.Valid(body) {
		return errors.New("invalid bounded native JSON")
	}
	// Detect duplicate decoded object keys before Go's decoder can discard them.
	probe := json.NewDecoder(bytes.NewReader(body))
	probe.UseNumber()
	var walk func(int) error
	walk = func(depth int) error {
		if depth > 20 {
			return errors.New("native JSON nesting exceeds bound")
		}
		token, err := probe.Token()
		if err != nil {
			return err
		}
		if delim, ok := token.(json.Delim); ok {
			switch delim {
			case '{':
				seen := map[string]bool{}
				for probe.More() {
					key, err := probe.Token()
					name, ok := key.(string)
					if err != nil || !ok || seen[name] || len(seen) >= 128 {
						return errors.New("invalid duplicate native JSON key")
					}
					seen[name] = true
					if err = walk(depth + 1); err != nil {
						return err
					}
				}
			case '[':
				count := 0
				for probe.More() {
					count++
					if count > 128 {
						return errors.New("native JSON array exceeds bound")
					}
					if err = walk(depth + 1); err != nil {
						return err
					}
				}
			default:
				return errors.New("invalid native JSON delimiter")
			}
			_, err = probe.Token()
			return err
		}
		return nil
	}
	if err := walk(0); err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	return decoder.Decode(value)
}
