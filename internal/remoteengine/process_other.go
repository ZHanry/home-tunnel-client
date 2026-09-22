//go:build !windows

package remoteengine

import "os/exec"

func configure(command *exec.Cmd) {}
