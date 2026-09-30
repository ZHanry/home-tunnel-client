# 客户端正式发行验收收据

格式由 [client_release_candidate.py](../scripts/client_release_candidate.py) 校验。校验器只验证结构、摘要绑定和记录的门槛；维护者仍须审阅原始证据。此仓库不附带预填通过的生产收据。

本文描述验收矩阵及通过证据的要求，不表示 10.0.0 的每项运行时验收已经完成。原始记录中的 Web→Windows 远控结果来自相同功能代码的开发构建，未在最终发行字节上重跑；最终 Windows 文件的安全复扫、安装器生命周期及安装文件哈希检查则有独立通过记录。CI 构建也不能代替完整运行时矩阵。[当前发行的实际验证范围](RELEASE_NOTES.md)与原始记录中的逐项状态应分别核对。

入口仓库 `validation/client/<完整客户端 SHA>/` 包含：

- `client-acceptance.json`：`schema_version: 1`、`acceptance_complete: true`、完整 `coverage` 和 `files`（每个附件的 `bytes`、`sha256`）。
- 每个门槛一个 `client-acceptance-<gate>.json`。
- 实测生成的 `windows-remote-native-acceptance.json` 和 `windows-final-defender-scan.json`。

主收据和各门槛收据均绑定 `repository: ZHanry/home-tunnel-client`、`status: passed`、客户端 `revision`、原始清单的 `candidate_sha256`、清单中原样的 `packages` 和 `server` 对象。任何绑定不同、缺少、失败或跳过的必需项都会拒绝发布。

门槛收据包含 `gate`、非空 `environment` 对象、`reviewed_by`、`cases`（必需 ID 对应 passed），以及 `raw_evidence` 数组（原始文件的 `location` 和 `sha256`）。case ID 以校验器的 `GATES` 为准，新增适用场景也须加入，不能删减已有要求。

| gate | 必需范围 |
| --- | --- |
| remote_sessions | Windows/Web/Android 控制 Windows；四种授权、越权拒绝、撤销、紧急断开 |
| desktop_service | 开机未登录、锁屏、登录、UAC、切换会话、注销重启、受限 IPC、用户权限 |
| media_input | 多屏、缩放、DPI、中文输入、故障释放 |
| files_clipboard_audio | 双向文本、多文件、空文件/大文件、取消清理、完整性、系统音频实播 |
| udp_network | LAN、NAT、双层 NAT、UDP 封锁、IPv6、延迟丢包、抓包、重连 |
| tunnel_management | 所有协议/模板、权限、生命周期、重连、MFA、账号隔离、配额、多服务器、批量、更新、诊断、监控 |
| gemini_screenshots | 所有适用界面/状态、角色、语言、主题、尺寸、键盘/DPI，实际图片读取与复审 |
| stability | 30 次连接、2 小时活动、24 小时在线、输入释放、恢复 |
| upgrade_recovery | 真实 9→10 升级、服务端迁移、备份、恢复、回退 |
| performance | 同一工况比较首帧、延迟、帧率、资源、吞吐 |
| other_desktop_builds | Linux/macOS amd64/arm64 构建和既有能力回归 |
| windows_security | 最终同字节复扫、安装/卸载、实际安装组件摘要 |

`gemini_screenshots.metrics` 要求 `applicable = reviewed = approved > 0`、`blocking = major = 0`、`actual_images_read: true`。数字须能从审核台账重算，不能用页面数量代替全部适用状态。

`stability.metrics` 要求 `consecutive_connections >= 30`、`connection_failures = 0`、`active_seconds >= 7200`、`online_seconds >= 86400`、`input_release_ms <= 2000`、`recovery_or_retry_ms <= 30000`；全部是实测的非负整数。`udp_network.metrics.server_relay_payload_bytes` 必须为整数 0，不能凭配置推断。

`performance.metrics` 包含真实 9.0.0 的 `baseline.version/revision/package_sha256`、`fixed_workload` 和按五个 case ID 记录的 `measurements`；保留两版本原始数据及环境差异。未实测的平台不能写成全功能通过。

所有日志、镜像/包摘要、环境、源码 SHA、抓包、截图、Gemini 结果及复审必须可定位。仅提交审阅过的必要摘要，先去除凭据、令牌、私钥和个人数据；不得修改原始报告或截图摘要来迁就新源码。
