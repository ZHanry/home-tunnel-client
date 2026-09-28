//go:build windows

package gui

import (
	"os/exec"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/windows"
)

// openSystemBrowser asks the Windows URL protocol handler to open address in
// the user's default browser. rundll32 is resolved from System32 and receives
// the URL as a single argument, so no command shell parses it.
func openSystemBrowser(address string) error {
	system, err := windows.GetSystemDirectory()
	if err != nil {
		return err
	}
	command := exec.Command(filepath.Join(system, "rundll32.exe"), "url.dll,FileProtocolHandler", address)
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := command.Start(); err != nil {
		return err
	}
	go func() { _ = command.Wait() }()
	return nil
}
