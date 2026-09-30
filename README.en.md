<img src="docs/assets/HomeTunnel.svg" alt="" width="64" height="64">

# Home Tunnel Client

The current version is **10.0.0**. Remote-control payloads use end-to-end DTLS-encrypted UDP, preferring direct P2P. Browser viewers can use the server's optional UDP TURN relay, which cannot read the payload; there is no TCP fallback. Windows provides keyboard/Unicode input, consent-bound files and authorized system audio. Fixed-password access skips approval on the signed-in desktop; lock screen, pre-login and UAC secure-desktop control are unavailable. Linux amd64 provides an Xorg host with local-session permission checks. macOS/Wayland hosting and native desktop viewing remain unavailable. See the [release notes](docs/RELEASE_NOTES.md) for supported scope, verified coverage and unverified cases.

The 10.0.0 Web-to-Windows runtime checks used development builds of the same feature code and were not rerun on the final release bytes. CI builds and final Windows artifact security/installation checks have separate passing evidence; see the [release notes](docs/RELEASE_NOTES.md) for the scope of each.

**Connect Windows, macOS, Linux and NAS hosts**

[![Stable release](https://img.shields.io/github/v/release/ZHanry/home-tunnel-client?label=stable)](https://github.com/ZHanry/home-tunnel-client/releases/latest) [![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

[简体中文](README.md) · [Website](https://zhanry.github.io/home-tunnel/en/) · [Downloads](https://github.com/ZHanry/home-tunnel/blob/main/docs/DOWNLOADS.md) · [Quick start](https://github.com/ZHanry/home-tunnel/blob/main/docs/GETTING_STARTED.md)


Run managed tunnels on your home computer or NAS. The GUI and CLI share a Go core;
the supervised Agent carries traffic while the window can remain closed.

[Windows installer / portable ZIP](https://github.com/ZHanry/home-tunnel-client/releases/latest) · [macOS Intel / Apple Silicon](https://github.com/ZHanry/home-tunnel-client/releases/latest) · [Linux amd64 / arm64](https://github.com/ZHanry/home-tunnel-client/releases/latest) · [NAS template](packaging/nas/README.md)

Verify `SHA256SUMS.txt` and the release evidence before installing. Windows/macOS
currently have no publisher certificates: the packages explicitly disclose their
unsigned state. Hashes and malware scans are not OS signatures. [Signing details](docs/PLATFORM_SECURITY.md).

Use server **10.0.0** (remote control requires its advertised capabilities); existing tunnels remain compatible with server 7.0. Sign in with an account plus MFA, or use a ten-minute one-time
enrollment code. Create local HTTP services or authorized TCP/UDP connections;
SSH/RDP/RTSP presets are available. Public ports are allocated server-side. The
target application supplies raw transport authentication/encryption.

This device session manages only the current host. The 10.1.0 candidate moves
current-device rename to My Devices and combines server details and updates in
Settings, without device tags or appearance controls. Select up to 50 local
connections for batch pause/resume with individual results. Use Web/Android for
account-wide management. Native remote sign-in reuse and rename require Server
10.1.0. This candidate is not released; see [verification scope](docs/V10_1_CANDIDATE.md).

```sh
home-tunnel-client enroll --server https://console.your-domain.net \
  --device-name home-nas --enrollment-code-file /secure/enrollment-code
home-tunnel-client doctor
```

Windows uses DPAPI, macOS uses Keychain, and Linux headless uses explicit 0600
files. The bundled Agent also uses 10.0.0; upstream FRP stays at 0.70.1.
Updates require HTTPS, an exact valid checksum and complete bounded content before
atomic promotion. Never mix Agent files between packages.

[Operations](docs/OPERATIONS.md) · [Features](docs/PLATFORM_FEATURES.md) · [Diagnostics/security](docs/PLATFORM_SECURITY.md) · [API](contracts/README.md)

Development: Go 1.26.6, `go test ./...`, then `python3 scripts/check-repository.py`.
CI covers native builds, Windows installer lifecycle, Defender scans, reproducible
Agent checks and browser interactions. Release evidence is kept with the packages.
