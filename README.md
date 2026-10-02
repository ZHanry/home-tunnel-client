# HomeDesk

HomeDesk 是基于 RustDesk 的家庭自建远控方案，目标是保留断公网可用的纯内网能力，并可显式选择自建公网 P2P 模式；同时为家庭设备提供设备清单、远程开机与会话审计。

桌面首页新增“家庭服务”，可在已确认的自建公网模式下登录自己的 home-tunnel，查看和管理设备与服务。Windows 完整包登录后自动登记本机并运行包内受管 Agent，默认不发布服务；支持 DPAPI 加密记住登录和设备凭据。其他平台暂只提供门户管理。完整设计见 [`docs/PORTAL_INTEGRATION_PLAN.md`](docs/PORTAL_INTEGRATION_PLAN.md)，使用方式见 [`docs/HOME_TUNNEL_PORTAL.md`](docs/HOME_TUNNEL_PORTAL.md)。

2026-09-22 已实现 `lan_only`（默认）与 `self_hosted` 双模式的客户端、配置迁移、网络策略、中文设置与独立公网部署工具；保持上游直连优先、中继兜底，Console 继续限制在内网或显式可信 VPN 路径。配置、网络、HTTP 撤权、界面和本地容器测试已通过，Windows Rust/Flutter Release 构建通过。**真实跨网 P2P、NAT、中继会话与生产部署仍待实机验收，不能把本地通过等同于公网发布完成。** 配置入口见 [`docs/CLIENT_NETWORK.md`](docs/CLIENT_NETWORK.md)，实际证据见 [`docs/T17_VALIDATION.md`](docs/T17_VALIDATION.md)。

当前已有 T-00～T-02 基础、可运行的 Console、原生设备墙、客户端心跳/会话上报、部分纯内网入口限制，以及 Windows/Linux x64/ARM64 原生构建脚本。**Windows 已生成测试配置的构建验证包，Console 静态镜像已通过容器测试；ARM64 定制包、真实 Windows 双机和麒麟验收仍未完成，不能视为全部功能已交付。** 最新逐项状态见 [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md)。

## 文档入口

- 唯一设计契约：[`docs/DESIGN.md`](docs/DESIGN.md)
- 串行任务卡：[`docs/ROADMAP.md`](docs/ROADMAP.md)
- 飞牛 NAS 部署：[`docs/DEPLOY.md`](docs/DEPLOY.md)
- 自建公网部署：[`docs/DEPLOY_PUBLIC.md`](docs/DEPLOY_PUBLIC.md)
- 客户端双模式配置：[`docs/CLIENT_NETWORK.md`](docs/CLIENT_NETWORK.md)
- home-tunnel 服务门户：[`docs/HOME_TUNNEL_PORTAL.md`](docs/HOME_TUNNEL_PORTAL.md)
- 公网开发与验收记录：[`docs/T17_VALIDATION.md`](docs/T17_VALIDATION.md)
- T-00 验证记录：[`docs/T00_VALIDATION.md`](docs/T00_VALIDATION.md)
- RustDesk 上游基线：[`docs/UPSTREAM.md`](docs/UPSTREAM.md)
- T-01 验证记录：[`docs/T01_VALIDATION.md`](docs/T01_VALIDATION.md)
- P0 冒烟验收：[`tests/smoke.md`](tests/smoke.md)
- 管理台部署/API：[`docs/CONSOLE.md`](docs/CONSOLE.md)
- ARM64 麒麟构建与限制：[`docs/XINCHUANG.md`](docs/XINCHUANG.md)
- 本轮实现与验证：[`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md)

## 服务端快速入口

```bash
cd server
cp .env.example .env
# 编辑 .env，把占位值替换为 NAS 的固定内网 IP
docker compose config
docker compose up -d
```

完整步骤、安全边界与公钥提取方法见 `docs/DEPLOY.md`。
