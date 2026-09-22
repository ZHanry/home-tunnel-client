//go:build !windows

package gui

import "os"

func replaceVerifiedDownload(source, destination string) error {
	return os.Rename(source, destination)
}
