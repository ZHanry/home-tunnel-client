# Home Tunnel Client

Windows、macOS、Linux 共用的 Home Tunnel 客户端。图形界面（GUI）、命令行（CLI）、后台运行逻辑和受管隧道 Agent 在同一个仓库维护，共用核心代码。

[项目主页](https://github.com/ZHanry/home-tunnel) · [服务端](https://github.com/ZHanry/home-tunnel-server) · [Android 管理 App](https://github.com/ZHanry/home-tunnel-android)

## 选择使用方式

| 场景 | 程序 |
| --- | --- |
| Windows / macOS / Linux 桌面 | `home-tunnel-gui`，窗口与系统托盘 |
| NAS、无桌面 Linux 主机 | `home-tunnel-client`，CLI 与 systemd 服务 |
| macOS 无界面服务 | `home-tunnel-client`，CLI 与 launchd 服务 |
| 底层隧道 | 安装包自带的 `home-tunnel-agent`，由客户端管理 |

CLI 用于注册设备、运行隧道、查看状态和管理本机连接。它与 GUI 共用登录、同步、续租、状态存储和 Agent 管理能力。
Linux headless 为 Stable；macOS headless 为 Beta；各平台图形界面共用同一套实现。

## 下载和安装

已有稳定版本：[原项目 5.0.0 安装包](https://github.com/ZHanry/home-tunnel/releases/tag/v5.0.0)。
后续客户端版本在[本仓库 Releases](https://github.com/ZHanry/home-tunnel-client/releases) 独立发布。
安装和运维说明见 [OPERATIONS.md](docs/OPERATIONS.md)。

## 构建

使用 Go 1.26.6。CLI 不需要图形库：

```sh
go test ./...
go vet ./...
CGO_ENABLED=0 go build ./cmd/home-tunnel-client
```

Windows GUI 使用 WebView2；Linux GUI 需要 GTK 3 与 WebKitGTK 4.1；macOS GUI 使用系统 WebKit。

```sh
# Linux/macOS native GUI
CGO_ENABLED=1 go build ./cmd/home-tunnel-gui
# Linux complete package
ARCH=amd64 ./packaging/build-release.sh
# macOS complete package
ARCH=arm64 ./packaging/macos/build-release.sh
```

Windows 完整安装包：`./packaging/windows/build-release.ps1`，需要 `windres`。
单独编译的 GUI 仅供开发；实际运行隧道应使用包含已验证 Agent 的完整安装包。

## 目录

| 目录 | 职责 |
| --- | --- |
| `cmd/` | GUI、CLI 和 Windows 安装器入口 |
| `internal/` | 共用核心、API、同步、状态、桌面界面 |
| `agent/` | 受限 FRP Agent，独立 Go 模块与第三方许可 |
| `packaging/` | 各平台构建、安装和服务配置 |
| `tests/browser/` | 桌面页面交互测试 |
| `contracts/` | 从服务端版本化协议提取的校验快照 |

浏览器测试单独使用 Node.js 24 与 pnpm，不影响 CLI 构建。
详见 [贡献指南](CONTRIBUTING.md)、[兼容记录](compatibility.json) 和 [发布流程](docs/RELEASING.md)。

Apache-2.0，见 [LICENSE](LICENSE)；FRP 许可见 `agent/`。
