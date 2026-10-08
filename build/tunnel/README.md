# Windows 本机隧道运行时

使用 `runtime.lock.json` 锁定的上游源码、Windows 发行包和 Go 1.26.0。`build-runtime.py` 将本目录受限助手复制到上游独立临时构建目录，复用设备登记、心跳、同步和官方 FRP Agent。设备凭据由上游 Windows DPAPI 存储实现处理，不打包上游 GUI、服务或原生远控程序。

在准备好离线源码、发行包和 Go 工具链后执行：

```powershell
python build/tunnel/build-runtime.py --source '<锁定源码目录>' --package '<固定 Windows ZIP>' --go '<Go 1.26.0 的 go.exe>' --executable homedesk.exe
```

独立验收命名空间使用 `--executable homedesk.exe`。产物在 `client/target/tunnel-runtime`；随后按对应品牌构建 Windows 客户端，CMake 会将该目录复制到程序包。助手固定父程序名称，原生层核验运行时清单、Agent/助手 SHA256 和普通文件路径；不能混用不同品牌产物。

原生层通过 Job Object 和 stdin 门闩管理生命周期；助手确认真实父进程映像后才读入许可。控制请求与公开配置均限制在批准的 HTTPS origin，FRPS 主机必须与之相同，证书必须存在。所有代理和重定向关闭。登记结果未知保留标记并停止自动重放；未发出登记请求的发现错误可明确报告为发现失败。

助手不会创建服务，设备运行时只接收已由用户创建并启用的本机服务。修改后台助手后重新构建运行时清单；修改原生进程管理后重新编译 Rust DLL。纯 Dart 界面修改可只重建 Flutter 前端。
