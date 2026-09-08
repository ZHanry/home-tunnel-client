# 飞腾 ARM64 / 麒麟适配记录

2026-09-08，用户目标为飞腾 ARM64、麒麟系统；具体麒麟版本、glibc 和桌面会话尚未提供。

## 已准备

- 已下载官方 RustDesk 1.4.9 的 `rustdesk-1.4.9-aarch64.deb` 到 `client/target/homedesk-p0/`（忽略目录）。
- SHA256 与 GitHub Release 资产一致：`ce62c996f14d33f3bbe3a330e953644a44bace7f05885a7953f7395d69fb49c0`。
- `dpkg-deb -f` 验证架构为 `arm64`，版本为 `1.4.9`。这是官方原版，未包含 HomeDesk 新增功能，也未在麒麟安装。
- `client/build.py` 已按原生架构选择 ARM64 bundle、deb 架构与 `flutter-elinux`；不再需要上游工作流中的源码 sed 替换。
- `build/ci/build-client.py --target linux-arm64` 在非 ARM64 主机明确拒绝执行；需要 ARM64 原生构建机。
- `build/ci/prepare-offline.sh` 和 `install-offline.sh` 提供同系统、同架构依赖下载、SHA256 检查及禁止联网安装路径。

## 实际依赖与限制

官方 ARM64 包声明 GTK3、XCB、XDo、XFixes、ALSA、systemd、curl、libva、GStreamer、PAM 和 gstreamer1.0-pipewire 等依赖。老版本麒麟未必提供全部包；不能据“CPU 架构一致”判定可安装。

仓库上游 `client/src/lang.rs` 的 `cjk_ui_unavailable()` 对 Linux aarch64 Flutter 启用中日韩语言回退，中文可能回退英文。当前保留此兼容处理，需在目标引擎/字体实测后决定修复方案；不能宣称 ARM64 中文界面验收通过。

目标电脑提供以下非敏感信息后再做兼容判定：

```bash
cat /etc/os-release
uname -m
getconf GNU_LIBC_VERSION
echo "$XDG_SESSION_TYPE"
```

优先 X11。安装后允许安全中心中的应用运行与开机自启动，验证锁屏/登录界面、中文输入、双向文件传输和重启恢复。

## 定制构建

锁定版本依据 `client/.github/workflows/flutter-build.yml`：Rust 最低 1.75；本轮验证工具链 1.96.0；Flutter 3.24.5；vcpkg 基线 `120deac3062162151622ca4860575a33844ba10b`，triplet 为 `arm64-linux`。ARM64 还需要对应的 sony/flutter-elinux 与 shader_lib 资源，按上游 ARM64 流程准备。

```bash
python3 build/ci/build-client.py --target linux-arm64 --config /受控路径/config.toml --check
python3 build/ci/build-client.py --target linux-arm64 --config /受控路径/config.toml
```

当前没有 ARM64 构建机或可用的模拟器，尚未生成 HomeDesk ARM64 安装包，也没有进行离线安装实测。龙芯 no-GUI 属于独立探索任务，本轮未实现。
