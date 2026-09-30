//go:build !windows && !cgo

package desktop

import "fmt"
import "github.com/ZHanry/home-tunnel-client/internal/model"

func createNativeWindow(string) error {
	return fmt.Errorf("home-tunnel-gui must be built with CGO on Linux and macOS so it can create a native window")
}

func runNativeWindow() {}

func showNativeWindow() {}

func quitNativeWindow() {}

func openNativeRemoteWindow(model.RemoteWindowLaunch) error { return ErrRemoteWindowUnavailable }

func closeNativeRemoteWindow() {}
