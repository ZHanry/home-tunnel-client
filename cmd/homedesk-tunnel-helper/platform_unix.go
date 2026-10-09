//go:build linux || darwin

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func checkParent(parentID uint32) error {
	if int(parentID) != os.Getppid() {
		return errors.New("parent mismatch")
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	expected, err := filepath.EvalSymlinks(filepath.Join(filepath.Dir(filepath.Dir(executable)), parentExecutable))
	if err != nil {
		return err
	}
	var image string
	if runtime.GOOS == "linux" {
		image, err = os.Readlink(fmt.Sprintf("/proc/%d/exe", parentID))
	} else {
		var value []byte
		value, err = exec.Command("/bin/ps", "-p", fmt.Sprint(parentID), "-o", "comm=").Output()
		image = strings.TrimSpace(string(value))
	}
	if err != nil {
		return err
	}
	image, err = filepath.EvalSymlinks(image)
	if err != nil || image != expected {
		return errors.New("parent image mismatch")
	}
	return nil
}

func protectDirectory(path string) error {
	if err := os.MkdirAll(path, 0700); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("unsafe state directory")
	}
	return os.Chmod(path, 0700)
}
