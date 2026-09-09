<div align="center">
  <img src="docs/assets/HomeTunnel.svg" alt="Home Tunnel" width="72" height="72">
  <h1>Home Tunnel Client</h1>
  <p><strong>专注于本机服务的桌面与命令行客户端</strong></p>
  <p><a href="https://github.com/ZHanry/home-tunnel-client/releases/latest"><img src="https://img.shields.io/badge/release-6.0.1-176653" alt="Release 6.0.1"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a></p>
  <p><a href="README.en.md">English</a> · <a href="https://zhanry.github.io/home-tunnel/">项目网站</a></p>
</div>

Windows 6.0.0 EXE 已因 Defender 告警撤下。6.0.1 改用标准安装器并增加实际杀毒扫描与安装验证；说明见 [Windows 发布检查](docs/WINDOWS_RELEASE_CHECKS.md)。

6.0 正式版以“本机服务”为中心重新设计桌面界面：设备状态、服务搜索、状态筛选、连接编辑与设置各有清晰入口。GUI 和 CLI 共用客户端核心。

## 下载与安装

在 [Releases](https://github.com/ZHanry/home-tunnel-client/releases/latest) 中选择：

| 平台 | 文件 |
| --- | --- |
| Windows x64 | `HomeTunnel-Setup-6.0.1-x64.exe`；便携版为 `.zip` |
| Linux amd64 / arm64 | `home-tunnel-linux-6.0.1-<架构>.tar.gz` |
| macOS Intel / Apple Silicon | `home-tunnel-macos-6.0.1-amd64.tar.gz` / `arm64.tar.gz` |

安装器或解压后的安装脚本会部署完整客户端及 Agent。`SHA256SUMS.txt` 提供安装文件校验值。首次运行填写自己的控制台地址、用户名与密码，设备会自动登记。

## 使用方式

1. 打开“本机服务”，添加本地服务名称与访问地址。
2. 本地目标填这台机器可以访问的主机和端口；本机服务通常使用 `127.0.0.1`。
3. 等待在线后复制公网地址。可随时搜索、暂停、启用或编辑服务。
4. 管理其他机器时打开 Web 控制台或 Android App。

客户端只展示并操作当前设备的连接，即使同一账号在多台电脑上登录也各自独立。关闭窗口保持后台运行；“退出程序”停止隧道；“退出账号”还会清除本机登录凭据。

## 命令行与开发

NAS 和无桌面主机使用安装包中的 CLI 与后台服务配置，详见[运行指南](docs/OPERATIONS.md)。源码入口为 `cmd/`，共用核心为 `internal/`，FRP Agent 是 `agent/` 中的独立 Go 模块。构建使用 Go 1.26.6；执行 `go test ./...`，桌面交互检查使用 `pnpm test:browser`。

[发布流程](docs/RELEASING.md) · [版本说明](docs/RELEASE_NOTES.md) · [安全报告](SECURITY.md) · [项目入口](https://github.com/ZHanry/home-tunnel)

![Home Tunnel 6.0 desktop](docs/assets/desktop.jpg)
