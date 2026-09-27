package remoteengine

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

type transportProcess struct {
	done   chan struct{}
	killed atomic.Bool
	waited atomic.Bool
	close  func() error
}

func (p *transportProcess) ProcessID() int { return 123 }
func (p *transportProcess) Wait() error    { <-p.done; p.waited.Store(true); return nil }
func (p *transportProcess) Kill() error    { p.killed.Store(true); return p.close() }

func transportFixture(t *testing.T, version string) (*transportProcess, net.Conn, <-chan string) {
	t.Helper()
	client, worker := net.Pipe()
	t.Cleanup(func() { client.Close(); worker.Close() })
	process := &transportProcess{done: make(chan struct{}), close: worker.Close}
	calls := make(chan string, 8)
	go func() {
		defer close(process.done)
		defer worker.Close()
		for {
			var length uint32
			if binary.Read(worker, binary.BigEndian, &length) != nil {
				return
			}
			if length > maximumFrame {
				return
			}
			body := make([]byte, length)
			if _, err := io.ReadFull(worker, body); err != nil {
				return
			}
			var request struct {
				ID        uint64
				Operation string
				Payload   json.RawMessage
			}
			if json.Unmarshal(body, &request) != nil {
				return
			}
			calls <- request.Operation
			result := any(map[string]any{})
			if request.Operation == "hello" {
				result = map[string]any{"version": version, "abi": 1, "max_frame_bytes": maximumFrame}
			}
			reply, _ := json.Marshal(map[string]any{"abi": 1, "id": request.ID, "ok": true, "result": result})
			frame := make([]byte, 4+len(reply))
			binary.BigEndian.PutUint32(frame, uint32(len(reply)))
			copy(frame[4:], reply)
			// Fragment the header/body to exercise the stream transport.
			for len(frame) > 0 {
				n := min(3, len(frame))
				if _, err := worker.Write(frame[:n]); err != nil {
					return
				}
				frame = frame[n:]
			}
		}
	}()
	return process, client, calls
}

func TestAuthenticatedTransportOwnsLifecycle(t *testing.T) {
	process, pipe, calls := transportFixture(t, model.Version)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	engine, err := NewTransport(ctx, process, pipe, pipe)
	if err != nil {
		t.Fatal(err)
	}
	if engine.ProcessID() != 123 || <-calls != "hello" {
		t.Fatal("transport handshake lost worker identity")
	}
	if err = engine.DelegateDesktop(ctx, 2, time.Now().Add(time.Second), DesktopPolicy{}); err != nil {
		t.Fatal(err)
	}
	if <-calls != "service_desktop" {
		t.Fatal("delegation did not reach private transport")
	}
	if err = engine.AdoptUserToken(ctx, 0); err != nil {
		t.Fatal(err)
	}
	if <-calls != "user_context" {
		t.Fatal("user revocation was not delivered")
	}
	cancel()
	if err = engine.Shutdown(); err != nil {
		t.Fatal(err)
	}
	if !process.waited.Load() || process.killed.Load() {
		t.Fatal("normal EOF must reap the worker without killing it")
	}
}

func TestTransportMismatchClosesAndReaps(t *testing.T) {
	process, pipe, _ := transportFixture(t, "foreign-version")
	if engine, err := NewTransport(context.Background(), process, pipe, pipe); err == nil || engine != nil {
		t.Fatal("foreign worker ABI/version was accepted")
	}
	if !process.waited.Load() {
		t.Fatal("failed handshake leaked the child")
	}
}
