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
