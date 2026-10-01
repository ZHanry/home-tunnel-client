# Home Tunnel Client 10.1.0

10.1.0 promotes the original, verified candidate bytes from [build 36795202532](https://github.com/ZHanry/home-tunnel-client/actions/runs/36795202532). It is not a rebuild. Source: `41c0e21fbb3a4c634fbc9d63fcd7453337e4d029`. Existing releases and historical candidate artifacts are preserved.

## Changes

- Fix native worker crash cleanup so an interrupted session closes safely and a subsequent explicitly started connection can recover
- Improve the approval popup background and display timing
- Show the current device clearly and offer device rename instead of a self-connection action
- Use an expiring, single-use sign-in handoff for the remote window
- Simplify Settings and improve sign-in field spacing and small-window scrolling

The new sign-in handoff and device rename need Server 10.1.0 and the frozen additive `api-v1.5.0` contract. Existing tunnels remain compatible with supported 7.0+ servers. The accompanying Android stable package remains 10.0.0. FRP remains 0.70.1.

## Verified on the distributed Windows worker

[Validation run 36800634596](https://github.com/ZHanry/home-tunnel-client/actions/runs/36800634596) used the exact sealed Windows worker with a clean production-source QA host and Chromium on the same Windows machine. It verified authenticated DTLS UDP video, confined keyboard/mouse/Unicode input, 30 successful connections, 7,202.463 seconds of continuous activity with 1,391 samples, and explicit QA-host restart recovery in 3.508 seconds after a worker crash. Heartbeat loss released held input in 1,539 ms; worker termination released key/button input in 11.5/12 ms.

The exact installer and portable package passed Microsoft Defender rescanning. Installation, uninstallation and installed-payload SHA-256 checks passed. Linux and macOS packages were built and sealed. The attached native report, acceptance receipts, package manifests, SBOMs, original Sigstore signatures and signed checksum manifest preserve the detailed evidence.

## Coverage limits

- The native run used one machine and a QA host. It does not establish independent-device or complete installed-GUI/system-service remote-session and recovery acceptance
- Android/Windows native controllers, multiple monitors/DPI, final-package clipboard/file/audio interoperability, the full tunnel runtime matrix, NAT/IPv6/blocked-UDP/loss and actual network-outage recovery remain unverified
- No 24-hour soak or fixed-workload performance comparison was performed; real upgrade/migration/backup/restore/rollback and full screenshot review remain unverified
- Linux production-desktop runtime was blocked by the available cloud desktop lacking logind/system-bus support. Linux/macOS runtime acceptance remains open
- Lock-screen, pre-login and UAC secure-desktop remote control are not supported
- Windows Authenticode status is `NotSigned`; macOS packages are unsigned. SHA-256, Defender and Sigstore provenance do not constitute an OS publisher signature

Unverified checks are retained as such in the machine-readable acceptance records and are not counted as passed. The original candidate-source documentation attached through the sealed source inventory predates this publication; this release body describes the published 10.1.0 scope.

## Downloads

- [Windows installer](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/HomeTunnel-Setup-10.1.0-x64.exe)
- [Windows portable](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/HomeTunnel-Windows-10.1.0-x64.zip)
- [Linux amd64](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/home-tunnel-linux-10.1.0-amd64.tar.gz)
- [Linux arm64](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/home-tunnel-linux-10.1.0-arm64.tar.gz)
- [macOS amd64](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/home-tunnel-macos-10.1.0-amd64.tar.gz)
- [macOS arm64](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/home-tunnel-macos-10.1.0-arm64.tar.gz)
- [SHA-256 checksums](https://github.com/ZHanry/home-tunnel-client/releases/download/v10.1.0/SHA256SUMS.txt)

Windows installer SHA-256: `58340bcd7d799ab7e5deaccc6d284fb4313b322ac869bdfd2ad2368b03b13eb5`

Windows portable SHA-256: `e1c04b5cd06dcd5ac4548bac0e1611d9a996e70ba71307bb05fdb82350b98df7`

中文：本次正式版直接晋升已验证的 10.1.0 原始候选文件，未重新构建。精确 Windows worker 完成 30 次连接、约 2 小时持续画面与输入，以及崩溃后显式重启恢复测试。最终文件 Defender 复扫、安装/卸载和安装文件哈希检查通过。测试为同机 Chromium 与生产源码 QA host；独立设备、完整安装后 GUI/系统服务、断网恢复、Linux/macOS 运行等范围仍未验证，未进行 24 小时测试。Windows 文件没有 Authenticode 发布者签名。新功能需服务端 10.1.0；Android 保持 10.0.0。


## Previous release: 10.0.0

# Home Tunnel Client 10.0.0

Historical 10.0.0 evidence follows; it is not reused as 10.1.0 final-artifact acceptance.

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
