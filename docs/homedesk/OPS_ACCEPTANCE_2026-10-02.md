# HomeDesk 与 home-tunnel 完整门户运维验收

日期：2026-10-02，时区 Asia/Singapore。指定目标为腾讯云服务器与本机 Windows。脱敏现场证据采集时间为 2026-10-02 08:32:53 +08:00。

## 本次结论

**完整门户实机验收未放行，业务项目尚未执行。** 已完成交付包核对、腾讯云只读现场检查和 Windows 隔离条件检查。指定腾讯云上未发现可核验的 home-tunnel 服务候选，未取得测试 HTTPS origin、专用账号及 MFA 条件；本机独立 Windows 测试身份或测试机也未确认。没有在现用 Windows 用户下启动测试包，没有用模拟测试补实机结果。

以下“失败”仅指验收环境前置门禁不满足，不代表已经复现 HomeDesk 的功能缺陷。不能据此断言 home-tunnel 已卸载或某个版本不兼容；当前事实是未找到可确认的目标实例，版本和 API 兼容性均未验证。

| 范围 | 通过 | 失败 | 未执行 | 说明 |
| --- | ---: | ---: | ---: | --- |
| 前置检查 | 4 | 2 | 2 | 包与操作通道已核对；服务实例和 Windows 隔离门禁未满足。 |
| 门户实机业务 | 0 | 0 | 25 | 缺少真实目标与隔离测试环境，不能判定功能通过或失败。 |

## 阅读依据与操作范围

已阅读本项目 `AGENTS.md`、[PORTAL_INTEGRATION_PLAN.md](D:/coding/codex/my-desk/docs/PORTAL_INTEGRATION_PLAN.md)、[HOME_TUNNEL_PORTAL.md](D:/coding/codex/my-desk/docs/HOME_TUNNEL_PORTAL.md)、[IMPLEMENTATION_STATUS.md](D:/coding/codex/my-desk/docs/IMPLEMENTATION_STATUS.md) 及 [DESIGN.md 5.4](D:/coding/codex/my-desk/docs/DESIGN.md:284)。参考构建说明用于核对交付物，没有将其中的历史测试结果计入本次实机通过项。

目标契约为 **home-tunnel Server 10.1.0 / api-v1.5.0**，对应文档引用的服务端源码提交为 `866e0cbb9ac89de39491ca353574f517f374554e`。该版本是期望值，不是现场已部署版本。

执行范围为只读 SSH、Windows 用户/虚拟化/进程清单、文件摘要与 PE 头核对，以及 Windows Computer Use 初始化和目标窗口清单。不读取生产账号密码、Token、私钥内容、MFA 恢复码或服务数据库；没有启动 HomeDesk 测试包、创建账号或设备、安装隧道 Agent、创建临时业务服务、修改现用配置、升级生产组件、重启服务或调整防火墙。

仓库开始验收时已有多处修改和未跟踪文件。本次未修改客户端或服务端源码，未重置工作树；只新增本报告和脱敏证据 JSON。

## 前置检查表

| 编号 | 检查 | 结果 | 实际证据与范围 |
| --- | --- | --- | --- |
| P-01 | 指定 Windows 交付包与交付摘要一致。 | 通过 | 文件为 `HomeDesk-1.4.9-portal-complete-win-x64.exe`，23,732,736 bytes；SHA256 与 `SHA256SUMS-complete.txt` 和实现状态记录一致。只证明交付物身份，不证明运行功能。 |
| P-02 | 文件确为 Windows x64 PE。 | 通过 | PE 签名 `50450000`，Machine `0x8664`。没有将 PE 格式核对视为客户端启动成功。 |
| P-03 | 腾讯云目标能经现有 SSH 只读检查。 | 通过 | Ubuntu 24.04.4 LTS；Docker、systemd 与进程查询成功。仅检查指定目标。 |
| P-04 | 本机 Windows 原生 UI 操作通道可用。 | 通过 | 按 computer-use 技能初始化 `@oai/sky`，应用清单调用成功；没有发现 HomeDesk/RustDesk 测试窗口。没有启动应用。 |
| P-05 | 找到真实 home-tunnel 实例并确认实际服务端版本。 | 失败 | 13 个 Docker 容器中没有 home-tunnel/control-center/FRP/RustDesk 候选；相关 systemd unit 和进程名候选为空；所检查的 Caddy 源配置没有门户相关关键词。尚未取得部署位置与 HTTPS origin。见 ENV-01。 |
| P-06 | 实际接口与 10.1.0 / api-v1.5.0 兼容。 | 未执行 | 没有可确认的目标 origin 或运行实例，不能查询实际版本、身份语义及资源接口。没有向其他生产应用猜测性发送登录请求。 |
| P-07 | 独立 Windows 测试用户或测试机可用。 | 失败 | 当前会话不是管理员；专用测试身份未确认。`Get-VM` 被权限策略拒绝，无法确认可用的隔离 Windows VM。现用用户已有 HomeDesk 配置，不能在该身份下试跑。见 ENV-02。 |
| P-08 | 专用门户测试账号、MFA、设备和协议能力已就绪。 | 未执行 | 未提供或确认专用账号、MFA 操作条件、测试设备/Agent 和 TCP/UDP 端口池权限。没有查取生产凭据或替用生产账号。 |

