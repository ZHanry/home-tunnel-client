# Home Tunnel Client 10.0.0

The separate [10.1.0 candidate](V10_1_CANDIDATE.md) is under verification and is not yet a stable release. The evidence below belongs to 10.0.0 only.

The GUI, CLI, managed Agent and native remote host identify as 10.0.0; upstream
FRP keeps its independent 0.70.1 version. Existing tunnels remain compatible with
7.0+ servers. Remote control requires a 10.0.0 server that advertises the matching
capabilities and API contract `api-v1.4.0`.

- Remote-control payloads (video, audio, input, clipboard, files) use authenticated,
  end-to-end DTLS-encrypted UDP. Direct P2P is preferred. When it fails, a browser
  viewer can reach a 10.0.0 host through the server's optional UDP TURN relay,
  which cannot read the payload. There is no TCP fallback.
- Hosting is on after sign-in. Stranger connections pop up a bottom-right,
  always-on-top approval card that does not steal focus, and a "being remotely
  controlled · disconnect" bar appears while connected. A fixed password skips
  approval. The device ID is shown as a grouped 9-digit number, and a one-time
  temporary password uses the same ID.
- Accepting a request or a temporary password allows screen, input, clipboard,
  files and system audio for that connection only. The microphone is never
  auto-approved.
- The managed Agent runs in a kill-on-close job, so it exits with the GUI. Quitting
  from the tray or the local API now exits reliably.
- Authorized system audio (WASAPI loopback on the ordinary desktop) with a
  500 ms media deadline. No microphone capture.
- Guided desktop publishing with local target checks, localized desktop screens
  and system theme support.

Lock screen, pre-login and UAC secure-desktop control are not available; unattended
access is the fixed password on the signed-in desktop. Windows/macOS executables
carry no publisher signature; hashes and malware scans are not OS signatures.

**Verification scope.** On development builds of the same feature code, a Web
viewer controlled this client's Windows host through the 10.0.0 production server,
over both direct UDP and the TURN relay. Those development-build checks covered
screen, keyboard, mouse, Chinese text, clipboard in both directions, file transfer
from viewer to host (SHA-256 checked), system audio, the approval popup, quit and
agent cleanup. They were not rerun on the final 10.0.0 release bytes and do not
establish final-package remote-session acceptance.

Build and security checks have separate evidence: CI built the packages, and the
final Windows artifacts passed Defender rescanning, installer lifecycle checks
and installed-payload hash checks. Those results remain valid within their scope;
they do not substitute for the unrun final-package remote-session tests.

The following were not verified for the final release artifacts. The attached
acceptance record preserves the detailed test status:

- Web-to-Windows remote sessions on final release bytes (development-build results only)
- file transfer from host to viewer
- fixed-password mode on the final build
- Android and Windows-to-Windows controllers
- multiple monitors and DPI
- the tunnel runtime matrix
- the 2-hour and 24-hour soaks
- the NAT, IPv6 and fault matrix
- performance comparison
- 9→10 installer upgrade
- Linux and macOS runtime

中文摘要：GUI、CLI、Agent 与原生被控端均为 10.0.0，FRP 保持 0.70.1。

- 远控载荷走端到端 DTLS 加密的 UDP，优先直连。直连失败时，浏览器控制端可经服务器可选的 UDP TURN 中继连接 10.0.0 被控端，中继无法读取内容，也不回退 TCP。
- 登录即开启被控。陌生连接在右下角弹出审批框，连接后显示"正在被远程控制 · 断开"条。
- 一次性临时密码使用固定设备 ID。接受连接后本次放行画面、键鼠、剪贴板、文件和系统声音，不含麦克风。
- 不支持锁屏、登录前与 UAC 安全桌面控制。
- 上述 Web→Windows 远控实测使用相同功能代码的开发构建，未在最终 10.0.0 发行字节上重跑，不能视为最终安装包远控验收通过。
- CI 构建、最终 Windows 文件的 Defender 复扫、安装器生命周期及安装文件哈希检查有独立通过记录；其他未验证范围见上文及随附验收记录。

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
