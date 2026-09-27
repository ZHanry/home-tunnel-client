//go:build !windows

package windowshost

import "context"

func Control(context.Context, ControlRequest) (ControlResponse, error) {
	return ControlResponse{}, ErrNotInstalled
}
func EnableWithApproval(context.Context, ControlRequest) error { return ErrNotInstalled }
