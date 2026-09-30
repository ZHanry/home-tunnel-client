package model

import (
	"strings"
	"testing"
)

func TestNormalizeDeviceName(t *testing.T) {
	for _, input := range []string{"", " \t\r\n", "\u2003\uFEFF", strings.Repeat("a", 121), strings.Repeat("😀", 61), "desk\nname", "desk\x00", "desk\x7f"} {
		if _, err := NormalizeDeviceName(input); err == nil {
			t.Fatalf("accepted invalid device name %q", input)
		}
	}
	for _, input := range []string{" \t工作电脑\u2003", strings.Repeat("a", 120), strings.Repeat("😀", 60)} {
		name, err := NormalizeDeviceName(input)
		if err != nil || name == "" {
			t.Fatalf("valid name rejected %q: %v", input, err)
		}
	}
	if name, _ := NormalizeDeviceName("\uFEFF Work PC \uFEFF"); name != "Work PC" {
		t.Fatalf("name not trimmed: %q", name)
	}
}
