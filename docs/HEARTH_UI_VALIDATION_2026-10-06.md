# HomeDesk 暖居视觉改版与验证记录（2026-10-06）

本轮按 `client/target/ui-proposals-20261006/README.md` 的 A「暖居」实现，并吸收 B 的中文状态栏和最近连接的路径、质量信息位置。改动留在工作区，没有 commit 或 push。

## 已实现

显式的浅色、深色 token 替代 `ColorScheme.fromSeed`，统一陶土主色、状态色、字号阶梯、圆角和间距；保持原字体设置，没有网络字体和新增依赖。自有模块中的颜色全部来自 token 或主题。

主界面和设置共用主导航；宽栏 220px，低于 960px 或大字体时为 84px 带文字窄栏，矮窗口允许导航滚动。页头和内容共用 24/28px 水平网格，底部各页明确显示网络模式、远控服务器、家庭账号状态。原远控状态组件继续执行现有更新，可见展示由自有状态组件负责。

家庭设备采用最小目标宽度 280px 的自动网格，默认卡片高度 208px，大字体自动增加高度。1280px 窗口采用三列，避免四列过窄；名称单行，长名称以省略号配合完整 tooltip 展示。“儿童房电脑”在 1280px 下完整单行。提供本机、账号在线、离线、待同步样式、状态筛选、最近连接摘要和本机连接码入口。

家庭服务合并账号与本机接入状态条，按设备分组并提供类型筛选。服务卡显示真实状态、公网地址、本地目标，提供打开、复制、编辑和更多菜单中的暂停/恢复、删除。原许可、互斥、版本冲突、结果未知和确认流程保留。

最近连接用独立模块读取上游最近、收藏、局域网发现模型，连接调用既有 `connectInPeerTab` 入口。设置保留主导航、分段分类和自适应卡片，单按钮的后台服务卡改成一行。添加/编辑服务、设备标签、本机信息、手动连接、网络模式和家庭服务地址输入统一使用新主题；自有表单标签在输入框上方。

## 改动文件清单

### 上游文件

仅修改 `client/flutter/lib/desktop/pages/desktop_home_page.dart` 的两处接线：新增 `homedesk_recent.dart` import；将 `recentBuilder` 的 `ConnectionPage` 替换为 `HomeDeskRecent`。每处均有 `// HOMEDESK:` 标记，未重排或重新格式化上游文件。

没有修改 `desktop_setting_page.dart`、PeerTabPage、peers_view、peer_card 或 Rust 传输、编解码、加密文件。

### HomeDesk 自有代码

以下路径均相对于 `client/flutter/lib/`。

| 文件 | 变更原因 |
|---|---|
| `homedesk_theme.dart` | 集中暖居浅深色、字号、圆角、间距，以及徽标、分段控件和上方标签组件。 |
| `homedesk_navigation.dart`（新增） | 主界面/设置复用导航和首页摘要面板；账号通知的展示刷新避开页面卸载锁树阶段。 |
| `homedesk_status.dart`（新增） | 只读现有模式、远控、账号状态，提供状态条与底栏，不修改网络许可。 |
| `homedesk_dashboard.dart` | 响应式外壳、对齐页头、常驻底栏、本机/手动连接弹窗、设置返回时的已有页面入口。 |
| `homedesk_family_devices.dart` | 账号设备网格和四类状态、过滤、名称单行；保留身份及服务器指纹检查。 |
| `homedesk_devices.dart` | 内网 Console 网格与首页摘要，保留连接、WOL、动态撤权和刷新行为。 |
| `homedesk_recent.dart`（新增） | 消费上游最近/收藏/发现模型，保留原连接入口；缺少的历史数据明确显示暂无记录。 |
| `homedesk_services.dart` | 合并服务页头和状态、按设备/类型显示紧凑服务卡，将暂停和删除移入更多菜单。 |
| `homedesk_settings_shell.dart` | 主导航、分段分类、密度一致的设置卡片；不改上游设置回调。 |
| `homedesk_service_editor.dart` | 表单标签和密度适配，所有验证、草稿、冲突、保存回调保持原样。 |
| `homedesk_local_info.dart` | 本机凭据和便携提示使用新颜色、间距、圆角。 |
| `homedesk_title_bar.dart` | 标题栏背景使用 chrome token，窗口动作不变。 |
| `homedesk_quality.dart` | 现有会话质量面板使用统一 token，路径/指标转换不变。 |
| `homedesk_advanced.dart` | 网络模式弹窗使用上方标签和语义错误色，标题改为“网络模式”，原校验和保存逻辑不变。 |
| `homedesk_service_address.dart` | 设置内的家庭账号/服务地址卡使用统一密度与上方标签。 |

