//go:build windows

package state

import (
	"strings"

	"golang.org/x/sys/windows/registry"
)

func readMachineID() string {
	key, err := registry.OpenKey(registry.LOCAL_MACHINE, `SOFTWARE\Microsoft\Cryptography`, registry.QUERY_VALUE|registry.WOW64_64KEY)
	if err != nil {
		return "machine-id-unavailable"
	}
	defer key.Close()
	value, _, err := key.GetStringValue("MachineGuid")
	if err != nil || strings.TrimSpace(value) == "" {
		return "machine-id-unavailable"
	}
	return strings.TrimSpace(value)
}
