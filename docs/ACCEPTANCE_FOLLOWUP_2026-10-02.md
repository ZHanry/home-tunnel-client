# 门户验收前置缺口与隔离修复

日期：2026-10-02。接续 [OPS_ACCEPTANCE_2026-10-02.md](OPS_ACCEPTANCE_2026-10-02.md)。原报告的 25 项业务仍未执行，本页不改写为通过。

## 已确认问题与修复

报告确认指定腾讯云未找到可核定的 home-tunnel 实例/HTTPS origin，本机干净测试环境未就绪。源码续查还发现原便携外壳共用 `LocalAppData/rustdesk`，时间戳变化时可能清整个共享缓存；旧辅助程序名及全机 `taskkill /IM` 也不区分品牌。这是实际外围隔离问题，不能只靠另一个目录、重定向 AppData 或同品牌的另一个用户解决。

已将外壳缓存改为已校验构建 namespace 的 `portable/<timestamp>` 版本目录，并核验本包标记、绝对边界和无链接/reparse；缺元数据或删除失败停止，不清旧共享目录。Windows 跨进程缓存使用排他文件句柄，崩溃遗留锁可恢复。写入后校验包内文件，失败返回非零。

辅助 broker 按构建 executable_name 派生，外壳不再终止进程；客户端只枚举名称/PID，持有句柄后核验真实映像属于本程序目录，再终止自身 broker。拒绝链接、外目录和 PID 复用认领，不读取进程命令行或环境变量。不修改传输/编解码/密码核心。

## 新交付物

| 交付物 | 用途 | SHA256 |
| --- | --- | --- |
| `client/target/portal-artifacts/HomeDesk-1.4.9-acceptance-ready-win-x64.exe` | 修正版同品牌便携包；仍须干净 Windows 环境跑完整原品牌验收。 | `e23be96e8ac8605a7516732b7196bf5c0245c08590ad7fbcf87fc9a55025a570` |
| `client/target/portal-artifacts/HomeDesk-1.4.9-acceptance-ready-win-x64.zip` | 修正版同品牌完整未压缩 runner；不经过便携外壳。 | `88862edc27dc9284beae4fbf72671e97112dd2b170454a2dc609f63eb164151a` |
| `client/target/portal-artifacts/HomeDeskAcceptance-1.4.9-acceptance-namespace-win-x64.zip` | 独立品牌的未压缩工程验收变体，配置/凭据/IPC/辅助进程 namespace 均不同。不能代替原品牌或独立 SID 安全验收。 | `f039a1f90ef485d863062ca6da87c65d2484d577b2b71e2ea3c750a4e19b0369` |

独立变体的 PE `ProductName=HomeDeskAcceptance`，原始文件名 `homedesk-acceptance.exe`；只改变构建品牌配置，仍为合成纯内网默认，尚未启动。依赖锁未变化，原报告指定的 `fb88799a...` 包保持原样供历史核对，不建议继续拿它在现用用户下试跑。

## 实际本地验证

- Windows 缓存模块 9 项通过，覆盖真实临时 Junction、文件占用、崩溃锁恢复、打包器真实路径形式、越界/无 owner 拒删除及品牌/版本分隔。
- 辅助进程路径纯函数检查通过；外目录不认领，链接/reparse 拒绝。持句柄再校验的 Windows 调用路径已独立审阅。
- 正式品牌修正版与独立品牌未压缩变体的 Rust/Flutter Windows Release 构建均通过，没有启动客户端。
- 使用生产 `BinaryReader` 与缓存模块，在注入工作区临时目录验证实际包内 93 个文件解压、MD5 与启动文件路径，随后清理测试目录；没有启动 HomeDesk、IPC、服务或读取真实 AppData。
- 环境准备工具 6 项范围检查通过，测试内容为目录/归档越界、固定 URL、资源双标签、只读 Compose 约束与 Windows PowerShell 5 的 UTF-8 BOM 兼容；不等于 Docker 或业务运行通过。
- 最终 config-only 项目 `hd-portal-acceptance-20261002-final-v2` 的私有目录/秘密文件 DACL 与 WSL Docker 29.1.3 / Compose 2.40.3 静态 JSON、`config --quiet` 检查通过；官方发行物仍缺 5 件，`prepared=false`、`runtime_launch_ready=false`。项目容器为 0，清理仅 dry-run、资源 0、`executed=false`。最初 TCP 18080 占用未被改动，最终 fixture 使用 18090/18454/18091/18092，只读观察占用为空。

完整构建日志、清单与校验文件位于 `client/target/portal-artifacts/`。本轮辅助进程与外壳上游接线都标记 `HOMEDESK`，主要边界放独立模块，未重格式化上游。

## 环境准备与后续

固定官方 10.1.0 的服务端/Agent、独立 Compose、私有 CA/秘密、预检、限定清理及 API 探针已在 [ACCEPTANCE_ENVIRONMENT.md](ACCEPTANCE_ENVIRONMENT.md) 说明。默认仅回环 `18443/17000/11000–11009`，不改既有 Caddy、DNS、防火墙或系统信任。默认 18443 只支持 API/工程探针，服务返回的 443 URL 不能被改写以冒充实际网页转发。

本地材料分为配置准备与完整发行物准备；官方资产未齐时 `prepared=false`、`official_assets_complete=false`，启动门禁保持阻塞。静态验证与真正运行分开，凭据及私钥仅在被忽略的私有 runtime，不能进入证据或聊天。

下一步需要在已确认测试宿主机部署独立测试栈、建立真实 HTTPS origin/专用账号/MFA/Agent，并准备干净 Windows 环境，才执行 25 项业务。生产现有服务/域名/防火墙变更及 Windows 身份/虚拟化权限不能从原只读前置检查或开发授权推导；仍按用户对运维给出的明确边界执行。

本机 Windows Sandbox 可执行文件不存在，没有发现已可调用的常见 VM 命令行工具；这个只读观察不能替代管理员对可用测试机的确认。官方资产下载因标准 TLS/CDN 通道超时未齐，锁文件和生成配置不是可启动证明：缺 Agent 归档、Server/Client manifest、compose.release 及 FRPS dependency。尚未建立腾讯云新实例，没有启动测试客户端或读现用配置。
