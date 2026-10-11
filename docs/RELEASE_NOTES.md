# NestLink 14.0.0

以桌面 update11 为基准，统一 Windows、Linux、服务端 Web 和 Android 的 NestLink 名称、客户端 SVG Logo、紫色主题、图标及“设备管理、远程协助、内网穿透”入口。设备目录按明确能力关联显示物理设备，分别展示远控与穿透状态；同名设备独立，取得完整目录后再归并、筛选和分页。旧服务端缺少扩展时显示兼容降级状态。

远控与穿透分别使用各自的能力主体。普通设备删除原子撤销整机两种能力并保留服务配置，管理员永久删除仍单独确认并检查权限。保留自建 HTTPS 账号、记住登录、短期签名许可和认证加密 P2P 直连，以及安装身份、配置命名空间和冻结认证协议。产品与受管运行时升级为 14.0.0。

正式发行复用源提交 `feaf1181efe55076dead52931203a8488cbad20d` 的 [CI 38069751230](https://github.com/ZHanry/home-tunnel-client/actions/runs/38069751230) 确切产物。该来源的质量、安全与完整构建材料已验证；正式标签相对构建来源仅增加本版验收 JSON 和两份发行文档。完整实测索引见 [acceptance-14.0.0.json](release/acceptance-14.0.0.json)，本版单独记录来源、执行时间和原件摘要。

| 安装包 | SHA-256 |
| --- | --- |
| NestLink-Setup-14.0.0-x64.exe | `6f772544fef487c2b084f83abe26a9bfb581b4cd8aeebd25b2bcc5647ebda41f` |
| NestLink-Linux-14.0.0-x64.deb | `9856a8ac83da603847f6796c006df04fdc9c83f651b1014763e5df28a308a4ce` |
| NestLink-Linux-14.0.0-arm64.deb | `ad109bb5b1379c3a2cbfcf936ab83b35a1ce6d919126ae00d18c2a2e443662a3` |

Windows x64 实测备份、卸载、清配置、清装、启动和全部 115 个普通载荷文件，以及中英文深浅色登录界面。Linux amd64 使用公开 13.0.0 安装包核验实际载荷与冷恢复，再升级到确切 14.0.0 包，核验全部 100 个普通载荷文件及 A/B 配置、钥匙环保留。这些前置 profile 最初由早期 14 测试创建，本轮验证其在公开 13 载荷上的冷恢复和再升级保留，未追溯最初的历史 13 登录来源。

隔离 X11 双端实际完成跨账号批准、紫色工具栏、真实屏幕、键盘标记及两端反向 TCP 连接配对。新建连接后，前台管理会话撤销使远控断开，同时保留两种设备能力和 HTTP、HTTPS 后端、TCP、UDP 四种穿透。随后整机原子撤权使两主体与租约失效、四种协议全部阻断；服务配置、其他同账号设备和其他账号授权状态保持。原始批准、输入、断开和三阶段穿透结果均独立保存。

浏览器批准、拒绝、离线、错误密码、正确固定密码和会话撤权六项实际场景通过。允许场景收到真实画面并核验键盘输入；撤权返回 204 后 27 毫秒内断开。独立签名 13.0.0 服务上的新客户端兼容检查另行记录，覆盖缺失扩展降级、明确配对、同名设备、主体选择和保留配置的删除，未将其作为 14 服务的媒体或穿透证据。

测试 B 的密码设置通过既有 root-admin IPC 临时设置 PIN 后，再在真实 GUI 解锁和保存。首次设置 PIN 的严格检查仍为失败，因为同时发生 trusted_devices 变化且其原语义未知；后续独立读取与清理通过，仅清空 unlock_pin，A 与 root 配置未变。系统 root 密码 GUI 解锁未验证。失败回执、原始截图与独立审查保留。

本地媒体实测范围为 WSL amd64 X11 和 Chromium；Windows、ARM64、Wayland 媒体、实体 Android、运营商 NAT、长期媒体、音频、剪贴板及文件传输未在本轮覆盖。Linux ARM64 有独立 CI 构建与质量验证，没有本机 ARM64 执行。Linux 本轮原图审核覆盖中文浅色，Windows 已登录业务页未本地执行。Windows 安装器没有 Authenticode，来源签名与平台代码签名分别记录。

联调使用任务专用 WSL、自签 TLS、host-network 健康适配、localhost 桥、HBBS LAN mask 和 STUN-only 后端。部分 API/Web 场景跳过任务自签证书验证；任务网络恢复和 Android P2P 的精确临时单端口规则均单独记录。原始失败、时钟域与未测范围保留，13.0.0 验收结论不复用于本版。

依赖安全范围已针对确切构建材料核对。截至本次审查，客户端仓库仍有 18 个未关闭的 Dependabot 告警（3 high、7 medium、8 low）。`mio` 高危告警来自虚拟显示独立旧锁，本次 Windows/Linux/Android 选择的版本已超出受影响范围。Linux 的 `users` 0.10.0/0.11.0 未修复，冻结消费者未发现调用该高危告警涉及的组列表访问控制入口；这只是静态范围判断，没有动态可达性或利用测试。Linux 的 `libgit2-sys` 高危版本仍是读取冻结本地源码元数据的构建输入，其依赖链未选入受管运行时，该构建依赖没有修复。Linux glib、users 的其他告警以及 atty 风险仍保留；没有关闭或 dismiss 告警，也不宣称安装包没有受影响依赖。

The exact build materials were reviewed against the open dependency alerts. Linux still selects unpatched users 0.10.0/0.11.0; no calls to the affected group-list access-control entry points were found in the frozen consumers, without dynamic reachability or exploitation tests. The affected libgit2-sys remains a Linux build input and is not selected into the managed runtime. Selected Mio versions are outside its affected range. Other glib/users and atty risks remain; this release does not claim that all dependency vulnerabilities are fixed.

此次发布更新 GitHub、下载站及自动更新信息。正在运行的生产服务端保持原版本。
