//go:build windows

package state

import (
	"encoding/base64"
	"fmt"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

func CredentialProtection() string { return "Windows DPAPI (current Windows identity)" }

func protectCredential(plain, _ string) (string, error) {
	data := []byte(plain)
	input := windows.DataBlob{Size: uint32(len(data)), Data: &data[0]}
	var output windows.DataBlob
	if err := windows.CryptProtectData(&input, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &output); err != nil {
		return "", fmt.Errorf("protect device credential with DPAPI: %w", err)
	}
	defer windows.LocalFree(windows.Handle(uintptr(unsafe.Pointer(output.Data))))
	return "dpapi:" + base64.StdEncoding.EncodeToString(unsafe.Slice(output.Data, int(output.Size))), nil
}

func unprotectCredential(stored, _ string) (string, error) {
	if !strings.HasPrefix(stored, "dpapi:") {
		return "", fmt.Errorf("credential was protected for a different operating system")
	}
	data, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(stored, "dpapi:"))
	if err != nil || len(data) == 0 {
		return "", fmt.Errorf("invalid protected device credential")
	}
	input := windows.DataBlob{Size: uint32(len(data)), Data: &data[0]}
	var output windows.DataBlob
	if err = windows.CryptUnprotectData(&input, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &output); err != nil {
		return "", fmt.Errorf("unlock device credential using the original Windows identity: %w", err)
	}
	defer windows.LocalFree(windows.Handle(uintptr(unsafe.Pointer(output.Data))))
	return string(unsafe.Slice(output.Data, int(output.Size))), nil
}

func forgetCredential(_, _ string) {}
