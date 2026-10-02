# T-17 公网兼容性核查与验收记录

日期：2026-09-22。客户端基线 RustDesk 1.4.9，服务端 OSS 1.1.16；实施前仓库提交 `053bba573`。本文件区分源码证据、本地开发验证与真实跨网验收，不把三者相互替代。

## 当前环境与结论

- Windows 有 Rust 1.96.0、Python 3.11.15，以及项目内 Flutter 3.24.5、桥接工具和原生依赖缓存。
- WSL Ubuntu x86_64 可访问 Docker 29.1.3；可执行隔离的本地容器验证。
- 已存在官方 Windows 1.4.9 客户端和旧 HomeDesk 验证包；旧包不能证明本轮修改生效。
- 开始本轮时 `build/config.toml` 与 `server/.env` 不存在；没有可使用的真实公网服务配置，也未取得第二个独立网络中的设备。
- 用户已要求完成方案开发，因此继续实施代码和本地验证；T-17 的真实跨网门禁仍保持未通过，不据此发布公网可用性结论。

## 已确认的源码行为

| 核查点 | 证据与影响 |
| --- | --- |
| TCP 直连/中继 | `client/src/client.rs` 中 `Client::connect` 选择可用直连，失败时进入自建 relay；公网功能可沿用现有协议 |
| 第一段 peer 公钥验证失败 | `Client::secure_connection` 在缺少或无法验证服务器签发的 peer 公钥时，可能发送空消息后返回 `Ok(None)`；函数成功返回不代表完成认证 |
| 第二段 peer 签名异常 | 同函数在 peer SignedId 不匹配等路径可能返回 `Ok(Some(pk))`，但未设置会话密钥；必须同时判断已验证 peer 公钥与流的加密状态 |
| 入站握手 | `server::create_tcp_connection` 的 `secure=true` 只表示尝试握手；空 PublicKey 等路径仍可能没有会话密钥。公网模式须在进入 `Connection::start`、发送 Hash 与处理登录前检查流已加密 |
| 非安全 UI 回退 | `client/io_loop.rs`、`port_forward.rs` 存在继续非安全连接流程；公网模式应在进入这些流程前拒绝未完成安全握手的连接 |
| IP 直连 | `Client::_start_inner` 的 IP/域名路径直接返回 TCP 流；`rendezvous_mediator.rs` 的 IP 监听以 `secure=false` 调用接入。公网模式不能把它当作加密旁路，应明确拒绝并提示 ID 连接 |
| 信令与 endpoint | 候选 endpoint 来自本次信令请求响应，并非所有 endpoint 字段均由 hbbs 公钥签名；地址分类与请求关联仅是外围限制，不能代替对端握手 |
| UDP 的两种用途 | hbbs UDP 21116 的注册保活/协调，与可选 UDP/KCP 会话数据路径分开；不能关闭前者来表示后者未启用 |
| 模式切换的进程边界 | 桌面 UI 与后台服务不能依靠各自本地 Config/CM 表同步。完整配置组须由后台确认；模式切换需覆盖正在握手的后台连接，不能只统计已授权连接 |

实施只在既有调用边界增加网络策略和拒绝条件，不更改签名格式、握手算法、传输协议或连接竞争顺序。若无法通过外围限制满足错误 Key/签名/加密负向用例，公网发布仍须停止。

## 本地验证

已执行的开发检查如下；完整构建结果在实现稳定后补充。源码检查不替代握手测试或真实远控。

| 检查 | 实际结果 |
| --- | --- |
| Windows `python -m unittest discover -s tests -v` | 12 项通过；Linux `dpkg-deb` 用例因平台跳过 1 项 |
| WSL `python3 -m unittest discover -s /mnt/d/coding/codex/my-desk/tests -v` | 13/13 通过，含真实 deb staging 与品牌路径验证 |
| WSL `bash tests/server-public/test-verify-public.sh` | 主代理复验通过：地址/DNS/接口/注入拒绝、运维离线检查、已有归档保护及备份失败恢复 |
| WSL `bash tests/server-public/run-loopback-smoke.sh` | 主代理复验通过：锁定镜像隔离启动，回环 TCP 21115/21116/21117 可接入，重启后公钥摘要不变；测试容器/网络/卷无残留 |
| Windows `cargo test --locked --offline --manifest-path tests/reporter/Cargo.toml` | 7/7 通过：原心跳/事件次序、Bearer、有界队列，以及新增在途 HTTP、失败退避、阻塞采样取消回归 |
| WSL 同一 Reporter 测试，独立 `client/target/homedesk-reporter-linux` 输出目录 | 主代理复验 7/7 通过；直接编译生产发送器，只访问回环 HTTP，不读写用户 AppData 或现用服务 |
| Dart `--enable-asserts run tests/dart/console_api_test.dart` | 主代理复验通过：地址/重定向边界、设备 ID、Bearer、WOL、401，以及撤销、openUrl 期间撤销和新 Token 恢复 |
| `rustc --edition=2021 --test client/src/homedesk_async.rs` | 主代理独立复验 3/3：忙队列立即拒绝、过期/放弃请求不执行、执行 claim 与 abandon 互斥 |
| `rustc --edition=2021 --test client/src/homedesk_net.rs` | 主代理独立复验 7/7：模式/特殊地址/CIDR/中继、双安全条件、固定信任 Key 与 Console 信任边界 |
| 固定 gitleaks 8.30.1，使用仓库 `scan-secrets.py` | 最终代码扫描：84 条精确上游示例基线、新增或变化的疑似密钥 0；工具压缩包 SHA256 与 CI 固定值一致 |

## Windows 验证产物

- 构建命令：`python build/ci/build-client.py --target win-x64 --config tests/fixtures/config.t02.toml`。
- 最终步骤：FRB 生成、Rust Release、Flutter Windows Release 与 portable 封装均通过。
- 文件：`client/HomeDesk-1.4.9-win-x64.exe`，23,644,672 bytes；2026-09-22 21:13:14 生成。
- SHA256：`8d21b2a47c564bf15c4fff8dd4edbd3c067fd27a68820bd6f81c0775bb82e5ba`；主代理已独立核对。
- 使用合成的 `lan_only` 测试配置，未安装或覆盖现用程序；使用前须按 [CLIENT_NETWORK.md](CLIENT_NETWORK.md) 设置真实服务器、中继与公钥。该产物证明构建完成，不证明真实公网连接已验收。
- 本轮没有升级依赖锁或镜像版本；远程 CI、当前安装服务 IPC、Linux/ARM64 完整客户端和真实跨网验证仍未覆盖。

## 真实跨网门禁（未执行）

- [ ] 固定版本官方客户端在两个独立外网完成加密 TCP P2P。
- [ ] 受控阻断直连后，自动经自建 hbbr 完成加密中继。
- [ ] HomeDesk 新构建包在相同环境复验，含错误 Key/密码、来源限制和非安全回退拒绝。
- [ ] 不同宽带及移动网络各连续连接 3 次，成功场景保持至少 10 分钟并记录性能和连接类型。
- [ ] 公网服务故障、DNS 故障、断公网及 Console 不可达的行为符合修订后的安全边界。
- [ ] 按 [smoke.md](../tests/smoke.md) 完成所声明平台与部署拓扑的必测项。

UDP/KCP 会话、IPv6 与 VPN 均按可选能力分别标记；未验证保持关闭/未覆盖，不以 hbbs UDP 流量证明桌面会话使用 UDP。真实 IP、公钥、Token 和敏感抓包不提交仓库。