### 测试和记录

| 文件 | 变更原因 |
|---|---|
| `client/flutter/test/homedesk_hearth_test.dart`（新增） | 四个尺寸/主题组合检查首页、服务、最近、设置布局；1280px 设备名完整单行；真实空态和原设备连接提交；预览导出。 |
| `client/flutter/test/homedesk_services_test.dart` | 更新打开/复制文案、状态圆点和更多菜单路径，等待滚动完成后点击；保留 MFA、许可、冲突、CRUD、版本和大字体覆盖。 |
| `client/flutter/test/homedesk_shell_test.dart` | 返回主页改为主导航入口，保留分类、双倍字体与窗口/托盘检查。 |
| `client/flutter/test/homedesk_advanced_test.dart` | 更新“网络模式”标题断言，模式整组加载和保存 ACK 互斥断言保留。 |
| `tests/smoke.md` | 记录本轮实际验证，明确实机未覆盖项。 |
| `docs/HEARTH_UI_VALIDATION_2026-10-06.md` | 本报告。 |

## 实际验证

| 检查 | 实际结果 | 证据 |
|---|---|---|
| 改动的 20 个 Dart 文件 `flutter analyze --no-pub --no-fatal-infos` | 0 error、0 warning、0 新增问题；保留上游 3 条 deprecated info。 | `client/target/hearth-analyze-final.log`；改前基线 `hearth-analyze-before.log`。 |
| 全部 9 个 `test/homedesk_*_test.dart` | 60 通过、0 失败；新增 5 项。 | `client/target/hearth-tests-all-final.log`。 |
| `HOMEDESK_UI_PREVIEW` 导出 | 5 项通过；16 张 PNG，四页 × 两种尺寸 × 两种主题。 | `client/target/hearth-preview-final.log`。 |
| PNG 尺寸与视觉检查 | 16 张均为要求尺寸；查看两张联系表和关键原尺寸图片，服务操作在 800×600 首屏可见。 | `client/target/ui-hearth-preview/`。 |
| Windows x64 Release | 编译通过，57.2 秒；`flutter build windows --release --no-pub`。 | `client/target/hearth-windows-release.log`。 |
| ZIP CRC 和包内容 | 全包 CRC 通过；102 个文件，根目录只有 `homedesk.exe` 一个主程序；文件集合与上一包一致。 | 交付 manifest。 |
| 原生核心、隧道 runtime | Rust DLL 与上一包 SHA256 完全一致；全部隧道 runtime 文件逐项摘要一致。 | 交付 manifest。 |
| 锁文件与差异 | `pubspec.lock`、`Cargo.lock` 无改动；`git diff --check` 通过。 | 工作区差异。 |

### 预览

目录为 `client/target/ui-hearth-preview/`，入口为其中的 `index.html`。文件命名为 `{home,services,recent,settings}-{800x600,1280x800}-{light,dark}.png`。另有 `contact-800x600.jpg`、`contact-1280x800.jpg` 便于并排检查。

预览使用生产组件和合成的账号、设备、服务数据，未读取用户 ID、密码、账号记录或 AppData。设置预览使用实际 `HomeDeskSettingsShell`、`HomeDeskSettingsCard` 与示例控件，没有启动真实程序或原生设置业务；它验证视觉外壳，不代表真实设置操作已经实机验收。

### 构建产物（上一轮；已由“返工 1”替代）

- ZIP：`client/target/portal-artifacts/HomeDesk-Hearth-UI-Windows-x64.zip`。
- Manifest：`client/target/portal-artifacts/HomeDesk-Hearth-UI-Windows-x64.manifest.json`。
- 校验文件：`client/target/portal-artifacts/HomeDesk-Hearth-UI-Windows-x64.sha256`。
- 文件大小：40421086 bytes。
- ZIP SHA256：`ea604447c53253fc6a4bd2073a9c5deab37b4dc6e459d9862691ae8a46b2f013`。
- 远控 DLL SHA256：`cb3cb2a9c2b19c8019409945e7c77721828a6cb6b887ac9cbf5af5314ab3e6a8`。

