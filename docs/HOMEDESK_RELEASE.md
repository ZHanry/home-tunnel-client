# HomeDesk 11.0.0-rc.2 候选发行

修复 RC.1 的 Windows 每用户升级误拦截：仅遗留旧服务程序、没有运行服务时，不再因为无管理员服务控制权限而拒绝安装。以实际可替换文件为最终检查条件；正在运行的 GUI、Agent 或服务仍会阻止覆盖，需退出或停止后重试。中英文提示与安装语言一致，已有账号和隧道配置保留。五个真实 Inno 隔离场景覆盖原版误拦截、遗留文件升级、新装以及运行中服务/GUI 的拒绝覆盖；构建材料保存检查结果。

整合暖居 Rust/Flutter 客户端与完整 Go/FRP 内网穿透。远控必须认证加密、P2P 直连，失败终止；无中继和供应商回退。普通隧道保留 HTTP/HTTPS、受控 TCP/UDP、权限、端口池、ACL、流量治理、诊断和独立 CLI/NAS/background Agent。

Windows x64 安装器包含原生 HomeDesk 与受管 helper，未做 Authenticode 签名。CLI 合集覆盖 Windows x64、Linux amd64/arm64、macOS amd64/arm64；Agent 仍是锁定的 10.1.0 原始字节。macOS/Linux 原生 GUI 尚未发布。通用包没有内置服务器地址、密钥或账户；按 README 配置自托管 hbbs 和 HTTPS 管理台。旧远控不作为兼容目标。

材料包包含 AGPL 对应源码、精确子模块、原生库/依赖许可证、构建证据和 GitHub 身份签名。SHA256SUMS 覆盖所有公开包，材料内 BUILD.json 绑定源码 revision 与附件哈希。

发布前更新了兼容的 TLS、证书解析、缓冲区和域名处理依赖；版本与尚未发行平台的依赖告警范围见 [依赖审查](HOMEDESK_DEPENDENCIES.md)。材料包记录实际 Windows/Android 依赖树，不将全仓安全扫描通过当作没有依赖漏洞的证明。

跨网络 NAT、长期媒体、Android 真机和完整安装后远控验收尚未完成。有限的源码/单元/界面/构建验证不能证明所有网络可用；受限网络打洞失败会停止。候选与历史 10.x 验收分开记录，不晋升稳定版。
