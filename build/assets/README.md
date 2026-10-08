# HomeDesk 品牌资源

`homedesk.svg` 是当前占位图标的唯一矢量源文件。运行：

```bash
python build/assets/export_icons.py --apply-client
```

脚本依赖 Pillow，导出 16–512px PNG 和多尺寸 ICO，并同步 RustDesk fork 的 Windows、Linux、Flutter 图标入口。正式视觉稿确定后，只替换 SVG 并重新运行脚本。
