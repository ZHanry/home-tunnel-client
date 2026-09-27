//go:build windows

package windowshost

import (
	"bytes"
	"context"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Microsoft/go-winio"
	"golang.org/x/sys/windows"
)

func TestControlFramesAndBounds(t *testing.T) {
	var buffer bytes.Buffer
	if err := writeControl(&buffer, ControlRequest{Version: 1, Operation: "status"}); err != nil {
		t.Fatal(err)
	}
	var request ControlRequest
	if err := readControl(&buffer, &request); err != nil || request.Operation != "status" {
		t.Fatal(err)
	}
	for _, body := range []string{`{"version":1,"operation":"status","command":"cmd.exe"}`, `{"version":1} {}`} {
		buffer.Reset()
		binary.Write(&buffer, binary.BigEndian, uint32(len(body)))
		buffer.WriteString(body)
		if readControl(&buffer, &request) == nil {
			t.Fatal("unbounded or unknown control data accepted")
		}
	}
	buffer.Reset()
	binary.Write(&buffer, binary.BigEndian, uint32(controlLimit+1))
	if readControl(&buffer, &request) == nil {
		t.Fatal("oversized request accepted")
	}
}
func TestPipeIdentityComesFromKernel(t *testing.T) {
	path := `\\.\pipe\HomeTunnel-test-` + filepath.Base(t.TempDir())
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		t.Fatal(err)
	}
	listener, err := winio.ListenPipe(path, &winio.PipeConfig{SecurityDescriptor: "D:P(A;;GA;;;" + user.User.Sid.String() + ")"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	result := make(chan error, 1)
	go func() {
		conn, err := winio.DialPipeContext(ctx, path)
		if err != nil {
			result <- err
			return
		}
		defer conn.Close()
		result <- authenticatedService(conn)
	}()
	conn, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	pid, err := pipeClientPID(conn)
	if err != nil || pid != uint32(os.Getpid()) {
		t.Fatal("pipe client PID was not authenticated", pid, err)
	}
	if err = <-result; err == nil {
		t.Fatal("an unrelated pipe server impersonated the SCM service")
	}
}
func TestTrayAndServiceHaveOneAtomicOwner(t *testing.T) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		t.Fatal(err)
	}
	identity := t.TempDir()
	release, held, err := AcquireOwner(identity)
	if err != nil || held {
		t.Fatal(err, held)
	}
	defer release()
	second, held, err := AcquireServiceOwner(identity, user.User.Sid.String())
	if second != nil {
		second()
	}
	if err != nil || !held {
		t.Fatal("service acquired simultaneous ownership", held, err)
	}
}

func TestServiceStopJoinsIdleControlReaders(t *testing.T) {
	path := `\\.\pipe\HomeTunnel-stop-test-` + filepath.Base(t.TempDir())
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		t.Fatal(err)
	}
	listener, err := winio.ListenPipe(path, &winio.PipeConfig{SecurityDescriptor: "D:P(A;;GA;;;" + user.User.Sid.String() + ")"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- (&Supervisor{}).serveListener(ctx, listener) }()
	dial, stop := context.WithTimeout(ctx, time.Second)
	defer stop()
	conn, err := winio.DialPipeContext(dial, path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	// A client stalls halfway through the length header. Service shutdown
	// must close/join that reader, rather than wait for its five-second limit.
	if _, err = conn.Write([]byte{0}); err != nil {
		t.Fatal(err)
	}
	cancel()
	select {
	case err = <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("service shutdown did not join the blocked pipe reader")
	}
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, err = conn.Read(make([]byte, 1)); err == nil {
		t.Fatal("service left a management connection alive after shutdown")
	}
}