交付包 SHA256：

```text
fb88799a4c1497d6ea7cc06cd1075aa5cb16d02c8ab1f54e796609cdfd3c844f
```

Authenticode 状态为 `NotSigned`。这与“本次测试包身份是否一致”是不同检查；不将无签名单独判为门户功能失败，也不绕过 Windows 安全拦截。真实隔离机运行时的信任和拦截行为尚未执行。

## 门户实机通过 / 失败 / 未执行表

阻塞代码：B1＝真实 home-tunnel HTTPS 实例和实际版本未确认；B2＝独立 Windows 身份/测试机未确认；B3＝专用账号/MFA 未确认；B4＝测试设备、Agent、协议授权及端口池未确认。

| 编号 | 用户重点 | 实机用例与判定要求 | 结果 | 阻塞 |
| --- | --- | --- | --- | --- |
| T-01 | 1 | 在真实 HTTPS origin 登录，验证 TLS、`/auth/me` 账号身份及 `device_id=null`。 | 未执行 | B1、B2、B3 |
| T-02 | 1 | 已启用 MFA 的专用账号正确/错误验证码交互，不自动重试验证码。 | 未执行 | B1、B2、B3 |
| T-03 | 1 | 勾选记住登录，验证本测试 Windows 用户的 DPAPI 密文记录及不写明文凭据。 | 未执行 | B1、B2、B3 |
| T-04 | 1 | 正常关闭并重开测试包，进入家庭服务后自动恢复；新会话身份和刷新轮换正确。 | 未执行 | B1、B2、B3 |
| T-05 | 2 | 退出登录后重开，旧持久记录不能继续恢复，服务器会话关闭语义正确。 | 未执行 | B1、B2、B3 |
| T-06 | 2 | 忘记登录删除测试用户持久记录，当前内存会话按设计继续；重开后不能自动恢复。 | 未执行 | B1、B2、B3 |
| T-07 | 2 | 服务端只撤销专用测试会话，旧访问/刷新凭据不能继续恢复。 | 未执行 | B1、B2、B3 |
| T-08 | 3 | 真实设备目录全分页、状态、账号所属范围与筛选正确。 | 未执行 | B1、B2、B3、B4 |
| T-09 | 3 | 真实服务目录全分页，与设备 UUID 关联；不将隧道在线混同 RustDesk 远控在线。 | 未执行 | B1、B2、B3、B4 |
| T-10 | 3 | 在专用测试设备创建 HTTP/HTTPS/TCP/UDP 临时服务，字段校验及能力限制正确。 | 未执行 | B1、B2、B3、B4 |
| T-11 | 3 | 编辑测试服务名称及本地目标，提交 expected_version，保留未编辑访问策略。 | 未执行 | B1、B2、B3、B4 |
| T-12 | 3 | 暂停临时测试服务，界面和服务端状态一致。 | 未执行 | B1、B2、B3、B4 |
| T-13 | 3 | 恢复临时测试服务，真实转发恢复且不产生重复资源。 | 未执行 | B1、B2、B3、B4 |
| T-14 | 3 | 应用内确认删除临时测试服务，仅删除本次创建的资源。 | 未执行 | B1、B2、B3、B4 |
| T-15 | 3 | 编辑专用测试设备标签，使用 expected_metadata_version，越界输入被拒绝。 | 未执行 | B1、B2、B3、B4 |
| T-16 | 3 | 收藏/取消收藏专用测试设备，刷新及重开后状态一致。 | 未执行 | B1、B2、B3、B4 |
| T-17 | 4 | 从门户打开实际 HTTP 服务，用本次生成的非敏感内容标记确认到达真实测试后端。 | 未执行 | B1、B2、B3、B4 |
| T-18 | 4 | 打开实际 HTTPS 服务并验证系统信任链、目标内容和服务端返回的地址，不关闭 TLS 校验。 | 未执行 | B1、B2、B3、B4 |
| T-19 | 4 | 核对复制的 TCP 地址/服务端分配端口，实际建立连接并校验测试数据。 | 未执行 | B1、B2、B3、B4 |
| T-20 | 4 | 核对 UDP 地址/端口，实际收发测试报文，不把监听或地址显示当作 UDP 成功。 | 未执行 | B1、B2、B3、B4 |
| T-21 | 5 | 对专用资源制造真实版本竞争，409 保留草稿，刷新核对后仅明确重试一次。 | 未执行 | B1、B2、B3、B4 |
| T-22 | 5 | 在独立测试链路断网，保留草稿，不自动重放写入；不改生产防火墙或现用网卡。 | 未执行 | B1、B2、B3、B4 |
| T-23 | 5 | 对专用测试请求丢弃已提交后的响应，核对结果未知提示、服务端实际写入次数和保留草稿。 | 未执行 | B1、B2、B3、B4 |
| T-24 | 6 | 切回 lan_only 后停止公网登录、恢复、刷新、轮询和写操作，并以请求计数/抓包验证。 | 未执行 | B1、B2、B3 |
| T-25 | 6 | 对专用请求延迟响应后撤销许可，旧响应不能恢复目录或会话；快速切回公网仍不能复用旧代次。 | 未执行 | B1、B2、B3、B4 |

