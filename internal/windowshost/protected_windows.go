//go:build windows

package windowshost

import (
	"path/filepath"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

func privilegedSID(sid *windows.SID) bool {
	return sid != nil && (sid.IsWellKnown(windows.WinLocalSystemSid) ||
		sid.IsWellKnown(windows.WinBuiltinAdministratorsSid) ||
		sid.String() == "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464")
}

// Paths alone are not authority. Require a privileged owner and reject every
// effective allow ACE granting mutation rights to an unprivileged identity.
func protectedACL(handle windows.Handle, allowCreate bool) error {
	descriptor, err := windows.GetSecurityInfo(handle, windows.SE_FILE_OBJECT,
		windows.OWNER_SECURITY_INFORMATION|windows.DACL_SECURITY_INFORMATION)
	if err != nil {
		return err
	}
	owner, _, err := descriptor.Owner()
	if err != nil || !privilegedSID(owner) {
		return ErrRejected
	}
	acl, _, err := descriptor.DACL()
	if err != nil || acl == nil {
		return ErrRejected
	}
	mutation := uint32(windows.FILE_WRITE_DATA | windows.FILE_APPEND_DATA | windows.FILE_WRITE_EA |
		windows.FILE_WRITE_ATTRIBUTES | 0x0040 /* FILE_DELETE_CHILD */ | windows.DELETE |
		windows.WRITE_DAC | windows.WRITE_OWNER | windows.GENERIC_WRITE | windows.GENERIC_ALL)
	if allowCreate {
		// Drive/ProgramData ancestors can allow creating unrelated children.
		// They must still forbid deleting or replacing an existing child.
		mutation &^= windows.FILE_WRITE_DATA | windows.FILE_APPEND_DATA
	}
	for index := uint32(0); index < uint32(acl.AceCount); index++ {
		var ace *windows.ACCESS_ALLOWED_ACE
		if err = windows.GetAce(acl, index, &ace); err != nil {
			return err
		}
		if ace.Header.AceFlags&windows.INHERIT_ONLY_ACE != 0 {
			continue
		}
		if ace.Header.AceType == windows.ACCESS_DENIED_ACE_TYPE {
			continue
		}
		// Object/callback ACEs are deliberately not guessed at for this local
		// package/store. The installer creates a simple allow-list DACL.
		if ace.Header.AceType != windows.ACCESS_ALLOWED_ACE_TYPE {
			return ErrRejected
		}
		sid := (*windows.SID)(unsafe.Pointer(&ace.SidStart))
		if uint32(ace.Mask)&mutation != 0 && !privilegedSID(sid) {
			return ErrRejected
		}
	}
	return nil
}

func pinProtected(path string, directory bool) (windows.Handle, error) {
	return pinPath(path, directory, false)
}

func pinPath(path string, directory, allowCreate bool) (windows.Handle, error) {
	wide, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return 0, err
	}
	flags := uint32(windows.FILE_FLAG_OPEN_REPARSE_POINT)
	access := uint32(windows.GENERIC_READ | windows.READ_CONTROL)
	sharing := uint32(windows.FILE_SHARE_READ)
	if directory {
		flags |= windows.FILE_FLAG_BACKUP_SEMANTICS
		access = windows.FILE_READ_ATTRIBUTES | windows.READ_CONTROL
		sharing |= windows.FILE_SHARE_WRITE
	}
	handle, err := windows.CreateFile(wide, access, sharing, nil, windows.OPEN_EXISTING, flags, 0)
	if err != nil {
		return 0, err
	}
	var info windows.ByHandleFileInformation
	err = windows.GetFileInformationByHandle(handle, &info)
	if err == nil && (info.FileAttributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 ||
		(info.FileAttributes&windows.FILE_ATTRIBUTE_DIRECTORY != 0) != directory) {
		err = ErrRejected
	}
	if err == nil {
		err = protectedACL(handle, allowCreate)
	}
	if err != nil {
		windows.CloseHandle(handle)
		return 0, err
	}
	return handle, nil
}

func pinAncestors(path string) ([]windows.Handle, error) {
	volume := filepath.VolumeName(path)
	if !filepath.IsAbs(path) || len(volume) != 2 || volume[1] != ':' {
		return nil, ErrRejected
	}
	var paths []string
	for current := filepath.Clean(path); ; current = filepath.Dir(current) {
		paths = append(paths, current)
		if filepath.Dir(current) == current {
			break
		}
	}
	var pins []windows.Handle
	for index := len(paths) - 1; index >= 0; index-- {
		pin, err := pinPath(paths[index], true, true)
		if err != nil {
			for _, handle := range pins {
				windows.CloseHandle(handle)
			}
			return nil, err
		}
		pins = append(pins, pin)
	}
	return pins, nil
}

// Hold ancestor handles without DELETE sharing until the child image has been
// mapped. This rejects junctions and closes rename/swap races during launch.
func pinPackage() (string, func(), error) {
	root, err := windows.KnownFolderPath(windows.FOLDERID_ProgramFilesX64, 0)
	if err != nil || !filepath.IsAbs(root) {
		return "", nil, ErrRejected
	}
	path := filepath.Join(root, "Home Tunnel")
	handles, err := pinAncestors(root)
	if err != nil {
		return "", nil, err
	}
	release := func() {
		for _, handle := range handles {
			windows.CloseHandle(handle)
		}
	}
	// Both the package and Program Files require the stricter mutation ACL.
	for _, item := range []string{root, path} {
		handle, pinErr := pinProtected(item, true)
		if pinErr != nil {
			release()
			return "", nil, pinErr
		}
		handles = append(handles, handle)
	}
	if strings.Contains(path, "..") {
		release()
		return "", nil, ErrRejected
	}
	return path, release, nil
}
