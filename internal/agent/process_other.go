//go:build !windows

package agent

import "os/exec"

func configureAgentProcess(*exec.Cmd) {}
