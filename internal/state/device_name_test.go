package state

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

func enrolledNameState() model.State {
	return model.State{InstallID: "installation", DeviceID: "device-one", DeviceCredential: "credential", DeviceName: "Old name",
		Profile: model.Profile{PublicBaseURL: "https://example.com/", APIBaseURL: "https://example.com/api/v1/"}}
}

func TestDeviceNamePersistsAcrossRuntimeSavesAndRestart(t *testing.T) {
	store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
	original := enrolledNameState()
	if err := store.Save(original); err != nil {
		t.Fatal(err)
	}
	var writers sync.WaitGroup
	for range 12 {
		writers.Go(func() {
			if err := store.Save(original); err != nil {
				t.Error(err)
			}
		})
	}
	if err := store.SetDeviceName(original, "  New name  "); err != nil {
		t.Fatal(err)
	}
	writers.Wait()
	original.LastConfigVersion = 42
	if err := store.Save(original); err != nil {
		t.Fatal(err)
	}
	fresh, err := (Store{Path: store.Path}).Load()
	if err != nil || fresh.DeviceName != "New name" || fresh.LastConfigVersion != 42 {
		t.Fatalf("runtime save lost renamed name/state: %#v, %v", fresh, err)
	}
}

func TestDeviceNameRejectsChangedEnrollmentAndMissingState(t *testing.T) {
	for _, change := range []string{"device", "server", "credential", "removed"} {
		t.Run(change, func(t *testing.T) {
			store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
			original := enrolledNameState()
			if err := store.Save(original); err != nil {
				t.Fatal(err)
			}
			replacement := original
			switch change {
			case "device":
				replacement.DeviceID = "other"
			case "server":
				replacement.Profile.APIBaseURL = "https://other.example/api/v1/"
			case "credential":
				replacement.DeviceCredential = "replacement"
			}
			if change == "removed" {
				if err := os.Remove(store.Path); err != nil {
					t.Fatal(err)
				}
			} else if err := store.Save(replacement); err != nil {
				t.Fatal(err)
			}
			if err := store.SetDeviceName(original, "Wrong name"); !errors.Is(err, ErrEnrollmentChanged) {
				t.Fatalf("changed enrollment accepted: %v", err)
			}
			if change == "removed" {
				if _, err := os.Stat(store.Path); !os.IsNotExist(err) {
					t.Fatal("rename restored signed-out state")
				}
			} else {
				current, err := store.Load()
				if err != nil || current.DeviceName == "Wrong name" {
					t.Fatalf("rename changed another enrollment: %v", err)
				}
			}
		})
	}
}

func TestDeviceNameRefreshDoesNotUndoLaterRename(t *testing.T) {
	store := Store{Path: filepath.Join(t.TempDir(), "state.json")}
	original := enrolledNameState()
	if err := store.Save(original); err != nil {
		t.Fatal(err)
	}
	if err := store.SetDeviceName(original, "Newer explicit name"); err != nil {
		t.Fatal(err)
	}
	if err := store.RefreshDeviceName(original, "Stale server response"); err != nil {
		t.Fatal(err)
	}
	current, err := store.Load()
	if err != nil || current.DeviceName != "Newer explicit name" {
		t.Fatalf("stale refresh reverted rename: %#v %v", current, err)
	}
	if err := store.RefreshDeviceName(current, "Reconciled after network interruption"); err != nil {
		t.Fatal(err)
	}
	fresh, err := store.Load()
	if err != nil || fresh.DeviceName != "Reconciled after network interruption" {
		t.Fatalf("current refresh failed: %#v %v", fresh, err)
	}
}
