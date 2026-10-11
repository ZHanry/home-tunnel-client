# NestLink 14.0.1 维护版准备

以正式 14.0.0 客户端提交 `46e6194b5e0474292a175b6247b36572434fa9a4` 为基准。维护修复在非 Windows 的桌面 Dashboard 显示现有品牌和偏好菜单，使 Linux 的正常首页可以打开版本、语言和主题操作。手机使用原菜单，Windows 使用原标题栏；不修改账号、原生权限或设备能力协议。

产品、Go Agent、受管穿透和浏览器运行时统一为 14.0.1，最低服务端仍为 14.0.0。四端目标发行组合为 14.0.1；Flutter 版本为 `14.0.1+14000100`。基础 API v2、浏览器扩展和设备能力扩展继续使用冻结字节。历史 `build/tunnel/runtime.lock.json` 与 `packaging/agent-packages.lock.json` 为 10.1.0 导入来源，现代发行通过 `build/tunnel/build-runtime.py` 从当前源码构建，不改写这些历史来源摘要。

当前维护源码不得填写预估安装包或运行时 SHA。Client CI 从新的干净提交构建，运行时自动记录真实 Agent/helper/browser 字节摘要、来源提交及编译器；安装器和 DEB 记录各自载荷。签名、来源校验及验收都绑定新产物。

具体编译、Windows 备份与清装流程继续遵循 [桌面开发工作流](DESKTOP_14_LOCAL.md)。本机 Windows 每次安装仍须使用 `packaging/windows/install-local-clean.ps1`；本文件不授权跳过备份或覆盖安装。此次源码准备没有执行安装或 fixture 操作。

必须独立验证 Linux 正常外层窗口的偏好菜单和版本显示、升级保持、Windows CI 安装器及回归检查，并完成发行规则要求的原生联调场景。本次用户要求不重复执行本机 Windows 清装；本机未重装范围单独记录。widget 检查与以前的 14.0.0 验收不能替代这些新产物检查。生产服务端不升级。
