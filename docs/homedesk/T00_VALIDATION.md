# T-00 验证记录

更新时间：2026-08-11

本文件记录仓库侧可重复验证和仍需飞牛 NAS 实机完成的门禁。它不是 `tests/smoke.md` 的替代品。

## 已验证

| 项目 | 证据 | 结果 |
| --- | --- | --- |
| TOML 语法 | Python 3.11 `tomllib` 读取 `build/config.toml.example` | 通过 |
| Compose YAML 结构 | PyYAML 解析并断言仅有 hbbs/hbbr 两个活动服务 | 通过 |
| Compose 规范 | 使用 compose-spec 官方 JSON Schema 验证 `server/compose.yml` | 通过 |
| 真实 Compose 配置 | WSL Ubuntu；Docker 29.1.3；Docker Compose 2.40.3；设置 RFC1918 测试地址后执行 `docker compose config --quiet` | 通过 |
| 固定镜像展开 | `docker compose config --images` 输出两行完全相同的 `ghcr.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00` | 通过 |
| NAS 验收脚本 | `bash -n server/verify.sh`；按 `.env.example` 结构保留未启用的 Console 占位值、仅替换两个 NAS IP 后执行 `bash server/verify.sh --config-only` | 通过 |
| 官方镜像拉取 | GHCR `1.1.16` 多架构摘要 `sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00`；amd64 `sha256:5c5d42feed1c85c54ffebaaf478dc2551e3efbab1b9ea97bc8bed5815f8c1d54`；arm64 `sha256:593c9af7fb8010df0104f9150e8cac8fface359bcc3a358533214cc09ec80520`；arm/v7 `sha256:ffec453db12e55699d37aaf7a8e9dd98582ab6a2e00d5cd4a0c1da8bfbf5e790`；amd64 实际拉取成功 | 通过 |
| 服务实际启动 | 使用 WSL eth0 的 RFC1918 地址执行完整 `bash server/verify.sh`；hbbs/hbbr 在 30 秒内均为 `running` | 通过 |
| 密钥生成与持久化 | 生成 `id_ed25519`/`id_ed25519.pub`；`docker compose restart` 前后文件 SHA256 比较一致 | 通过 |
| 端口策略 | 自动断言仅启用 TCP 21115、TCP/UDP 21116、TCP 21117；无活动的 21118/21119 | 通过 |
| 内网地址防护 | `verify.sh` 强制 Bind/Server 地址相同且属于 RFC1918；实测拒绝 `0.0.0.0` 与两个私网地址不一致；调用者环境预置全接口/公网值时仍被 `.env` 的已校验私网值覆盖，并只绑定 WSL 私网接口 | 通过 |
| 持久化与重启 | 自动断言两个服务均为 `./data:/root` 和 `restart: unless-stopped` | 通过 |
| 文档链接 | 检查仓库内 Markdown 相对链接目标存在 | 通过 |
| 忽略规则 | `git check-ignore` 验证 `.env`、真实 `config.toml`、数据卷和私钥被排除，example 文件可跟踪 | 通过 |
| 基础密钥扫描 | 检查私钥块和疑似长 Token/密码赋值 | 未发现 |
| 独立复核 | 对照 DESIGN 4/5/9/11 节与 ROADMAP T-00 逐项审阅 | 无 Blocker / Major |

真实 Compose 校验命令：

```bash
cd /mnt/d/coding/codex/my-desk/server
HOMEDESK_BIND_IP=192.168.1.10 \
HOMEDESK_SERVER_HOST=192.168.1.10 \
docker compose config --quiet
```

## 本机实际启动结果

2026-08-11，Docker Hub 入口仍超时，但官方 GHCR 恢复可用。核对 GHCR `1.1.16` 多架构清单后，确认 amd64、arm64、arm 平台摘要与官方 Docker Hub 同版本完全一致，因此生产 Compose 改用 GHCR 且继续锁定原多架构摘要。

完整执行 `server/verify.sh` 后取得以下结果：

- hbbs、hbbr 均在 30 秒内进入 `running`；
- hbbs 生成密钥对和 SQLite 数据库；
- 日志确认 hbbs 内部监听 21115、21116，hbbr 内部监听 21117；
- 宿主机只在所配置的 WSL eth0 私网地址发布 21115/tcp、21116/tcp+udp、21117/tcp，未发布 21118/21119；
- 两个容器的镜像 ID 均为锁定摘要，重启策略均为 `unless-stopped`；
- `docker compose restart` 后两个密钥文件的 SHA256 保持一致；
- 验证结束后执行 `docker compose down`，并删除本轮 WSL 私网测试生成的数据库与密钥，避免误作生产身份。

## 仍需飞牛 NAS / 家庭设备完成

本机启动证明编排和上游服务可运行，但不能替代真实家庭网络、fnOS 和客户端性能验收。以下项目仍须现场完成：

- 飞牛 NAS 使用真实固定内网 IP 执行 `server/verify.sh`；
- fnOS 防火墙只允许家庭网段访问 21115–21117；
- NAS 重启后两个容器自动恢复；
- 两台官方客户端完成 P0 的 M1–M7。

## NAS 可重复验收

在 `server/.env` 填好真实内网配置后运行：

```bash
cd server
chmod +x verify.sh
./verify.sh --config-only
./verify.sh
```

脚本会校验占位值、Compose 配置、固定镜像引用、容器运行状态、公钥文件和 `unless-stopped`，成功后保持服务运行，供后续 `tests/smoke.md` 验收。
