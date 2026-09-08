# 参与开发

本仓库负责GUI、CLI、客户端核心、Agent 与各平台打包。整体架构与任务归属见[项目总览](https://github.com/ZHanry/home-tunnel)。

## 提交方式

1. 从 `main` 建立聚焦单一问题的分支。
2. 在 PR 中说明问题、修改后的行为与验证结果。
3. 行为变化更新相关测试；文档、接口或配置变化更新对应说明。
4. 跨组件改动列出相关仓库与提交，完成所需联调后再合入。

## 开发环境和检查

Go 1.26.6；Linux 完整 GUI 检查需要 GTK 3、WebKitGTK 4.1、pkg-config 与 GCC，macOS 需要 Xcode Command Line Tools。
Windows 使用 WebView2。安装平台依赖后执行：

```sh
go test ./...
go vet ./...
```

Agent 子模块可以独立执行 `go test ./...`。正式打包仍使用固定的 FRP 源码和可复现的 Agent 构建路径。
桌面页面检查使用 Node.js 24 与 pnpm 11：

```sh
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
pnpm run lint
pnpm run test:browser
```

修改安装器、托盘或系统服务时补充对应平台的实际运行结果。源码测试通过不等于系统集成已验证。

## 约定

- 内部测试期间可以调整接口和配置，但需说明影响和重新验证方式。
- 安全相关改动说明身份、租约、Agent 配置校验或公开入口的影响。
- 不提交密钥、设备状态、测试机私有配置或生成的安装包。
- 使用代码仓库自己的 CI 与发布流程，不要求相邻检出另一个源码仓库。

疑似漏洞使用 [SECURITY.md](SECURITY.md) 中的私密入口。提交内容按 [Apache-2.0](LICENSE) 分发。
