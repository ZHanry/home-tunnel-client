# HomeDesk 实现与交付状态

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