构建沿用 CMake 缓存和 Rust 构建记录中指向的 `tests/fixtures/config.acceptance.toml`，没有修改该配置。仓库当前不存在 `build/config.toml`，首次使用该默认路径的尝试失败；定位原配置后成功。Flutter AOT 和 Windows runner 实际重新编译，未改动的 Rust 核心复用上一包相同 DLL。封包使用上一包的文件集合，并逐项保留原隧道 runtime；旧 ZIP 未覆盖。

构建后的 Python 输出助手因 GBK 控制台不能打印 Flutter 的勾号发生过输出编码错误；Flutter 子进程退出码为 0，日志明确显示 Release 已生成，不是编译失败。

## 数据限制、设计差异与未覆盖项

1. 上游 `Peer` 模型未提供历史时间、时长、实际连接路径或会话质量。列表显示“暂无记录”，没有根据公网模式或“强制中继”设置伪造路径，也没有新增历史持久化逻辑；现有会话中的实际质量面板继续保留。
2. 账号设备目录没有 WOL 配置或唤醒 API。账号离线卡保留已有“尝试连接”；内网 Console 中配置过 WOL 的离线设备保留“远程开机”。没有为了效果图增加业务能力或假按钮。
3. 首页“让家人连接这台电脑”提供“查看连接码”，点击后才显示原本机信息弹窗中的 ID 和允许的认证方式。没有常驻明文密码，遵守 `DESIGN.md` 6.4 的凭据默认隐藏要求；固定密码/本机确认模式不会展示旧临时密码。
4. 1280px 采用三列而非效果图中挤窄的四列；更多设备和摘要需要滚动。长设备名使用单行省略号和完整提示，不强行缩小字号。
5. 服务卡异常/等待提示使用 API 已返回的真实状态；当前模型没有额外诊断文本时不编造原因。
6. 没有安装、覆盖、启动 `D:/Program Files/HomeDesk` 的程序，没有结束任何 HomeDesk/隧道助手进程，没有修改用户 AppData。真实程序下的主导航、原生设置操作、DPAPI 恢复、真实远控/WOL 和公网路径没有在本轮实机执行；现有合成行为回归通过不替代这些实机验收。


## 返工 1（2026-10-06）

本节替代上一轮的测试数字、预览和构建产物摘要。上一轮 SHA256 保留为历史记录；同名 ZIP 已按返工单覆盖。

### 逐项处理

