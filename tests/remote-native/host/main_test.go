//go:build windows && remote_native_e2e

package main

import "testing"

func TestSameScopesIgnoresOrderButRejectsDuplicates(test *testing.T) {
	actual := []string{"input.keyboard", "input.pointer", "input.text", "view"}
	expected := []string{"view", "input.keyboard", "input.pointer", "input.text"}
	if !sameScopes(actual, expected) {
		test.Fatal("equivalent scopes were rejected")
	}
	if sameScopes([]string{"view", "view"}, []string{"view", "input.keyboard"}) || sameScopes(actual, []string{"view", "input.keyboard", "input.pointer", "clipboard.read"}) {
		test.Fatal("duplicate or changed scopes were accepted")
	}
}
