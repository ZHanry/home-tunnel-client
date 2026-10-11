# NestLink 14.0.1 维护版

本维护版恢复 Linux 正常首页的版本入口，沿用 NestLink 品牌和顶部偏好菜单，可切换主题、语言并打开“版本与下载”。共享 Flutter/Rust 工程同步安全授权诊断和窄屏布局；原生确认需要重试时保留已提交 GUI 凭据，允许继续恢复确认流程。

设备登录令牌刷新先完成原生授权同步再交给消费者。旧令牌 HTTP 401 的有界重试限于同一 origin、设备、会话和 epoch 内的已验证新 revision；退出、账号切换、网络错误或真实撤权仍使旧授权失效。版本及受管运行时为 14.0.1，Flutter build number 为 `14000100`，最低服务端为 14.0.0。安装身份、配置 namespace、Logo 与冻结认证/版本扩展保持兼容。

This maintenance release restores the Linux dashboard version entry and adds safe authorization guidance and narrow-layout support. Committed GUI credentials remain recoverable when native confirmation needs retry. Pending C refresh, input and revocation scenarios remain not_run after the owner stopped regression.

C 产物源码为 `7ca0fd7186586965921e48beef2dbb2ae44fc895`，来源为成功的 [Client CI 38172051186](https://github.com/ZHanry/home-tunnel-client/actions/runs/38172051186)（attempt 1）。本版实际验收见 [acceptance-14.0.1.json](release/acceptance-14.0.1.json)。

| C 固定产物 | SHA-256 |
| --- | --- |
| NestLink-Setup-14.0.1-x64.exe | `a37e5aea80368c8d39fdbd82f621d936aea4783fa67f2b907ecc07f8faad725e` |
| NestLink-Linux-14.0.1-x64.deb | `e65e748eff2d48fb1ccacc60245ce28f30d2b2b1d47edb49496dceebea272c4f` |
| NestLink-Linux-14.0.1-arm64.deb | `6fcfb2eb64c1432edc0546ee0173d4bccdb8de4d1c71f3305a77a87f5dbb0dea` |

产物源码提交用于绑定已构建的 C 运行时字节；正式 `v14.0.1` 标签提交还会包含本版验收 JSON 与两份发行文档。本版 owner waiver 仅允许三个发行文档与 `scripts/homedesk-release.py`、`scripts/test_homedesk_release.py` 两项政策文件相对产物源码变化；逐场景绑定这两份政策的实际 SHA-256，运行时字节保持固定。验收 `source_revision/build_run` 保留 C 产物来源，正式 Materials 的 `BUILD.json.revision/build_run` 另记实际正式提交与 release.yml run，`payload_source_revision` 保留 C 来源；正式 Materials、附件签名和校验和在真正发布后独立核验，不宣称文档提交重新构建了产物。

此前 A/B 的故障、安装链和原始尝试单独保留，13.0.0、14.0.0 及 A/B 结论不替代 C。用户取消后续远控回归并要求直接发布。未执行的 C 运行时场景明确记录为 not_run 和 owner waiver，不推断通过；通过场景才绑定实际执行原件。

本次仅更新 GitHub 发行、下载站和自动更新信息；正在运行的生产服务端保持原版本。

The acceptance source and candidate build run identify the exact C payload bytes. Formal documentation commits and release-workflow runs remain separate. Unfinished runtime scenarios remain not_run under the explicit owner waiver. Only GitHub releases, downloads and update information change; the running production server is not upgraded.

## 本版实际验收范围

状态：`accepted_with_waivers`。用户授权原话：`不需要远控回归,直接做后面的`。

Exact C build provenance and payload hashes are verified. Client exact-source CI provenance and payload hashes are verified. The Windows installer has no Authenticode signature. Formal Materials Sigstore verification is performed separately after publication and cannot replace platform executable signing. Pending installed-product remote, authorization, account and tunnel runtime scenarios are not_run after the owner requested direct publication. The Android C overlay is the sole passed required installed-product scenario. Existing local Linux overlay evidence remains a separate completed check. No production server deployment or Windows reinstallation is performed.

- **account-revocation**：not_run — The owner stopped pending remote-control regression and requested direct publication. This unfinished runtime scenario remains not_run; exact-source CI and payload/signature verification do not constitute installed-product runtime acceptance.
- **browser-screen-input**：not_run — The owner stopped pending remote-control regression and requested direct publication. This unfinished runtime scenario remains not_run; exact-source CI and payload/signature verification do not constitute installed-product runtime acceptance.
- **installed-native-p2p**：not_run — The owner stopped pending remote-control regression and requested direct publication. This unfinished runtime scenario remains not_run; exact-source CI and payload/signature verification do not constitute installed-product runtime acceptance.
- **managed-tunnels**：not_run — The owner stopped pending remote-control regression and requested direct publication. This unfinished runtime scenario remains not_run; exact-source CI and payload/signature verification do not constitute installed-product runtime acceptance.

签名范围：Client exact-source CI provenance and payload hashes are verified. The Windows installer has no Authenticode signature. Formal Materials Sigstore verification is performed separately after publication and cannot replace platform executable signing.

准备过程实际记录（不替代运行时回归）：

- **linux-c-payload-overlay**：`passed` — Exact C Linux x64 payload installed with identity, configuration and keyring preserved; GUI and media not run.
- **private-fixture-c-conversion-preflight**：`failed_before_dispatch` — The private application-image transition refused its shim identity preflight before any dispatch. Existing B application containers and FRPS remained unchanged. No C GUI or runtime fixture acceptance is asserted.

## UI 与健康观察

本版 C 产品 UI 与健康回归未完成；保留官网真实 14.0.0 图库、原 capture manifest 和 SHA-256，并明确标注 14.0.0 截图参考。没有 C 真实界面矩阵，不把历史像素改版本冒充新版截图。此前 B 的中文 remote placeholder 和 gatewayUnhealthy 观察保留为历史记录。本版 C 的中文初次打开、EN↔ZH 既有表单切换及健康结果须按实际原件判断，文档不会据源码 CI 或截图 helper exit 0 推断通过。英文管理区“策略队列/备份”的混合语言观察仍保留；未覆盖的管理员项与 FRPS 健康没有本版通过结论。

## 限制与未测范围

Windows 14.0.1 本机清装与 GUI 未实测；安装器由 CI 验证且没有 Authenticode，Materials 的 Sigstore 签名不能替代平台可执行文件签名。Linux ARM64/Wayland 实机媒体、实体 Android、运营商 NAT、长期媒体，以及音频/文件/剪贴板等未测范围继续如实保留。Android 被控方向、PIN/`trusted_devices` 与安装归属不宣称全部通过；具体边界以下方本版 unverified 原列表为准。历史安装链不等同于直接公开 13→C，synthetic 迁移不等同于生产原数据库升级。

既有审查记录的 18 个 open 依赖告警（3 high、7 medium、8 low）及具体未修复依赖继续保留；没有通过版本同步关闭或 dismiss 告警，历史审查不是新的动态可达性或利用测试。Linux `users` 0.10.0/0.11.0、受影响的 `libgit2-sys` 构建输入、其他 glib/users 与 atty 风险没有由本维护修复消除。

Windows local installation/GUI, physical Android/ARM64, Wayland media, carrier NAT and long-duration media remain outside the tested scope unless the original C acceptance explicitly records otherwise. Windows has no Authenticode signature, and the existing dependency advisory scope remains unresolved. Production deployment is not part of this release.

本版原验收 unverified：`account-revocation`, `browser-screen-input`, `carrier-network-nat`, `current-c-product-ui-matrix`, `installed-native-p2p`, `local-windows-14.0.1-reinstallation`, `long-duration-media`, `managed-tunnels`, `physical-android-device`, `physical-linux-arm64-gui`。

本机日后安装仍遵循 `packaging/windows/install-local-clean.ps1` 的备份与清装要求。历史完整发行说明：[14.0.0 HOMEDESK_RELEASE.md](https://github.com/ZHanry/home-tunnel-client/blob/v14.0.0/docs/HOMEDESK_RELEASE.md)。
