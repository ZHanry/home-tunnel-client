# HomeDesk 实现与交付状态

## 2026-10-02 运维接续与隔离修复

运维实机报告保留前置 4 通过/2 失败/2 未执行，业务 25 项未执行。开发侧据源码进一步修复便携外壳共用旧缓存根、全机同名 broker 清理和版本缓存锁的边界；采用构建 namespace、带所有权标记的版本目录、无链接/reparse、排他句柄和真实映像路径认领。Windows 缓存模块 9 项、进程路径检查及独立审阅通过，实际包内 93 文件解包/MD5/启动路径探针通过，没有启动 App。

修正版正常品牌与独立品牌未压缩变体的 Windows Rust/Flutter Release 构建通过，旧报告指定包摘要未变；新包摘要、用途和限制见 [ACCEPTANCE_FOLLOWUP_2026-10-02.md](ACCEPTANCE_FOLLOWUP_2026-10-02.md)。本次外围接线均标记 `HOMEDESK`，依赖锁与核心协议未变。

独立测试环境工具 6 项检查通过，官方 Server tar 摘要核验、专用配置/CA/秘密材料及 Docker Compose 静态检查已完成；其余 5 件发行资产未下载齐，环境启动就绪为 false，未部署指定腾讯云或启动任何测试容器/客户端。实机门禁仍不放行。环境说明见 [ACCEPTANCE_ENVIRONMENT.md](ACCEPTANCE_ENVIRONMENT.md)。

## 2026-10-01 完整门户与安全记住登录（目标模式）

