package state

import (
	"errors"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

var ErrEnrollmentChanged = errors.New("current device enrollment changed")

func sameDevice(left, right model.State) bool {
	return left.InstallID != "" && left.InstallID == right.InstallID &&
		left.DeviceID != "" && left.DeviceID == right.DeviceID &&
		left.Profile.APIBaseURL == right.Profile.APIBaseURL
}

// SetDeviceName updates only the current enrollment's name, never an old copy
// of its runtime state. A login/logout or credential change invalidates an
// in-flight rename. Save preserves this value against older service snapshots.
func (store Store) SetDeviceName(expected model.State, name string) error {
	return store.updateDeviceName(expected, name, false)
}

// RefreshDeviceName ignores a server list fetched before a newer rename. The
// comparison and write share the same process/file locks as ordinary saves.
func (store Store) RefreshDeviceName(expected model.State, name string) error {
	return store.updateDeviceName(expected, name, true)
}

func (store Store) updateDeviceName(expected model.State, name string, compareName bool) error {
	name, err := model.NormalizeDeviceName(name)
	if err != nil {
		return err
	}
	persistenceMu.Lock()
	defer persistenceMu.Unlock()
	release, err := store.lockFile()
	if err != nil {
		return err
	}
	defer release()
	current, err := store.load(false)
	if err != nil {
		return err
	}
	if !sameDevice(current, expected) || !current.Enrolled() || current.DeviceCredential != expected.DeviceCredential {
		return ErrEnrollmentChanged
	}
	if compareName && current.DeviceName != expected.DeviceName {
		return nil
	}
	if current.DeviceName == name {
		return nil
	}
	current.DeviceName = name
	return store.save(current, false)
}
