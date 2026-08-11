# HomeDesk 服务端部署（飞牛 NAS / fnOS）

本文对应 T-00 与 P0，目标是在飞牛 NAS 上启动上游 `hbbs`（ID 注册、信令、打洞协调）和 `hbbr`（中继兜底）。Console 将在 T-04 实现，本阶段不会启动。

## 1. 安全边界与版本

- 镜像固定为官方 GHCR `ghcr.io/rustdesk/rustdesk-server:1.1.16`，并锁定多架构清单摘要 `sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00`，不使用 `latest`。
- GHCR 的 `1.1.16` 清单包含 Linux `amd64`、`arm64`、`arm`，适用于常见 x86 与 ARM 飞牛设备；其平台摘要与官方 Docker Hub 同版本清单一致。
- 只开放内网端口，不在路由器配置任何 RustDesk 端口映射、DMZ 或 UPnP 映射。
- P0 使用官方客户端验证链路；官方客户端尚未具备 HomeDesk 的“强制纯内网”定制，测试前必须手工填写自建 ID Server 与 Key。
- `server/data/id_ed25519` 是服务端私钥：只备份到受控的加密目录，禁止发给客户端、贴到聊天或提交 Git。

核心端口如下：

| 服务 | 端口 | 协议 | 用途 | P0 |
| --- | ---: | --- | --- | --- |
| hbbs | 21115 | TCP | NAT 类型测试 | 必开 |
| hbbs | 21116 | TCP + UDP | 注册、心跳、打洞与连接协调 | 必开 |
| hbbr | 21117 | TCP | 中继数据 | 必开 |
| hbbs / hbbr | 21118 / 21119 | TCP | WebSocket | 默认关闭，P2 再验证 |

## 2. 部署前检查

1. 给飞牛 NAS 设置固定内网 IPv4（路由器 DHCP 静态租约或 NAS 静态地址）。后续更换 IP 时，需要同步修改 `.env` 和客户端服务器设置。
2. 确认 NAS 已启用 Docker 与 Compose，并能通过终端执行 `docker compose version`。
3. 在持久存储卷中新建 HomeDesk 目录。下面用 `/你的持久卷/docker/homedesk` 表示，实际路径以飞牛“文件管理”显示为准。
4. 将仓库的 `server/compose.yml`、`server/.env.example` 和 `server/verify.sh` 上传到该目录。
5. 确认 21115–21117 没有被其他容器占用。

飞牛官方帮助中心没有给出统一的 Compose 项目路径、Docker 卷备份或容器端口防火墙教程；不同 fnOS 版本的界面也可能变化。因此本文使用标准 Docker Compose 命令作为确定路径，飞牛界面中的“项目目录、端口、防火墙规则”需要按实机版本核对。

## 3. 配置

进入部署目录：

```bash
cd /你的持久卷/docker/homedesk
cp .env.example .env
chmod 600 .env
```

编辑 `.env`，将两个 IP 占位值都替换为 NAS 的固定内网 IP：

```dotenv
HOMEDESK_BIND_IP=192.168.1.10
HOMEDESK_SERVER_HOST=192.168.1.10
```

上面的地址只是示例，必须换成你的实际地址。`HOMEDESK_BIND_IP` 控制容器端口只绑定到指定的 NAS 内网接口；`HOMEDESK_SERVER_HOST` 是 hbbs 告知客户端的中继地址。

T-00 单机部署要求两个值完全相同，且必须属于 RFC1918 私网地址（`10.0.0.0/8`、`172.16.0.0/12` 或 `192.168.0.0/16`）。`verify.sh` 会拒绝 `0.0.0.0`、回环地址、公网地址和两个值不一致的配置，避免意外把远控端口暴露到非内网接口。

Console 相关的两个变量在 T-04 前不会被使用，可暂时保留占位值。

## 4. 校验并启动

先检查 Compose 展开结果。命令必须成功，且输出中不应再出现 `REPLACE_WITH_`：

```bash
docker compose config
```

也可以使用仓库提供的验收脚本先只检查配置。脚本要求 Bash 4 或更高版本；请使用 `./verify.sh` 或 `bash verify.sh`，不要使用 `sh verify.sh`：

```bash
chmod +x verify.sh
./verify.sh --config-only
```

