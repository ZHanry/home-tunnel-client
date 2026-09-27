//go:build windows

package windowshost

import (
	"golang.org/x/sys/windows"
	"unsafe"
)

func systemTokenForSession(session uint32) (windows.Token, error) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil || !user.User.Sid.IsWellKnown(windows.WinLocalSystemSid) || session == 0 || session == 0xffffffff {
		return 0, ErrRejected
	}
	var privileges windows.Token
	if err = windows.OpenProcessToken(windows.CurrentProcess(), windows.TOKEN_QUERY|windows.TOKEN_ADJUST_PRIVILEGES, &privileges); err != nil {
		return 0, err
	}
	defer privileges.Close()
	for _, name := range []string{"SeTcbPrivilege", "SeAssignPrimaryTokenPrivilege", "SeIncreaseQuotaPrivilege"} {
		wide, _ := windows.UTF16PtrFromString(name)
		var luid windows.LUID
		if err = windows.LookupPrivilegeValue(nil, wide, &luid); err != nil {
			return 0, err
		}
		grant := windows.Tokenprivileges{PrivilegeCount: 1}
		grant.Privileges[0] = windows.LUIDAndAttributes{Luid: luid, Attributes: windows.SE_PRIVILEGE_ENABLED}
		if err = windows.AdjustTokenPrivileges(privileges, false, &grant, 0, nil, nil); err != nil {
			return 0, err
		}
	}

	var current windows.Token
	if err := windows.OpenProcessToken(windows.CurrentProcess(), windows.TOKEN_DUPLICATE|windows.TOKEN_QUERY|windows.TOKEN_ASSIGN_PRIMARY, &current); err != nil {
		return 0, err
	}
	defer current.Close()
	var duplicated windows.Token
	if err := windows.DuplicateTokenEx(current, windows.MAXIMUM_ALLOWED, nil, windows.SecurityImpersonation, windows.TokenPrimary, &duplicated); err != nil {
		return 0, err
	}
	if err := windows.SetTokenInformation(duplicated, uint32(windows.TokenSessionId), (*byte)(unsafe.Pointer(&session)), uint32(unsafe.Sizeof(session))); err != nil {
		duplicated.Close()
		return 0, err
	}
	return duplicated, nil
}
