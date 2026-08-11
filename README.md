# HomeDesk

HomeDesk 是基于 RustDesk 的家庭内网远控方案，目标是断公网仍可用、数据不出户，并为家庭设备提供设备清单、远程开机与会话审计。

当前仓库处于 **T-00：仓库初始化 + 服务端编排**。本阶段只提供锁定版本的 hbbs/hbbr 服务端、飞牛 NAS 部署说明和 P0 冒烟清单，不包含客户端 fork 与 Console 实现。

## 文档入口

- 唯一设计契约：[`docs/DESIGN.md`](docs/DESIGN.md)
- 串行任务卡：[`docs/ROADMAP.md`](docs/ROADMAP.md)
- 飞牛 NAS 部署：[`docs/DEPLOY.md`](docs/DEPLOY.md)
- T-00 验证记录：[`docs/T00_VALIDATION.md`](docs/T00_VALIDATION.md)
- P0 冒烟验收：[`tests/smoke.md`](tests/smoke.md)

## 服务端快速入口

```bash
cd server
cp .env.example .env
# 编辑 .env，把占位值替换为 NAS 的固定内网 IP
docker compose config
docker compose up -d
```

完整步骤、安全边界与公钥提取方法见 `docs/DEPLOY.md`。
