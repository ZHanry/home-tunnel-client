package remoteengine

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

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
	if len(capability.Permissions) != 4 || capability.Permissions[0] != "view" {
		t.Fatal("worker advertised unimplemented capabilities")
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
