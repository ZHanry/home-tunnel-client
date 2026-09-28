//go:build !windows

package gui

import (
	"os/exec"
	"runtime"
)

// openSystemBrowser opens address in the desktop's default browser. The URL is
// passed as one argument; no shell is involved.
func openSystemBrowser(address string) error {
	name := "xdg-open"
	if runtime.GOOS == "darwin" {
		name = "open"
	}
	command := exec.Command(name, address)
	if err := command.Start(); err != nil {
		return err
	}
	go func() { _ = command.Wait() }()
	return nil
}
