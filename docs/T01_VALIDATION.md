# T-01 验证记录

更新时间：2026-08-11

本文件记录 RustDesk 上游引入与 HomeDesk 品牌化的仓库侧验证。完整 Windows/Linux 安装包验收仍以实际构建、安装和截图为准。

## 实现结果

- RustDesk `1.4.9` 以保留历史的 subtree 引入 `client/`，完整提交见 `docs/UPSTREAM.md`。
- `build/config.toml [brand]` 是品牌值的首选来源；本地文件不存在时使用可入库的 `build/config.toml.example`，也可用 `HOMEDESK_CONFIG_PATH` 显式覆盖。
- Rust 客户端在全局初始化最前段把默认 `RustDesk` 替换为编译期品牌，同时保留上游已签名 custom-client 对 `app-name` 的后续覆盖能力。
- Windows/Linux Flutter CMake 从同一配置生成启动器名和 C/C++/RC 宏；Windows 文件元数据、窗口 fallback、Linux 窗口标题与系统图标名同步。
- Linux deb 只在临时 staging 目录改写桌面项、systemd/PAM/维护脚本，不原地批量替换上游资源。
- 占位图标以 `build/assets/homedesk.svg` 为唯一矢量源，导出脚本生成 PNG/ICO 并同步 Flutter、托盘、Windows resource、Linux package 入口。
- 约定产物名为 `HomeDesk-<version>-win-x64.exe` 与 `homedesk_<version>_amd64.deb`；当前版本对应 `HomeDesk-1.4.9-win-x64.exe`、`homedesk_1.4.9_amd64.deb`。

## 上游改动清单

以下文本接线点均可由 `rg -n "HOMEDESK:" client` 定位：

| 文件 | 原因 |
| --- | --- |
| `client/build.rs` | 构建前读取并导出品牌配置 |
| `client/src/lib.rs`、`client/src/common.rs` | 注册并尽早应用品牌默认值 |
| `client/build.py` | Windows/Linux Flutter 产物名和 deb staging 接线 |
| `client/flutter/windows/CMakeLists.txt` | 配置 Windows 启动器文件名 |
| `client/flutter/windows/runner/Runner.rc` | Windows ProductName、FileDescription、OriginalFilename |
| `client/flutter/windows/runner/main.cpp` | Rust DLL 返回名称前的窗口名 fallback |
| `client/flutter/linux/CMakeLists.txt` | 配置 Linux 启动器文件名 |
| `client/flutter/linux/my_application.cc` | Linux 窗口标题与图标缓存名 |

`client/homedesk_build.rs`、`client/src/homedesk_brand.rs`、`client/homedesk_package.py` 是隔离的新逻辑。图标二进制无法嵌入源码注释，其来源和导出命令固定在 `build/assets/README.md`。

内部 `rustdesk` crate/动态库名、Flutter IPC channel 和 Linux application ID 刻意保留；它们不是用户可见品牌，改名会扩大上游冲突和运行兼容风险。

## 已验证

| 项目 | 命令/证据 | 结果 |
| --- | --- | --- |
| Python 配置与 deb staging 单测 | WSL2 Ubuntu：`python3 -m unittest discover -s tests -v` | 7/7 通过 |
| 真实 deb 结构 | WSL2 `dpkg-deb --root-owner-group --build`，检查 control 与 branded paths | 通过 |
| 打包安全边界 | 拒绝含 shell/path 字符的 `DEB_ARCH`；control 只写 staging，源资源无污染 | 通过 |
| Python 语法 | Windows + WSL2：`python -m py_compile ...` / `python3 -m py_compile ...` | 通过 |
| Rust 品牌解析单测 | Windows：`rustc --test client/homedesk_build.rs` | 2/2 通过 |
| Cargo 清单 | Windows：`cargo metadata --manifest-path client/Cargo.toml --no-deps --format-version 1` | 通过 |
| 品牌生成文件 | `python build/brand_config.py --cmake-out ... --header-out ... --print-json` | 生成 HomeDesk/homedesk 正确 |
| 图标导出 | Windows Pillow 12.2.0；16/32/48/64/128/256/512 PNG + 多尺寸 ICO | 通过 |
| 图标目视 | 512px PNG：蓝色圆角底、白色房屋与深蓝屏幕，透明边缘正常 | 通过，占位稿 |
| Python 构建入口 | `python client/build.py --help` | 通过 |
| 差异卫生 | `git diff --check` | 通过 |
| 独立代码复核 | 配置路径、CMake/RC 宏、Linux staging、HOMEDESK 标记 | 无 Blocker |

## 尚未完成的门禁

- WSL2 Ubuntu 当前没有 Cargo、CMake 和 Pillow，因此 WSL 内无法跑完整 Rust/CMake/图标构建；这不需要飞牛 NAS，但需要补齐客户端构建工具链。
- Windows 有 Cargo，但 `cargo check --locked --lib --features flutter` 拉取锁定的 `rustdesk-org/hwcodec` 提交时网络超时；使用 Git CLI 与本机代理重试 180 秒仍未完成，未取得完整 Rust 编译通过证据。
- 当前环境没有 Flutter/CMake，尚未实际生成并安装 Windows x64 exe 与 Linux x64 deb；“安装后全部可见文案为 HomeDesk”仍待产包截图验收。
- fnOS 不参与 T-01 开发验证；只在后续家庭 NAS 服务端和客户端联调阶段使用。

在上述门禁完成前，T-01 代码可进入版本控制，但不得把 Windows/Linux 出包验收标为通过。
