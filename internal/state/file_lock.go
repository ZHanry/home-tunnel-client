package state

import (
	"fmt"
	"os"
	"path/filepath"
)

// Keep the lock in a separate stable file: state.json itself is atomically
// replaced on every save. Locks are released by the OS if a process exits.
func (store Store) lockFile() (func(), error) {
	if err := os.MkdirAll(filepath.Dir(store.Path), 0o700); err != nil {
		return nil, fmt.Errorf("create state directory: %w", err)
	}
	file, err := os.OpenFile(store.Path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open state lock: %w", err)
	}
	if err := lockStateFile(file); err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("lock state: %w", err)
	}
	return func() {
		unlockStateFile(file)
		_ = file.Close()
	}, nil
}
