# Home Tunnel Client 6.0.1

修订 Windows 安装器与发布验证流程。原 6.0.0 EXE 被 Microsoft Defender 报告为 `Trojan:Win32/Sabsik.FL.A!ml`，已经撤下；请使用本版本的安装包。

- 用固定版本的官方 Inno Setup 生成标准安装器和原生卸载程序，移除自制 Go 自解压安装器、PowerShell 快捷方式生成和批处理卸载方式。
- EXE、ZIP、GUI、Agent 均需通过 Microsoft Defender 扫描；缺少扫描、命中威胁、病毒库过期或文件哈希改变会阻止发布。
- 增加实际安装、已安装文件哈希和卸载检查。
- 分别记录 EXE 与 ZIP 的 GitHub 构建来源，扫描记录与发布文件哈希逐项绑定。
- 安装包和便携包补齐项目与第三方许可文件。

检测报告仅说明所记录的引擎、病毒库与扫描时间下的结果，不代替其他安全产品的判断或 Microsoft 的误报复核。Windows 代码签名与 SmartScreen 信誉提示是另外的检查；本版本未配置 Authenticode 证书。

下载附件继续只提供各平台安装包与 `SHA256SUMS.txt`，完整验证记录在对应 Actions 工作流中。[Windows 发布检查说明](https://github.com/ZHanry/home-tunnel-client/blob/v6.0.1/docs/WINDOWS_RELEASE_CHECKS.md)。
