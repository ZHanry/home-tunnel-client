# AGENTS.md — HomeDesk 开发规则

## 项目是什么

基于 RustDesk fork 的家庭自建远控（默认纯内网，可选显式启用自建公网 P2P；服务端 + 客户端 + 自研管理台 console）。
完整设计方案见 `docs/DESIGN.md`，它是唯一需求来源；实现与方案冲突时，以 `DESIGN.md` 为准。

## 技术底座

- `client/` = fork 自 rustdesk/rustdesk（AGPL-3.0，git subtree 固定 tag 引入，保留上游历史）
- `server/` = 上游 hbbs/hbbr 容器（一行不改）+ 自研 console（Rust axum + SQLite + askama，单二进制）
- `build/config.toml` = 品牌及网络默认值的构建期注入口；服务器/公钥/网段/模式仅可由它或本机受控高级设置显式配置，仓库只提交 `config.toml.example`

## 硬性约束（违反即打回）

1. 最小侵入：`client/` 上游代码每处修改加 `// HOMEDESK:` 标记；新逻辑放独立文件/模块；禁止重排或重新格式化上游代码——必须保住季度 rebase 上游安全补丁的能力
2. 不碰核心：传输协议、编解码、加密逻辑零改动；只做配置、UI、外围模块
3. 配置外置：品牌/服务器/Key/网段/模式禁止硬编码；构建默认走 `build/config.toml`，运行时变更只允许本机受控高级设置显式校验并保存
4. 零密钥入库：真实 IP/公钥/Token 只出现在未跟踪的本地配置中；example 文件仅放占位值；CI 跑 gitleaks，检出即失败
5. console 质量线：所有 API 带单元测试；单二进制；零额外运行时依赖
6. 依赖锁定：`Cargo.lock` 与镜像 tag 固定版本；依赖升级单独开 PR
7. 双模式网络边界：客户端默认 `lan_only`，不发起任何公网请求；只有构建默认或本机受控高级设置显式选择并通过整组配置校验的 `self_hosted`，才允许访问自建公网 hbbs/hbbr、必要 DNS、经审核的打洞服务及当前连接需要的对端公网地址。校验失败保留上一份有效配置，不得静默改模式或扩大权限；两种模式始终禁止上游公共服务器回退、遥测和自动更新

## 工作方式

- 每个任务先读 `docs/DESIGN.md` 对应章节再动手
- 每 PR 三件套：目标平台编译通过 + `tests/smoke.md` 勾选记录 + 变更说明（动了上游哪些文件、为何）
- 小步提交：`feat(client):` / `feat(console):` / `chore(build):` 前缀；正文列出上游改动文件清单
- 注释、文档、UI 文案一律中文
- 方案有歧义时：按上游 RustDesk 默认行为实现，代码处留 `TODO(design)` 注释，汇总到 `DESIGN_QUESTIONS.md` 等待确认
