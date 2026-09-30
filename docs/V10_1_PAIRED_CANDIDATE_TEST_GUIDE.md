# 10.1.0 配套候选包测试指引

状态：两次候选构建均成功，Windows 原包和 Server 候选已完成下述来源/摘要/签名核验。本文用于隔离环境测试；真实环境验收尚未完成，当前生产稳定版仍为 10.0.0。本轮按用户明确要求不做 24 小时稳定性测试；该项不执行，也不宣称通过，其余检查保持要求。

## 1. 只使用这一配套批次

- Windows Client / Agent：`9b3dbb751942fee040049f9901ea61e95e60c10c`，候选 [run 36696397157](https://github.com/ZHanry/home-tunnel-client/actions/runs/36696397157)
- Server：`194ae805f3569dc16d94b7fda71367e5d68fdff5`，候选 [run 36696725173](https://github.com/ZHanry/home-tunnel-server/actions/runs/36696725173)
- API：不可变标签 `api-v1.5.0` 对应上述 Server SHA；Client 的 REST、远控及 native-test 服务端锁均须保持该来源
- Client 原包：`HomeTunnel-Windows-10.1.0-x64.zip`；安装生命周期另用 `HomeTunnel-Setup-10.1.0-x64.exe`
- Server 原包：`home-tunnel-server-10.1.0.tar.gz` 与原 `compose.release.yaml`，必须使用 `image@sha256:…`，禁止重建或改成浮动 `:10.1.0`

两次 run 均成功。下载时固定下列 artifact 与摘要，完成来源/签名验证后再安装。旧 run、旧 proposed-contract 包及稳定版 10.0.0 的验收不能移用。

### Client 原始下载与核验

- `candidate-assets` ID：`11089548057`
- GitHub 返回的完整 artifact ZIP SHA-256：`985228faa3eadf896558a7d46fe696c79d8d62b1677f5ff865334301d112e95c`
- 原 Windows ZIP：`HomeTunnel-Windows-10.1.0-x64.zip`，SHA-256 `c0e35e647df34ba2c138823aa550a4aeca4004444150b5d75f5e1cf673d1e690`
- 原安装器：`HomeTunnel-Setup-10.1.0-x64.exe`，SHA-256 `c592f2bac3551231fbdcdeb56e69589f25174943dfef4f774ff5c427195a2a51`

使用上述 Client SHA 的干净源码与现有 Python 3、GitHub CLI、cosign，在源码根目录执行下载器。它核对精确 run/artifact/source、全部文件摘要、签名与同一 run/attempt 的证明；测试下载不传验收收据参数：

```sh
python scripts/fetch-client-candidate.py \
  --run-id 36696397157 --artifact-id 11089548057 \
  --artifact-sha256 985228faa3eadf896558a7d46fe696c79d8d62b1677f5ff865334301d112e95c \
  --revision 9b3dbb751942fee040049f9901ea61e95e60c10c --version 10.1.0 \
  --output client-36696397157
```

原包位于 `client-36696397157/candidate/`。保留整个候选目录和 `verification/`，把原 Windows ZIP/安装器复制到测试 VM 后再次核对摘要；不重新打包或签名。实际 ZIP 根目录已核验含 `home-tunnel-gui.exe`、`home-tunnel-agent.exe` 与 `home_tunnel_remote_host.exe`；worker SHA-256 为 `bd04a279fa178cdc5662565fb5946d98afc314f3137d409a0f0011f0d4557da9`。原 `client-candidate.json` SHA-256 为 `177c7a06bf760587a33ce60f4d3e37c315159f195836cf0926f924a828d55717`，其中 `acceptance_complete=false` 保持原样。Windows 平台签名报告为 `unsigned-no-certificate-configured`：GUI、Agent、service、worker、安装器均为 `NotSigned`。清单、安装器、ZIP、ZIP 校验和、Windows SBOM 与 Agent provenance 的六份 Sigstore 签名已独立验证；清单、安装器及 ZIP 的 SLSA 证明也已核验，绑定原 run `36696397157/attempts/1`、source/signer SHA `9b3dbb751942fee040049f9901ea61e95e60c10c`、`refs/heads/codex/windows-v10-1` 和 `client-candidate.yml`，并拒绝 self-hosted runner。完整多平台 artifact 未整体下载到本次验证机，Windows 原包及相关元数据来自该 run 的独立 artifacts；上面的下载器会对完整 artifact ZIP 摘要再做验证。Sigstore 证明来源，不等同于 Authenticode、SmartScreen 信任或完整运行时验收。

### Server 原始下载与核验

从上述 Server run 下载 `candidate-assets`，artifact ID `11088486160`，大小 `964269` bytes，ZIP SHA-256：
`f25f95184fa6126afe8e043b7abfa06e884d216867d7e7863bdb87185814ac0f`。将它保留为 `server-candidate.zip`。

已核验的原文件与镜像：

- `home-tunnel-server-10.1.0.tar.gz`：`dea0300d37f275bc8b97a7069aad48df04c5ef424e9bbc484ffbd2b3d7ff2694`
- `compose.release.yaml`：`6e7b3a9894c59e7cfc2d2dbbc3e0cc41f55c58c33865af7d6b3e75af38c9bba3`
- control-center：`ghcr.io/zhanry/home-tunnel-control-center@sha256:d286c574f229060f3169b7c68fef5094a22c082c5373a23ca0406b2ed6872afd`
- traffic-gateway：`ghcr.io/zhanry/home-tunnel-traffic-gateway@sha256:91793c36ec849d0c8722e7379e14520d17d7d8a3484c1142fccb4e3aa93968ff`

以下命令使用 GitHub CLI 2.102.0 的原始字节下载选项与 cosign 3.0.6。也可在 run 页面下载 artifact，再从校验开始。所有命令在新的工作目录执行：

```sh
set -eu
gh api repos/ZHanry/home-tunnel-server/actions/artifacts/11088486160/zip --allow-escape-sequences > server-candidate.zip
printf 'f25f95184fa6126afe8e043b7abfa06e884d216867d7e7863bdb87185814ac0f  server-candidate.zip\n' | sha256sum -c -
test ! -e verified-server
unzip server-candidate.zip -d verified-server
cd verified-server
cosign verify-blob --bundle SHA256SUMS.txt.sigstore.json \
  --certificate-identity https://github.com/ZHanry/home-tunnel-server/.github/workflows/server-candidate.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
cd ..
```

核验仅确认原字节及来源。两个镜像的签名与 SLSA 证明已独立核验，绑定本次 run/attempt 1、冻结 SHA、ci.yml 调用方与 server-candidate.yml 构建方；amd64/arm64 smoke 成功。sealed STUN 报告的 `source_modified: true` 保持原样：工作流在检测前生成未忽略的 `integration/` 证据，足以触发该标记；记录的五个 STUN 源文件哈希与冻结源完全一致。报告未保存完整工作树差异，不能把它称为干净检出的证明。

## 2. 准备环境与保存回退点

需要独立 Linux amd64/arm64 测试服务器、两个互相独立的 Windows 测试 VM/设备，以及后续真实 Android/浏览器和指定网络工况。测试服务器使用独立 HTTPS 域名、独立 Docker Compose 项目、全新数据卷、测试账号和新配置；不要复制生产账号、令牌、私钥或数据库到一般测试环境。

先保存可验证的 VM 快照及现有安装、配置、数据备份。升级/恢复专项在隔离克隆上单独执行；保留原包与原始证据，不覆盖生产 10.0.0，也不要让旧服务端二进制打开新 schema。

Windows 优先便携包，解压到新目录，整套 GUI / Agent / remote worker 保持同包。`HOME_TUNNEL_STATE_PATH` 可隔离状态，但 GUI 固定监听 `127.0.0.1:8788`，不能据此在同机并行运行稳定版和候选版；换 Windows 用户也不隔离该端口。使用独立 VM/设备，测试机不要同时运行其他 Home Tunnel GUI/服务。安装器与服务生命周期验收使用可回滚的单独快照。

## 3. Server 10.1 测试环境

旧生产 Server 10.0 缺少本次免重复登录与本机改名的新端点，不能用它判定修复失败或通过。使用本批次归档内的部署文件；归档中的部分说明仍描述稳定版 10.0，不能把其镜像/下载示例直接当作本候选步骤。

回到包含 `verified-server/` 的下载工作目录，在全新目录解压已核验归档。配置、凭据、RD 签名密钥和 HTTPS 由测试环境管理员在本机准备；不将它们发到聊天或提交仓库。所需域名、端口、STUN 与权限必须事先获准，本文不授权更改网络/安全设置。

```sh
mkdir ht-10.1-server-test
tar -xzf verified-server/home-tunnel-server-10.1.0.tar.gz -C ht-10.1-server-test
cd ht-10.1-server-test
# 管理员按照归档 deploy/scripts/new-selfhost-config.sh 与
# docs/REMOTE_DESKTOP_OPERATIONS.md 准备隔离测试 .env、secrets 和 RD key。
# .env 中明确 HOME_TUNNEL_RD_ENABLED=true；只填实际获准可用的 STUN。
docker compose -p ht101-candidate -f compose.yaml -f compose.release.yaml -f deploy/compose.rd.yaml config --quiet
docker compose -p ht101-candidate -f compose.yaml -f compose.release.yaml -f deploy/compose.rd.yaml config --images
```

检查两个服务镜像与本批次 `image-control-center.json`、`image-traffic-gateway.json` 中的 digest 完全一致，FRPS 与 `frps-dependency.json` 一致。独立主机上的 HTTPS/FRPS 端口确认无冲突，所有 secrets 对相应容器用户可读后，由管理员启动该测试项目：

```sh
docker compose -p ht101-candidate -f compose.yaml -f compose.release.yaml -f deploy/compose.rd.yaml up -d --no-build
docker compose -p ht101-candidate -f compose.yaml -f compose.release.yaml -f deploy/compose.rd.yaml ps
curl --fail https://TEST-CONSOLE/healthz
curl --fail https://TEST-CONSOLE/api/v1/public/capabilities
```

确认控制中心健康版本 `10.1.0`、capabilities 的 `contract_version: 1.5.0` 与 `server_version: 10.1.0`，两个服务使用正确 digest；gateway 的 healthz 不返回产品版本，使用镜像来源/digest和健康状态确认。由管理员首次登录并建立专用测试账号。开启服务端 RD 不等于已经授权 Windows 采集或输入；Windows 端仍需明确本机授权。

暂停时使用相同 `-p` 和覆盖文件执行 `stop`，不要用 `down -v` 删除证据/数据。

## 4. Windows 便携包与五项修复实测

在两个独立的已登录、解锁测试桌面上分别解压原 ZIP；不要覆盖现有目录。PowerShell 示例（实际目录由本机选择）：

```powershell
$TestRoot = Join-Path $env:LOCALAPPDATA 'HomeTunnel-10.1-candidate-test'
New-Item -ItemType Directory -Path $TestRoot -ErrorAction Stop | Out-Null
$Zip = 'C:\verified\HomeTunnel-Windows-10.1.0-x64.zip'
if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'c0e35e647df34ba2c138823aa550a4aeca4004444150b5d75f5e1cf673d1e690') { throw '候选 ZIP 摘要不匹配' }
Expand-Archive -LiteralPath $Zip -DestinationPath (Join-Path $TestRoot 'package')
$env:HOME_TUNNEL_STATE_PATH = Join-Path $TestRoot 'state\state.json'
Start-Process -FilePath (Join-Path $TestRoot 'package\home-tunnel-gui.exe')
# GUI、home-tunnel-agent.exe、home_tunnel_remote_host.exe 必须仍为同包原文件。
```

在 GUI 填测试 Server 的真实 HTTPS 地址，使用测试账号登录。每项记录测试时间、VM/OS/WebView2、客户端包与 worker SHA、Server digest、账号角色（不记录凭据），保存实际窗口截图/录像及脱敏日志：

1. **登录布局与恢复**：默认和最小窗口、125%/150%/200% DPI，检查字段宽度、间距、滚动与键盘焦点；错误密码、断网重试、MFA、重复点击、关闭再开均可恢复。
2. **本机与改名**：“我的设备”显示当前设备、本机只有改名；改名在另一端控制台同步。验证取消、空白/无效名、失败重试、退出后重新登录。保持另一台真实设备在线用于远控，不把本机记录替换成另一台。
3. **拒绝自连**：本机无远控按钮；通过本机设备 ID、帮助请求等适用路径尝试自连应明确拒绝。随后向另一台 Windows 发起合法会话，确认没有误挡正常远控。
4. **免重复登录边界**：已登录客户端打开另一台设备的远控页时不重复登录；关闭/替换窗口、重复打开、退出账号、撤销父会话后不会留下有效旧授权。过期、重复使用或错误来源的 handoff 被拒绝；不能变成一般账号/管理员访问，URL、存储和日志不泄露 handoff。
5. **真实右下角授权弹窗与设置**：从另一设备发起实际授权请求，在主窗口可见、最小化和托盘隐藏时分别检查独立右下角 HWND。背景不透明、文字填充后才显示，无透明/空白闪烁；同意、拒绝、撤销、会话结束、重复请求和紧急断开状态正确。主窗口中加载 popup HTML 的 CI 截图不能替代此项。设置只有预期的更新/服务器地址；改名在“我的设备”，旧设备标记/外观/返回本地服务入口已移除。

不得仅凭页面能打开、一次成功连接或源码单测给上述全部项目写 passed。

## 5. 正式版仍缺的真实证据

以客户端 `docs/CLIENT_ACCEPTANCE.md`、`scripts/client_release_candidate.py` 的 case ID 及服务端 `docs/server-acceptance.schema.json` 为准，完整保留以下门槛：

- Windows↔Windows、Web→Windows、Android→Windows；四种授权、越权/账号隔离、撤销、紧急断开
- 服务与桌面：开机未登录、锁屏/登录屏、UAC、安全桌面、会话切换、注销重启、IPC/文件权限。逐项预先明确当前能力与预期安全边界，实测不可用状态、转换时输入释放、拒绝新输入，以及返回普通桌面后的恢复；不得将安全拒绝写成支持安全桌面控制
- 真实画面、键鼠/中文、多屏/DPI，双向剪贴板/多文件、空/大文件、取消清理与哈希，系统音频实播
- LAN、可穿透 NAT、双层 NAT、UDP 封锁、IPv6、延迟丢包、断网恢复及抓包；指定直连验收的实测服务端 relay payload 为 0，不凭配置推断
- 连续 30 次零失败、活动 ≥7200 秒；输入释放 ≤2000ms，恢复/明确重试 ≤30000ms。24 小时连续在线测试按本轮用户要求不执行，不作为已验证结果
- 真实 9→10 升级、服务端迁移、加密备份、干净卷恢复、回退，以及相同工况的真实 9.0.0 性能基线：首帧/延迟/帧率/资源/吞吐
- 所有适用界面/状态、角色、语言、主题、尺寸与 DPI 的实际图片和 Gemini 审核/复审台账；阻断/重大问题必须为 0
- 全部隧道协议/模板/权限/生命周期、重连/MFA/配额/多服务器/批量/更新/诊断/监控；Linux/macOS 各架构的既有能力回归
- 同一原安装器/ZIP/GUI/Agent/worker 的最终 Defender 复扫、安装/卸载及安装后文件哈希；正式发布前另存最终复扫，原 CI 扫描记录保持不变
- Server 原镜像 amd64/arm64、Web UI、迁移、备份、网络、长期稳定性六类证据，以及四仓同批次的 12 项联调 gate

Server CI 的 `tests/client-baseline.json` 固定真实 v9.0.0 Linux 包，只证明向后兼容联调；不能当作本次 Windows 10.1 配对远控验收，不能凭空改成新的客户端哈希。

上述门槛尚未完成，需准备列出的隔离环境并保留实测证据。锁屏、登录前及 UAC 场景按现有产品的安全边界与返回/恢复预期实测，明确不可用能力；本次五项修复不新增安全桌面控制能力。门槛通过须有预期与实测证据相符的记录，不能从“被拒绝”自动推定通过。最终收据必须绑定这批原包、源码、镜像与原始日志；全部适用门槛完成并核验同一批原始字节后，才进入正式发布流程。

## 依据

- [Client candidate notes](https://github.com/ZHanry/home-tunnel-client/blob/9b3dbb751942fee040049f9901ea61e95e60c10c/docs/V10_1_CANDIDATE.md)
- [Client acceptance requirements](https://github.com/ZHanry/home-tunnel-client/blob/9b3dbb751942fee040049f9901ea61e95e60c10c/docs/CLIENT_ACCEPTANCE.md)
- [Client fetch verifier](https://github.com/ZHanry/home-tunnel-client/blob/9b3dbb751942fee040049f9901ea61e95e60c10c/scripts/fetch-client-candidate.py)
- [Server candidate workflow](https://github.com/ZHanry/home-tunnel-server/blob/194ae805f3569dc16d94b7fda71367e5d68fdff5/.github/workflows/server-candidate.yml)
- [Server publication gates](https://github.com/ZHanry/home-tunnel-server/blob/194ae805f3569dc16d94b7fda71367e5d68fdff5/docs/RELEASING.md)
