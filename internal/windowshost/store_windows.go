//go:build windows

package windowshost

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"unsafe"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"github.com/ZHanry/home-tunnel-client/internal/state"
	"golang.org/x/sys/windows"
)

type machineRecord struct {
	Schema   int             `json:"schema"`
	OwnerSID string          `json:"owner_sid"`
	Origin   string          `json:"origin"`
	DeviceID string          `json:"device_id"`
	Remote   json.RawMessage `json:"remote"`
}
type machineStore struct {
	mu     sync.Mutex
	path   string
	record machineRecord
	pins   []windows.Handle
}

func openMachineStore() (*machineStore, error) {
	current, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil || !current.User.Sid.IsWellKnown(windows.WinLocalSystemSid) {
		return nil, ErrRejected
	}
	root, err := windows.KnownFolderPath(windows.FOLDERID_ProgramData, 0)
	if err != nil {
		return nil, err
	}
	store := &machineStore{path: filepath.Join(root, "Home Tunnel", "service", "identity.json")}
	store.pins, err = pinAncestors(root)
	if err != nil {
		return nil, err
	}
	descriptor, err := windows.SecurityDescriptorFromString("O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)")
	if err != nil {
		store.Close()
		return nil, err
	}
	attributes := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: descriptor}
	for _, directory := range []string{filepath.Join(root, "Home Tunnel"), filepath.Dir(store.path)} {
		wide, _ := windows.UTF16PtrFromString(directory)
		if err = windows.CreateDirectory(wide, &attributes); err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
			store.Close()
			return nil, err
		}
		// A preexisting writable directory is rejected; it is never trusted
		// merely because its name matches, nor silently taken over.
		pin, pinErr := pinProtected(directory, true)
		if pinErr != nil {
			store.Close()
			return nil, pinErr
		}
		store.pins = append(store.pins, pin)
	}
	if _, err = os.Stat(store.path); errors.Is(err, os.ErrNotExist) {
		return store, nil
	}
	pin, err := pinProtected(store.path, false)
	if err != nil {
		store.Close()
		return nil, err
	}
	saved, err := (state.Store{Path: store.path}).Load()
	windows.CloseHandle(pin)
	if err != nil {
		store.Close()
		return nil, err
	}
	if len(saved.DeviceCredential) > 768<<10 || json.Unmarshal([]byte(saved.DeviceCredential), &store.record) != nil ||
		store.record.Schema != 1 || store.record.OwnerSID == "" || store.record.DeviceID == "" || len(store.record.Remote) == 0 {
		store.Close()
		return nil, ErrRejected
	}
	return store, nil
}
func (s *machineStore) Close() {
	for _, pin := range s.pins {
		windows.CloseHandle(pin)
	}
	s.pins = nil
}
func (s *machineStore) metadata() machineRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	copy := s.record
	copy.Remote = nil
	return copy
}
func (s *machineStore) Load() ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]byte(nil), s.record.Remote...), nil
}
func (s *machineStore) save(record machineRecord) error {
	raw, err := json.Marshal(record)
	if err != nil {
		return err
	}
	// state.Store uses DPAPI under LocalSystem and an atomic replacement.
	// Its parent is held with a protected ACL and without DELETE sharing.
	if err = (state.Store{Path: s.path}).Save(model.State{InstallID: "remote-system-service", DeviceCredential: string(raw)}); err != nil {
		return err
	}
	s.record = record
	return nil
}
func (s *machineStore) Save(raw []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.record.Schema != 1 || len(raw) > 512<<10 {
		return ErrRejected
	}
	next := s.record
	next.Remote = append([]byte(nil), raw...)
	return s.save(next)
}
func (s *machineStore) adopt(owner, origin, device string, raw []byte) error {
	if _, err := windows.StringToSid(owner); err != nil || !ValidEndpointID(device) {
		return ErrRejected
	}
	if err := remotehost.ValidateServiceTransfer(raw, origin); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.record.Schema != 0 {
		if s.record.OwnerSID == owner && s.record.Origin == origin && s.record.DeviceID == device &&
			remotehost.SameServiceIdentity(s.record.Remote, raw) {
			return nil
		}
		return ErrIdentity
	}
	return s.save(machineRecord{Schema: 1, OwnerSID: owner, Origin: origin, DeviceID: device, Remote: append([]byte(nil), raw...)})
}
