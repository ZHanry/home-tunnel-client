//go:build !windows

package agent

import "os/exec"

func configureAgentProcess(*exec.Cmd) {}

func bindAgentToSupervisor(*exec.Cmd) {}
