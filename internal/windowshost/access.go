package windowshost

type Peer struct {
	Packaged    bool
	Elevated    bool
	Interactive bool
}

// Authorize reports whether this peer may perform the message.
// Routine status, disable, and emergency stop are available to the packaged
// interactive tray. Enabling unattended access requires an elevated administrator.
func Authorize(peer Peer, kind uint8) error {
	if !peer.Packaged {
		return ErrRejected
	}
	switch kind {
	case TypeStatus, TypeDisableUnattended, TypeEmergencyStop, TypeCapability:
		if peer.Interactive || peer.Elevated {
			return nil
		}
		return ErrRejected
	case TypeEnableUnattended:
		if peer.Elevated {
			return nil
		}
		return ErrAdmin
	case TypeClipboardRead, TypeClipboardWrite, TypeFileRead, TypeFileWrite, TypeDesktop, TypeClientHello:
		if peer.Interactive {
			return nil
		}
		return ErrRejected
	default:
		return ErrRejected
	}
}

func WorkerDesktop(session uint32, secure bool) (string, error) {
	if session == 0 || session == 0xffffffff {
		return "", ErrRejected
	}
	if secure {
		return `WinSta0\Winlogon`, nil
	}
	return `WinSta0\Default`, nil
}
