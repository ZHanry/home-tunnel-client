# 客户端候选构建与发行

当前稳定发行为 10.1.0，使用新增的冻结契约 `api-v1.5.0`。客户端锁文件已从核验后的不可变 API 标签导入，复现导入须用 `scripts/import-remote-contract.py <服务端检出> --revision <标签提交> --published-ref api-v1.5.0` 冻结到该提交；锁文件仍为 proposed 的候选只能用于测试，不能发布。最终验收前先冻结版本、协议、源码和依赖；相关字节改变后需要新候选包及相应重测。

## 先构建，不创建标签

入口为已注册的 [release.yml](../.github/workflows/release.yml)。在开发分支手动 dispatch，设置 `candidate=true`，`revision` 为该分支当前完整的 40 位 SHA。工作流拒绝标签、脏工作区、移动后不匹配的 SHA 和其他调用入口。

入口调用 [client-candidate.yml](../.github/workflows/client-candidate.yml)，以只读仓库权限构建 Windows 安装器/便携包、Linux/macOS amd64/arm64 包、Windows 共享 SDK 和同源 Android x64/arm64 SDK。不创建标签、合并 main 或生成 Release。候选允许明确标注的 API 草案，正式发布拒绝草案。

Windows 顺序为原生 worker 构建与授权测试 → worker/Agent 平台签名（如已配置）→ 将最终 worker 哈希固定到 GUI → GUI 签名 → 打包和安装器签名 → Defender 扫描和安装/卸载检查。未配置平台证书时如实记录 unsigned；半配置签名环境失败。Sigstore 和 GitHub 构建证明不能代替 Authenticode 或扫描。

收集作业校验原始包、SDK、许可证、扫描与安装报告，生成不可变 `client-candidate.json`，绑定源码 SHA、调用/签名工作流、run ID/attempt、全部文件摘要和锁定服务端。`acceptance_complete` 始终为 false。清单经 Sigstore 签名和 GitHub 构建证明封存，包保留原始签名与证明；`candidate-assets` 保存 90 天。

调用方是 `.github/workflows/release.yml`，签名方是 `.github/workflows/client-candidate.yml`。记录实际成功 run ID、artifact ID 和 GitHub 返回的 ZIP SHA-256。

只需要 Android SDK 时，既有 `android-webrtc.yml` 的 `candidate=true` 入口仍调用 `android-sdk-candidate.yml`。其清单和签名身份独立，消费者必须按实际类型验证来源，不能混用证据。

## 下载与本地验收

[fetch-client-candidate.py](../scripts/fetch-client-candidate.py) 接受精确 `--run-id`、`--artifact-id`、`--artifact-sha256`、`--revision`、`--version` 和全新 `--output` 目录。省略 `--acceptance-revision` 仅用于下载测试包。

下载器核对成功 dispatch、源码、artifact 摘要、安全 ZIP 路径、全部文件摘要、Sigstore 身份及同一 run/attempt 的构建证明。不能重编译、重新签名或重新打包替代候选文件。

按 [CLIENT_ACCEPTANCE.md](CLIENT_ACCEPTANCE.md) 完成本地虚拟机全部适用验收。开发单测、浏览器模拟及共享核心测试不能代替最终安装包上的媒体、输入、安全桌面、文件、音频和网络测试。

[基础原生验收](../tests/remote-native/README.md) 使用独立桌面、分发 worker 的真实 SHA、干净客户端源码和 `tests/remote-native/server-lock.json` 指定的服务端。服务端须重新构建。运行 `scripts/test-remote-native.mjs`，传入 `--worker`、`--sha256`、`--server-root`、`--report-dir` 及 `--input chromium`，把实际报告保存为 `windows-remote-native-acceptance.json`。

报告须证明持续真实视频、双端 UDP/DTLS、键鼠/中文输入、epoch 拒绝、撤销、心跳丢失和 worker 崩溃后两秒内释放。仅 view-only、跳过、伪引擎或合成视频不能通过。安全桌面拒绝补发释放时须保留释放债务，恢复前禁止新输入，不能伪报跨越系统限制。该基础报告不能替代完整矩阵。

## 长时间测试与复扫

原始 `windows-defender-scan.json` 永不覆盖，其时效相对于签名候选创建时间验证，因此 24 小时在线测试不会使构建记录失效。

发布前，用更新后的 Defender 对同一安装器、ZIP、GUI、Agent、worker 复扫，生成独立 `windows-final-defender-scan.json`。复扫晚于候选创建、距发布不超过一天，病毒库在扫描时不超过两天。过期只需复扫原文件并更新独立收据，不重建候选、不修改旧时间戳。安装器、ZIP、实际安装组件的摘要必须匹配。

## 验收通过后发布原文件

审阅真实证据后，把收据提交到入口仓库 `validation/client/<client SHA>/`，记录包含收据的完整 main SHA。另一个仓库的收据不会改变客户端 SHA。未通过全部门槛时不创建正式标签、不合并产品 main、不清理开发分支。

验收通过后，代码归入 main，并在同一候选 SHA 建立版本标签。该提交的 Quality Gate、CodeQL、Secret scan 必须通过；REST 与远控锁必须指向同一干净、已发布的不可变协议标签。不能在候选验收之后修改源码或依赖来适配标签。

在该标签 dispatch `release.yml`，保持 `candidate=false`，填写 `build_run_id`、`artifact_id`、`artifact_sha256`、`acceptance_revision`。发布不接收内联验收 JSON、不使用平台签名密钥、不编译包或重建 SBOM；它重新验证候选和收据，复制原文件，增加独立发行清单和完整校验和的 Sigstore 签名。

原始候选清单及其 `acceptance_complete=false` 不变；完成验收由独立 `client-acceptance.json` 表达。Release 保存包、SDK、许可证、SBOM、原始及最终扫描、安装/验收摘要、来源、构建证明、校验和及签名。发布后下载核对附件，再按客户端/SDK → Android 与服务端 → 入口仓库更新下载。历史版本和协议标签保留。
