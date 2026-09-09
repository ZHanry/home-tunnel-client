# 客户端运行与排查

当前使用正式发布构建。先按 [README](../README.md) 生成包含 Agent 的完整包，并记录服务端和客户端提交。

## 桌面 GUI

启动 `home-tunnel-gui`，填写服务端 HTTPS 根地址，登录后注册设备并管理连接。
关闭窗口会隐藏到托盘，退出入口结束程序。遇到 Agent 缺失或校验错误时，核对完整包与可执行文件路径。

桌面状态的默认位置：

| 平台 | 状态文件 |
| --- | --- |
| Windows | `%APPDATA%\HomeTunnel\state.json` |
| macOS | `~/Library/Application Support/HomeTunnel/state.json` |
| Linux | `$XDG_DATA_HOME/home-tunnel/state.json`，未设置时为 `~/.local/share/home-tunnel/state.json` |

`HOME_TUNNEL_STATE_PATH` 和 `HOME_TUNNEL_AGENT_PATH` 可覆盖默认位置。
状态文件含设备凭据，不应复制到公开 Issue；它不是可随意分享的日志。

桌面管理接口还要求当前窗口的临时会话授权，并拒绝跨站请求和非本地连接。
通过安装的客户端启动窗口；手动打开没有会话授权的本地页面不会获得操作权限。
私有状态目录下的 `.ui-session` 用于同一用户的窗口唤起，退出时清理；不要分享窗口会话地址或该文件。

## Linux headless

在目标主机解压构建产物，进入该包目录：

```sh
sudo ./install.sh
sudo home-tunnel-enroll
sudo systemctl status home-tunnel-client
sudo journalctl -u home-tunnel-client -n 100 --no-pager
sudo -u home-tunnel home-tunnel-client status --json
sudo -u home-tunnel home-tunnel-client connection ls
```

交互式注册助手读取账号信息并启动服务。默认状态文件为 `/var/lib/home-tunnel/state.json`，归专用服务账号所有。

## macOS headless

进入解压后的包目录安装并注册：

```sh
sudo ./install.sh
sudo home-tunnel-enroll
sudo launchctl print system/com.hometunnel.client
sudo tail -n 100 /usr/local/var/log/home-tunnel/client.log
sudo -u _hometunnel home-tunnel-client status --json
```

默认状态文件为 `/usr/local/var/lib/home-tunnel/state.json`，服务由 `_hometunnel` 账号运行。
launchd 的重启和文件权限机制与 Linux systemd 不同，需要在实际 macOS 主机验证。

## CLI 使用约定

命令应在拥有对应设备状态的账号下运行，或显式指定 `--state`。例如：

```sh
home-tunnel-client connection ls --state /path/to/test-state.json
home-tunnel-client connection add --name demo --subdomain my-demo --local-port 8080 --state /path/to/test-state.json
home-tunnel-client connection set --id CONNECTION_ID --enabled=false --state /path/to/test-state.json
```

使用 `home-tunnel-client help` 查看入口。前台调试通过 `run --state ... --agent ...` 明确指定状态和 Agent。
不要在已有后台进程运行时，对同一份设备状态重复启动另一个监督进程。

## 建议验证顺序

1. 本地服务能否从客户端主机直接访问。
2. 服务端 HTTPS、账号登录与设备注册。
3. HTTP 连接的创建、暂停、恢复与目标修改。
4. 客户端重启、网络短暂中断与会话 / 授权变化。
5. GUI 的窗口托盘行为、headless 的服务启动与日志。

TCP / UDP 只能使用管理员授权的端口，相关应用需要自己的认证和加密。
跨版本配置与状态变化记录在升级说明中；升级前保留配置和数据备份。

## 安装包更新

GUI 当前检查客户端仓库的稳定 Release 入口；内部预发布包以手动安装和验证为主。
headless 包也通过明确的安装流程更新。正式对外分发前再确定完整的自动更新体验。
安装和更新以安装包自身的版本、说明和哈希为准，不依赖项目入口仓库的聚合下载。