本轮按用户明确授权完成整套设计和开发，范围以 [DESIGN.md 5.4](DESIGN.md#54-homedesk-统一门户2026-10-01) 与 [PORTAL_INTEGRATION_PLAN.md](PORTAL_INTEGRATION_PLAN.md) 为准，替代下方首阶段只读门户的产品范围。HomeDesk 保持统一入口，home-tunnel 是账号资源与隧道后端，RustDesk 原连接引擎未替换。

已完成服务创建、名称/本地目标编辑、暂停/恢复和确认删除，设备标签/收藏，真实接口能力限制与子域检查；所有资源操作带版本保护，409 和网络结果未知保留草稿，刷新核对并在应用内明确重试，不自动重复写操作。设备名称和传输/公网端口的不可编辑范围按 10.1.0 真实契约处理。

Windows 可勾选 DPAPI 当前用户加密的记住登录，恢复先原子消费旧令牌，再单次刷新并校验 origin/账号身份，最后加密保存新令牌。跨进程锁和持久事务代次防止重复恢复、退出后的迟保存及旧实例误删新实例记录；密码/MFA/access Token 不落盘。冷纯内网不读取记录或联网，恢复需独立本机批准地址与有效动态许可。普通关闭保留成功保存的记录，退出/撤权条件清理自身事务，明确忘记登录才全局清除。

实际验证全部通过：

- API 25 组真实回环行为检查，覆盖所有资源操作、权限/版本、单次刷新、未知写结果、恢复/保存先后顺序、并发、退出/撤权/晚写和跨实例新登录保护；原 Console 请求探针回归通过。
- Windows DPAPI 10 组真实系统测试，仅操作注入临时目录，包含密文、损坏/异产品 entropy、原子替换失败、跨进程单消费、失效和条件销毁。
- 真实回环 HTTPS：默认拒绝不可信证书，信任测试 CA 后仍拒绝错误主机名；正确 localhost TLS 成功登录、读取目录及独立退出。测试证书运行时生成并清理。
- Flutter 四组套件共 37 项通过（含深浅色预览导出），覆盖 CRUD、MFA、记住/恢复、未批准 origin、冲突与未知草稿、实体互斥、设备元数据、窄窗口和双倍字体，以及原设备墙/导航/高级设置回归。
- Rust 网络策略 8/8；新增批准 origin 校验以生产函数源码及其实际 `url` 库做独立探针通过。全客户端 `cargo test --lib` 的测试链接因已有 C/C++ CRT 混用未通过，不把它计为成功；Windows 正式 Release 编译另行通过。
- 新模块静态检查无问题；联同上游首页检查只保留原有 deprecated 提示。独立安全/正确性审阅已清除具体问题，深浅色最终预览已检查。
- 固定 gitleaks 8.30.1 在 WSL/Linux 下匹配原 84 条精确示例、新增或变化疑似密钥 0，未改基线；差异检查通过，依赖锁未变。
- 最终源码 Windows x64 Rust/Flutter Release 编译和独立便携封包通过，没有安装、启动或覆盖现用程序。

完整测试包：`client/target/portal-artifacts/HomeDesk-1.4.9-portal-complete-win-x64.exe`，23,732,736 bytes；SHA256 `fb88799a4c1497d6ea7cc06cd1075aa5cb16d02c8ab1f54e796609cdfd3c844f`。同目录保留 `build-complete.log` 与 `SHA256SUMS-complete.txt`。此前只读门户包和 2026-09-22 原包摘要保持不变。使用合成的纯内网默认配置，实际连接需按文档填写自己的合法服务器配置。

新增逻辑在独立 Dart API、会话协议、DPAPI、门户与编辑器模块；上游接线仍仅首页 builder、Rust local-option 与保存生命周期，每处标记 `HOMEDESK`。未修改 hbbs/hbbr、RustDesk 传输/编解码/密码核心，也未修改 home-tunnel 服务端或安装 Agent。

开发和本地交付已完成；真实公网服务端账号/MFA/撤权、NAS实际服务、Linux/ARM64 完整构建及真机、原 RustDesk 双独立网络门禁仍未执行。高级账号/运营者设置由现有管理台处理，Linux 没有明文记住登录回退。使用方式见 [HOME_TUNNEL_PORTAL.md](HOME_TUNNEL_PORTAL.md)。

## 2026-10-01 HomeDesk 统一服务门户

用户确认桌面客户端首页作为统一门户，首阶段接入 home-tunnel Server 10.1.0 账号目录。已新增“家庭服务”导航、HTTPS 账号与 MFA 登录、全部分页设备/服务、设备筛选、网页打开与 TCP/UDP 端点复制；创建、修改和改密跳原管理台。导航按需初始化并保留会话，首屏不请求公网。

公网管理使用独立模块和动态网络许可。配置保存期间暂停门户，后台/UI 各自更新许可代次；撤权、快速恢复与迟到响应均不能复用旧会话。Token 只在内存，刷新严格单次串行；未注册设备、申请 FRP 租约或接入 home-tunnel 原生远控，内网 Console 不开放公网。

本轮实际验证：

- Rust 独立网络策略 8/8 通过，包含默认纯内网及后台确认未知时的门户拒绝。
- Dart API 11 组行为检查通过，包含真实回环 mock、101 项全分页、目录变化拒绝、MFA、账号身份、并发刷新/失响应、重定向、大小/超时和在途撤权。原内网 Console 请求探针回归通过。
- Flutter 家庭设备、主页、高级设置与服务门户共 23 项通过（含 1 项深浅色预览导出）；覆盖懒加载、状态保持、MFA、打开/复制、模式与许可代次变化后旧按钮/旧响应拒绝，以及窄窗口/大字体。
- 新 API、门户、导航和主页静态检查通过；仅保留既有上游 deprecated 提示。深浅色合成预览已人工检查。
- 固定 gitleaks 8.30.1 在与 CI 一致的 WSL/Linux 路径下通过：84 条精确上游示例基线、新增或变化的疑似密钥 0。Windows 扫描报告的临时路径未匹配既有基线，因此以 Linux 复验记录为准，没有扩大白名单或修改基线。
- Windows x64 Rust/Flutter Release 与隔离便携封包通过，使用 `tests/fixtures/config.t02.toml` 合成纯内网默认。没有安装或启动产物，没有修改现用 AppData/后台服务。

新测试包为 `client/target/portal-artifacts/HomeDesk-1.4.9-portal-win-x64.exe`，SHA256 `4138ef8eb4b7b31b253964f0577581ed59761ac826134584628dc3e945f511fa`；同目录保存构建日志和校验清单。标准构建最后重命名阶段因旧同名测试包存在而拒绝，新产物通过相同构建环境完成 Rust/Flutter 编译后独立封包，旧包保持不变。

本轮上游接线仅在 `client/flutter/lib/desktop/pages/desktop_home_page.dart`（导入、builder）、`client/src/ui_interface.rs`（动态许可与缓存同步）、`client/src/flutter_ffi.rs`（保存生命周期暂停门户），新增处均有 `HOMEDESK` 标记；主要逻辑留在独立 `homedesk_*` 模块。依赖锁与 RustDesk 核心协议未变更。

尚未完成真实服务端 HTTPS/TLS、真实账号 MFA/撤权和访问地址联调，也未执行本轮 Linux/ARM64 完整构建及实机。门户测试不能替代下方原有 RustDesk 真实跨网门禁。使用方式见 [HOME_TUNNEL_PORTAL.md](HOME_TUNNEL_PORTAL.md)。

## 2026-09-22 自建公网增量

本轮已完成代码开发与下述本地验证，保留默认纯内网。真实公网服务和第二个独立网络设备尚未提供，T-17/T-19 的真实跨网门禁未放行；下方 2026-09-08 记录继续作为历史事实。

| 范围 | 本轮结果 |
| --- | --- |
| 构建与迁移 | Rust/Python 配置支持 `net.mode`、独立中继、来源限制与 Console 信任开关；旧 true 迁移纯内网，旧 false/冲突配置拒绝隐式公网 |
| 运行时模式 | 两份完整配置组，通过专用后台 IPC 校验、持久化核对与确认；通用单项/批量/同步入口不能部分覆盖组；有活动连接时拒绝切换。排队保存有期限与互斥执行权，ACK 未知时只读重同步，失败暂停新连接 |
| 网络与会话 | 服务器/中继/DNS/对端候选按用途准入；保持原 TCP P2P 与中继算法；公网出入站拒绝未加密回退，链接参数不能替换固定 Key；来源限制与家庭 CIDR 分离 |
| 设置界面 | 中文模式表单、对应组加载、异步等待后台、错误保留和防重复提交；移除旧的无效纯内网布尔开关 |
| Console 降级 | 公网默认不使用 Console；显式可信路径才许可。后台可取消在途 HTTP/退避/队列，前端撤权关闭旧客户端并按新 URL/Token 重建，丢弃过期响应 |
| 服务部署 | 独立公网 Compose/校验/运维脚本，固定 OSS 1.1.16 digest，仅 hbbs/hbbr；接口与通告地址分离，注入/特殊地址/DNS/端口校验，一致性备份与失败恢复 |
| CI | 增加公网配置、回环容器、Reporter 取消和设置界面检查；尚未在远程 CI Runner 实际运行 |

验证：Python 13/13（WSL 含实际 deb staging）；Rust 构建配置 11/11、网络策略 7/7、保存请求时限与并发状态 3/3；Reporter Windows/Linux 各 7/7；Flutter 设备墙、主页和高级设置测试通过，含异步保存交互；Dart 实际回环 HTTP 探针通过；公网部署/运维回归、锁定容器 TCP 与重启身份验证通过。Windows `cargo check --locked --features flutter`、Rust Release、Flutter Windows Release 通过。检查使用合成配置与隔离测试目录，没有安装覆盖现用程序或用真实后台服务试验保存。

重要实现边界：上游原始 IP/域名连接不经过同等加密握手，因此公网模式拒绝并提示使用设备 ID；经 hbbs 撮合的同网段 P2P 保留。公网 ID 服务故障不承诺新建连接。UDP/KCP 会话、IPv6 与 VPN 未被冒充已验收能力，保持关闭或未覆盖。Linux/ARM64 完整客户端构建和真机未在本轮完成。

本轮上游接线主要为 `client/src/client.rs`、`common.rs`、`ipc.rs`、`ui_interface.rs`、`flutter_ffi.rs`、`flutter.rs`、`rendezvous_mediator.rs`、`server.rs`、`server/connection.rs`、`auth_2fa.rs`、`hbbs_http/http_client.rs`、`hbbs_http/downloader.rs` 和 Flutter 设置页；独立策略与界面位于 `homedesk_*` 文件。未改签名协议、编解码或 NAT 穿透算法，未升级依赖锁或镜像版本。

配置与交付证据见 [CLIENT_NETWORK.md](CLIENT_NETWORK.md)、[DEPLOY_PUBLIC.md](DEPLOY_PUBLIC.md) 和 [T17_VALIDATION.md](T17_VALIDATION.md)。

## 2026-09-08 历史状态

更新时间：2026-09-08。用户要求加快完成全部功能，并包含飞腾 ARM64 麒麟客户端。本轮完成可在当前环境实现和验证的核心模块；不把官方原版安装包、代码接线或脚本存在当作定制版验收通过。

## 已实现

| 范围 | 结果 |
| --- | --- |
| Console API 与存储 | 新增独立 Rust axum + SQLite crate，Cargo.lock 固定；设备心跳 upsert、90 秒在线判定、房间/成员/名称编辑 |
| WOL | 单独设置有线 MAC；只向当前家庭网段广播 UDP 9；同设备 30 秒限一次；MAC 不受后续心跳覆盖 |
| 会话审计 | start/end、持续秒数、实际直连/中继入口元数据、重复事件幂等、按设备/时间/序号筛选、CSV 导出、保留天数和过期清理 |
| 网页管理台 | askama + 内嵌 JS/CSS，登录、设备、审计、设置、退出；无外部 CDN，手机布局与深浅色 |
| 访问限制 | RFC1918 绑定与来源检查、Bearer/Cookie、Cookie 写请求来源标记、口令摘要存储、登录限速、口令轮换注销 |
| 客户端上报 | 独立异步发送器；后台服务启动心跳，认证成功后登记会话，释放时结束；有界队列及退避 |
| 客户端外围限制 | 私网直接 IP/CIDR 检查、HTTP POST/重定向/下载边界、公网 STUN 阻断、关闭插件初始化及公网机器人读取 |
| 家庭界面 | 原生首页设备墙、设备连接和 WOL；默认简体中文配置；隐藏账号/云地址簿；设置仅保留四组；新增纯内网模式开关 |
| 家庭设备中心改版 | 左侧导航、设备卡片与房间筛选、手动连接、本机信息弹层、浅深色主题及网络状态入口；设备服务未接入时显示真实空态 |
| 构建支持 | Windows x64/Linux x64/ARM64 原生预检与构建入口；ARM64 bundle 与 deb 目录识别；离线依赖准备/安装脚本 |
| CI 与部署 | 仓库验证工作流、三平台私有 Runner 构建工作流、固定 gitleaks 扫描、Console Dockerfile 和 NAS host 网络 Compose 覆盖文件 |

## 实际验证

- Console：`cargo test --locked`，9 组集成测试通过，覆盖各 API 鉴权、非法输入、心跳幂等/备注保留、审计幂等与筛选/导出、Cookie/CSRF、网段、设置/口令轮换、WOL 报文，以及文件数据库重启/清理/离线状态。
- 上报发送器：真实生产源文件独立编译，4 组测试通过：退避、关闭时不启动、队列上限、HTTP mock 下心跳先于 start/end 且带 Bearer。
- Rust 构建配置：8/8；网络边界：3/3；WSL Python 配置/真实 deb staging：10/10。合计 34 项通过。
- 原生 Flutter 设备墙：3/3 组件测试通过，覆盖选中设备连接、WOL 等待/上线收敛、故障提示、200% 字体无溢出；测试发现的 6 像素溢出已修复。
- 独立 Dart HTTP 探针通过，覆盖 11 类非法 URL、显式端口、Bearer、设备 ID 注入过滤、WOL、禁止重定向与 401；新增 Dart 文件 analyzer 无问题，原首页保留 3 项上游弃用提示。
- Windows `cargo check --lib --features flutter,hwcodec --locked` 和 Rust Release DLL、Flutter Windows Release、portable 外壳构建均通过。外壳文件属性已统一为 HomeDesk。使用测试配置，未启动或安装该验证包。
- Windows bundle 的 15 个 EXE/DLL 共检查 51 个依赖，构建机未发现缺失项，也未发现需单独附带的 VC 动态运行时依赖；不替代干净 Windows 实机安装验证。
- Console Linux x64 release 编译成功，单文件约 3.3 MiB，位于 `server/console/target/release/homedesk-console`。
- Console x64 musl 静态程序、scratch 镜像和离线镜像 tar 已生成；非 root/只读容器下心跳 API 与容器重启保留数据实测通过。
- 浏览器实际验证登录、设备编辑、WOL 配置二次打开保留、审计筛选与设置；375×812 深色手机布局目视正常。未点击测试设备的唤醒按钮，不把 UI 测试当作真实 WOL。
- JS 语法、Python 语法、Bash 语法、Compose 合并配置和 `git diff --check` 通过。
- gitleaks 初次识别 84 项上游已公开的公钥示例/测试字符串，已逐类核对并建立精确文件摘要/行号基线；不排除整个上游或测试目录。基线扫描新增/变化的疑似密钥为 0。

## 当前产物

| 产物 | 性质 |
| --- | --- |
| `server/console/target/release/homedesk-console` | 本轮编译的 Linux x64 管理台，可运行；仍需 NAS 部署验收 |
| `server/console/target/homedesk-console-0.1.0-linux-amd64.tar` | 已实测的静态管理台镜像，x64 NAS 可导入，约 1.8 MiB |
| `client/target/homedesk-p0/HomeDesk-1.4.9-win-x64-validation.exe` | 本轮编译的 HomeDesk Windows 验证包，约 22.4 MiB；测试服务器/公钥、Console 默认关闭，不能用于正式连接 |
| `client/target/homedesk-p0/rustdesk-1.4.9-x86_64.exe` | 官方 Windows 原版，SHA256 与签名通过，用于 P0 |
| `client/target/homedesk-p0/rustdesk-1.4.9-aarch64.deb` | 官方 ARM64 原版，SHA256 与 deb 架构通过，尚未麒麟安装 |

以上构建/下载目录均被 Git 忽略。Windows 验证包 SHA256：`3c10fa5b49e990883330ae6012562a9ab3b4066516dc968a3d46787e90d4a3e9`；Console 镜像包 SHA256：`0fa910e0b8ae15c26c1035c9aa52f0bce58ab2d788d2dd75bc94f87df44d18e6`。尚未生成 HomeDesk ARM64 定制客户端。

## 未完成与阻塞

1. **正式客户端配置**：Windows 构建链已打通，已有测试配置验证包；需要真实 NAS 地址、公钥、网段和可选 Console Token 重新构建正式包。未配置正式签名，未安装验证。
2. **ARM64 真机**：没有 ARM64 构建机/模拟器或麒麟系统版本。上游 Linux ARM64 的中文回退也需要引擎/字体实测。见 XINCHUANG.md。
3. **NAS 容器验收**：基础镜像下载阻塞已通过本机 musl + scratch 构建解决；镜像与重启测试已完成。真实 NAS 网卡广播、防火墙及数据卷权限仍需部署验证。
4. **真实远控链路**：未获得 NAS 管理入口及另一台 Windows 地址，尚未正式部署、双机连接、加密/P2P/UDP 检查、锁屏/重启/断外网/性能实测；smoke 保持未勾选。
5. **纯内网全量保证**：已补充入口限制，但尚未完成所有出站点清单、代理配置/外部链接与服务端回包地址的全路径核验，也未抓包。不能宣称零公网出站验收通过。
6. **会话审计完善**：直连/中继类型已接入并编译通过，真实链路对照仍待实测；队列不是落盘 outbox，断电和长时间服务故障可能丢事件；控制台与设备共享静态 Token。
7. **原生界面验收**：家庭设备中心已通过合成设备组件测试和本机进程验证；完整安装后的高级模式、中文/错误提示、托盘及多 DPI 仍需实机审核。设备服务未接入时应显示真实空态。
8. **后续功能**：Web 自托管尚无符合当前 OSS 约束的已验证交付，见 WEB_CONSOLE.md；龙芯 no-GUI、Android 真机、WireGuard 回家、管理台 TOTP/成员权限尚未实现或验收。
9. **正式 CI/Gemini 审计**：工作流未推送运行，私有 Runner 未配置；Console 和整体设计尚未完成 Gemini 审计。家庭客户端合成图已单独审查且无 Blocker，但不替代实机视觉验收。

## 上游改动范围

保留原传输协议、编解码与加密实现，接线均有 HOMEDESK 标记：

- `client/homedesk_build.rs`：Console 构建配置。
- `client/build.py`：ARM64 bundle 与打包入口。
- `client/libs/portable/build.rs`：安装包外壳的品牌属性与单仓库配置一致。
- `client/flutter/pubspec.lock`：修复固定 Flutter 3.24.5 的 SDK/测试依赖约束，没有升级应用直接依赖。
- `client/src/lib.rs`、`server.rs`、`server/connection.rs`：注册模块、服务心跳、认证后会话钩子。
- `client/src/homedesk_config.rs`、`homedesk_net.rs`：默认设置与外围地址检查。
- `client/src/client.rs`、`common.rs`：直接输入地址、HTTP POST、STUN 入口。
- `client/src/hbbs_http/http_client.rs`、`downloader.rs`：重定向与下载入口。
- `client/src/auth_2fa.rs`、`flutter_ffi.rs`、`plugin/mod.rs`：公网通知/插件入口。
- `client/src/rendezvous_mediator.rs`：初始化本地连接类型元数据。
- `client/flutter/lib/desktop/pages/desktop_setting_page.dart`、`desktop_home_page.dart`：四组家庭设置、开关与原生设备墙。
- `client/flutter/lib/homedesk_dashboard.dart`、`homedesk_devices.dart`：家庭设备中心布局、设备卡片、房间筛选和 WOL 入口。

新增逻辑独立在 `homedesk_console.rs`、`homedesk_report.rs`、`server/console/` 和 `build/ci/`。本次保存为阶段性 Git 版本，不代表全部功能或实机门禁通过；没有推送或部署到真实 NAS，没有填写真实 IP、公钥、Token。

## 2026-09-08 家庭设备中心 UI 更新

- 已在本机安装的 HomeDesk 中更新家庭设备中心；安装文件与本轮 Release 构建文件摘要一致，主窗口重新启动后可响应。
- 常规合成设备组件测试共 6 项通过，覆盖设备卡片、房间筛选、手动连接、本机信息默认隐藏、窄窗口/双倍字体和空态；仅启用本机预览环境变量时额外导出 1 项深浅色合成预览（共 7 项）。Gemini 对合成图审计无 Blocker。手动连接已改为描边按钮，网络状态入口已补充文案与设置入口。
- CI 的 Flutter 静态分析和组件测试已纳入 `homedesk_dashboard.dart` 与 `homedesk_dashboard_test.dart`；CI 不设置本机预览环境变量。
- 当前安装仍使用测试服务器配置，设备服务尚未接入，故会显示真实空态；旧 portable 验证包未重新打包，尚未创建新的 Git 提交。未进行真实双机、ARM、WOL 实机或完整 Windows 视觉验收。
