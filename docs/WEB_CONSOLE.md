# Web 主控可行性记录

2026-09-08。结论：**当前仓库的 OSS 方案尚不具备经过验证的自托管浏览器远控客户端**。本轮的 Home Console 是设备管理台，不能在浏览器内显示远程桌面。

官方 [Web Client V2 说明](https://rustdesk.com/blog/rustdesk-web-client-v2-preview/)列出公共 Web 入口和由 Server Pro 提供的自托管 Web 入口；[官方 FAQ](https://github.com/rustdesk/rustdesk/wiki/FAQ)说明 Server Pro 的自托管 Web 客户端定制。仅放行 hbbs/hbbr WebSocket 端口并不会自动提供完整 Web 客户端。

项目约束为免费 OSS、纯内网，故本轮没有接入公共 Web 服务、购买 Pro 或开放额外端口。保留 Windows/Linux/ARM64 原生主控；Android 官方主控也需要另行设备验证。

后续若更换这项边界，应先提供可离线部署的 Web 客户端来源与许可，再在两台真实设备上验证；不能将管理台页面完成算作 F9 完成。
