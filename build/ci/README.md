# 构建与验证入口

- `build-client.py`：配置及工具链预检、Windows x64/Linux x64/Linux ARM64 原生构建。不支持在 x64 上伪装 ARM64；`--check` 只检查。
- `prepare-offline.sh`：在与目标麒麟同版本/同架构的联网机器准备 deb 及完整依赖。
- `install-offline.sh`：检查摘要和架构，使用 `apt-get --no-download` 离线安装。
- `prepare-windows-plugins.ps1`：使用项目内 Junction 准备 Windows 插件链接，不修改开发者模式；已验证 Dart 3.5.4 识别及删除链接时不触及目标目录。
- `build-console.sh`：Linux x64/ARM64 原生 musl 构建及 scratch 镜像；避免基础镜像下载依赖。
- `scan-secrets.py`：使用 gitleaks 8.30.1 扫描 Git 可提交文件，跳过被忽略的真实配置和缓存，始终脱敏输出。
- `gitleaks-baseline.json`：84 项上游原样公钥示例与测试夹具，限定文件内容 SHA256、行号和检测规则。文件任何变更会使对应豁免失效，不是目录级排除。

`.github/workflows/verify.yml` 执行 API、发送器、配置、打包和密钥检查。`.github/workflows/build-clients.yml` 仅手动触发，使用带 `homedesk-build` 标签的私有 Windows/Linux/ARM64 原生 Runner；真实构建配置位于 Runner 的受控本地路径，通过变量 `HOMEDESK_CONFIG_PATH` 指定，不上传配置或口令。

Runner 需要预装（构建入口会识别项目本地 `client/target/toolchains/` 和已安装 VS Build Tools）：

| 平台 | 前置条件 |
| --- | --- |
| Windows x64 | Rust、Visual Studio C++/Windows SDK、CMake、Flutter 3.24.5、Python、vcpkg x64-windows-static、LLVM/libclang |
| Linux x64 | Rust、CMake/Clang/Ninja/pkg-config、GTK3/X11/音频/VA 开发包、Flutter 3.24.5、vcpkg x64-linux |
| Linux ARM64 | 同架构原生工具链、sony/flutter-elinux、shader_lib 资源、vcpkg arm64-linux；麒麟系统依赖另见 XINCHUANG.md |

vcpkg 基线使用上游 `120deac3062162151622ca4860575a33844ba10b`，不能浅克隆，否则历史 override 端口的 tree 缺失。桥接工具固定 `flutter_rust_bridge_codegen 1.80.1`（uuid feature）与 `cargo-expand 1.0.95`，入口会生成被上游忽略的 Rust/Dart 桥接文件。Windows ffigen 使用完整 libclang.dll 路径，codegen 的 `RUST_LOG` 需为 info/debug。

本机已找到 VS2022 Build Tools，并准备 Flutter 3.24.5、libclang、vcpkg 原生库、桥接工具和便携 PowerShell。vcpkg 在短 buildtrees/ASCII TEMP 下通过 aom，便携 PowerShell 解决 Store 版本子进程不可执行的问题。原生库全套安装与 Windows 完整 Rust 编译检查已通过；私有 Runner 与三平台 CI 尚未实际运行。

`pubspec.lock` 已按固定 Flutter 3.24.5 修复缺失的 flutter_test 及其 SDK 依赖约束，未升级应用依赖；后续 pub get 使用 `--enforce-lockfile`，不能任意升级依赖解决构建问题。
