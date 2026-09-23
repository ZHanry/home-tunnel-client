# 发布流程

8.0 按维护者确认直接发布 `8.0.0` / `v8.0.0`，`compatibility.json` 的阶段为 `public-release`。安装包、界面和标签必须使用相同版本。正式发布不等于所有规划功能都已实现：未完成或未验证的平台能力必须在界面和发行说明中如实呈现；不得把开发测试替代为完整实机验收。

客户端采用“构建、实机验收、发布同一产物”的两阶段流程。发布入口是 [release.yml](../.github/workflows/release.yml)，最终校验由 [scripts/release.py](../scripts/release.py) 执行。原生核心单元测试、授权测试、Go 控制面测试和浏览器模拟测试都不能代替实际 Windows worker 的媒体与输入验收。

## 1. 固定源码并构建候选产物

1. 将最终代码提交到 `main`，等待该提交的 Quality Gate、CodeQL、Secret scan 全部通过。原生依赖使用 `native/remote/remote-deps.lock.json` 的固定版本；验收服务端使用 `tests/remote-native/server-lock.json` 的固定提交。
2. 在这个提交上创建版本标签。标签 push 运行构建阶段，生成 Windows 安装器、ZIP、Linux/macOS 包、扫描与安装报告、原生构建来源、依赖许可证等材料。
3. 构建阶段写出 `verification_stage: "prepared"` 的发布清单，保存为 Actions 产物。`prepared` 表示待实机验收，不能直接发布；不得预填原生验收成功报告。
4. 记录本仓库 `release.yml` 的成功构建 run ID、标签、完整提交 SHA 和构建产物身份。后续发布必须下载这个运行的原始产物，不能另行重新编译、重新签名或重新打包来替代。

Windows 构建顺序必须是：原生 worker 构建和授权/守护进程测试 → worker 与 Agent 的平台签名（如已配置）→ 将最终分发字节的 SHA-256 固定到 GUI → GUI 签名 → 打包和安装器签名。验收对象是此后分发的 `home_tunnel_remote_host.exe`，不能用签名前或本地临时编译的同名文件替代。

没有平台证书时必须保留实际的 unsigned 状态；半配置的签名环境会阻止发布。GitHub 构建证明、哈希校验和 Sigstore 封存均不能替代 Authenticode 或杀毒扫描。

## 2. 在真实 Windows 桌面验收冻结的 worker

从上述构建产物取出最终 Windows ZIP 和其中的 worker，按 `remote-host-provenance.json` 核对 SHA-256。准备干净的客户端标签检出和锁定的服务端检出；按各仓库锁定的依赖安装并重新构建服务端，不能沿用无法对应源码提交的旧 `control-center/dist`。客户端与服务端的提交和工作区状态会写入验收报告。

在解锁的独立测试桌面运行 Node 24、项目要求的 Go 与已安装的 Playwright Chromium：

```powershell
$provenance = Get-Content -Raw D:\release-acceptance\remote-host-provenance.json | ConvertFrom-Json
node scripts/test-remote-native.mjs `
  --worker D:\release-acceptance\home_tunnel_remote_host.exe `
  --sha256 $provenance.worker.sha256 `
  --server-root D:\release-acceptance\home-tunnel-server `
  --report-dir D:\release-acceptance\evidence `
  --input chromium
