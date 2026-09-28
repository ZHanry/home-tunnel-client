//go:build !windows

package desktop

// The approval popup is Windows-only for now; elsewhere requests stay in the
// main window.
func showNativeApprovalPopup(string, string, bool) bool { return false }

func hideNativeApprovalPopup() {}
