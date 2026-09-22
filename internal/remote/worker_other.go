//go:build !windows

package remote

import "os/exec"

func configureWorker(_ *exec.Cmd) {}
