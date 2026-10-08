# 家庭设备管理台

管理台使用 Rust axum、内置 SQLite、askama 和原生 JS，独立于 hbbs/hbbr；管理台退出不影响远控。页面包含设备在线状态、房间/成员备注、WOL、审计筛选与 CSV 导出、网段/保留天数/口令设置。

## 构建与运行

```bash
cargo test --locked --manifest-path server/console/Cargo.toml
cargo build --locked --release --manifest-path server/console/Cargo.toml
```

运行时变量：

| 变量 | 含义 |
| --- | --- |
| BIND_IP | NAS 内网 IPv4；默认仅 127.0.0.1，禁止全接口和公网监听 |
| PORT | 默认 8080 |
| TOKEN | 必填，32 至 256 位访问口令；通过本机受控环境设置，不写仓库 |
| NET_CIDR | 必填，RFC1918 IPv4 CIDR，前缀 8 至 30 |
| DB_PATH | 数据库路径；默认当前目录 homedesk.sqlite3 |
| RETENTION_DAYS | 初始保留天数，默认 90，范围 1 至 3650 |

首次启动将口令摘要、网段和保留天数存入数据库。页面修改后的设置会持久化，并优先于再次启动的初始环境变量；口令轮换会清空所有网页会话。不要把初始 TOKEN 当作数据库口令恢复入口。

## NAS 容器

先按 [DEPLOY.md](DEPLOY.md) 填写未跟踪的 `server/.env`，另填 `HOMEDESK_CONSOLE_TOKEN`、`HOMEDESK_NET_CIDR`。执行：

```bash
cd server
docker compose -f compose.yml -f compose.console.yml config --quiet
docker compose -f compose.yml -f compose.console.yml up -d --build
```

Console 使用 Linux host 网络，让 UDP 广播可到达家庭网卡，并由 BIND_IP 和应用网段检查限制访问。NAS 防火墙只向家庭网段开放 8080。WSL NAT 环境不能替代 NAS 的 WOL 广播验收。

本机另已生成 Linux x64 musl 静态产物和 `homedesk/console:0.1.0` 镜像，并通过非 root、只读容器启动及重启保留数据测试。离线镜像文件位于 `server/console/target/homedesk-console-0.1.0-linux-amd64.tar`。在 x64 NAS 导入后可使用已有镜像启动：

```bash
docker load -i homedesk-console-0.1.0-linux-amd64.tar
docker compose -f compose.yml -f compose.console.yml up -d --no-build
```

在其他 Linux x64/ARM64 构建机可执行 `bash build/ci/build-console.sh`，生成对应本机架构的 musl 产物及 scratch 镜像，不依赖下载 Rust Docker 基础镜像。需要预装 Rust 和 musl-tools。

## 客户端接入

在未跟踪的 `build/config.toml` 中设置 `[console] enabled=true`、内网 HTTP URL（含端口）、同一 Token，再构建 Windows/Linux/ARM64 客户端。官方原版安装包不会主动向本管理台上报。

设备每 60 秒上报；90 秒内收到心跳视为在线。管理台不可用时按 30、60、300 秒退避，不弹窗、不阻塞远控。会话在成功认证后记录 start，正常连接释放时记录 end 和持续时间。

被控端从实际中继建立入口传递连接元数据，start/end 同时记录 `conn_type=direct/relay`，不根据 IP 猜测。旧客户端未提供类型时仍显示“未上报”；双机直连/强制中继实测仍待完成。

上报是尽力发送：队列容量 256，超过容量会丢弃新事件并写 debug 日志；进程崩溃/掉电不会补报 end，重启也不会恢复内存队列。不能把它当作无损审计归档。

启用 Console 后，原生客户端首页出现“我的设备”，每 10 秒刷新，可按设备 ID 发起连接或发送 WOL；管理台故障时保留下方手动连接。

## API

全部 `/api/v1/` 接口要求 Bearer Token 或网页登录 Cookie，且请求来源在家庭网段或回环地址内。Cookie 写请求额外要求 `X-HomeDesk-Request: 1`；未开放跨域访问。心跳与会话正文上限 16 KiB。

| 方法/路径 | 请求或结果 |
| --- | --- |
| POST /api/v1/heartbeat | id、hostname、platform、arch、version、ip、mac；设备 upsert |
| POST /api/v1/session | event_id（重试保持一致）、device_id、peer_id、peer_ip、action（start/end）、duration_s、conn_type |
| GET /api/v1/devices | 设备列表、在线状态、独立 wol_mac 配置 |
| POST /api/v1/devices/{id} | name、room、owner、wol_mac；MAC 留空关闭 WOL |
| POST /api/v1/wol | device_id；广播到当前网段 UDP 9，30 秒内同设备限一次 |
| GET /api/v1/sessions | device_id、from/to（Unix 秒）、before（序号）、limit |
| GET /api/v1/sessions.csv | 同上；最多 10000 条，超出按日期分段导出 |
| GET/POST /api/v1/settings | net_cidr、retention_days；POST 可附 new_token，GET 不回传口令或摘要 |

管理台使用静态访问口令，客户端和管理员目前同一信任域；设备标识未做每台设备独立认证。仅适用于设计中的可信家庭内网。
