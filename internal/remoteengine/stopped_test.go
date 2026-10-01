package remoteengine

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"testing"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

type stoppedFixtureProcess struct {
	wait chan struct{}
	err  error
}

func (p *stoppedFixtureProcess) ProcessID() int { return 321 }
func (p *stoppedFixtureProcess) Wait() error    { <-p.wait; return p.err }
func (p *stoppedFixtureProcess) Kill() error    { return nil }

type stoppedFixtureInput struct{ bytes.Buffer }

func (*stoppedFixtureInput) Close() error { return nil }

func stoppedFixture(t *testing.T, process Process) *Engine {
	t.Helper()
	e := &Engine{process: process, input: &stoppedFixtureInput{}, output: io.NopCloser(bytes.NewReader(nil)), done: make(chan struct{}), stopped: make(chan struct{})}
	go e.read()
	select {
	case <-e.done:
	case <-time.After(time.Second):
		t.Fatal("EOF did not fail IPC")
	}
	return e
}

func TestWaitStoppedRequiresReapedWorker(t *testing.T) {
	process := &stoppedFixtureProcess{wait: make(chan struct{})}
	e := stoppedFixture(t, process)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := e.WaitStopped(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("IPC EOF certified a live worker: %v", err)
	}
	close(process.wait)
	if err := e.WaitStopped(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := e.WaitStopped(context.Background()); err != nil {
		t.Fatal("confirmed stop was not stable", err)
	}
	canceled, cancelCanceled := context.WithCancel(context.Background())
	cancelCanceled()
	if err := e.WaitStopped(canceled); err != nil {
		t.Fatal("expired caller lost already-confirmed stop", err)
	}
}

func TestWaitStoppedRejectsWaitFailureAndHealthyWorker(t *testing.T) {
	e := &Engine{done: make(chan struct{})}
	if err := e.WaitStopped(context.Background()); !errors.Is(err, remotehost.ErrUnavailable) {
		t.Fatal("healthy worker did not return immediately", err)
	}
	process := &stoppedFixtureProcess{wait: make(chan struct{}), err: errors.New("OS wait failed")}
	close(process.wait)
	e = stoppedFixture(t, process)
	if err := e.WaitStopped(context.Background()); !errors.Is(err, remotehost.ErrUnavailable) {
		t.Fatal("arbitrary Wait error certified death", err)
	}
}

func TestWaitStoppedAcceptsActualNonzeroProcessExit(t *testing.T) {
	if os.Getenv("HT_TEST_STOPPED_CHILD") == "1" {
		os.Exit(23)
	}
	command := exec.Command(os.Args[0], "-test.run=^TestWaitStoppedAcceptsActualNonzeroProcessExit$")
	command.Env = append(os.Environ(), "HT_TEST_STOPPED_CHILD=1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	e := stoppedFixture(t, commandProcess{command})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := e.WaitStopped(ctx); err != nil {
		t.Fatal("OS-confirmed nonzero exit was not recognized", err)
	}
	if command.ProcessState == nil || command.ProcessState.ExitCode() != 23 {
		t.Fatal("wrong child status")
	}
}
