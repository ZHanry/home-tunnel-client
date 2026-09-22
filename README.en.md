<img src="docs/assets/HomeTunnel.svg" alt="" width="64" height="64">

# Home Tunnel Client

The current source is **8.0.0 development**, restricted to prereleases. Native remote media is not available yet. The 7.0.0 links below remain the existing stable downloads. See [implementation status and verification limits](native/remote/README.md).

**Connect Windows, macOS, Linux and NAS hosts**

[![Stable 7.0.0](https://img.shields.io/badge/stable-7.0.0-176653)](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) [![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

[简体中文](README.md) · [Website](https://zhanry.github.io/home-tunnel/en/) · [Downloads](https://github.com/ZHanry/home-tunnel/blob/main/docs/DOWNLOADS.md) · [Quick start](https://github.com/ZHanry/home-tunnel/blob/main/docs/GETTING_STARTED.md)


Run managed tunnels on your home computer or NAS. The GUI and CLI share a Go core;
the supervised Agent carries traffic while the window can remain closed.

[Windows installer / portable ZIP](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) · [macOS Intel / Apple Silicon](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) · [Linux amd64 / arm64](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) · [NAS template](packaging/nas/README.md)

Verify `SHA256SUMS.txt` and the release evidence before installing. Windows/macOS
currently have no publisher certificates: the packages explicitly disclose their
unsigned state. Hashes and malware scans are not OS signatures. [Signing details](docs/PLATFORM_SECURITY.md).

Use server **7.0.0**. Sign in with an account plus MFA, or use a ten-minute one-time
enrollment code. Create local HTTP services or authorized TCP/UDP connections;
SSH/RDP/RTSP presets are available. Public ports are allocated server-side. The
target application supplies raw transport authentication/encryption.

This device session manages only the current host. Edit tags/favorites in settings
and select up to 50 local connections for batch pause/resume with individual
results. Use Web/Android for account-wide management.

```sh
home-tunnel-client enroll --server https://console.your-domain.net \
  --device-name home-nas --enrollment-code-file /secure/enrollment-code
home-tunnel-client doctor
```

Windows uses DPAPI, macOS uses Keychain, and Linux headless uses explicit 0600
files. The bundled Agent also uses 7.0.0; upstream FRP stays at 0.70.1.
Updates require HTTPS, an exact valid checksum and complete bounded content before
atomic promotion. Never mix Agent files between packages.

[Operations](docs/OPERATIONS.md) · [Features](docs/PLATFORM_FEATURES.md) · [Diagnostics/security](docs/PLATFORM_SECURITY.md) · [API](contracts/README.md)

Development: Go 1.26.6, `go test ./...`, then `python3 scripts/check-repository.py`.
CI covers native builds, Windows installer lifecycle, Defender scans, reproducible
Agent checks and browser interactions. Release evidence is kept with the packages.
