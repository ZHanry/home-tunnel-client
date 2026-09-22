//go:build windows

package filedialog

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"
)

// Opt-in real dialog lifecycle test. It never selects a file or sends input to
// another process. The production hook cancels only its own native dialog.
func TestNativeDialogCancellation(t *testing.T) {
	if os.Getenv("HT_FILE_DIALOG_TEST") != "1" {
		t.Skip("requires an explicitly enabled interactive Windows desktop")
	}
	for _, multiple := range []bool{true, false} {
		name := "save"
		if multiple {
			name = "open"
		}
		t.Run(name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			observed := make(chan bool, 1)
			go func() {
				deadline := time.NewTimer(5 * time.Second)
				defer deadline.Stop()
				ticker := time.NewTicker(20 * time.Millisecond)
				defer ticker.Stop()
				for {
					select {
					case <-deadline.C:
						observed <- false
						cancel()
						return
					case <-ticker.C:
						dialogs.Lock()
						visible := len(dialogs.windows) == 1
						dialogs.Unlock()
						if visible {
							observed <- true
							cancel()
							return
						}
					}
				}
			}()
			started := time.Now()
			paths, err := runDialog(ctx, "home-tunnel-cancel-test.bin", multiple)
			if !<-observed {
				t.Fatal("native dialog hook was never initialized")
			}
			if !errors.Is(err, context.Canceled) || len(paths) != 0 {
				t.Fatalf("selection after cancellation: %d paths, %v", len(paths), err)
			}
			if time.Since(started) >= 5*time.Second {
				t.Fatal("native cancellation exceeded deadline")
			}
			dialogs.Lock()
			remaining := len(dialogs.pending) + len(dialogs.windows)
			dialogs.Unlock()
			if remaining != 0 {
				t.Fatalf("native dialog contexts leaked: %d", remaining)
			}
		})
	}
}
