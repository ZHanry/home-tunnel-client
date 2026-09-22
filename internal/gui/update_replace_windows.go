//go:build windows

package gui

import "golang.org/x/sys/windows"

// Only replaces an already verified download, never installed application files.
// MOVEFILE_REPLACE_EXISTING permits a safe retry without deleting the previous
// download before the replacement is complete.
func replaceVerifiedDownload(source, destination string) error {
	from, err := windows.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	to, err := windows.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	return windows.MoveFileEx(from, to, windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH)
}
