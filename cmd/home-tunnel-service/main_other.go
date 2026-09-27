//go:build !windows

package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "home-tunnel-service is the Windows service host")
	os.Exit(2)
}
