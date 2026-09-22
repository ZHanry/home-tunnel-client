//go:build !windows && !darwin && !linux

package remotehost

import "errors"

func platformBackend(string) (protectedBackend, error) {
	return nil, errors.New("RD_KEYSTORE_UNAVAILABLE")
}
