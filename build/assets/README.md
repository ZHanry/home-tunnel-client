# NestLink 品牌资源

`brand/icon.svg` 是图标的唯一矢量源文件。开发桌面客户端时运行：

```bash
python build/assets/export_icons.py --apply-client --desktop-only
```

脚本依赖 Pillow，导出 16–1024 px PNG 和多尺寸 ICO，同步 Windows 可执行文件、托盘及 Flutter 图标入口。不加 `--desktop-only` 时还会同步移动端和 macOS 资源。
