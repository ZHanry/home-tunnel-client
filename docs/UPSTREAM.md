# RustDesk 上游基线

更新时间：2026-08-11

## 当前客户端基线

| 项目 | 值 |
| --- | --- |
| 上游仓库 | <https://github.com/rustdesk/rustdesk> |
| 稳定标签 | `1.4.9` |
| 标签提交 | `6c578292e8ebbbec708b76986ba8c4bc7c509747` |
| 上游发布日期 | 2026-07-06 |
| 引入方式 | `git subtree`，目录 `client/`，保留上游历史 |
| 本仓库引入提交 | `79035e842852049ecc9e40c0922affeec64b9303` |
| 许可证 | AGPL-3.0 |

稳定版本以[官方 1.4.9 Release](https://github.com/rustdesk/rustdesk/releases/tag/1.4.9)和标签提交为准，不跟随 `master` 或 nightly。

`client/libs/hbb_common` 是上游 gitlink，固定到 `7e1c392c62d39c364127307cd408421dd5f8cfb0`。根目录 `.gitmodules` 使用完整路径 `client/libs/hbb_common`，新克隆执行：

```bash
git submodule sync --recursive
git submodule update --init --recursive client/libs/hbb_common
```

## HomeDesk 定制边界

- 保留内部 Cargo crate、`librustdesk` 动态库名、Flutter method channel、Linux application ID 与协议实现，避免破坏上游兼容性。
- 只把用户可见应用名、启动器名、安装包名、桌面项、托盘/窗口标题和图标接到 `build/config.toml [brand]`。
- 上游文本代码的接线点均带 `HOMEDESK:` 标记；品牌逻辑优先放在独立文件。
- 不修改传输协议、编解码、加密或认证实现。

## 后续更新流程

1. 核对新的官方稳定 Release、完整标签 SHA 与许可证变化。
2. 单独提交上游 subtree 更新，不与 HomeDesk 功能修改混合。
3. 同步并核对嵌套 submodule gitlink。
4. 用 `rg -n "HOMEDESK:" client` 逐项复核品牌接线冲突。
5. 重跑 Windows x64、Linux x64 构建和 `tests/smoke.md`，通过后再更新本文件。