| 编号 | 处理方式 | 验证与边界 |
|---|---|---|
| 1 | 每行加入“⋯”，通过 `homedesk_peer_menu.dart` 调用上游 Recent/Favorite/Discovered 卡片的公开菜单 builder，动作实现和可用条件原样复用。保留收藏/取消收藏、删除、忘记密码、重命名、文件传输、终端、TCP 隧道、RDP、局域网 WOL，也保留上游提供的快捷方式、强制中继等菜单项。新增按名称/ID 搜索和“经典视图”弹窗，完整嵌入原 `ConnectionPage`，其 ID 自动补全、上次 ID、排序、多选删除继续可达。 | 三种上游菜单接线契约检查通过；菜单项及注入动作、搜索、收藏分段、发现 WOL、经典视图入口检查通过。未复制上游动作代码或修改 PeerTabPage 系列。 |
| 2 | `TickerMode` 重新可见时加载当前分段；窗口 focus/restore、生命周期恢复时重新加载；首页摘要使用同一机制；经典视图和更多菜单关闭后也加载。 | 首页摘要/最近页切回与窗口返回的加载次数、分段保持检查通过。 |
| 3 | 行内显示上游 `peer.online` 状态；6 秒查询只在页面可见、窗口活跃且未最小化时执行。Windows restore 后紧随的 blur 保留上游 300ms 保护。 | 失焦、最小化、隐藏时不查询，恢复后查询和加载检查通过。 |
| 4 | 状态条/底栏在服务停止时显示“启动服务”，调用原 `start_service(true)`；仅增加按钮在途展示互斥。 | 启动回调检查通过，没有新增启动协议或进程管理逻辑。 |
| 5 | 重试点击重新读取忙状态、API、当前许可及代次，验证通过后才置忙。使用 try/finally 复位本次操作拥有的忙状态，旧操作不会清除新代次的忙状态。对话框随状态刷新；撤权或代次变化只移除自己拥有的 route。Flutter 3.24 `removeRoute` 不完成 push Future，因此改为等待 `route.completed` 清理引用。 | 撤权、代次变化、旧回调不发请求、抛异常后可再次操作、重新登录后重新打开并重试检查通过。API 为注入实例，未运行真实 Agent。 |
| 6 | 正常网络/账号信息只保留底栏。页面内只显示服务器异常、后台停止等需要处理的提示；目录中存在非本机未同步远控 ID 时提供需处理提示。 | 正常状态条隐藏检查通过；没有重复的模式/账号条。 |
| 7 | 最近行删除缺失的时间、时长、路径和质量字段，仅呈现名称、ID、已返回的平台、在线状态及收藏标记。 | 无“暂无记录”重复文本，没有用强制中继选项猜测实际路径。 |
| 8 | 状态条末端的刷新和账号菜单右对齐；补回 `api.base.host`。窄窗大字体时工具独占一行且右对齐。 | 真实主机字符串和末端坐标检查通过。 |
| 9 | 全局按钮基准 40px；页头设备下拉与添加按钮使用同一高度，大字体允许相应增高。自有服务操作行图标和更多入口也为 40px。 | 页头两种控件实际尺寸等高检查通过，首屏服务操作可见。 |
| 10 | 服务卡读 `Get.find<RxBool>(tag: 'stop-service')`，不靠按钮文字推断；运行时“停止”改为描边，停止时“启动”保留主色；取不到状态仅显示“后台服务”。主题卡把上游三项单选控件转为紧凑下拉，只读取原值/标签并转发原回调和禁用条件。语言控件原上游字体为 15px、带下拉箭头，主题补齐上游颜色扩展和正常正文层级；预览不再用小字号的静态 ListTile 取值。 | 任意按钮文案下仍从状态源显示正确状态；未知态不猜测；主题值/原回调/固定选项禁用检查通过。设置页无需修改上游文件。 |
| 11 | 账号卡 ID 下显示实际所属账号；Console 卡补明确 ID，继续显示已有系统或最近在线信息。不添加不存在的网络/成员数据。常规账号卡默认从 208px 减至 200px；待同步或异常时按内容增加高度，大字体增加高度以避免溢出。 | 原连接、服务器指纹、大字体检查保持通过。 |
| 12 | 窄栏减少上下留白和条目间距；800×600 下六个导航项均完整可见。更矮窗口和双倍字体仍允许导航滚动。 | 逐项 hit test 与矩形检查：账号项底边不超过底栏顶边。 |
| 13 | 去掉全局 IconButton 的最大 32px 限制，最小点击区域 40px；不再缩小上游设置图标点击范围。 | 最小尺寸与无最大尺寸限制检查通过。 |
| 14 | 浅色 muted 调整为 `#71675B`，深色 muted 为 `#A59B8E`，浅色 success 为 `#276F46`、warning 为 `#85570E`，背景维持暖居色板。 | 浅色 muted/chrome 约 4.68:1，深色 muted/surface-2 约 5.49:1；浅色 success/soft 5.22:1、warning/soft 5.46:1。全部受检正常文字 token/对应背景均 ≥4.5:1。 |
| 15 | “需处理”排除已知 UUID 的本机；在线/离线优先使用实际绑定状态，没有绑定时使用目录的在线状态，因此未同步离线设备也进入离线筛选。 | 包含未同步本机、在线设备、离线待同步和在线待同步设备的分类检查通过。没有按名称/IP 猜测本机身份。 |

### 返工文件与上游边界

相对于上一轮，修改 `client/flutter/lib/` 下的 `homedesk_recent.dart`、`homedesk_status.dart`、`homedesk_theme.dart`、`homedesk_dashboard.dart`、`homedesk_navigation.dart`、`homedesk_family_devices.dart`、`homedesk_devices.dart`、`homedesk_services.dart`、`homedesk_settings_shell.dart`；新增 `homedesk_peer_menu.dart`。修改 `test/homedesk_hearth_test.dart` 的真实空态、菜单预览、设置预览断言及导出边界；新增 `test/homedesk_rework_test.dart` 的 14 项回归检查。

返工没有新增上游改动。累计上游仍只涉及 `desktop_home_page.dart` 中的最近页 import 和 recentBuilder 接线，两处均有 HOMEDESK 标记。没有修改 `desktop_setting_page.dart`、PeerTabPage、peers_view、peer_card、传输、编解码或加密文件；没有依赖升级、锁文件修改或 git 提交。

