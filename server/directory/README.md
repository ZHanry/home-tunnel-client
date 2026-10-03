# HomeDesk 账号设备目录

固定 Go 1.26.0、仅标准库的独立单二进制。通过已有 home-tunnel 会话验证账号与设备，只保存远控地址和服务器公钥指纹。设备 ID 为设备自报的连接地址，实际远控仍由 RustDesk 验证密码、确认与会话密钥。

## 接口

| 方法 | 路径 | 身份与用途 |
| --- | --- | --- |
| GET | `/api/v1/homedesk/devices` | 未绑定设备的账号会话，返回当前账号所属设备的远控绑定。 |
| PUT | `/api/v1/homedesk/devices/current` | 设备绑定会话，只能写入自己的 UUID；相同配置重复上报仅更新活动时间。 |
| GET | `/health` | 容器内部健康检查；公网反代只开放上述认证目录路径。 |

PUT 字段为 `device_id`、`remote_id`、`server`、`key_sha256`、`platform`。服务器从 `/auth/me` 推导账号所有者，拒绝管理会话写绑定、外来 UUID、地址伪装、未知字段和重复远控 ID。GET 会实时校验完整分页设备目录，过滤已撤销设备。状态表示账号活动，不保证远控或服务隧道已连通。

## 构建与部署

在本目录使用锁定工具链运行 `go test ./...`，以 `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w'` 构建 `homedesk-directory`。Dockerfile 以非 root 用户运行，持久目录须由 UID 10001 可写；实际镜像和二进制摘要保存在部署配置中。

环境变量 `HOMEDESK_CONTROL_CENTER` 指定受控的内部控制服务，例如 `http://control-center:8080`；`HOMEDESK_DIRECTORY_FILE` 默认为 `/data/directory.json`。数据原子写入、权限 0600，损坏时拒绝启动。内部授权请求无代理、不跟随重定向、有大小和时间限制；令牌仅在请求期间转发，不进入文件或日志。

容器仅接入原控制网络和 Caddy 私有网络，禁止发布宿主端口。现有管理域增加专用 `reverse_proxy /api/v1/homedesk/*`，其余请求继续走原控制服务；修改前备份、验证后原位更新及 reload，失败恢复旧配置。
