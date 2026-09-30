package state

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestStateWriterProcess(t *testing.T) {
	path := os.Getenv("HOME_TUNNEL_TEST_STATE_WRITER")
	if path == "" {
		return
	}
	fmt.Println("ready")
	if err := (Store{Path: path}).Save(enrolledNameState()); err != nil {
		t.Fatal(err)
	}
}

func TestFileLockPreventsCrossProcessNameLoss(t *testing.T) {
	store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
	original := enrolledNameState()
	if err := store.Save(original); err != nil {
		t.Fatal(err)
	}
	release, err := store.lockFile()
	if err != nil {
		t.Fatal(err)
	}
	locked := true
	defer func() {
		if locked {
			release()
		}
	}()
	command := exec.Command(os.Args[0], "-test.run=^TestStateWriterProcess$")
	command.Env = append(os.Environ(), "HOME_TUNNEL_TEST_STATE_WRITER="+store.Path)
	stdout, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if command.ProcessState == nil {
			_ = command.Process.Kill()
			_ = command.Wait()
		}
	}()
	reader := bufio.NewReader(stdout)
	if line, err := reader.ReadString('\n'); err != nil || line != "ready\n" {
		t.Fatalf("child not ready: %q %v", line, err)
	}
	finished := make(chan error, 1)
	go func() { finished <- command.Wait() }()
	select {
	case err := <-finished:
		t.Fatalf("another process wrote through the state lock: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	original.DeviceName = "Cross-process rename"
	if err := store.save(original, false); err != nil {
		t.Fatal(err)
	}
	release()
	locked = false
	select {
	case err := <-finished:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("writer did not resume after unlocking")
	}
	fresh, err := store.Load()
	if err != nil || fresh.DeviceName != "Cross-process rename" {
		t.Fatalf("other process lost name: %#v %v", fresh, err)
	}
}