```

完整说明见 [真实原生验收](../tests/remote-native/README.md)。输入验收使用独立 Chromium 目标进程：按下、移动、滚轮和文字注入必须满足目标进程焦点限制，指针还必须命中该窗口的客户区。已经注入的按键或按钮抬起必须在焦点变化后仍可补发；不能为了通过焦点检查而遗留按下状态。

发布所需证据包括：

- 真实服务端、生产 Go 适配层和实际原生 worker 完成身份登记、双方配对码核对、绑定连接 epoch 的本地批准、签名验证和租约检查。
- 两端验证直接 UDP，DTLS 已连接，原生桌面视频在 Chromium 中实际解码并持续增加帧数；假引擎、录制视频和合成视频轨均不计入。
- 目标页面实际观察到可信键盘按下/抬起、Unicode 文字和指针按下/抬起，释放控制后停止输入。
- 输入心跳停止时，在两秒内释放已按键和按钮；终止正在按住输入的 worker 后，独立守护进程也必须在两秒内补发释放。测试只终止该 worker PID，不能把同名的释放守护进程一起杀掉。
- 重新申请控制与旧 input epoch 的消息不会恢复旧按下状态或绕过新同步。普通关闭会停止守护监测并退出，不能误杀仍存活的空闲 worker；看门狗超时或工作线程挂起则必须停止 worker 的采集和注入。

锁屏或安全桌面暂时拒绝系统输入时，释放债务必须保留并在普通桌面恢复后重试，期间禁止新的控制输入。“两秒”不能伪报为已跨越 Windows 安全桌面限制成功注入。

报告必须由实际运行产生。`status: "passed"` 和 `input.status: "passed"` 均为必需，缺失、失败、跳过、仅 view-only 或未验证的项目不能手工改成通过。默认输出名为 `report.json`，最终导入时保存为 `windows-remote-native-acceptance.json`。报告只包含验收结果和必要身份信息，不保存截图、视频、SDP、候选地址、密码、令牌或私钥。

**报告保存在源码树外或已忽略的输出目录，不提交进 Git。** 生成报告后再提交源码会改变待发布 SHA，使报告与包失配。任何源码、编译参数、依赖锁或 worker 字节的变化都需要新的构建和实机验收；不能修改报告中的提交或哈希来迁就变化。

## 3. 导入报告并发布原始产物

在同一个版本标签上手动触发发布工作流的 `workflow_dispatch`，在 `build_run_id` 中传入原构建 run ID，在 `acceptance_json` 中传入完整的实际验收 JSON。必须使用标签作为工作流 ref，不能改用 `main`。导入阶段检查构建来自同一仓库的 `release.yml`、属于成功的 tag push 构建，并与当前标签、提交和 `prepared` 清单对应；它复用已下载的 `candidate-assets`，不启动替代构建。

封存前必须再次通过以下身份检查：

| 材料 | 必须匹配的对象 |
| --- | --- |
| `remote-host-build.json` | 干净的客户端提交、版本、Windows x64、锁定 WebRTC 提交与依赖锁、构建测试结果、签名前 worker 哈希 |
| `remote-host-provenance.json` | 最终 worker 哈希、签名前构建、ABI、锁定服务端来源与依赖许可证哈希 |
| `remote-source-manifest.json` | 构建所用原生源码清单及其在构建记录中的哈希；公开附件、ZIP 与安装器中的字节一致 |
| Windows ZIP | worker 及来源文件和许可证的真实字节；Windows 路径别名不能导致同名组件覆盖 |
| Windows 安装报告 | 当前安装器哈希、真实安装后的各组件哈希与对应 ZIP/扫描内容、安装/卸载和 GUI 检查 |
| Defender 报告 | 当前安装器、ZIP、GUI、Agent、worker 的精确字节，成功扫描、引擎与病毒库版本和有效时间 |
| 原生验收报告 | 分发 worker 的最终哈希、客户端标签提交、锁定服务端提交、两端干净工作区与全部必需验收结果 |
| Windows Remote SDK | 实际 `webrtc.lib` 的字节数和 SHA-256、公共头文件、C ABI、锁定依赖及全部已审阅补丁、与 worker 一致的来源清单和许可证；独立归档摘要及 GitHub 构建证明 |

Defender 报告具有时效限制：扫描须在过去一天内，使用扫描时不超过两天的病毒库。请在此期限内完成实机验收和导入；过期后当前流程会拒绝发布，需要重新运行构建阶段并验收对应产物。不能修改时间戳、替换冻结产物中的报告或放宽门禁。

全部检查成功后，封存阶段把清单升级为 `verification_stage: "verified"`，将实际验收报告加入完整的 `SHA256SUMS.txt` 并生成最终 Sigstore bundle。只有这个 verified 集合可以创建公开 Release。`prepared` 清单、缺失输入证据或身份不匹配都会阻止发布。

安装包、SBOM、原生构建来源、扫描/安装/实机验收报告、平台签名状态、依赖许可证、完整校验清单和 Sigstore bundle 必须一起作为 Release 附件持久保存，Actions 产物仅作为额外副本。最终签名后不能删减附件、重写校验清单或只发布安装文件。发布后下载正式附件，再核对版本、哈希、安装与启动结果。

## 验收范围与跨仓库发布

上述原生验收证明 Windows 与同机 Chromium 的桌面视频和已测试输入路径，不证明跨网络 NAT 穿透、Android/macOS/Linux 原生后端、音频、剪贴板、文件传输或无人值守可用。发布说明必须逐项反映真实完成情况；未实现或未验证的能力保持不可用，不能据此宣称“8.0 全功能验收完成”。

各组件独立构建、签名与发布。普通下载入口指向 Android APK、桌面 EXE/ZIP、Linux/macOS tar.gz 和服务端部署包；Android AAB 与验证证据也要持久保存。组件发布完成并验证实际下载链接后，再更新入口仓库的 `releases.json`、网站副本和下载说明。服务端引用的客户端基线必须使用已发布 Linux 包的真实 SHA-256，不能预填未来链接或哈希。

Windows 安装器和扫描的进一步约束见 [Windows release checks](WINDOWS_RELEASE_CHECKS.md)。
