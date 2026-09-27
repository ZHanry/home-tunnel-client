//go:build windows

package windowshost

import (
	"golang.org/x/sys/windows"
	"path/filepath"
)

func protectInstalledPackage() error {
	token := windows.GetCurrentProcessToken()
	if !token.IsElevated() {
		return ErrAdmin
	}
	user, err := token.GetTokenUser()
	if err != nil {
		return err
	}
	root, err := windows.KnownFolderPath(windows.FOLDERID_ProgramFilesX64, 0)
	if err != nil {
		return err
	}
	ancestors, err := pinAncestors(root)
	if err != nil {
		return err
	}
	defer func() {
		for _, pin := range ancestors {
			windows.CloseHandle(pin)
		}
	}()
	parent, err := pinProtected(root, true)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(parent)
	packagePath := filepath.Join(root, "Home Tunnel")
	descriptor, err := windows.SecurityDescriptorFromString("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)")
	if err != nil {
		return err
	}
	acl, _, err := descriptor.DACL()
	if err != nil {
		return err
	}
	owner, _, err := descriptor.Owner()
	if err != nil {
		return err
	}
	// The installer may own newly written files under its elevated user SID.
	// Reject foreign ownership and reparse points before changing any ACL.
	for _, name := range []string{"", ServiceBinary, WorkerName, "home-tunnel-gui.exe"} {
		path := packagePath
		flags := uint32(windows.FILE_FLAG_OPEN_REPARSE_POINT)
		if name == "" {
			flags |= windows.FILE_FLAG_BACKUP_SEMANTICS
		} else {
			path = filepath.Join(path, name)
		}
		wide, _ := windows.UTF16PtrFromString(path)
		handle, openErr := windows.CreateFile(wide, windows.READ_CONTROL|windows.WRITE_DAC|windows.WRITE_OWNER,
			windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, flags, 0)
		if openErr != nil {
			return openErr
		}
		var info windows.ByHandleFileInformation
		err = windows.GetFileInformationByHandle(handle, &info)
		if err == nil && info.FileAttributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			err = ErrRejected
		}
		if err == nil {
			var current *windows.SECURITY_DESCRIPTOR
			current, err = windows.GetSecurityInfo(handle, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION)
			if err == nil {
				existing, _, ownerErr := current.Owner()
				if ownerErr != nil || (!privilegedSID(existing) && !existing.Equals(user.User.Sid)) {
					err = ErrRejected
				}
			}
		}
		if err == nil {
			err = windows.SetSecurityInfo(handle, windows.SE_FILE_OBJECT,
				windows.OWNER_SECURITY_INFORMATION|windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION,
				owner, nil, acl, nil)
		}
		windows.CloseHandle(handle)
		if err != nil {
			return err
		}
	}
	return nil
}
