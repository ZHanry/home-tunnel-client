package model

// RemoteWindowLaunch carries only a single-use handoff, never an account,
// device, access or refresh credential. It must never be formatted or logged.
type RemoteWindowLaunch struct {
	URL         string
	HandoffCode string
	WindowID    string
	Generation  uint64
}
