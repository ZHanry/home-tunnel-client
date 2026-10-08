//go:build !windows

// HOMEDESK: Managed GUI helper is Windows-only; standalone CLI/Agent remains portable.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "Use home-tunnel-client for independent CLI/NAS tunneling on this platform.")
	os.Exit(1)
}
