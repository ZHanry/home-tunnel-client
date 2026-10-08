# HomeDesk 门户独立验收环境准备包

日期：2026-10-02。该包只准备、校验和审阅材料；本轮不部署服务、不启动 Docker/Agent/HomeDesk，不修改 SSH、DNS、防火墙、系统证书信任或 Windows 身份。[运维验收报告](OPS_ACCEPTANCE_2026-10-02.md) 的 25 项业务仍为未执行。

## 固定发行来源

入口为 `tests/acceptance/lock.json`。Server 使用官方 v10.1.0 部署包，真实发行 revision 为 `194ae805f3569dc16d94b7fda71367e5d68fdff5`；API 契约为 1.5.0。后续 main 文档提交 `866e0cbb` 不作为发行镜像来源。Linux amd64 Client/Agent 使用官方 v10.1.0，revision 为 `41c0e21fbb3a4c634fbc9d63fcd7453337e4d029`。

准备脚本核验两个归档的 SHA256、Server/Client release-manifest、FRPS dependency 和官方 compose.release 镜像引用。四个运行镜像均固定摘要，Caddy 摘要来源为冻结源码的 `tests/release-smoke.compose.yaml`。不使用 `latest`，不安装依赖，不执行发行包内安装器；解压不创建符号链接，原始归档完整保留。

## 准备与只读预检

在仓库根目录运行下列准备命令。需要现有 Python 3.10+ 和 OpenSSL；脚本不安装工具。

```powershell
python tests/acceptance/prepare.py --project hd-portal-acceptance-20261002-local
```

新材料只写入 `tests/acceptance/.runtime/<project>/`。目录被专用 `.gitignore` 忽略；脚本拒绝覆盖既有项目目录。Linux 限制私有父目录为 0700；Windows 对新目录和秘密文件逐个限制 DACL，仅允许当前 SID 及系统固有的 SYSTEM/Administrators，不授予 Users/Everyone，不修改 Owner 或申请恢复特权。仅新测试栈使用的秘密文件需在容器单文件挂载后让 uid10001 读取，因此 Linux 采用官方生成器同样的“私有父目录 0700、挂载文件 0644”安排；CA 私钥为 0600，且不挂载给任何容器。Windows 依赖实际文件 ACL，不把 chmod 或目录保护当作独立 SID 证明。

准备阶段下载公开发行物，标准验证 HTTPS，失败时可回退 Windows 原生下载，最终仍必须通过相同摘要。任何失败均保留已产生材料且不写 `prepared.json` 成功记录，不把锁文件或脚本存在当作下载成功。密码、验证码、令牌和私钥不输出，也不进入 Git。

CDN 下载失败时，可显式使用 `--config-only` 生成配置/CA/秘密并开展只读静态检查；该模式写出的范围记录始终是 `prepared=false`、`official_assets_complete=false`，不冒充完整准备成功。`--reuse-artifacts <同包运行目录>` 只复用固定文件名且已核对摘要的公开发行文件。失败后应选择新的项目名，不覆盖旧目录。两份原生 PowerShell 工具保留 UTF-8 BOM，以免 Windows PowerShell 5 按 ANSI 误解中文脚本；Python 路径交给 WSL 时使用正斜杠。

准备成功后进行只读预检：

```powershell
python tests/acceptance/preflight.py --runtime tests/acceptance/.runtime/hd-portal-acceptance-20261002-local
```

预检验证运行目录、发行摘要、模板摘要、秘密文件存在性和权限，检查 Docker/Compose 版本，执行 `docker compose config --quiet`，审查镜像、回环端口、命名、范围标签及禁止外部卷/网络的条件。Windows PATH 没有 Docker 时尝试现有 WSL 的 Docker。它不启动 daemon、容器或业务探针；端口结果是 CLI 宿主机的观察，不能替代另一 Docker context、指定腾讯云或跨 VM 的检查。

## 默认端口和实际验证范围

| 入口 | 默认绑定 | 说明 |
| --- | --- | --- |
| 测试 API HTTPS | `127.0.0.1:18443` | 私有测试 CA；不安装系统信任。 |
| FRPS 接入 | `127.0.0.1:17000/TCP` | 仅后续在该 Linux 宿主机运行的专用 Agent 使用。 |
| 原始服务池 | `127.0.0.1:11000–11009/TCP+UDP` | 只预留池；管理员仍须在新后台启用协议及账号权限。 |
| 临时后端 | 默认 `127.0.0.1:18090/18454/TCP` | HTTP/HTTPS 唯一非敏感内容标记。 |
| 临时 echo | 默认 `127.0.0.1:18091/TCP,18092/UDP` | 必须检查真实报文收发，不能把监听当成功。 |

Control Center、Gateway 和 FRPS 插件端口不单独发布。SQLite 卷、control/edge 网络均由专用 Compose 项目命名；没有硬编码 container_name、生产卷、外部网络、主机网络或特权容器。部署根目录的生产 Caddy 不参与该栈。

临时后端的宿主机端口可用 `--fixture-http-port/--fixture-https-port/--fixture-tcp-port/--fixture-udp-port` 另选，不能与本栈固定端口冲突；以生成 `.env` 和预检输出为准，不改已有监听。容器内部端口仍是 18080/18444/12000/12001。预检发现占用时添加 `test_ports_in_use` 阻塞项，不能据 Compose config 成功忽略真实端口冲突。

