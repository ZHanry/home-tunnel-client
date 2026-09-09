//go:build windows

package agent

import (
	"os/exec"
	"syscall"

	"golang.org/x/sys/windows"
)

// The console Agent is owned by the GUI/CLI supervisor and reports through its
// existing output handles. It must never allocate another console window.
func configureAgentProcess(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
}
