# 本机自动接入修订与 Windows 工程验证

## 原因与改动

原 HomeDesk 登录只建立未绑定设备的账号管理会话，本机没有隧道 Agent，客户端与网页均显示零设备。2026-10-02 用户确认登录后自动接入本机、默认不发布服务，设计契约更新为 `DESIGN.md 5.4.2`。

Windows 完整包包含固定 10.1.0 Agent 与受限助手。管理会话申请一次性接入码，经父进程校验和 stdin 门闩交给助手；设备凭据以 DPAPI 保存。身份按品牌、用户、账号 UUID 和 origin 隔离；已有设备必须属于当前账号目录。重开复用原设备，不创建服务。

进程以 Windows Job Object 管理。许可撤销和模式保存开始同步终止本实例进程，停止的票据拒绝迟到命令，操作序号阻止旧检查/登记回调清理新的运行进程。应用关闭或崩溃也停止子进程。没有启用上游 GUI、原生远控或系统服务，没有改动 RustDesk 协议、加密和编解码。

## 实际验证

- 固定发行包、Agent、Go 1.26.0 摘要核对与受限助手两项配置边界检查通过。
- Windows Rust/Flutter Release 完整构建和界面构建通过。
- 26 组账号 API 检查、31 项界面回归，以及接入身份复用、零默认服务、账号校验、未知结果与撤权检查通过。
- 指定 Windows 独立品牌程序真实登记本机，服务端设备表和客户端目录从零变为一，服务保持零。
- 设备凭据为 `dpapi:` 密文；登记完成后不存在未完成标记。
- 实际关闭客户端后，本程序目录中的助手与 Agent 进程数归零。重开恢复记住登录并复用原设备，设备数和已消费接入码数保持一。
- 心跳与远控连接分别标示；未启用的内网设备中心明确显示未启用。

以上是当前 Windows 用户、独立品牌包的工程验证，没有证明独立 Windows SID、其他架构、真实服务转发或跨网远控验收。服务端原生端口和服务子域 DNS 的缺口仍需处理；进程运行和 API 心跳不能代替转发结果。服务端只读核验真实设备记录，没有伪造设备计数或直接写数据库。

## 上游接线

`client/src/lib.rs` 注册模块；`client/src/ui_interface.rs` 接入受限命令和公开状态；`client/Cargo.toml` 启用既有 winapi Job Object 功能；`client/flutter/windows/CMakeLists.txt` 打包运行时；`connection_page.dart` 区分远控状态；`desktop_setting_page.dart` 保留此前版本点击解锁修复。接线均有 HOMEDESK 标记。

新增逻辑位于独立 `homedesk_tunnel_runtime.rs`、`homedesk_local_agent.dart` 和 `build/tunnel`。依赖版本未升级；真实地址、公钥、凭据、二进制与运行状态不入库。
