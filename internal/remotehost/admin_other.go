//go:build !windows

package remotehost

import "context"

func RequireElevatedAdmin(context.Context) error { return ErrLocalApproval }
