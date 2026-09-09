# Home Tunnel Client 6.1.1

- 修复 Windows 启动时额外控制台窗口：直接读取机器标识，不再调用 reg.exe；受管 Agent 的启动和配置校验均不创建控制台，日志保留在本地文件。
- 为 GUI EXE 嵌入图标和版本资源，并为原生窗口绑定图标。桌面窗口默认尺寸调整为适合服务工作区的大小。
- 新建连接提供 Web（HTTP/HTTPS）、RTSP、SSH、RDP、通用 TCP 和 UDP。公网端口在服务端已开放范围内自动分配，RTSP 使用 TCP 交错传输。
- 显示服务端版本、端口开放和账号权限限制；保留版本冲突与端口耗尽等可恢复错误。
- Windows 发布继续执行 Defender 扫描、安装／卸载检查，并新增 EXE 图标、GUI 子系统和实际窗口图标验证。

TCP/UDP 创建需要服务端 6.1.0。管理员需启用实际公网端口范围；普通用户还需获得控制台中的自助创建授权。[连接类型说明](https://github.com/ZHanry/home-tunnel-client/blob/v6.1.0/docs/CONNECTION_TYPES.md)。

Windows 使用标准 Inno Setup 安装器。未配置 Authenticode 代码签名，系统的发布者／信誉提示与 Defender 恶意软件扫描是不同检查。原 6.0.0 EXE 保持撤回。

- 新建连接的标题和空状态统一使用通用文案，避免 RTSP/TCP/UDP 流程仍显示 HTTP。
