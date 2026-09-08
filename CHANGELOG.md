# 开发记录

## Unreleased · 内部测试

- 当前仓库负责GUI、CLI、客户端核心、Agent 与各平台打包。
- 统一开发文档、源码构建入口和内部测试状态。
- 自动化检查与真实环境反馈共同用于后续功能完善。

数字版本与已有标签用于识别内部构建。项目尚未建立正式稳定版本和长期支持政策。
后续用户可见变化在这里记录，并注明影响到的接口、配置和测试步骤。


## 5.0.1 · Security test build

- Added per-session local UI authorization, loopback/origin checks and frame protection.
- Prevented redirect replay and API origin/path escapes; redacted remote errors and CLI logs.
- Agent 5.0.1 uses go-ntlmssp v0.1.1 in both development and packaged builds, with a reproduced binary hash.
- Security CI now checks open CodeQL findings after analysis.
