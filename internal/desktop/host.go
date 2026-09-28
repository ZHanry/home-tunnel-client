package desktop

import "sync"

// Host lets the local HTTP API ask the native window to come to the front.
type Host struct {
	mu            sync.Mutex
	show          func()
	openRemote    func(string) error
	closeRemote   func()
	emergencyStop func()
	emergencyKey  string
	popupShow     func(mode string, attention bool) bool
	popupHide     func()
}

func (host *Host) setShow(show func()) {
	host.mu.Lock()
	host.show = show
	host.mu.Unlock()
}

// Show restores the native window if the desktop host is running.
func (host *Host) Show() {
	host.mu.Lock()
	show := host.show
	host.mu.Unlock()
	if show != nil {
		show()
	}
}

func (host *Host) setOpenRemote(open func(string) error) {
	host.mu.Lock()
	host.openRemote = open
	host.mu.Unlock()
}

func (host *Host) OpenRemote(url string) error {
	host.mu.Lock()
	open := host.openRemote
	host.mu.Unlock()
	if open == nil {
		return ErrRemoteWindowUnavailable
	}
	return open(url)
}

func (host *Host) setCloseRemote(close func()) {
	host.mu.Lock()
	host.closeRemote = close
	host.mu.Unlock()
}

func (host *Host) CloseRemote() {
	host.mu.Lock()
	close := host.closeRemote
	host.mu.Unlock()
	if close != nil {
		close()
	}
}

func (host *Host) SetEmergencyStop(stop func()) {
	host.mu.Lock()
	host.emergencyStop = stop
	host.mu.Unlock()
}

func (host *Host) EmergencyStop() {
	host.mu.Lock()
	stop := host.emergencyStop
	host.mu.Unlock()
	if stop != nil {
		stop()
	}
}

func (host *Host) SetEmergencyHotkey(key string) error {
	if key != "X" && key != "Q" && key != "F12" {
		return ErrRemoteWindowUnavailable
	}
	if err := setNativeEmergencyHotkey(key); err != nil {
		return err
	}
	host.mu.Lock()
	host.emergencyKey = key
	host.mu.Unlock()
	return nil
}

func (host *Host) setApprovalPopup(show func(string, bool) bool, hide func()) {
	host.mu.Lock()
	host.popupShow = show
	host.popupHide = hide
	host.mu.Unlock()
}

// ShowApprovalPopup shows the always-on-top approval popup in the given mode
// ("request" or "session"). It reports false until the native window exists.
func (host *Host) ShowApprovalPopup(mode string, attention bool) bool {
	host.mu.Lock()
	show := host.popupShow
	host.mu.Unlock()
	return show != nil && show(mode, attention)
}

// HideApprovalPopup hides the popup; it is a no-op before the window exists.
func (host *Host) HideApprovalPopup() {
	host.mu.Lock()
	hide := host.popupHide
	host.mu.Unlock()
	if hide != nil {
		hide()
	}
}