没有运行回环 mock、组件注入测试或旧 DPAPI 探针来替代以上实机用例。已有开发测试仅是项目历史证据，本次不计分。

## 脱敏证据

现场结构化证据见 [preflight.redacted.json](D:/coding/codex/my-desk/docs/ops-acceptance-2026-10-02/preflight.redacted.json)。目标只标记为 `TENCENT_TARGET`，不记录真实 IP、域名、Windows 用户名、密钥路径、账号标识或凭据。

主要证据摘录：

```json
{
  "docker_query_ok": true,
  "tunnel_container_candidates": [],
  "unit_query_ok": true,
  "tunnel_unit_candidates": [],
  "process_query_ok": true,
  "tunnel_process_candidates": [],
  "caddy_source_query_ok": true,
  "portal_keyword_present": false,
  "actual_server_version": null,
  "actual_api_version": null,
  "compatibility": "not_verified",
  "windows_elevated": false,
  "dedicated_test_identity_confirmed": false,
  "hyperv_inventory": "permission_denied",
  "test_exe_launched": false
}
```

Docker 现场共有 13 个容器，运行 10 个、停止 3 个；均为现有业务组件。没有因为测试包要求而启动停止的 Sub2API，也没有改动现用 Caddy。

本机现用 HomeDesk Roaming 目录存在，观察到 16 个文件。只检查目录存在性和文件数量，没有读取配置、记住登录记录或凭据内容。Windows Computer Use 运行时可初始化，但这不构成独立用户隔离，也不构成 HomeDesk 启动通过。

另外，本机 `D:/coding/codex/home-tunnel` 主仓 `VERSION` 为 7.0.0，其文档说明服务端和客户端已分仓。该主仓版本不能作为腾讯云 Server 版本，也不能直接用来断定 `api-v1.5.0` 不兼容。

## 环境问题与复现步骤

### ENV-01：指定目标尚无可确认的 home-tunnel 实例

结果：前置门禁失败，客户端兼容性未执行。没有客户端错误截图或响应日志，因为未获得真实目标且未启动测试包。

复现方式是在用户指定腾讯云上经现有授权 SSH 执行以下只读命令，不包含账号密码或私钥内容：

```sh
sudo -n docker ps -a --format '{{.Names}} {{.Image}} {{.State}}'
systemctl list-unit-files --type=service --no-pager --no-legend
ps -eo comm=
```

检查名称、镜像及进程中的 home-tunnel、control-center、frps/frpc、HomeDesk、RustDesk、hbbs/hbbr。本次候选均为空。另检查 `/opt`、`/srv`、`/home/ubuntu` 的限定目录，以及既有 Caddy 源配置的门户相关关键词，未找到可确认入口。

