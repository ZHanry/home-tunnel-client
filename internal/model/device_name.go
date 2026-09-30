package model

import (
	"errors"
	"strings"
	"unicode"
	"unicode/utf16"
)

// NormalizeDeviceName mirrors the server's 120 UTF-16-unit limit (and the
// desktop input's maxlength), including names that use non-BMP characters.
func NormalizeDeviceName(value string) (string, error) {
	value = strings.TrimFunc(value, func(r rune) bool { return (unicode.IsSpace(r) && r != '\u0085') || r == '\uFEFF' })
	if value == "" || len(utf16.Encode([]rune(value))) > 120 || strings.ContainsFunc(value, unicode.IsControl) {
		return "", errors.New("device name must contain 1–120 characters without control characters")
	}
	return value, nil
}