菜单 builder 的上游内部 widget 类型没有导出，因此动态读取其公开字段的适配集中在一个函数，并有三种卡片的契约测试。若后续上游改变这份接线，测试会暴露问题，运行时也有经典视图入口兜底。

### 实际验证结果

| 检查 | 结果 | 证据 |
|---|---|---|
| 修改范围 Dart analyze | 22 文件；0 error、0 warning、0 新增提示，保留既有 3 条上游 deprecated info；退出码 0。 | `client/target/hearth-rework1-analyze-final.log` |
| 全部 HomeDesk 测试 | 10 文件；74 通过、0 失败，较上一轮新增 14 项。 | `client/target/hearth-rework1-tests-all.log` |
| 预览导出 | 5 项通过；四页×两尺寸×浅深色共 16 PNG，加 1 张展开菜单 PNG；17 张尺寸检查通过，联系表和关键原尺寸图已查看。 | `client/target/hearth-rework1-preview-final.log`；`client/target/ui-hearth-preview/` |
| Windows x64 Release | `flutter build windows --release --no-pub` 实际通过，54.5 秒；沿用原配置和 Rust DLL。 | `client/target/hearth-rework1-windows-release.log` |
| 包内容与完整性 | 102 文件 CRC 全部通过；文件集合与原 HomeDesk-Windows-x64.zip 相同；Rust DLL 和 tunnel-runtime 与原包逐项一致。 | 更新后的 manifest |
| 工作区检查 | 两份锁文件 SHA256 与上一包一致；`git diff --check` 通过；中文写入编码已修复，无损坏占位文本残留。 | 工作区与 manifest |

预览索引为 `client/target/ui-hearth-preview/index.html`；菜单展开图为 `recent-menu-800x600-dark.png`。设置使用实际外壳和表单示例；展开菜单使用与生产菜单同型的注入项。生产动作和可用条件复用原菜单 builder，预览及测试均不读取用户配置或凭据。

同名便携包已更新为 `client/target/portal-artifacts/HomeDesk-Hearth-UI-Windows-x64.zip`，40742591 bytes。

新的 ZIP SHA256：`e17a6ea642155ac615290d112739106527878fd9c4967586fcdd895df424932b`。

Manifest 和校验文件分别为同目录的 `HomeDesk-Hearth-UI-Windows-x64.manifest.json`、`HomeDesk-Hearth-UI-Windows-x64.sha256`。上一轮 manifest 另保留为 `HomeDesk-Hearth-UI-Windows-x64.pre-rework1.manifest.json`；原 `HomeDesk-Windows-x64.zip` 未修改。

### 未覆盖项

15 条代码处理均已完成。按禁止启动/安装的约束，没有启动 HomeDesk 或真实隧道 Agent，没有结束现用进程或修改用户 AppData。真实菜单动作、Windows 快捷方式创建、远控连接、WOL、原生设置持久化和真实 Agent 重试没有实机点验；注入动作和状态回归、上游接线契约、Release 编译与 ZIP 校验已完成，不能将它们表述为实机操作通过。


## 2026-10-08 客户端源码发布前复核

暖居改版及返工代码纳入独立分支 `codex/hearth-client-ui`，目标是用户指定的 GitHub 仓库 `ymhaha/home-tunnel`。本仓库是 HomeDesk/RustDesk 客户端，服务端暖居代码位于另一独立分支 `codex/hearth-web-ui`；发布源码分支不代表创建正式软件 Release。

本次重新执行 22 个修改范围 Dart 文件的静态分析，0 错误、0 警告，保留 3 条既有上游弃用提示；全部 10 个 HomeDesk 测试文件 74 项通过；Windows x64 Release 编译通过（20.4 秒）。验证期间源文件摘要保持一致，Rust DLL、Cargo.lock 与 pubspec.lock 的摘要与返工交付 manifest 一致。

固定 gitleaks 8.30.1 扫描当前 Git 可提交文件通过：84 条精确上游示例基线，新增疑似密钥 0。另检查首次导出的 HomeDesk 主线提交历史，84 条命中均属于同一批已审阅上游示例；历史英文翻译文件两处示例虽行号不同，但与当前已冻结基线行逐字一致，没有修改仓库基线。已确认的真实部署域名、服务器 IP 和 Gitea 地址没有出现在提交文件中。

新日志和源文件摘要保存在 `client/target/github-client-publish-20261008/`，属于 Git 忽略目录。没有安装或启动客户端、修改用户 AppData 或执行真实远控；上一节列出的实机未覆盖项保持原结论。