这些检查不是全盘搜索，关键词缺失也不是不存在服务的数学证明。若服务使用不同名称、外部上游或其他部署位置，需要提供准确路径和 HTTPS origin 后重新核验。**本次没有已取得的服务端版本号、API 版本号或真实兼容性结论。**

### ENV-02：独立 Windows 身份/测试机未确认

结果：前置门禁失败，测试包未启动，现用 HomeDesk 环境未拿来试跑。

复现步骤：

1. 在当前 Windows 会话查询 `WindowsPrincipal.IsInRole(Administrator)`，本次为 false。
2. 只读查看本地用户清单，未确认专用 HomeDesk 验收用户；系统和工具维护的账户不能默认当作测试账号使用。
3. 调用 `Get-VM`，本次返回没有完成此任务所需权限的错误。没有提权、修改 Hyper-V 权限或接管未知虚拟机。
4. 查看现用 HomeDesk 目录存在性，确认它已有配置；因此不能在相同 Windows 用户下通过临时 AppData 路径冒充独立用户，尤其不能据此证明 DPAPI CurrentUser 隔离和恢复行为。

需要可登录的独立测试 Windows 用户或可用测试机。与现用用户同 SID 的进程、环境变量重定向或回环测试不满足本次隔离要求。

### ENV-03：专用账号、MFA 与转发资源尚未确认

结果：相关业务用例未执行。没有尝试从现用客户端、服务器数据库、`.env` 或日志中提取生产登录凭据。

需要准确 HTTPS origin、专用原生账号会话（`device_id=null`）、可人工完成的 MFA 条件、属于该账号的测试设备/Agent、协议能力及 TCP/UDP 端口池。没有这些条件时，创建临时 HTTP 后端或本机回环 echo 不能替代真实隧道访问通过。

## 补齐条件后的实机复验顺序

以下是尚未执行的后续步骤，不是本次通过证据。

1. 确认准确部署路径、实际 Server 版本、API 版本和真实 HTTPS 入口；若需要部署或升级服务端、调整生产 Caddy 或防火墙，另行处理，不混入本次验收。
2. 在独立 Windows 测试身份下启动已核对摘要的指定测试包；记录测试前后的本账号配置范围，避免安装覆盖或连接现用 HomeDesk 后台。
3. 只用专用账号完成 HTTPS/MFA、记住和关闭重开，记录认证流程事件而不是密码、验证码、访问/刷新 Token。
4. 用专用账号和设备创建带本次验收标识的临时服务，完成标签、收藏、编辑、启停、访问和确认删除；保留最少量的脱敏 UUID 映射与资源清单。
5. 对这些专用资源实施版本竞争、断链和响应丢失，核对 UI 草稿和服务器写入次数，禁止用生产资源制造故障。
6. 验证退出/忘记/专用会话撤销，再验证切回纯内网及迟到响应；抓包或审计只覆盖测试进程和测试 origin，不记录凭据载荷。
7. 清理仅由验收创建的资源和凭据；生产升级、防火墙调整及现有服务变更仍属于独立操作。

## 本次遗留与限制

未完成真实客户端登录或资源操作，所以没有可复现的客户端功能失败；不能把 ENV-01/02 写成应用缺陷，也不能据此签署完整门户通过。当前报告提供了确定的交付物身份、现场发现和逐项未执行理由，实机业务全部待环境补齐后复验。

## 开发侧接续说明（不改本次分数）

开发侧另行核查并修复了便携缓存与辅助进程的品牌隔离问题，提供修正版包、独立品牌未压缩变体及测试环境准备工具。详情见 [ACCEPTANCE_FOLLOWUP_2026-10-02.md](ACCEPTANCE_FOLLOWUP_2026-10-02.md) 与 [ACCEPTANCE_ENVIRONMENT.md](ACCEPTANCE_ENVIRONMENT.md)。这些新包尚未启动，不能把构建、解包验证或静态 Compose 检查回填为本报告的实机业务通过。

结构化证据中的非门户 Sub2API 镜像长版本已额外脱敏为 `REDACTED_VERSION`，只为减少无关现场细节和扫描误报；容器名、停止状态、候选为空及所有门禁结论保持原意，未新增密钥扫描白名单。
