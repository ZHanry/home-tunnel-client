package state

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

func TestNativeCredentialProtectionAndLegacyMigration(t *testing.T) {
	if runtime.GOOS != "windows" && runtime.GOOS != "darwin" {
		t.Skip("OS vault test")
	}
	store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
	input := model.State{InstallID: "legacy-install", DeviceID: "test-device", DeviceCredential: "legacy-plaintext-device-secret"}
	raw, _ := json.Marshal(input)
	if err := os.WriteFile(store.Path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	loaded, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.DeviceCredential != input.DeviceCredential {
		t.Fatal("migration lost credential")
	}
	protected, err := os.ReadFile(store.Path)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(protected, []byte(input.DeviceCredential)) {
		t.Fatal("credential remains in JSON")
	}
	var disk model.State
	if err = json.Unmarshal(protected, &disk); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(disk.DeviceCredential, "dpapi:") && !strings.HasPrefix(disk.DeviceCredential, "keychain:") {
		t.Fatal("missing native protection")
	}
	loaded, err = store.Load()
	if err != nil || loaded.DeviceCredential != input.DeviceCredential {
		t.Fatal("protected roundtrip failed", err)
	}
	if err = store.Save(model.State{InstallID: input.InstallID}); err != nil {
		t.Fatal(err)
	}
}

func TestWrongPlatformCredentialFailsWithoutDestroyingState(t *testing.T) {
	store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
	input := `{"install_id":"test","device_credential":"dpapi:invalid"}`
	if err := os.WriteFile(store.Path, []byte(input), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load(); err == nil {
		t.Fatal("invalid ciphertext was used as a credential")
	}
	raw, err := os.ReadFile(store.Path)
	if err != nil || string(raw) != input {
		t.Fatal("original state was destroyed")
	}
}
