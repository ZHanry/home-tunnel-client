//go:build windows

package remoteengine

import (
	"os/exec"
	"syscall"
)

func configure(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
}
