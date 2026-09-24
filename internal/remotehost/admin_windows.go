//go:build windows

package remotehost

import (
	"context"

	"golang.org/x/sys/windows"
)

func RequireElevatedAdmin(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if !windows.GetCurrentProcessToken().IsElevated() {
		return ErrLocalApproval
	}
	return nil
}
