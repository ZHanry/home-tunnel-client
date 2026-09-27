//go:build windows

package windowshost

import (
	"crypto/sha256"
	"encoding/hex"
	"golang.org/x/sys/windows"
	"unsafe"
)

func endpointOwner(identity, ownerSID string) (func(), bool, error) {
	if identity == "" || ownerSID == "" {
		return nil, false, ErrIdentity
	}
	if _, err := windows.StringToSid(ownerSID); err != nil {
		return nil, false, ErrIdentity
	}
	digest := sha256.Sum256([]byte(identity))
	name, _ := windows.UTF16PtrFromString(`Global\HomeTunnelHostOwner-` + hex.EncodeToString(digest[:]))
	descriptor, err := windows.SecurityDescriptorFromString("D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;" + ownerSID + ")")
	if err != nil {
		return nil, false, err
	}
	attributes := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: descriptor}
	handle, err := windows.CreateMutex(&attributes, false, name)
	if err == windows.ERROR_ALREADY_EXISTS {
		if handle != 0 {
			windows.CloseHandle(handle)
		}
		return nil, true, nil
	}
	// ACCESS_DENIED is an ownership failure, never evidence that no owner exists.
	if err != nil {
		return nil, false, err
	}
	return func() { windows.CloseHandle(handle) }, false, nil
}

// One atomic, endpoint-specific Global object is shared by tray and service.
// There is no check-then-create race between Global and Local namespaces.
func AcquireOwner(identity string) (func(), bool, error) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return nil, false, err
	}
	return endpointOwner(identity, user.User.Sid.String())
}
func AcquireServiceOwner(identity, ownerSID string) (func(), bool, error) {
	return endpointOwner(identity, ownerSID)
}
