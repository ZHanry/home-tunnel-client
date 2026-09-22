package remote

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

type testRuntime struct {
	mu               sync.Mutex
	releases, closes int
}

func (runtime *testRuntime) ReleaseInput() {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	runtime.releases++
}
func (runtime *testRuntime) Close() { runtime.mu.Lock(); defer runtime.mu.Unlock(); runtime.closes++ }

func TestSessionIsolationAndLimits(t *testing.T) {
	manager := NewSessionManager()
	runtimes := make([]*testRuntime, 4)
	for index := range 4 {
		runtimes[index] = &testRuntime{}
		identity := SessionIdentity{SessionID: fmt.Sprint(index), ServerInstanceID: "server", UserID: "user", HostEndpointID: fmt.Sprint(index)}
		if err := manager.Attach(ManagedSession{identity, runtimes[index]}); err != nil {
			t.Fatal(err)
		}
	}
	if err := manager.Attach(ManagedSession{SessionIdentity{"extra", "server", "user", "host5"}, &testRuntime{}}); err == nil {
		t.Fatal("fifth window admitted")
	}
	if err := manager.Focus("0"); err != nil {
		t.Fatal(err)
	}
	if err := manager.BindPeripheral("microphone", "0"); err != nil {
		t.Fatal(err)
	}
	if err := manager.Focus("1"); err != nil {
		t.Fatal(err)
	}
	if runtimes[0].releases != 1 || manager.microphone != "0" {
		t.Fatal("focus leaked microphone or did not release previous input")
	}
	manager.Close("0")
	if runtimes[0].closes != 1 || runtimes[1].closes != 0 || manager.microphone != "" {
		t.Fatal("close affected wrong window")
	}
	manager.RevokeAll()
	if len(manager.sessions) != 0 {
		t.Fatal("logout retained windows")
	}
	for _, runtime := range runtimes {
		if runtime.closes != 1 {
			t.Fatal("window not closed exactly once")
		}
	}
}

func TestConcurrentAttachDoesNotExceedLimit(t *testing.T) {
	manager := NewSessionManager()
	var group sync.WaitGroup
	for index := range 30 {
		group.Go(func() {
			_ = manager.Attach(ManagedSession{SessionIdentity{fmt.Sprint(index), "server", "user", fmt.Sprint(index)}, &testRuntime{}})
		})
	}
	group.Wait()
	if len(manager.sessions) != MaxControllerSessions {
		t.Fatalf("unexpected sessions: %d", len(manager.sessions))
	}
	manager.RevokeAll()
}

func TestAccountAndHostIsolation(t *testing.T) {
	manager := NewSessionManager()
	first := ManagedSession{SessionIdentity{"one", "server", "user", "host"}, &testRuntime{}}
	if err := manager.Attach(first); err != nil {
		t.Fatal(err)
	}
	for _, id := range []SessionIdentity{{"two", "other", "user", "host2"}, {"two", "server", "other", "host2"}, {"two", "server", "user", "host"}} {
		if err := manager.Attach(ManagedSession{id, &testRuntime{}}); err == nil {
			t.Fatal("cross-account, cross-server or duplicate host accepted")
		}
	}
}

func TestNativeBackendMissingFailsClosed(t *testing.T) {
	capability, err := QueryWorker(context.Background(), WorkerFiles{})
	if err != ErrUnavailable || capability.Available || capability.CanHost || capability.CanControl {
		t.Fatal("missing media backend claimed usable")
	}
}
func TestWorkerDoesNotInheritCredentialEnvironment(t *testing.T) {
	t.Setenv("HT_REMOTE_TEST_SECRET", "must-not-be-inherited")
	for _, value := range workerEnvironment() {
		if strings.HasPrefix(value, "HT_REMOTE_TEST_SECRET=") {
			t.Fatal("worker inherited unrelated secret environment")
		}
	}
}

func TestWorkerHashIsRequired(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.bin")
	if err := os.WriteFile(path, []byte("not an executable"), 0600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256([]byte("not an executable"))
	if err := verifyFile(path, hex.EncodeToString(sum[:])); err != nil {
		t.Fatal(err)
	}
	if err := verifyFile(path, fmt.Sprintf("%064x", 0)); err == nil {
		t.Fatal("wrong hash accepted")
	}
	if err := verifyFile("relative.exe", hex.EncodeToString(sum[:])); err == nil {
		t.Fatal("relative executable accepted")
	}
}

func TestBuiltWorkerIntegration(t *testing.T) {
	path := os.Getenv("HT_REMOTE_TEST_WORKER")
	library := os.Getenv("HT_REMOTE_TEST_LIBRARY")
	if path == "" || library == "" {
		t.Skip("set explicit paths to the CMake-built worker and shared library")
	}
	hash := func(path string) string {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(data)
		return hex.EncodeToString(sum[:])
	}
	capability, err := QueryWorker(context.Background(), WorkerFiles{path, hash(path), library, hash(library)})
	if err != nil {
		t.Fatal(err)
	}
	if capability.Available || capability.ABI != 1 {
		t.Fatal("unexpected worker capability")
	}
}
