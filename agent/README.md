# Managed tunnel Agent

This is the shared capability-restricted FRP Agent for Windows, macOS and Linux.
It was previously called `windows-agent`. GUI and headless packages use the same source.

The nested Go module keeps FRP dependencies out of the GUI/CLI module. For development,
run `go test ./...` from this directory. Official packaging uses the pinned FRP source
archive and checksum in the packaging scripts to preserve reproducible Agent binaries.
Windows CI additionally reproduces `expected-sha256.txt`; it must not silently accept a new hash.

FRP licensing and third-party notices remain in this directory.
