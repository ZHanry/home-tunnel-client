# Home Tunnel 8.0.0-rc.1 development

This source is restricted to prereleases (`stage=internal-testing`). The existing
7.0 API contract and tunnel behavior remain supported; the managed Agent version
is 8.0.0 and upstream FRP remains 0.70.1.

The Windows host worker connects to the production account, pairing and
local-approval service. It independently verifies signed authority, peer proofs,
leases and the actual direct UDP path before sharing the selected display.
Same-machine Windows-to-Chromium H.264 and VP8 video passed actual decoding
tests. Each uses software encoding; hardware support is not established.
The actual keyboard, Unicode text, pointer and stale-input-epoch tests also
passed against a dedicated browser target. Input heartbeat loss released the
held key in 1885 ms; worker termination released the key/button in 44/46 ms.
These measurements use development worker bytes, not a final installation.

Windows file sharing uses a separate reliable DataChannel, explicit feature
permissions, local OS file selection, streaming writes and SHA-256 validation.
Real bidirectional empty/multi-chunk file tests passed using isolated selection
fixtures. Native open/save dialog cancellation was tested separately; these
results do not replace full user-facing picker or final-package acceptance.
The Windows text clipboard implementation is opt-in; protocol tests passed,
but actual system clipboard interoperability remains unverified.

The Linux Xorg backend includes an active/unlocked logind gate and an independent
input-release guard. Real XTest and filesystem checks passed in an isolated Linux
container. Production desktop, lock/unlock and full package acceptance remain
outstanding. Wayland/macOS hosting, desktop native viewing, audio, virtual
microphones and AV1/HEVC are not available. Android's same-source controller and
Surface acceptance entry are implemented, but actual device decoding has not
passed acceptance. Unsupported capabilities remain unavailable in the UI.

This is development evidence, not a published release or a claim that all 8.0
features work. Final package input/release timing, cross-network traversal,
physical platforms, upgrade/restore, long-running and signing gates remain open.

Windows/macOS publisher-signature status must be read from each artifact's actual
evidence; source checksums and CI do not replace certificates. The original
stable download links continue pointing to 7.0.0 until real prerelease artifacts
are available. See [native implementation status](../native/remote/README.md).
