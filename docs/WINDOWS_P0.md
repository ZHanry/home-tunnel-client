# Windows 双机 P0 联调

更新时间：2026-09-08。用户已确认两台 Windows 位于同一个家庭局域网，当前优先调通 Windows → Windows；飞腾麒麟适配后置。本记录对应 DESIGN.md 4.3、8、9、10 节，不代表实机验收通过。

## 当前准备结果

- 本机 WSL Ubuntu 的 Docker 可访问，当前未运行 HomeDesk 容器。
- 仓库没有真实 `server/.env`、`build/config.toml` 或服务端数据卷。
- 已下载官方 RustDesk 1.4.9 Windows x64 客户端到被 Git 忽略的 `client/target/homedesk-p0/rustdesk-1.4.9-x86_64.exe`。
- SHA256：`eaedeb0088e687bf46f7c46a9c6ea5493ce51f3134dfd6acbedb47b5b9136274`，与 GitHub Release 资产摘要一致；Windows Authenticode 状态为 `Valid`。
- 尚未启动或安装该客户端，尚未配置服务器、修改防火墙或进行双机连接。
- 待提供 NAS 内网地址及可用管理方式、另一台 Windows 内网地址。真实地址和密钥不写入本文。

## P2P 与 UDP 的边界

P2P 表示两台客户端直接传输会话数据。hbbs 负责注册和撮合，hbbr 在直连失败时兜底。P2P、TCP/UDP、会话是否加密必须分别检查。

本仓库代码依据：

- `client/src/client.rs` 的连接分支通过 `select_ok` 选择首个成功的 TCP/UDP/IPv6 连接；直连失败或强制中继时请求 relay。
- 同文件 `udp_nat_connect` 使用 `KcpStream::connect`，客户端确有 UDP/KCP 实现；建立连接后调用 `secure_connection`。
- `client/src/common.rs` 的 `get_local_option` 在自建服务器且没有显式设置时，对 UDP/IPv6 打洞返回 `N`。不能声称本项目默认已经启用 UDP。
- [官方 UDP 配置说明](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/#enable-udp-punch)列出客户端和 Pro 服务端版本要求，不能据此认定仓库锁定的 OSS 1.1.16 已支持该完整路径。

本次采用上游直连优先、中继兜底行为，不修改传输协议或连接竞争顺序。先验证加密直连，再验证现有服务器与两端客户端的 UDP 兼容性；不为追求 UDP 字样更换或购买服务端。

## 执行顺序

1. 按 [DEPLOY.md](DEPLOY.md) 在 NAS 配置并启动锁定的 hbbs/hbbr，验证家庭设备能访问；不把 WSL NAT 地址直接当成家庭网络服务地址。
2. 两台 Windows 使用同版本官方客户端，配置同一个自建 ID 服务器与公钥；保持“始终通过中继”关闭，配置设备密码和家庭网段访问范围。密码、私钥不贴入聊天或仓库。
3. 先按设备 ID 建立会话，核实直连和加密状态。IP 直连仅作为排障入口，不能仅凭 IP 连接成功判定加密通过。
4. 验证双向画面与键鼠、剪贴板、文件传输及哈希一致；再验证安装服务后的锁屏、UAC 和重启无人值守。
5. 记录实际传输类型 TCP/UDP/Relay；不能用 hbbs 的 UDP 心跳流量证明桌面数据走 UDP。需要时检查会话日志和两端之间的实际连接。
6. 在可恢复的测试窗口验证断外网和中继停止后的内网新建直连，完整结果填入 [smoke.md](../tests/smoke.md)。

## 验收状态

- [x] 两台电脑处于同一家庭局域网（用户确认）。
- [x] 官方 Windows 客户端下载、摘要与数字签名检查。
- [ ] NAS 服务部署和客户端配置。
- [ ] 双机加密 P2P 直连及传输类型确认。
- [ ] 文件传输、锁屏、重启和断外网验证。
- [ ] `tests/smoke.md` 的 P0 门禁通过。

官方客户端通过只代表底层链路通过；HomeDesk 定制版仍须另外编译、安装并复验。

## 2026-09-08 构建补充

已生成 `client/target/homedesk-p0/HomeDesk-1.4.9-win-x64-validation.exe`，约 22.4 MiB，验证了 Rust（含硬件编解码）、Flutter Windows 和安装包外壳的构建，文件属性为 HomeDesk。

该文件使用 `tests/fixtures/config.t02.toml` 的测试地址和测试公钥，Console 默认关闭；仅作为构建验证产物，不应拿来做家庭远控或覆盖正式安装。拿到真实 `build/config.toml` 后按 `build/ci/build-client.py` 重建，再执行上面的双机清单。当前没有启动/安装该验证包，也没有把双机清单标为通过。