**18443 是 API/工程联调入口，不是完整门户服务打开验收。** 当前服务端对 HTTP 连接返回 `https://<subdomain>.services.acceptance.test`，使用标准 443，不能自动改写返回 URL 为 18443 来冒充 T-17/T-18 成功。完整浏览器/指定 EXE 验收需要干净测试环境提供这些测试 hostname 的 443 监听和解析，并确认未修改的 EXE 使用正确信任链；这些 DNS/证书/端口操作不由本准备脚本进行。

## 后续人工启动步骤（本轮未执行）

先明确指定的测试 Docker 主机和资源、空闲端口、专用 Windows 身份及真实 HTTPS 信任条件。独立普通用户无需天然管理员，但同品牌系统服务和 IPC 仍可能共用；干净 VM 是更明确的选项。`--config` 不是 profile 参数，临时 AppData 和 `--no-server` 不能作为现用 HomeDesk 隔离保证。

只在已确认测试宿主机上，进入成功准备的运行目录后使用如下**待执行**命令；项目名必须等于 `prepared.json`，不能省略 `-p` 或改成生产项目。

```sh
docker compose -p hd-portal-acceptance-20261002-local --env-file .env -f compose.yaml --profile fixtures up -d
```

首次管理员凭据只由测试操作人在该私有运行目录本地读取，不复制到聊天或证据报告。完成强制改密后建立专用普通账号，人工配置 MFA 和必要的 TCP/UDP 权限。门户使用未绑定设备的账号会话，不替 HomeDesk 注册 Agent。下载的官方 Linux Client 应在独立 Linux 测试配置中按其官方帮助登录、注册并运行；不能套用现用 Client 状态文件。可给该进程设置新生成 CA 的 `SSL_CERT_FILE`，不修改主机全局信任。

临时后端在 Agent 所在宿主机通过上述回环端口提供。创建服务时选择对应本地端口，使用服务端分配的公网端口，返回内容或 echo 前缀应等于本次项目名。没有实际 Agent/FRP 数据时，只能记录真实控制面 CRUD，不能记录转发访问成功。大量分页边界数据可作为明确标识的专用 API fixture；不能将离线数据说成 101 台真实在线设备。

后续已启动后可使用准备好的 API 探针：

```powershell
python tests/acceptance/api_probe.py --runtime tests/acceptance/.runtime/hd-portal-acceptance-20261002-local
python tests/acceptance/api_probe.py --runtime tests/acceptance/.runtime/hd-portal-acceptance-20261002-local --username 专用普通测试账号
```

默认只检查实际运行版本和 HTTPS。账号模式从隐藏输入读密码/MFA，只登录、核实 `device_id=null`、全分页读取目录并结束该会话，不创建业务资源、不保存 refresh Token、不自动重试 MFA。探针只在进程中加载测试 CA，保留证书和主机名校验；结果明确标为 `LOCAL_BACKEND_ONLY`，不证明指定 Windows EXE 或系统信任配置通过。

真实故障注入应限于这个测试网络/测试入口：停止专用入口模拟断链，或使用另行审阅的测试代理在服务端提交后丢弃响应；不得改生产防火墙或现用网卡。本包没有自动执行故障注入，也没有交付未经验证的生产代理。

## 限定清理

清理默认仅生成计划：

```powershell
python tests/acceptance/cleanup.py --runtime tests/acceptance/.runtime/hd-portal-acceptance-20261002-local
```

明确只清本项目时才追加 `--execute`。脚本先验证运行目录真实绝对范围和固定模板，再只读枚举这个 Compose project 的容器、卷、网络；每个资源必须同时带匹配的 Compose project 和 `io.homedesk.acceptance.scope` 标签，名称必须属于专用项目，卷只能是该项目的 sqlite-data。任何不匹配、检查失败或 Docker 不可用均拒绝清理。随后仅对已检查的这份 Compose 执行 `down --volumes`，不删除文件目录、不删除镜像、不影响其他项目。运行目录与秘密保留供测试操作人按准确目录人工收尾，不能套用全盘或跨 shell 的递归删除命令。

## 验证记录与仍需补齐的门禁

工具范围测试为 `python tests/acceptance/test_environment.py`，覆盖目录越界、归档越界/链接、非官方下载 URL、清理双标签和资源名称，以及禁止公网绑定/外部卷/变化镜像。

2026-10-02 实际生成的配置-only项目为 `hd-portal-acceptance-20261002-final-v2`，目录在本包 `.runtime` 下；专用测试 CA、证书、秘密和 Compose 已生成，没有安装 CA。它复用了已核验 SHA256 的 Server tar。Agent tar、Server/Client release-manifest、compose.release 和 frps-dependency 五个文件尚未取得，`prepared=false` 保持原样。先前默认临时 HTTP 18080 被只读发现已占用，最终新项目另选 18090/18454/18091/18092，未动已有监听。

WSL Compose 2.40.3、Docker 29.1.3 的只读查询及 `config --quiet`/JSON 静态审查已实际执行；它们只证明配置形态。`runtime_launch_ready=false` 分别记录缺官方资产、独立 Windows 身份未确认及指定腾讯云实例未确认，不写“全部环境通过”。本轮没有执行启动、API业务探针、Agent、EXE 或清理的 `--execute`。

本地准备与静态配置验证的结果另行记录；它们不改变 `OPS_ACCEPTANCE_2026-10-02.md`。仍需指定真实实例/origin、专用 Windows 身份、账号/MFA、测试设备/Agent 和授权端口池，才开展该报告的 25 项实机业务。RustDesk 两端独立网络的 P2P/中继仍独立验收。
