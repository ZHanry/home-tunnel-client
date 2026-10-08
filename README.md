# HomeDesk / Home Tunnel Client

当前主线为 **11.0.0-rc.1 候选版**。暖居 Flutter 界面与 RustDesk 原生核心提供远控；必须认证加密并通过 P2P 直连，禁止中继和供应商服务器回退。直连失败会明确停止。

[English](README.en.md) · [候选发行](https://github.com/ZHanry/home-tunnel-client/releases/tag/v11.0.0-rc.1) · [最后稳定版 10.1.0](https://github.com/ZHanry/home-tunnel-client/releases/tag/v10.1.0)

## 下载与接入

候选 Release 只有四个附件：Windows x64 HomeDesk 安装器、五平台 CLI/Agent 合集、源码与构建材料包、SHA256SUMS。macOS/Linux 当前候选下载提供独立 CLI/Agent；原生桌面 GUI 暂只发布 Windows。Android 从 [Android 仓](https://github.com/ZHanry/home-tunnel-android/releases) 下载同源通用 APK。

安装前核验 SHA-256。Windows 安装器未做 Authenticode 签名。通用包不含服务器地址、公钥或账户凭据；先配置你自己的 hbbs 地址、公钥和允许的来源，再登录 HTTPS 管理台。远控目标需明确开启共享并授权；接入账号不等于自动授权远控。

HTTP/HTTPS、受控 TCP/UDP、端口池、权限、ACL、流量治理、诊断和 NAS 使用原 Go/FRP 协议。自有 Agent 保持 10.1.0 已校验原始字节，CLI 与 HomeDesk 为 11.0.0-rc.1；内置 FRP 0.70.1。不混用平台 Agent。

```sh
home-tunnel-client enroll --state /secure/home-tunnel/state.json \
  --server https://console.your-domain.net --device-name home-nas \
  --enrollment-code-file /secure/enrollment-code
home-tunnel-client run --state /secure/home-tunnel/state.json --agent /opt/home-tunnel/home-tunnel-agent
```

关闭 GUI 后继续穿透，按 [独立 CLI/Agent](docs/INDEPENDENT_TUNNEL.md) 安装登录任务、systemd 或 NAS 服务。GUI 内受管 Agent 跟随窗口；同一状态不能同时启动两个 Agent。远控配置、直连失败不撤销独立穿透进程。

## 验证和源码

本次候选尚未完成跨网 NAT、长期媒体及 Android 真机验收，不能视为稳定版。限制与已验证范围见 [候选说明](docs/HOMEDESK_RELEASE.md)。旧 10.x worker/DTLS/TURN 文档与代码仅保留历史，不作为新包的远控引擎。

`client/` 保留 RustDesk 上游及暖居来源历史；Android 仓通过固定 gitlink 复用同一 Rust/Flutter 树。核心来源与修改清单见 [来源记录](docs/homedesk/PROVENANCE.md)。原 Go 代码仍为 Apache-2.0；整合的 Rust/Flutter HomeDesk 按 [AGPL-3.0](LICENSE-RUSTDESK) 分发，对应源码、依赖源和构建说明在材料包中提供。

```sh
git submodule update --init --recursive
go test ./...
python3 scripts/check-repository.py
python3 build/ci/build-client.py --target win-x64 --config build/config.toml.example
```

固定 Rust 1.96.0、Flutter 3.24.5、FRB 1.80.1、Go 1.27.0。构建入口和 Windows 原生依赖见 `build/ci`；API 使用 `api-v1.6.0`，HomeDesk 目录要求 Server 11.x。

[项目入口](https://github.com/ZHanry/home-tunnel) · [NAS](packaging/nas/README.md) · [API](contracts/README.md) · [安全](SECURITY.md)
