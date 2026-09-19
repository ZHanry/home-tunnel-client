//go:build darwin && !cgo

package state

import "fmt"

func CredentialProtection() string { return "macOS Keychain unavailable in this non-native build" }
func protectCredential(_, _ string) (string, error) {
	return "", fmt.Errorf("macOS credential storage requires the official native Keychain-enabled build")
}
func unprotectCredential(_, _ string) (string, error) {
	return "", fmt.Errorf("macOS credential storage requires the official native Keychain-enabled build")
}
func forgetCredential(_, _ string) {}
