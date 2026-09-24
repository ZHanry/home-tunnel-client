# Changelog

## 9.0.0

- Rework the desktop around a sidebar and separate remote viewer; add request approval, a fixed password, a one-time password and an emergency disconnect hotkey.
- Cross-account access keeps signed grants and leases. Fixed-password access currently covers an already signed-in Windows desktop, not the lock screen, login screen or UAC secure desktop.
- The native worker still requires exact-package verification before publication. A high-privilege Windows service and secure-desktop control are not included. System audio and full clipboard interoperability remain unavailable or unverified.

## 8.0.0 — development (not a stable release)

- Adds the shared C++20 remote ABI, locked WebRTC source/build inputs, protocol framing/transcript tests, UDP selected-pair/lease/epoch safety gates, keyboard and mouse watchdog tests, and Windows input adapter groundwork.
- Adds four-session ownership/focus isolation, hash-checked inherited-pipe worker diagnostics, and bounded text/file receipt with integrity and no-overwrite checks.
- Adds native-core CI on Windows, macOS and Linux. The 7.0 API contract remains pinned for existing tunnels; remote contracts have a separate source digest.
- **Remote media remains unavailable.** These changes do not yet provide a complete remote host/controller, audio or virtual microphone, connected clipboard/file UI, or verified AV1/HEVC. Real platform/network, signing and long-running release gates are still outstanding. Only prerelease tags are allowed while `stage=internal-testing`.


## 7.0.0 — 2026-09-19

All first-party components and the managed Agent now use 7.0.0. Upgrade the server,
desktop/CLI and Android together; FRP remains at its independent 0.70.1 version.

- Fix Web multi-tab refresh, stale access-policy writes and persistent backup health.
- Reject unverified/incomplete desktop updates and use stable semantic versions.
- Add full REST OpenAPI/JSON Schema and capability-driven Android transport controls.
- Add TOTP/recovery codes, session management and single-use enrollment codes.
- Add OS credential protection, redacted diagnostics and host-only admin recovery.
- Add encrypted off-host backup, verified fresh-volume restore, preflight/NAS
  templates, monitoring and alert rules.
- Add encrypted Android server profiles, tags/favorites and per-item batch operations.
- Publish checksums, SBOMs, provenance and verification evidence as durable assets.

Windows/macOS have no publisher certificates configured and are explicitly unsigned;
their signing/notarization workflow is ready. Android retains its release signing
identity. Read the migration and platform-security guides before upgrading.

## 6.1.1 — 2026-09-09

统一新建连接标题与空状态文案，适用于 HTTP、TCP、UDP 及应用预设。

## 6.1.0 — 2026-09-09

- 修复 Windows 启动时额外控制台窗口：直接读取机器标识，不再调用 reg.exe；受管 Agent 的启动和配置校验均不创建控制台，日志保留在本地文件。
- 为 GUI EXE 嵌入图标和版本资源，并为原生窗口绑定图标。桌面窗口默认尺寸调整为适合服务工作区的大小。
- 新建连接提供 Web（HTTP/HTTPS）、RTSP、SSH、RDP、通用 TCP 和 UDP。公网端口在服务端已开放范围内自动分配，RTSP 使用 TCP 交错传输。
- 显示服务端版本、端口开放和账号权限限制；保留版本冲突与端口耗尽等可恢复错误。
- Windows 发布继续执行 Defender 扫描、安装／卸载检查，并新增 EXE 图标、GUI 子系统和实际窗口图标验证。

TCP/UDP 创建需要服务端 6.1.0。管理员需启用实际公网端口范围；普通用户还需获得控制台中的自助创建授权。[连接类型说明](https://github.com/ZHanry/home-tunnel-client/blob/v6.1.0/docs/CONNECTION_TYPES.md)。

Windows 使用标准 Inno Setup 安装器。未配置 Authenticode 代码签名，系统的发布者／信誉提示与 Defender 恶意软件扫描是不同检查。原 6.0.0 EXE 保持撤回。


## 6.0.1 — 2026-09-09

Replace the flagged custom Windows self-extractor with the native Inno Setup installer. Scan final Windows artifacts with Defender, exercise installation/uninstallation, and require matching evidence before publication. The 6.0.0 EXE has been withdrawn.

## 6.0.0 — 2026-09-09

Home Tunnel 6.0 正式发布。Web、桌面与手机端采用全新的页面结构，统一使用清晰的设备与账号边界。

- 全新本机服务工作区、独立设备状态区和设置页。
- 新增名称搜索、状态筛选和明确的本地目标分组。
- 实时结果与离线缓存均按本机设备过滤，防止不同机器的服务混在一起。
- Windows 提供安装器与便携包，Linux / macOS 提供 amd64 和 arm64 安装包。


## Unreleased · 正式发布

- 当前仓库负责GUI、CLI、客户端核心、Agent 与各平台打包。
- 统一开发文档、源码构建入口和正式发布状态。
- 自动化检查与真实环境反馈共同用于后续功能完善。

以下为 5.x 早期版本的历史记录；从 6.0 起按正式发布流程维护。
后续用户可见变化在这里记录，并注明影响到的接口、配置和测试步骤。


## 5.0.1 · Security maintenance

- Added per-session local UI authorization, loopback/origin checks and frame protection.
- Prevented redirect replay and API origin/path escapes; redacted remote errors and CLI logs.
- Agent 5.0.1 uses go-ntlmssp v0.1.1 in both development and packaged builds, with a reproduced binary hash.
- Security CI now checks open CodeQL findings after analysis.
