//go:build !windows && !darwin

package state

import "fmt"

func CredentialProtection() string                      { return "Owner-only file permissions (headless Linux fallback)" }
func protectCredential(plain, _ string) (string, error) { return plain, nil }
func unprotectCredential(_, _ string) (string, error) {
	return "", fmt.Errorf("this credential belongs to another operating system; enroll again")
}
func forgetCredential(_, _ string) {}
