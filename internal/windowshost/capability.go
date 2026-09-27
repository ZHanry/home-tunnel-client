package windowshost

type Availability string

const (
	Available          Availability = "available"
	Unavailable        Availability = "unavailable"
	PermissionRequired Availability = "permission_required"
	Unsupported        Availability = "unsupported"
)

type Probe struct {
	WorkerObserved   bool
	WorkerUnattended bool
	Capture          bool
	Keyboard         bool
	Pointer          bool
	Text             bool
	SecureDesktop    bool
	UserContext      bool
	SignedIn         bool
	ServiceConnected bool
}

type Native struct {
	Schema   int               `json:"schema"`
	Reporter string            `json:"reporter"`
	Backends map[string]string `json:"backends"`
}

func availability(ok bool) Availability {
	if ok {
		return Available
	}
	return Unavailable
}

// NativeReport is empty unless a packaged service worker produced the probe.
// Audio stays unavailable. Secure desktop is never inferred from the OS name.
func NativeReport(probe Probe) (Native, bool) {
	if !probe.WorkerObserved || !probe.ServiceConnected {
		return Native{}, false
	}
	files := Unavailable
	clipboard := Unavailable
	switch {
	case probe.UserContext && probe.SignedIn:
		files = Available
		clipboard = Available
	case probe.SignedIn:
		files = PermissionRequired
		clipboard = PermissionRequired
	}
	if probe.SecureDesktop && !probe.UserContext {
		clipboard = PermissionRequired
		files = PermissionRequired
	}
	if probe.SecureDesktop {
		clipboard = Unavailable
	}
	return Native{
		Schema:   1,
		Reporter: "agent",
		Backends: map[string]string{
			"capture":        string(availability(probe.Capture)),
			"input_keyboard": string(availability(probe.Keyboard)),
			"input_pointer":  string(availability(probe.Pointer)),
			"input_text":     string(availability(probe.Text)),
			"system_audio":   string(Unavailable),
			"microphone":     string(Unavailable),
			"clipboard":      string(clipboard),
			"files":          string(files),
			"secure_desktop": string(availability(probe.SecureDesktop && probe.WorkerUnattended)),
		},
	}, true
}
