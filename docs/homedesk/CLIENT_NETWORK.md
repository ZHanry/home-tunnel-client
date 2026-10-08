# HomeDesk 客户端网络模式配置

本文对应本轮双模式开发。使用前核对 [实现状态](IMPLEMENTATION_STATUS.md) 与 [公网验收记录](T17_VALIDATION.md)；测试配置产物不能直接视为正式部署完成。

## 1. 构建配置

复制 `build/config.toml.example` 为未跟踪的 `build/config.toml`，保留品牌字段，填写以下网络字段：

| 字段 | 用途 |
| --- | --- |
| `net.mode` | `lan_only` 默认纯内网；明确选择 `self_hosted` 才允许自建公网连接 |
| `server.host` | 自建 hbbs 主机，建议明确写上 `:21116`；纯内网只接受私网 IPv4，公网模式可用配置的域名或 IPv4 |
| `server.relay_host` | 自建 hbbr 主机与端口，通常为 `:21117`；应与 hbbs 通告的中继配置保持一致，不能填写任意公共中继 |
| `server.key` | 对应自建服务的 Base64 公钥，来自 `id_ed25519.pub`；不能填写服务器私钥 |
| `net.whitelist_cidr` | 家庭私网 CIDR，用于纯内网来源限制及同网段地址识别；不因选择公网模式改成 `0.0.0.0/0` |
| `net.source_cidr` | 公网模式的可选来源 IPv4 CIDR；留空表示无额外来源限制，设备认证与加密验证仍必需 |
| `console.enabled` | 是否编入家庭设备中心与上报配置；外出用途默认保持 `false` |
| `console.trusted_path` | 仅在明确使用可信家庭网络或受控 VPN 访问 Console 时设为 `true`；它不是自动检测 VPN 的功能 |

公网场景的服务器部署见 [DEPLOY_PUBLIC.md](DEPLOY_PUBLIC.md)。真实地址、公钥、Token 只留在本地配置；不要修改 example 为真实值或把配置提交仓库。

旧 `pure_lan_default=true` 可迁移为纯内网；旧 false 不能作为隐式公网授权，新旧字段冲突会被拒绝。新配置直接使用 `net.mode`。

在具备构建工具链的仓库根目录执行：

```powershell
python build/ci/build-client.py --target win-x64 --config build/config.toml --check
python build/ci/build-client.py --target win-x64 --config build/config.toml
```

Linux 需要对应架构原生构建环境，目标分别为 `linux-x64`、`linux-arm64`；本轮 Windows 构建通过不能代替 Linux 或麒麟真机验收。工具链准备见 [build/ci/README.md](../build/ci/README.md)。

## 2. 已安装客户端修改模式

升级时需要让界面与后台服务使用同一份新构建；旧后台不识别新的模式保存请求，不能只替换界面后就把保存超时当作成功。

1. 断开现有主控与被控会话。
2. 在“关于”页按现有方式解锁高级设置，进入网络页的“HomeDesk 网络模式”。
3. 选择“纯内网”或“自建公网”，填写这一模式自己的服务器、中继、公钥和来源规则。两组配置分别保存，不能把公网服务器直接复制成纯内网组。
4. 点击“保存并重启服务”，等待后台确认。忙队列立即拒绝，过期的排队请求不会稍后执行；明确校验拒绝保留旧配置。若请求已发出但确认超时，客户端会只读重新同步后台有效配置；无法同步时暂停新连接和 Console 请求，并提示重新打开客户端核对状态，不能把“未确认”当作“没有生效”。
5. 使用设备 ID 连接，确认实际直连/中继和加密状态；被控端仍需独立密码或本地确认。服务器公钥不能替代设备密码。

保留自建中继兜底，并关闭原上游“始终通过中继”的偏好，才能按默认策略优先直连。当前版本未验收的 UDP/KCP 会话与 IPv6 路径保持关闭；hbbs UDP 心跳仍正常使用，不能依据 UDP 端口流量判断桌面数据走 UDP。

## 3. 设备中心与故障行为

- 公网模式不自动开放 Console。没有可信内网/VPN 路径时，设备中心会显示不可达，仍可使用设备 ID 和最近连接。
- 模式撤销 Console 许可时，上报队列和 HTTP 请求停止；设备墙也会关闭旧客户端，恢复后读取当前配置，避免继续使用旧 Token。
- WOL 由家庭网络中的常开 Console 发出，公网 P2P 本身不能唤醒已关机的设备。
- 锁定上游的手输 IP/域名路径没有同等加密握手，公网模式会拒绝并提示改用设备 ID。经 hbbs 撮合的同网段 P2P 保留。
- 公网 hbbs 故障时，不承诺公网模式能新建连接。需要切换至完整有效的私网 ID 服务器组后再连；原纯内网 IP/发现兼容路径不能当作加密验收已通过。
- 错误服务器 Key、异常对端签名或未加密回退会导致拒绝连接，不能通过“继续非安全连接”绕过。

本轮没有自动修改真实防火墙、路由器或现用安装。正式使用需在实际部署后执行 [smoke.md](../tests/smoke.md) 的跨网、失败中继、认证与故障矩阵。
