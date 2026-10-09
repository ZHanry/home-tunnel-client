package main

import (
	"errors"
	"golang.org/x/sys/windows"
	"os"
	"path/filepath"
	"strings"
	"unsafe"
)

func checkParent(parentID uint32) error {
	snapshot, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(snapshot)
	var entry windows.ProcessEntry32
	entry.Size = uint32(unsafe.Sizeof(entry))
	err = windows.Process32First(snapshot, &entry)
	matched := false
	for err == nil {
		if entry.ProcessID == uint32(os.Getpid()) {
			matched = entry.ParentProcessID == parentID
			break
		}
		err = windows.Process32Next(snapshot, &entry)
	}
	if !matched {
		return errors.New("parent mismatch")
	}
	process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, parentID)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(process)
	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	if err = windows.QueryFullProcessImageName(process, 0, &buffer[0], &size); err != nil {
		return err
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	expected := filepath.Join(filepath.Dir(filepath.Dir(executable)), parentExecutable)
	if !strings.EqualFold(filepath.Clean(windows.UTF16ToString(buffer[:size])), filepath.Clean(expected)) {
		return errors.New("parent image mismatch")
	}
	return nil
}
func protectDirectory(path string) error {
	if err := os.MkdirAll(path, 0700); err != nil {
		return err
	}
	descriptor, err := windows.SecurityDescriptorFromString("D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;OW)")
	if err != nil {
		return err
	}
	dacl, _, err := descriptor.DACL()
	if err != nil {
		return err
	}
	return windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT,
		windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION,
		nil, nil, dacl, nil)
}
