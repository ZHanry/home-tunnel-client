<img src="docs/assets/HomeTunnel.svg" alt="" width="64" height="64">

# Home Tunnel Client

当前源码为 **8.0.0 开发版**，只允许预发布；原生远控媒体尚不可用。下方 7.0.0 链接仍指向已有正式版。详见 [开发状态与验证边界](native/remote/README.md)。

**连接 Windows、macOS、Linux 与 NAS**

[![Stable 7.0.0](https://img.shields.io/badge/stable-7.0.0-176653)](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) [![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

[English](README.en.md) · [项目网站](https://zhanry.github.io/home-tunnel/) · [下载](https://github.com/ZHanry/home-tunnel/blob/main/docs/DOWNLOADS.md) · [快速开始](https://github.com/ZHanry/home-tunnel/blob/main/docs/GETTING_STARTED.md)


在家中电脑或 NAS 上运行受管隧道，访问自己的 Home Tunnel 服务器。GUI 与 CLI
共享 Go 核心，后台 Agent 执行转发；窗口关闭后仍可保持连接。

| 平台 | 7.0.0 下载 |
| --- | --- |
| Windows x64 | [安装器](https://github.com/ZHanry/home-tunnel-client/releases/download/v7.0.0/HomeTunnel-Setup-7.0.0-x64.exe) · [便携 ZIP](https://github.com/ZHanry/home-tunnel-client/releases/download/v7.0.0/HomeTunnel-Windows-7.0.0-x64.zip) |
| macOS Intel / Apple Silicon | [选择 amd64 / arm64 包](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) |
| Linux amd64 / arm64 · NAS | [选择平台包](https://github.com/ZHanry/home-tunnel-client/releases/tag/v7.0.0) · [NAS Compose 模板](packaging/nas/README.md) |

核验 Release 的 `SHA256SUMS.txt` 和证明文件后安装。Windows/macOS 当前没有平台
发行证书，包内如实标明未签名；不要把哈希或病毒扫描当成平台签名。
[签名流程与凭据保护](docs/PLATFORM_SECURITY.md)。

## 接入自己的服务器

1. 服务端使用 **7.0.0**。桌面输入 HTTPS 地址，使用账号 + MFA 或一次性接入码。
2. 选择本机可访问的服务，创建 HTTP/HTTPS 或被授权的 TCP/UDP 连接。
3. 等待在线并验证公网访问。SSH/RDP/RTSP 有预设，原始传输由应用负责认证和加密。

桌面会话只管理本机。标签、收藏在设置中修改；选中最多 50 条本机连接可以批量暂停/
恢复，确认范围后逐项显示结果。跨设备/服务器管理使用 Web 或 Android。

```sh
home-tunnel-client enroll --server https://console.your-domain.net \
  --device-name home-nas --enrollment-code-file /secure/enrollment-code
home-tunnel-client doctor
home-tunnel-client run
```

CLI 服务安装和状态路径请按 [运维指南](docs/OPERATIONS.md)；勿直接复制示例私密路径。
Windows 使用 DPAPI，macOS 使用 Keychain，Linux headless 明确使用 0600 文件权限。
自有 Agent 与客户端均为 7.0.0，内置 FRP 为 0.70.1，必须使用同包 Agent。

## 开发与验证

```sh
go test ./...
python3 scripts/check-repository.py
```

Go 1.26.6；原生 GUI 构建依赖见各平台打包脚本。CI 检查 Windows 安装/卸载、
Defender 扫描、Agent 可复现哈希、macOS/Linux 构建和浏览器交互。

[功能说明](docs/PLATFORM_FEATURES.md) · [诊断/签名](docs/PLATFORM_SECURITY.md) · [API](contracts/README.md) · [项目入口](https://github.com/ZHanry/home-tunnel)
