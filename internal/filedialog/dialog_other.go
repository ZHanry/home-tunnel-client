//go:build !windows

package filedialog

import "context"

func (Native) Sources(context.Context) ([]string, error)           { return nil, ErrUnavailable }
func (Native) Destination(context.Context, string) (string, error) { return "", ErrUnavailable }
