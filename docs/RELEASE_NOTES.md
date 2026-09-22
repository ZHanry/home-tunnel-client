# Home Tunnel 8.0.0 development

This source is restricted to prereleases (`stage=internal-testing`). The existing
7.0 API contract and tunnel behavior remain supported; the managed Agent version
is 8.0.0 and upstream FRP remains 0.70.1.

The new remote work includes a C++20 ABI, pinned WebRTC source/build inputs,
server-owned protocol snapshots, lease/epoch/UDP-path/input watchdog safety tests,
four-session ownership boundaries, private worker capability probing and bounded
text/file receive primitives. Windows ordinary-desktop input adapter groundwork
is compiled; no system input is injected by automated tests.

**Native remote media is not operational in this build.** It does not yet provide
remote hosting/viewing, audio or virtual microphone routing, connected clipboard
or file-transfer UI, or verified AV1/HEVC. Capability queries report unavailable.
The plan's cross-platform, real-network, hardware, permissions, long-running and
signing gates remain outstanding. A successful core build is not evidence that
these features work.

Windows/macOS publisher-signature status must be read from each artifact's actual
evidence; source checksums and CI do not replace certificates. The original
stable download links continue pointing to 7.0.0 until real prerelease artifacts
are available. See [native implementation status](../native/remote/README.md).
