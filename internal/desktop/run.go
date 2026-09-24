package desktop

import (
	"errors"
	"sync/atomic"
)

var ErrRemoteWindowUnavailable = errors.New("remote window is unavailable")

// Run starts the tray and the native window. Closing the window hides it to
// the tray; the process exits when the user quits from the tray or the UI.
func Run(url string, host *Host, onQuit func()) error {
	setEmergencyHost(host)
	var quitting atomic.Bool
	doQuit := func() {
		if !quitting.CompareAndSwap(false, true) {
			return
		}
		quitNativeWindow()
		stopTray()
		if onQuit != nil {
			onQuit()
		}
	}
	startTray(showNativeWindow, doQuit)
	if err := createNativeWindow(url); err != nil {
		stopTray()
		return err
	}
	if host != nil {
		host.setShow(showNativeWindow)
		host.setOpenRemote(openNativeRemoteWindow)
		host.setCloseRemote(closeNativeRemoteWindow)
	}
	runNativeWindow()
	doQuit()
	return nil
}

// Quit closes the native window loop so the process can exit.
func Quit() {
	quitNativeWindow()
}
