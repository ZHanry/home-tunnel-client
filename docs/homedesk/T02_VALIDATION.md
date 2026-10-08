# T-02 验证记录

更新时间：2026-08-13

本文件记录构建期配置注入、纯内网服务器边界、默认白名单与桌面高级模式的仓库侧验证。真实双机抓包、白名单外连接和重启持久化仍以 Windows/Linux 安装包实测为准。

## 实现结果

- `build/config.toml` 是服务器地址、公钥和家庭网段的唯一真实配置来源；仓库仅提交占位示例和不对应真实部署的测试夹具。
- 构建器要求 `server.host` 为 RFC1918 IPv4、`server.key` 为解码后 32 字节的 Base64 公钥、`net.whitelist_cidr` 完全位于 RFC1918 网段，且 `pure_lan_default = true`；占位示例不能产出客户端。
- 首次启动在任何联网逻辑前安装私有 hbbs、固定公钥与白名单默认值，无配置向导或确认弹窗。
- 设置页普通模式隐藏服务器和白名单编辑；Windows/Linux“关于”页两秒内连续点击版本号五次解锁高级模式，状态写入本地配置，重启后可恢复。
- 高级模式只开放 ID 服务器与白名单；服务器只接受非空 RFC1918 IPv4（可带端口），白名单只接受完全位于 RFC1918 范围的 IPv4/CIDR，不能清空为允许全部；逗号、分号、空格和换行会统一规范为逗号存储。
- 白名单拒绝提示改为“当前 IP 不在家庭网络白名单中，连接已拒绝”，与密码错误可区分。

## 公网回退关闭清单

以下上游路径均保留原协议实现，只在外围入口添加 `// HOMEDESK:` 边界：

| 路径 | HomeDesk 行为 |
| --- | --- |
| `client/src/common.rs`：rendezvous 获取、NAT 测试、TCP API 代理 | IPC/许可证/旧配置结果只保留 RFC1918；无可用值时回退构建期私有服务器 |
| `client/src/client.rs`：`@public`、多服务器重试、hbbs relay 响应 | 拒绝公网 ID 服务器；公共列表不可进入重试；relay 建连前再次校验 RFC1918 |
| `client/src/rendezvous_mediator.rs`：注册循环、服务端服务器列表、relay | 注册只使用过滤后的私有列表；公共推送不落盘；relay 只允许 RFC1918 |
| `client/src/ipc.rs`：服务与 UI 的 rendezvous/配置同步 | 只发布私有服务器；批量配置剔除公网服务器和固定安全项 |
| `client/src/ui_interface.rs`、`client/src/hbbs_http/sync.rs` | UI、导入、账号同步均不能覆盖固定公钥/API/relay/更新策略或写入公网范围 |
| `client/src/common.rs`：更新检查与默认 API | 版本检查在创建请求前返回；默认 API 只从私有 ID 服务器派生，异常时返回空值 |
| `client/src/platform/windows.rs`：文件名许可覆盖 | HomeDesk 不接受文件名覆盖构建期服务器；公钥始终使用构建期值 |

上游公共常量 `RENDEZVOUS_SERVERS`、`RS_PUB_KEY` 未修改，避免改动 `hbb_common` 子模块；HomeDesk 的所有可达入口在使用这些常量前均被拒绝或替换。

## 已验证

| 项目 | 命令/证据 | 结果 |
| --- | --- | --- |
| Python 配置/打包单测 | WSL2 Ubuntu：`python3 -m unittest discover -s tests -v` | 10/10 通过（含 dpkg 安装包结构测试） |
| Python 语法 | WSL2：`python3 -m py_compile build/brand_config.py ...` | 通过 |
| 配置输出脱敏 | `HOMEDESK_CONFIG_PATH=tests/fixtures/config.t02.toml python3 build/brand_config.py --print-json` | 仅输出 `server_key_configured=true`，不输出公钥正文 |
| Rust 构建配置单测 | `rustc --test client/homedesk_build.rs` | 6/6 通过；含非法 Base64/填充拒绝 |
| RFC1918 边界单测 | `rustc --test client/src/homedesk_net.rs` | 2/2 通过；覆盖空白拒绝和多分隔符规范化 |
| 占位配置门禁 | Python 单测调用 `load_config(build/config.toml.example)` | 按预期拒绝 |
| 差异卫生 | `git diff --check` | 通过 |
| 公网源路径扫描 | `rg` 检查公共 rendezvous、公钥、API、更新、relay 使用点 | 已逐项接入或记录为 T-07 用户主动功能 |

## 尚未完成的门禁

- `cargo check --manifest-path client/Cargo.toml --lib --no-default-features --locked` 再次在线运行约两分钟，仍停在 Git/crates 依赖获取且无编译输出；离线模式明确缺少 `aes v0.8.4`，所以没有伪报完整 Rust 客户端编译通过。
- 当前 Windows/WSL2 没有 Flutter/Dart SDK，未执行 `dart format --output=none --set-exit-if-changed`、Flutter analyzer 或 Windows/Linux 安装包构建。
- 停止私有 hbbs 后的 10 分钟 DNS/流量抓包、白名单外真实设备连接拒绝、五连击后重启持久化均需要生成安装包并在两台设备上测试；对应项目已添加到 `tests/smoke.md`，当前保持未勾选。
- T-02 关闭的是自动发生的公共服务器、更新和默认 API 回退。帮助链接、Telegram 2FA、插件下载等用户主动公网功能属于 T-07“全部公网出站总开关”，本卡不宣称已完成。

## 回滚

整体回滚本任务提交即可；没有迁移数据库或修改 RustDesk 传输、编解码、加密协议。
