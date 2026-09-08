<div align="center">
  <img src="docs/assets/HomeTunnel.svg" alt="Home Tunnel" width="80" height="80">
  <h1>Home Tunnel Client</h1>
  <p><strong>One core for desktop GUI, CLI and headless hosts</strong></p>
  <p>
    <img src="https://img.shields.io/badge/status-internal_testing-92400e" alt="Status: internal testing">
    <a href="https://github.com/ZHanry/home-tunnel-client/actions/workflows/ci.yml"><img src="https://github.com/ZHanry/home-tunnel-client/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license"></a>
  </p>
  <p><a href="README.md">简体中文</a> · <a href="https://zhanry.github.io/home-tunnel/">Project website</a></p>
</div>

Register a home computer or NAS, synchronize connection policy and supervise a managed tunnel Agent. Windows, macOS and Linux share the same GUI/CLI core.

> **Internal testing.** Source builds and integration testing are the current focus. Installation, tray behavior, background services and reconnects still need real-device validation.

[Project overview](https://github.com/ZHanry/home-tunnel) · [Server](https://github.com/ZHanry/home-tunnel-server) · [Android management app](https://github.com/ZHanry/home-tunnel-android)

## Programs

| Program | Purpose |
| --- | --- |
| `home-tunnel-gui` | Desktop login, connection management, native window and tray |
| `home-tunnel-client` | Device enrollment, CLI connection commands and headless supervision |
| `home-tunnel-agent` | Restricted FRP forwarding, supervised by the client |

CLI and GUI share authentication, sync, persistence and Agent supervision. Android manages the account remotely; it does not run this Agent.

## Build

Use Go 1.26.6 and a configured test server. Clone this repository, then choose a packaging entry point:

| Platform | Build command | Additional requirements |
| --- | --- | --- |
| Windows x64 | `./packaging/windows/build-release.ps1 -WindRes 'C:\tools\mingw\bin\windres.exe'` | PowerShell, windres, WebView2 Runtime |
| Linux | `ARCH=amd64 ./packaging/build-release.sh` | GTK 3, WebKitGTK 4.1, pkg-config, GCC for native GUI |
| macOS | `ARCH=arm64 ./packaging/macos/build-release.sh` | Xcode Command Line Tools; use amd64 for Intel |

Replace the windres path with your installation. Packages are written to `outputs/windows`, `outputs/linux` or `outputs/macos`. They include the validated Agent. Build a native GUI on a matching platform and architecture.

For CLI-only development: `CGO_ENABLED=0 go build ./cmd/home-tunnel-client`. A standalone binary still needs a configured Agent to run tunnels.

## Use and test

Sign in through the GUI, or install a Linux/macOS package and run `sudo home-tunnel-enroll`. Execute CLI commands as the account owning the device state, or pass `--state` explicitly.

```sh
home-tunnel-client status --json
home-tunnel-client connection ls
home-tunnel-client connection add --name demo --subdomain my-demo --local-port 8080
```

With native GUI prerequisites installed, run `go test ./...` and `go vet ./...`. Browser tests use Node.js 24 and pnpm 11: install dependencies, install Playwright Chromium, then run `pnpm run lint` and `pnpm run test:browser`.

See [operations](docs/OPERATIONS.md), [contributing](CONTRIBUTING.md), [test releases](docs/RELEASING.md), [Agent details](agent/README.md) and [security](SECURITY.md).

Licensed under [Apache-2.0](LICENSE); FRP notices are in `agent/`.
