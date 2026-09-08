<div align="center">
  <img src="docs/assets/HomeTunnel.svg" alt="Home Tunnel" width="80" height="80">
  <h1>Home Tunnel Client</h1>
  <p><strong>Windows · macOS · Linux，共用核心的 GUI 与 CLI</strong></p>
  <p>
    <img src="https://img.shields.io/badge/status-internal_testing-92400e" alt="Status: internal testing">
    <a href="https://github.com/ZHanry/home-tunnel-client/actions/workflows/ci.yml"><img src="https://github.com/ZHanry/home-tunnel-client/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license"></a>
  </p>
  <p><a href="README.en.md">English</a> · <a href="https://zhanry.github.io/home-tunnel/">项目网站</a></p>
</div>

在家中的电脑或 NAS 上注册设备、同步连接配置并运行受管隧道。图形界面、命令行和后台服务共用登录、同步、状态存储与 Agent 管理逻辑。

> **内部测试阶段。** 当前以源码构建和联调为主，安装、系统服务、托盘与重连行为仍需在真实设备上验证。

[项目总览](https://github.com/ZHanry/home-tunnel) · [服务端](https://github.com/ZHanry/home-tunnel-server) · [Android 远程管理](https://github.com/ZHanry/home-tunnel-android)

## 选择使用方式

| 场景 | 入口 | 说明 |
| --- | --- | --- |
| Windows / macOS / Linux 桌面 | `home-tunnel-gui` | 登录、管理连接、窗口与托盘 |
| NAS、无桌面 Linux | `home-tunnel-client` | 命令行管理与 systemd 后台运行 |
| macOS 后台运行 | `home-tunnel-client` | 命令行管理与 launchd 服务 |
| 底层转发 | `home-tunnel-agent` | 由客户端启动和监督，使用经过校验的配置 |

CLI 的定位是本机设备与隧道管理，适合脚本和无界面主机。它与 GUI 放在同一个仓库，避免两套客户端逻辑分叉。

## 构建完整测试包

先准备一个可访问的[测试服务端](https://github.com/ZHanry/home-tunnel-server#readme)和测试账号。构建工具使用 **Go 1.26.6**；Agent 构建会下载并校验固定版本的 FRP 源码。

```sh
git clone https://github.com/ZHanry/home-tunnel-client.git
cd home-tunnel-client
```

### Windows x64

安装 Go、WebView2 Runtime 和 `windres` 后，在 PowerShell 中运行：

```powershell
.\packaging\windows\build-release.ps1 -WindRes 'C:\tools\mingw\bin\windres.exe'
```

将 `windres` 路径替换成实际位置。`outputs/windows/` 会生成 Setup EXE、ZIP 及校验文件。完整包包含 GUI 与受管 Agent。

### Linux

完整 GUI 包需要 GTK 3、WebKitGTK 与 C 编译工具。以下依赖命令适用于 Debian / Ubuntu：

```sh
sudo apt-get install -y libgtk-3-dev libwebkit2gtk-4.1-dev pkg-config gcc
ARCH=amd64 ./packaging/build-release.sh
```

arm64 主机使用 `ARCH=arm64`。产物位于 `outputs/linux/`；在目标主机解压后，进入包目录运行 `sudo ./install.sh`，再运行 `sudo home-tunnel-enroll` 注册设备。

### macOS

安装 Xcode Command Line Tools 和 Go，按目标处理器构建：

```sh
ARCH=arm64 ./packaging/macos/build-release.sh
# Intel Mac 使用 ARCH=amd64
```

产物位于 `outputs/macos/`。原生 GUI 应在匹配架构的 macOS 环境构建和验证。安装与 launchd 操作见 [运行指南](docs/OPERATIONS.md)。

## 使用 GUI 或 CLI

GUI 启动后填写服务端 HTTPS 根地址，使用测试账号登录。窗口关闭后会隐藏到托盘；从托盘或退出入口结束进程。

Linux / macOS 安装并注册设备后，常用 CLI 命令如下：

```sh
home-tunnel-client help
home-tunnel-client status --json
home-tunnel-client connection ls
home-tunnel-client connection add --name demo --subdomain my-demo --local-port 8080
home-tunnel-client connection set --id CONNECTION_ID --enabled=false
```

请在持有设备状态的服务账号下执行命令，或显式指定 `--state`。连接 ID、子域和目标端口按实际测试环境填写。状态位置、日志与后台服务命令见 [OPERATIONS.md](docs/OPERATIONS.md)。

## 开发与测试

只编译 CLI 时无需图形库：

```sh
CGO_ENABLED=0 go build ./cmd/home-tunnel-client
```

完整源码检查需要所在平台的 GUI 构建依赖：

```sh
go test ./...
go vet ./...
```

桌面页面测试单独使用 Node.js 24 与 pnpm 11：

```sh
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
pnpm run lint
pnpm run test:browser
```

直接编译的客户端程序需要另外配置 Agent 才能实际运行隧道。体验完整流程时优先使用上述打包脚本生成的安装包。

## 目录与边界

| 目录 | 职责 |
| --- | --- |
| `cmd/` | GUI、CLI、Windows 安装器入口 |
| `internal/` | 共用核心、API、同步、状态、Agent 监督与桌面界面 |
| `agent/` | 受限 FRP Agent、独立 Go 子模块与第三方许可 |
| `packaging/` | 各平台的构建、安装及后台服务配置 |
| `tests/browser/` | 桌面页面交互测试 |
| `contracts/` | 固定版本的服务端协议测试夹具 |

当前仅接受服务端授权的 HTTP / HTTPS、TCP 与固定端口 UDP 配置，不提供任意 FRP 命令。客户端与 Agent 的版本分别维护。

[贡献指南](CONTRIBUTING.md) · [运行指南](docs/OPERATIONS.md) · [测试发布](docs/RELEASING.md) · [安全报告](SECURITY.md) · [Apache-2.0](LICENSE)
