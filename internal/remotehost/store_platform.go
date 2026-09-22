//go:build windows || darwin

package remotehost

import (
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/state"
)

type credentialBackend struct{ path string }

func platformBackend(path string) (protectedBackend, error) { return credentialBackend{path}, nil }
func (b credentialBackend) Load() ([]byte, error) {
	saved, e := (state.Store{Path: b.path}).Load()
	if e != nil {
		return nil, e
	}
	return []byte(saved.DeviceCredential), nil
}
func (b credentialBackend) Save(data []byte) error {
	return (state.Store{Path: b.path}).Save(model.State{InstallID: "remote-host", DeviceCredential: string(data)})
}