确认无误后拉取并启动：

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail 100 hbbs hbbr
```

等价的一键启动与验收命令是：

```bash
./verify.sh
```

脚本成功后会保持两个服务运行，并检查固定镜像、容器状态、公钥文件和重启策略；不会输出私钥内容。

验收启动状态：

- `docker compose ps` 中 `hbbs`、`hbbr` 都是 `Up`/`running`；
- `data/` 下出现 `id_ed25519` 与 `id_ed25519.pub`；
- 日志没有持续重启、端口占用或权限拒绝；
- `docker compose config --images` 展开的声明镜像引用包含 `ghcr.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00`。

如需持续观察日志：

```bash
docker compose logs -f --tail 100 hbbs hbbr
```

## 5. fnOS 防火墙与路由器

在飞牛“设置 → 安全性/防火墙”中，添加仅允许家庭网段访问的规则：

- TCP 21115
- TCP 21116
- UDP 21116
- TCP 21117

规则来源应限制为家庭网段（例如 `192.168.1.0/24`），不要填写“任意来源”。不同 fnOS 版本可能使用不同菜单名称；保存后从另一台家庭电脑测试端口，而不是只看界面状态。

路由器侧保持以下状态：

- 不创建 21115–21119 的公网端口转发；
- 不把 NAS 放进 DMZ；
- 如路由器支持，关闭针对这些端口的 UPnP 自动映射；
- 访客 Wi-Fi / IoT VLAN 不加入放行网段，除非你明确需要它们访问远控服务。

注意：飞牛官方资料显示，fnOS 管理页面端口在不同版本间存在 5666/5667 与旧版 8000/8001 的差异。这些是 fnOS 自身管理端口，与 HomeDesk 的 21115–21117 无关；不要为了部署 HomeDesk 改动 NAS 管理端口。

## 6. 提取服务器公钥

hbbs 首次启动后执行：

```bash
docker compose exec hbbs cat /root/id_ed25519.pub
```

也可读取宿主机文件：

```bash
cat ./data/id_ed25519.pub
```

屏幕上这一行是**公钥**，可以填写到官方客户端的 Key；不要读取或复制没有 `.pub` 后缀的 `id_ed25519` 私钥。

P0 中，在两台官方 RustDesk 客户端分别完成：

1. 打开设置中的网络设置并解锁；
2. ID Server 填 NAS 内网 IP；
3. Key 填上面取得的公钥；
4. API Server 留空；Relay Server 可留空，由 hbbs 下发 `NAS_IP:21117`；
5. 保存后确认客户端显示就绪，再进行 `tests/smoke.md`。

P0 通过后，把公钥填入本机未跟踪的 `build/config.toml`，供后续 T-02 构建期注入：

```bash
cp build/config.toml.example build/config.toml
```

只编辑 `build/config.toml`；不要把真实值写回 `config.toml.example`。

## 7. 数据备份与恢复

`./data` 同时保存服务端身份密钥和运行数据。备份时短暂停服，避免得到不一致副本：

```bash
docker compose stop
tar -C . -czf /你的加密备份目录/homedesk-data-YYYYMMDD.tar.gz data
docker compose start
```

备份完成后检查文件存在且大小非零，并把备份目录纳入 NAS 的第二份备份。飞牛的“系统配置备份”不包含 Docker 数据卷，因此不能替代上述 `data/` 备份。

恢复或迁移前先停止服务，保留当前 `data/` 为带时间戳的旁路副本，再解压备份。恢复后必须确认 `id_ed25519.pub` 与客户端当前 Key 一致；若密钥变了，所有客户端都要重新配置。

## 8. 断电重启自检

Compose 已设置 `restart: unless-stopped`。完成一次 NAS 重启测试：

1. 正常重启飞牛 NAS并开始计时；
2. Docker 可用后执行 `docker compose ps`；
3. 确认两个容器自动进入 `running`，没有手工执行 `up`；
4. 两台客户端在 60 秒内恢复就绪；
5. 发起一次远控与一次小文件传输；
6. 将结果记入 `tests/smoke.md` 的 M7 与服务端自恢复项。

如果容器没有自启，先检查 Docker 服务是否随 fnOS 启动，再检查容器重启策略：

```bash
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' homedesk-hbbs homedesk-hbbr
```

预期两个结果均为 `unless-stopped`。

## 9. mini 主机作为备机的迁移

1. 在主 NAS 上执行第 7 节的一致性备份，然后保持主 NAS 的 hbbs/hbbr 停止，避免两个服务端同时持有同一身份运行。
2. 将 `compose.yml`、`.env.example`、本地 `.env` 与完整 `data/` 安全复制到 mini 主机的持久目录。
3. 把备机 `.env` 中 `HOMEDESK_BIND_IP`、`HOMEDESK_SERVER_HOST` 改为 mini 主机的固定内网 IP。
4. 在备机执行 `docker compose config`、`docker compose up -d`，确认公钥与主 NAS 完全一致。
5. 在 P0 官方客户端中修改 ID Server；HomeDesk 定制客户端完成 T-02 后，通过“高级模式”修改服务器地址。
6. 运行 M1、M5、M6 快速回归。主 NAS 恢复前先停止备机，避免双活。

## 10. 常见问题

| 现象 | 检查顺序 |
| --- | --- |
| Compose 报变量未设置 | 确认命令在 `compose.yml` 所在目录运行，且 `.env` 已从 example 复制并替换占位值 |
| 容器反复重启 | 看 `docker compose logs`；检查 `data/` 写权限、CPU 架构和镜像拉取完整性 |
| 客户端未就绪 | 核对 NAS IP、公钥、TCP 21116 与 UDP 21116、防火墙来源网段 |
| 能注册但不能中继 | 检查 hbbs 的 `-r` 地址和 TCP 21117；确认 NAS IP 没写成旧地址 |
| 同网段仍显示中继 | 检查 AP 隔离、访客 Wi-Fi、VLAN ACL；再用 IP 直连做旁路定位 |
| 重启后 Key 变化 | `data/` 没有正确持久化或部署到了新目录；立即恢复原数据卷备份 |

## 11. 官方资料

- [rustdesk-server 1.1.16 Release](https://github.com/rustdesk/rustdesk-server/releases/tag/1.1.16)
- [rustdesk-server 官方 GHCR 包](https://github.com/rustdesk/rustdesk-server/pkgs/container/rustdesk-server)
- [RustDesk OSS Docker 部署](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [RustDesk OSS 安装与端口说明](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/)
- [飞牛 fnOS 端口设置](https://help.fnnas.com/articles/v1/settings/port-customization)
- [飞牛 fnOS 系统配置备份与恢复](https://help.fnnas.com/articles/v1/settings/sysrestore)

仓库侧验证记录见 [`T00_VALIDATION.md`](T00_VALIDATION.md)。

## 12. P0 完成后需要手工保留的信息

- NAS 固定内网 IP 与家庭网段；
- `id_ed25519.pub` 公钥；
- 私钥数据卷的加密备份位置（不要记录私钥内容）；
- `tests/smoke.md` 的 M1–M7 实测数据；
- fnOS 版本、CPU 架构及防火墙菜单实际路径。
