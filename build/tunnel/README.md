# Windows 本机穿透运行时

当前 `build-runtime.py` 使用固定 Go 1.27.2，从本仓库的 `agent` 模块构建 NestLink 14.0.0 穿透执行器，从根 Go 模块的 `cmd/homedesk-tunnel-helper` 和 `cmd/nestlink-browser-helper` 构建受管助手。Windows x64、Linux x64／ARM64 均使用当前提交及安全依赖锁；运行时记录来源提交、编译器版本、许可证和各文件 SHA-256。`helper/` 保留已导入分支的 Windows 模板用于追溯，产品使用 canonical cmd 源码。

```powershell
python build/tunnel/build-runtime.py --package '<锁定的 HomeTunnel-Windows-10.1.0-x64.zip>'
```

从干净的产品提交构建，产物位于 `client/target/tunnel-runtime`，清单记录 helper 来源 revision、脏树状态及实际二进制哈希。HomeDesk 使用同目录的副本，通过 Job Object、父进程确认和 stdin 门闩管理；退出 GUI 会停止此受管实例。独立 CLI/NAS/background Agent 按 `docs/INDEPENDENT_TUNNEL.md` 另行接入。

HTTPS origin、设备凭据、无重定向、单次登记、权限与撤权边界保持；助手只执行已经启用的服务，不将远控转入穿透。
