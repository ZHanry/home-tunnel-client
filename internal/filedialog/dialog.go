// Package filedialog obtains file paths from an explicit local OS dialog.
// Remote peers and local HTTP request bodies cannot supply these paths.
package filedialog

import (
	"context"
	"errors"
)

var ErrCancelled = errors.New("RD_FILE_SELECTION_CANCELLED")
var ErrUnavailable = errors.New("RD_FILE_PICKER_UNAVAILABLE")

type Picker interface {
	Sources(context.Context) ([]string, error)
	Destination(context.Context, string) (string, error)
}

type Native struct{}
