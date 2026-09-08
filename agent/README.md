# 受管隧道 Agent

Windows、macOS 与 Linux 客户端共用的受限 FRP 引擎，由 GUI / CLI 核心启动和监督。
它只执行受管配置，不提供通用 FRP 命令行入口。

本目录是独立 Go 子模块，可以在这里执行 `go test ./...`。
正式打包使用打包脚本中固定的 FRP 源码提交、归档哈希与工具链，以复现经过审查的 Agent 二进制。
Windows CI 会比较 `expected-sha256.txt`；改变 Agent 时需要重新验证和记录哈希，不能直接跳过检查。

Agent 的版本与客户端版本分别维护。FRP 许可与第三方声明位于本目录。
