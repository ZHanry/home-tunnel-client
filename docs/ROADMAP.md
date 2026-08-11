# Codex 开发提示词 · HomeDesk（全集）

> 本文件保留任务卡与阶段顺序；具体需求边界以 `docs/DESIGN.md` 为准。

<aside>
🚀

**用法（3 步）**：① 把 [家庭远程工具 HomeDesk · 设计方案（内网优先）](https://app.notion.com/p/HomeDesk-a598c517541e4f0691c8ee83499bf92e?pvs=21) 导出为 Markdown 存进仓库 `docs/DESIGN.md`——它是唯一需求来源；② 把下面 `AGENTS.md` 代码块存为仓库根目录 `AGENTS.md`——Codex 每次执行任务前自动读取；③ 贴「首条任务提示词」启动，之后按 T 编号顺序逐条发送：**一张卡 = 一个新会话 = 一个 PR**，验收不过不进下一张。

</aside>

## 〇、变量表（贴任何提示词前先替换）

| 变量 | 含义 | 示例 |
| --- | --- | --- |
| {SERVER_IP} | 飞牛NAS 内网固定 IP（服务端） | 192.168.1.10 |
| {NET_CIDR} | 家庭网段（IP 白名单） | 192.168.1.0/24 |
| {PUB_KEY} | hbbs 首启生成的公钥（P0 部署后从 data 卷取出回填） | 形如 OeVuKk...= |
| {TOKEN} | console 上报 Token（自己生成 ≥32 位随机串） | — |

硬件已定：服务端 = **飞牛NAS（fnOS，Debian 系，自带 Docker）**；mini 主机 = 主力主控/被控端，兼服务端备机。

## 一、[AGENTS.md](http://AGENTS.md)（放仓库根目录，Codex 自动读取）

```markdown
# AGENTS.md — HomeDesk 开发规则

## 项目是什么
基于 RustDesk fork 的家庭内网远控（服务端 + 客户端 + 自研管理台 console）。
完整设计方案见 docs/DESIGN.md，它是唯一需求来源；实现与方案冲突时，以 DESIGN.md 为准。

## 技术底座
- client/ = fork 自 rustdesk/rustdesk（AGPL-3.0，git subtree 固定 tag 引入，保留上游历史）
- server/ = 上游 hbbs/hbbr 容器（一行不改）+ 自研 console（Rust axum + SQLite + askama，单二进制）
- build/config.toml = 品牌/服务器地址/公钥/网段的唯一注入口（构建期读取），仓库只提交 config.toml.example

## 硬性约束（违反即打回）
1. 最小侵入：client/ 上游代码每处修改加 // HOMEDESK: 标记；新逻辑放独立文件/模块；
   禁止重排或重新格式化上游代码——必须保住季度 rebase 上游安全补丁的能力
2. 不碰核心：传输协议、编解码、加密逻辑零改动；只做配置、UI、外围模块
3. 配置外置：品牌/服务器/Key/网段禁止硬编码，一律走 build/config.toml 构建期注入
4. 零密钥入库：真实 IP/公钥/Token 只出现在 *.example 占位符里；CI 跑 gitleaks，检出即失败
5. console 质量线：所有 API 带单元测试；单二进制；零额外运行时依赖
6. 依赖锁定：Cargo.lock 与镜像 tag 固定版本；依赖升级单独开 PR
7. 纯内网原则：客户端产物默认不发起任何公网请求（含更新检查、遥测、公共服务器回退）

## 工作方式
- 每个任务先读 DESIGN.md 对应章节再动手
- 每 PR 三件套：目标平台编译通过 + tests/smoke.md 勾选记录 + 变更说明（动了上游哪些文件、为何）
- 小步提交：feat(client): / feat(console): / chore(build): 前缀；正文列出上游改动文件清单
- 注释、文档、UI 文案一律中文
- 方案有歧义时：按上游 RustDesk 默认行为实现，代码处留 TODO(design) 注释，
  汇总到 DESIGN_QUESTIONS.md 等我确认
```

## 二、首条任务提示词（T-00 · 仓库初始化 + 服务端编排）

```
背景：仓库根目录已有 AGENTS.md；docs/DESIGN.md 是完整设计方案，先通读第四、五、十一节再动手。
目标：我今晚就能在飞牛NAS（fnOS，Debian 系，自带 Docker）上把服务端拉起来。本卡不引入 client/ fork。

任务 T-00 — 仓库骨架与服务端编排：
1. 建骨架：docs/、server/、build/（config.toml.example + assets/ + ci/ 占位）、tests/；
   .gitignore 覆盖 Rust/Flutter 产物、data 卷、真实 config.toml、一切密钥文件
2. server/compose.yml：hbbs + hbbr 两服务（console 段先写好但注释掉，T-04 解开）；
   镜像 tag 锁定到具体版本号；数据卷 ./data；端口按 DESIGN.md 4.2；restart: unless-stopped
3. docs/DEPLOY.md 面向飞牛NAS写部署手册：目录规划、compose 拉起命令、fnOS 防火墙放行清单
   （21115、21116 TCP+UDP、21117 必开）、从 ./data 取出公钥的方法、data 卷备份、断电重启自检清单；
   附录：mini 主机作服务端备机的迁移步骤（拷 data 卷 + 客户端高级模式改服务器指向）
4. tests/smoke.md：对应 DESIGN.md 第九节 M1–M7 的手工核对清单
   （直连标识 / 无人值守 / 文件传输 SHA256 / 断线重连 / 冷启动计时）

验收：docker compose config 校验通过；在任一 Debian x64 环境实际拉起 hbbs/hbbr 无报错；
DEPLOY.md 我能从零照做且无歧义。
完成后输出：文件清单、我需要手动做的事（含如何取出并回填 {PUB_KEY}）。
```

T-00 合并后由**我**执行 P0：飞牛NAS 拉起服务端 → 两台机器装官方客户端 → 跑 tests/[smoke.md](http://smoke.md) 过 M1–M7 及格线 → 取出公钥回填 {PUB_KEY} → 放行 P1。

## 三、P1 阶段提示词（定制客户端 + Console v1 · T-01 → T-08 串行）

**T-01 · 上游引入与品牌化（C1）**

```
背景：读 DESIGN.md 6.1/6.3（C1）与 AGENTS.md 硬性约束 1。
任务 T-01 — 上游引入与品牌化：
1. 用 git subtree 把 rustdesk/rustdesk 固定 tag 引入 client/（保留上游历史；引入为独立 commit，
   PR 描述记录 tag 与 commit 哈希）；同时在 docs/UPSTREAM.md 记录引入版本与日期
2. 品牌化：应用名 HomeDesk、可执行/包名 homedesk、托盘与关于页同步；图标源文件放 build/assets/
   （SVG + 各尺寸导出脚本），先用占位图标
3. 品牌字符串统一从 build/config.toml [brand] 段注入；每处接线加 // HOMEDESK: 标记；
   禁止全仓搜索替换式改名
4. 产包命名：HomeDesk-<版本>-win-x64.exe、homedesk_<版本>_amd64.deb

验收：win x64 与 linux x64 出包安装后所有可见文案为 HomeDesk；
rg "HOMEDESK:" 的输出与 PR 描述的上游改动清单一一对应。
回滚：revert PR（subtree 引入 commit 可整体回退）。
```

**T-02 · 构建期配置注入与安全基线（C2/C3）**

```
背景：读 DESIGN.md 4.4、6.3（C2/C3）。目标是家人零配置 + 纯内网安全默认。
任务 T-02 — 配置注入与安全基线：
1. build/config.toml 增加 [server] host/key 与 [net] whitelist_cidr；example 文件用占位符
2. 构建产物默认值：ID 服务器 = {SERVER_IP}，Key = {PUB_KEY}，IP 白名单 = {NET_CIDR}；
   首次启动零弹窗、零配置向导
3. 设置页隐藏服务器配置项；「关于」页版本号连点 5 次解锁高级模式（可改服务器/白名单），修改持久化
4. 硬关闭公共服务器回退逻辑（编译期 feature 或强制配置，加 // HOMEDESK: 标记），
   PR 描述列出上游全部回退路径的源码位置

验收：停掉自建服务端后抓包，客户端零公网请求；白名单外 IP 连接被拒且文案明确；
高级模式修改后重启仍生效。
回滚：revert PR。
```

**T-03 · 被控端 console 上报模块（C4）**

```
背景：读 DESIGN.md 5.2（方案 B）、5.3。console 的数据全部来自被控端主动上报。
任务 T-03 — 上报模块（独立模块，主流程仅一处挂载点）：
1. 心跳：每 60s POST http://{SERVER_IP}:8080/api/v1/heartbeat，
   字段 id/hostname/platform/arch/version/ip/mac，头 Authorization: Bearer {TOKEN}
2. 会话事件：被控会话 start/end 各 POST 一次 /api/v1/session（对端 id、对端 ip）
3. 失败静默退避 30s→60s→300s 封顶；console 不可达时零弹窗、仅 debug 日志；
   任何情况下不阻塞、不影响远控路径
4. build/config.toml [console] 段：enabled/url/token；enabled=false 时模块完全不初始化
   （无线程、无网络请求）

验收：模块单测（序列化/退避/开关）+ mock server 集成测试通过；
开关关闭时进程内无该模块任何活动痕迹。
回滚：挂载点单行注释即可摘除；revert PR。
```

**T-04 · Home Console 后端（API + 存储 + 容器）**

```
背景：读 DESIGN.md 5.2（API 表）、5.3（数据模型）。全新 crate，位于 server/console/。
任务 T-04 — console 后端：
1. Rust axum + SQLite + askama，单二进制；配置走环境变量：
   PORT(默认 8080)/TOKEN/DB_PATH/NET_CIDR/RETENTION_DAYS(默认 90)
2. 实现 4 个 API（全部 Bearer 鉴权）：
   POST /api/v1/heartbeat（device 表 upsert）、POST /api/v1/session（session_log 追加）、
   GET /api/v1/devices、POST /api/v1/wol（UDP 9 魔术包，广播地址取 wol_target 表）
3. 启动自动建表（device/session_log/wol_target/setting，按 5.3）；每日清理超期 session_log
4. 在线判定：online_at 距今 ≤ 90s 为在线
5. Dockerfile 多阶段 musl 静态编译，镜像 ≤ 30MB，amd64/arm64 双架构；
   解开 server/compose.yml 里 console 段注释接入

验收：cargo test 全绿（4 个 API 正反用例：鉴权失败/非法 payload/幂等 upsert + WOL 报文字节断言）；
compose 拉起后 curl 全链路通；配合 T-03 实测设备 90s 内上线/离线状态正确。
回滚：console 是独立容器，revert 后把 compose 注释回去即可。
```

**T-05 · Home Console 页面（设备墙 / 审计 / 设置）**

```
背景：读 DESIGN.md 5.2（页面清单）、第十二节 U7——手机可用是硬要求。
任务 T-05 — console 页面（askama 模板 + 原生 JS）：
1. 设备墙：按房间分组的卡片 = 设备名/房间/在线状态（绿点+文字，不只靠颜色）/最近在线相对时间/
   WOL 按钮（仅离线设备可点）；点击 WOL 后按钮变「已发送，等待上线…」，设备上线自动恢复
2. 审计流水页：时间倒序，按设备筛选；设置页：网段白名单、Token 重置、日志保留天数、
   设备备注与房间编辑（console 仅有的写操作）
3. 移动端优先（375px 基准）、单手可操作；原生 JS ≤ 200 行，10s 轮询刷新；
   深浅色跟随系统；全中文
4. 空状态（0 设备）给引导文案：提示检查被控端上报开关与 Token

验收：手机浏览器实测单手完成「看状态 → WOL → 确认上线」全流程（U7）；
模板渲染测试通过；与 T-04 API 联调无误。
回滚：纯展示层，revert 即可。
```

**T-06 · CI 矩阵与离线安装包（C8）**

```
背景：读 DESIGN.md 6.3（C8）、2.2——信创内网机常无软件源，离线可装是硬要求。
任务 T-06 — CI 与安装包：
1. 构建矩阵：client 出 win x64（exe）、linux x64（deb+tar.gz）、linux arm64（deb+tar.gz）；
   console 镜像 amd64/arm64
2. deb 包 postinst 注册 systemd 服务并自启；tar.gz 附 install.sh/uninstall.sh（含 systemd 单元）
3. 离线原则：安装过程不联网；产物附 SHA256SUMS 与依赖清单
4. gitleaks 密钥扫描进 CI，检出即失败（AGENTS.md 硬性约束 4 落地）

验收：三平台产物在干净虚拟机离线安装 → 服务自启 → 能被主控端连上；
CI 一次跑通全矩阵。
回滚：CI 配置独立目录，revert 即可。
```

**T-07 · 纯内网模式总开关（C5）**

```
背景：读 DESIGN.md 4.4——本项目的特色安全开关，也是审计重点。
任务 T-07 — 纯内网模式：
1. 设置页新增「纯内网模式」开关，默认开（config.toml 可设默认值）
2. 开启时禁止一切白名单网段之外的出站：更新检查、遥测、公共服务器、任何域名解析请求
3. 托盘与主界面显示「纯内网」标识（配合 U 系列审计）
4. PR 描述必须附完整出站点清单（逐个源码定位），说明每个如何被拦截

验收：开启后抓包 10 分钟零公网出站（含 DNS 查询）；关闭后行为回到 T-02 基线。
回滚：revert PR。
```

**T-08 · 简化设置页与中文默认（C6）**

```
背景：读 DESIGN.md 6.3（C6）、6.4 与第十二节 U1/U3——这是给家人用的界面。
任务 T-08 — 设置页简化：
1. 默认中文；设置页只留 常规/安全/网络（高级模式内）/关于 四组，
   隐藏账号、地址簿云同步等与家庭场景无关的项
2. 关于页：版本号、开源声明（基于 RustDesk 的 AGPL-3.0 fork + 上游链接）、高级模式入口
3. 错误文案按 U3 改造：服务器不可达/密码错误/白名单拒绝 三类各给「下一步怎么办」提示
4. 术语统一「设备/连接/密码」，不得出现 ID Server、Rendezvous、hbbs 等上游词（U1）

验收：全部界面截图存 PR；自查 U1/U3/U9 通过（正式审计由 Gemini 出报告）。
回滚：revert PR。
```

T-08 合并后 = P1 收官：跑一次 Gemini UI 审计（见第六节提示词）→ Blocker 转 FIX 卡清零 → 对照 DESIGN.md 第十节 P1 验收行放行 P2。

## 四、P2 阶段提示词（信创深化 + Web 主控 · T-09 → T-12）

**T-09 · 信创 T2 适配：麒麟/UOS 编译与离线包**

```
背景：读 DESIGN.md 第七节（7.1 策略 1/2、7.2 坑表 K1/K2/K7、7.3 清单）。
任务 T-09 — 信创 T2 适配：
1. 提供麒麟 V10 SP1 与统信 UOS 的目标机源码编译脚本：x86_64 与 aarch64 两套；
   依赖清单支持离线预下载（不假设目标机有可用软件源）
2. 新建 docs/XINCHUANG.md：逐条记录 glibc/依赖坑（系统版本、报错原文、解法）（K2）
3. 文档化麒麟安全中心 / UOS「信任应用 + 允许自启动」操作路径（K7，留截图位）
4. install.sh 增加会话类型检测：Wayland 时先打印切换 X11 的指引再继续（K1）

验收：DESIGN.md 7.3 清单前两项在实机勾选通过；照 XINCHUANG.md 能复现编译全过程。
回滚：独立目录，revert 即可。
```

**T-10 · 龙芯 no-GUI 被控探索（硬 timebox 5 人日）**

```
背景：读 DESIGN.md 6.3（C7）、7.2（K3–K6）、第十三节（R1）。这是探索卡，允许失败。
硬约束：累计投入满 5 人日仍未达验收 → 立即停手写失败报告
（卡点、已试路径、残留分支、建议），不许恋战。
任务 T-10 — loongarch64 纯被控形态：
1. feature flag "no-gui" 裁剪 Flutter/UI 依赖，产出纯被控守护进程（TOML 配置 + CLI 起停）
2. 编译前置：确认目标系统属于龙芯新/旧世界 ABI（K5）；一律目标机原生编译
3. ring 等依赖升级到支持 loongarch64 的版本并锁定 Cargo.lock（K3）；
   libvpx/opus/libyuv/aom 走系统包或手工编译（K6），过程全记 XINCHUANG.md
4. 交付 tar.gz + install.sh + systemd 单元

验收：龙芯实机完成 注册/被控/文件传输（7.3 第三项）；或交付失败报告。
回滚：feature flag 默认关，主线零影响。
```

**T-11 · Web 主控自托管验证**

```
背景：读 DESIGN.md 2.1（F9）、第十三节（R5）——先验证可行性，再决定是否承诺。
任务 T-11 — Web 主控验证：
1. 调研上游 Web 客户端当前的开源与自托管状态，结论写 docs/WEB_CONSOLE.md
   （证据附链接与版本号，结论二选一：可自托管 / 不可）
2. 可行 → server/compose.yml 增加 profile "web"（默认关闭），放开 21118/21119 WebSocket，
   DEPLOY.md 增章；不可行 → 写替代建议（Android 主控为主）

验收：结论文档落库；若可行，浏览器完成一次成功远控并截图。
回滚：profile 默认关闭，revert 即可。
```

**T-12 · 会话审计完善（F8）**

```
背景：读 DESIGN.md 2.1（F8）、5.3。
任务 T-12 — 审计完善：
1. session 事件补字段：duration_s（end 时计算）、conn_type（直连/中继）
2. console 审计页：按设备 + 日期范围筛选、CSV 导出；保留天数设置实际生效
3. SQLite 迁移脚本向后兼容（老库自动加列，不丢数据）

验收：实测 3 次会话（含 1 次强制走中继）记录完整准确；导出 CSV 可打开；老库升级不丢数据。
回滚：revert PR。
```

P2 收官：7.3 信创清单全绿（T3 允许降级）+ Gemini 对 UKUI/DDE 桌面下的 UI 审计通过 → P3 按需启动。

## 五、P3 可选提示词 + 长期维护（T-13 → T-16）

**T-13 · WireGuard 回家隧道（可选）**

```
背景：读 DESIGN.md 2.1（F11）、第十节 P3——外网访问的唯一入口，远控端口保持零公网暴露。
任务 T-13 — 回家隧道：
1. server/ 增加 wireguard 服务（compose profile "remote"，默认关闭）；
   全屋只在路由器映射 UDP 51820 一个端口
2. 脚本生成手机/笔记本 peer 配置与二维码；支持吊销单个 peer
3. DEPLOY.md 增章：「先连 VPN（等效回家）再照常远控」流程、密钥轮换、风险边界说明

验收：外网 4G 环境连 VPN 后远控成功；全程远控端口无任何公网暴露。
回滚：profile 默认关闭。
```

**T-14 · TOTP 与成员权限（可选）**

```
背景：读 DESIGN.md 第十节 P3。
任务 T-14：console 登录加 TOTP；设备可标记「连接需确认」，被控端弹窗同意后才建立会话（父母机场景）。
验收：错误 TOTP 进不了 console；标记设备未确认时连接被拒且提示清晰。
回滚：revert PR。
```

**T-15 · Android 主控适配验证（可选）**

```
背景：读 DESIGN.md 2.1（F10）。
任务 T-15：官方 Android 客户端配自建服务器实测；家人手机的安装配置步骤写进 DEPLOY.md（截图版）；
发现的 UI 问题整理成清单转 Gemini 审计。
验收：手机主控 mini 主机与 NAS 各成功一次；文档家人可照做。
回滚：纯文档与验证，无需回滚。
```

**T-16 · 季度上游 rebase 评估（长期循环）**

```
背景：读 DESIGN.md 第十三节（R2）。每季度执行一次。
任务 T-16：
1. 列出上游自当前引入 tag 以来的安全修复与重要变更，给出「本季是否 rebase」结论
2. 若做：subtree pull 新 tag → 逐个核对 rg "HOMEDESK:" 改动点仍在 →
   全量 tests/smoke.md + 三平台重新出包
验收：评估报告记入 docs/UPSTREAM.md；若 rebase，smoke 全绿后才并主线。
回滚：rebase 在独立分支验证，不达标不合并。
```

## 六、Gemini UI 审计提示词（每阶段末执行）

```
你是「HomeDesk 家庭远程工具」的 UI 审计员，独立于开发（Codex），只审 UI/文案/交互，不审代码。
输入：本阶段安装包的实测截图/录屏 + 设计契约 DESIGN.md 第六节（客户端设计）与第十二节（审计清单）。
任务：按 U1–U9 逐项走查，输出报告表，列：编号 / 审计点 / 结论(通过|问题) / 分级 / 复现步骤 / 修复建议。
分级：Blocker=阻断家人独立使用；Major=明显不适或误导；Minor=观感问题。Blocker 未清零不得进下一阶段。
额外必答：让 60 岁家人独立完成「打开 → 选设备 → 进入控制」需要几步？哪一步最可能卡住？给最小改动建议。
约束：修复建议必须具体到控件与文案改法，能直接转成 FIX 卡。

审计清单（与 DESIGN.md 第十二节一致）：
U1 术语一致：全程「设备/连接/密码」，不得出现 ID Server、Rendezvous 等上游遗留词
U2 直连 vs 中继状态可见、色弱可辨（不只靠红绿）
U3 错误态文案是人话：服务器不可达/密码错误/白名单拒绝，各给下一步动作
U4 家人视角走查：3 步内完成「打开 → 选设备 → 进入控制」
U5 DPI 125%–200% 与 UKUI/DDE 桌面下无布局破碎
U6 深色/浅色模式对比度达标
U7 console 手机端：单手完成「看状态 → WOL → 确认上线」
U8 托盘/通知不打扰：被控时有明确提示但不弹窗轰炸
U9 中文化完整：无遗漏英文串（设置深层页、错误弹窗重点查）

各阶段审计范围：P1 = Windows/Ubuntu 客户端 + console 手机端；P2 = UKUI/DDE 桌面（U5 重点）+ Web 主控（若启用）。
```

## 七、FIX 卡模板与使用小贴士

**FIX 卡模板（Gemini 问题 → Codex 修复）**

```
任务 FIX-xx — <问题标题>
来源：Gemini <日期> 审计报告 · 编号 Ux · 分级 Blocker/Major
现象与复现：<贴 Gemini 原文>
期望表现：<一句话>
改动范围：<限定到文件/页面>
验收：修复后截图 + Gemini 复审该项通过。
回滚：revert PR。
```

使用小贴士：

- 每张卡合并前先让 Codex **自查验收标准**；不达标就把验收标准原文重发一遍
- 纠偏话术：「重读 `DESIGN.md` 第 X 节，对照后列出差异并修复」
- `DESIGN_QUESTIONS.md` 攫的歧义问题定期回答，然后让 Codex 按答案更新实现
- 严格串行不跳卡：T-03 依赖 T-02 的配置体系，T-05 依赖 T-04 的 API
- 变量表四个值贴卡前替换；公钥要等 P0 部署后才有——T-01/T-02 之前先完成 P0
- 每阶段验收结论写在设计方案页评论区（对应 DESIGN.md 的阶段门禁）
