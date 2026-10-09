# HomeDesk / Home Tunnel Client

The current main line is **11.0.0-rc.2**. Hearth Flutter UI and the native RustDesk core provide authenticated, encrypted **direct P2P only** remote desktop. Relay/proxy/vendor fallback is forbidden; a failed direct connection terminates clearly.

[简体中文](README.md) · [Candidate release](https://github.com/ZHanry/home-tunnel-client/releases/tag/v11.0.0-rc.2) · [Last stable 10.1.0](https://github.com/ZHanry/home-tunnel-client/releases/tag/v10.1.0)

Four attachments: Windows x64 installer, five-platform standalone CLI/Agent bundle, source/build materials, SHA256SUMS. macOS/Linux candidate packages currently provide CLI/Agent only. Android ships from its own repository using a pinned copy of this same Rust/Flutter source.

Verify hashes before installing. The Windows installer has no Authenticode certificate. Generic builds contain no server address, key or credentials. Configure your own hbbs trust settings and HTTPS portal. Remote hosting requires explicit local permission; account enrollment does not grant desktop control.

HTTP/HTTPS, governed TCP/UDP, port pools, ACLs, quotas, traffic policies, diagnostics and NAS support retain the Go/FRP implementation. HomeDesk and CLI are 11.0.0-rc.2; the checksum-pinned Agent retains original 10.1.0 bytes and FRP 0.70.1. [Independent background tunneling](docs/INDEPENDENT_TUNNEL.md). GUI-managed Agents follow the window; enroll a separate CLI state to continue after closing it.

RC.2 fixes per-user upgrades blocked by an unused legacy service executable. The installer checks actual loaded files and write access, preserving account and tunnel state. Running applications, agents or services in the installation folder must still exit before replacement.

Cross-network NAT, sustained media and physical Android acceptance remain pending. [Candidate notes](docs/HOMEDESK_RELEASE.md). Historical 10.x acceptance records and DTLS/TURN engines do not describe the new runtime.

The imported native tree keeps upstream and Hearth history. Go components remain Apache-2.0; integrated HomeDesk Rust/Flutter distribution is [AGPL-3.0](LICENSE-RUSTDESK). Materials provide corresponding source, dependencies and build recipes. [Provenance](docs/homedesk/PROVENANCE.md).

Initialize recursive submodules. Fixed tools: Rust 1.96.0, Flutter 3.24.5, FRB 1.80.1 and Go 1.27.0. Build with `python3 build/ci/build-client.py --target win-x64 --config build/config.toml.example`; test Go with `go test ./...`. API `api-v1.6.0`; native directory discovery requires Server 11.x.
