# Changelog

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
