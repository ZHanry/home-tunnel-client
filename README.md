# HomeDesk

HomeDesk 是基于 RustDesk 的家庭内网远控方案，目标是断公网仍可用、数据不出户，并为家庭设备提供设备清单、远程开机与会话审计。

当前已有 T-00～T-02 基础、可运行的 Console、原生设备墙、客户端心跳/会话上报、部分纯内网入口限制，以及 Windows/Linux x64/ARM64 原生构建脚本。**Windows 已生成测试配置的构建验证包，Console 静态镜像已通过容器测试；ARM64 定制包、真实 Windows 双机和麒麟验收仍未完成，不能视为全部功能已交付。** 最新逐项状态见 [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md)。

## 文档入口

- 唯一设计契约：[`docs/DESIGN.md`](docs/DESIGN.md)
- 串行任务卡：[`docs/ROADMAP.md`](docs/ROADMAP.md)
- 飞牛 NAS 部署：[`docs/DEPLOY.md`](docs/DEPLOY.md)
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
