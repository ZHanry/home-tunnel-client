//go:build !windows

package desktop

func setEmergencyHost(*Host) {}

func setNativeEmergencyHotkey(string) error { return ErrRemoteWindowUnavailable }
