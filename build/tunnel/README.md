# Windows 本机穿透运行时

当前 `build-runtime.py` 从本仓库根 Go 模块的 `cmd/homedesk-tunnel-helper` 构建助手，固定 Go 1.27.0。只提取经过 SHA-256 核验的原始 10.1.0 Windows Agent 与许可证，不使用历史 GUI、服务或远控程序。`helper/` 保留已导入分支的 Windows 模板用于追溯，产品使用 canonical cmd 源码。

```powershell
python build/tunnel/build-runtime.py --package '<锁定的 HomeTunnel-Windows-10.1.0-x64.zip>'
```

从干净的产品提交构建，产物位于 `client/target/tunnel-runtime`，清单记录 helper 来源 revision、脏树状态及实际二进制哈希。HomeDesk 使用同目录的副本，通过 Job Object、父进程确认和 stdin 门闩管理；退出 GUI 会停止此受管实例。独立 CLI/NAS/background Agent 按 `docs/INDEPENDENT_TUNNEL.md` 另行接入。

HTTPS origin、设备凭据、无重定向、单次登记、权限与撤权边界保持；助手只执行已经启用的服务，不将远控转入穿透。
