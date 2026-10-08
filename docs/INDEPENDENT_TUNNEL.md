# 独立 CLI / Agent

HomeTunnel-CLI-Agent-11.0.0-rc.1.zip 包含 Windows x64、Linux amd64/arm64、macOS amd64/arm64 子目录。选择相应目录，不混用不同架构的 Agent；CLI 固定检查随包 Agent 的 SHA-256。CLI 为本次源码构建的 11.0.0-rc.1，Agent 保持经过校验的 10.1.0 原始字节和版本。

先在管理台创建设备接入码，再运行 `home-tunnel-client enroll --state <路径> --server https://你的管理台 --device-name <名称> --enrollment-code-file <受保护的接入码文件>`。保护文件与父目录，接入后删除接入码文件。启动 `home-tunnel-client run --state <同一路径> --agent <随包 Agent 路径>`。`status`、`doctor` 和 `support-bundle` 保持可用。

Windows 可在同目录执行 `powershell -File independent-tunnel.ps1 -Action install -StatePath <独立状态文件>`。任务在当前用户登录时启动，关闭 HomeDesk 后继续运行；`stop` 暂停，`uninstall` 删除任务，均不删除设备状态。GUI 中的受管 Agent 跟随窗口，应避免为同一设备状态同时启动两个 Agent。

Linux/NAS 使用包内 `packaging/nas` 模板与持久卷；也可通过 systemd 以专用用户执行上述 `run` 命令，使用 `Restart=on-failure`，状态目录 0700、状态文件 0600。撤销或租约失效仍会按既有策略停止服务。macOS 可通过 launchd 管理同一独立命令，保持状态目录只对当前用户可读。

HTTP/HTTPS 与受控 TCP/UDP、端口池、权限、ACL、配额、流量治理及诊断继续由现有协议处理。远控配置、直连失败与这些独立进程互不影响。此包负责服务发布；P2P 远控由 HomeDesk 安装包提供。
