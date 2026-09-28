# Home Tunnel Client 10.0.0

The GUI, CLI, managed Agent and native remote host identify as 10.0.0; upstream
FRP keeps its independent 0.70.1 version. Existing tunnels remain compatible with
7.0+ servers. Remote control requires a 10.0.0 server that advertises the matching
capabilities and API contract `api-v1.4.0`.

- Remote-control payloads (video, audio, input, clipboard, files) use authenticated
  UDP P2P only. The server brokers identity, signed grants and leases, and never
  relays payloads. When no direct UDP path exists, the session fails instead of
  falling back to a relay or TCP.
- Optional Windows service host, installed only through an unchecked
  administrator task, with a durable endpoint, verified pipe peers and local
  opt-in for secure-desktop access. Unattended access stays off after install.
- Authorized system audio (WASAPI loopback on the ordinary desktop) with a
  500 ms media deadline. No microphone capture.
- Scoped file transfer for the Android controller SDK, released as sealed
  arm64-v8a and x86_64 archives from one source lock.
- Guided desktop publishing with local target checks, localized desktop screens
  and system theme support.

The attached acceptance summary records what was verified on these exact package
bytes. Windows/macOS publisher-signature state is recorded per artifact; hashes
and malware scans are not OS signatures.

中文摘要：GUI、CLI、Agent 与原生被控端均为 10.0.0，FRP 保持 0.70.1。远控载荷仅走经认证的 UDP P2P，服务器不中继；无直连 UDP 路径时会话失败，不回退中继或 TCP。新增可选 Windows 服务宿主（默认不启用无人值守）、授权系统音频、Android 控制端 SDK 文件传输与桌面发布向导。实际验证范围以附带的同包验收摘要为准。

## Previous release: 9.0.0

The desktop uses sidebar navigation for tunnels and remote desktop, with a
separate remote-control window. The host supports requests that require local
approval, a reusable fixed password for the signed-in Windows desktop, and a
single-use temporary password. Pairing, signed authority, leases and direct UDP
verification remain required. The managed Agent and GUI identify as 9.0.0;
upstream FRP retains its independent version.

The release does not add a privileged Windows service. Lock screen, pre-login
and UAC secure-desktop capture/input are not supported. System audio and full
clipboard interoperability are unavailable or unverified. Windows executables
are unsigned unless their attached artifact evidence says otherwise. Consult
the exact-package native acceptance report before using remote control.

### 8.0.0

This is the 8.0.0 public release with the platform limits listed below. The existing
7.0 API contract and tunnel behavior remain supported; the managed Agent version
is 8.0.0 and upstream FRP remains 0.70.1.

The Windows host worker connects to the production account, pairing and
local-approval service. It independently verifies signed authority, peer proofs,
leases and the actual direct UDP path before sharing the selected display.
Same-machine Windows-to-Chromium H.264 and VP8 video passed actual decoding
tests. Each uses software encoding; hardware support is not established.
The actual keyboard, Unicode text, pointer and stale-input-epoch tests also
passed against a dedicated browser target. Input heartbeat loss released the
held key in 1473 ms; worker termination released the key/button in 57/59 ms.
These measurements use development worker bytes, not a final installation.
An earlier run of the same worker missed a keydown event; its failed report is
retained. A passing repeat does not establish the cause of that failure.

Windows file sharing uses a separate reliable DataChannel, explicit feature
permissions, local OS file selection, streaming writes and SHA-256 validation.
Real bidirectional empty/multi-chunk file tests passed using isolated selection
fixtures. Native open/save dialog cancellation was tested separately; these
results do not replace full user-facing picker or final-package acceptance.
Incomplete Windows receives are deleted by the OS when the worker is terminated;
completed files survive. Both cases passed actual child-process termination tests.
The Windows text clipboard implementation is opt-in; protocol tests passed,
but actual system clipboard interoperability remains unverified.

The Linux Xorg backend includes an active/unlocked logind gate and an independent
input-release guard. The complete GUI package was built with its pinned worker.
Real H.264/VP8 UDP decoding, XTest and filesystem checks passed in an isolated
Linux container. The Linux candidate exposes view, keyboard and pointer only;
text, clipboard and file capabilities remain unavailable there.
Production desktop, lock/unlock and full package acceptance remain
outstanding. Wayland/macOS hosting, desktop native viewing, audio, virtual
microphones and AV1/HEVC are not available. Android's same-source controller and
Surface acceptance entry are implemented, but actual device decoding has not
passed acceptance. Unsupported capabilities remain unavailable in the UI.

This release has incomplete platform coverage. Development evidence does not
replace the separate final-package release gate. Cross-network traversal,
physical platforms, upgrade/restore, long-running and signing gates remain open.

Windows/macOS publisher-signature status must be read from each artifact's actual
evidence; source checksums and CI do not replace certificates. The original
7.0.0 release remains available from its versioned download links. See
[native implementation status](../native/remote/README.md).
