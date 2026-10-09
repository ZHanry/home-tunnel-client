#!/usr/bin/env python3
"""从简单 SVG 占位图导出 HomeDesk PNG/ICO，并可同步客户端资源。"""

from __future__ import annotations

import argparse
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw


SIZES = (16, 32, 48, 64, 128, 256, 512, 1024)
SVG_NS = "{http://www.w3.org/2000/svg}"


def _number(value: str | None, default: float = 0) -> float:
    if value is None:
        return default
    return float(re.sub(r"[^0-9.+-]", "", value))


def _points(value: str) -> list[tuple[float, float]]:
    numbers = [float(item) for item in re.split(r"[ ,]+", value.strip()) if item]
    return list(zip(numbers[0::2], numbers[1::2]))


def render_svg(source: Path, size: int) -> Image.Image:
    root = ET.parse(source).getroot()
    view_box = [float(item) for item in root.attrib.get("viewBox", "0 0 512 512").split()]
    scale = size / max(view_box[2], view_box[3])
    supersample = 4
    canvas = Image.new("RGBA", (size * supersample, size * supersample), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    def xy(value: float) -> int:
        return round(value * scale * supersample)

    for element in root:
        tag = element.tag.removeprefix(SVG_NS)
        if tag in {"title", "desc"}:
            continue
        fill = element.attrib.get("fill")
        stroke = element.attrib.get("stroke")
        fill = None if fill in (None, "none") else fill
        stroke = None if stroke in (None, "none") else stroke
        width = xy(_number(element.attrib.get("stroke-width"), 1))
        if tag == "rect":
            box = (
                xy(_number(element.attrib.get("x"))),
                xy(_number(element.attrib.get("y"))),
                xy(_number(element.attrib.get("x")) + _number(element.attrib.get("width"))),
                xy(_number(element.attrib.get("y")) + _number(element.attrib.get("height"))),
            )
            draw.rounded_rectangle(box, radius=xy(_number(element.attrib.get("rx"))), fill=fill, outline=stroke, width=width)
        elif tag == "circle":
            cx, cy, radius = (_number(element.attrib.get(k)) for k in ("cx", "cy", "r"))
            draw.ellipse((xy(cx-radius), xy(cy-radius), xy(cx+radius), xy(cy+radius)), fill=fill, outline=stroke, width=width)
        elif tag == "polygon":
            points = [(xy(x), xy(y)) for x, y in _points(element.attrib["points"])]
            draw.polygon(points, fill=fill)
            if stroke:
                draw.line(points + [points[0]], fill=stroke, width=width, joint="curve")
        elif tag in ("polyline", "line"):
            if tag == "line":
                coords = [(_number(element.attrib["x1"]), _number(element.attrib["y1"])), (_number(element.attrib["x2"]), _number(element.attrib["y2"]))]
            else:
                coords = _points(element.attrib["points"])
            points = [(xy(x), xy(y)) for x, y in coords]
            draw.line(points, fill=stroke, width=width, joint="curve")
            radius = width // 2
            for x, y in (points[0], points[-1]):
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=stroke)
        else:
            raise ValueError(f"不支持的 SVG 元素：{tag}")

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def export(source: Path, output: Path) -> dict[int, Path]:
    output.mkdir(parents=True, exist_ok=True)
    generated: dict[int, Path] = {}
    images: list[Image.Image] = []
    for size in SIZES:
        image = render_svg(source, size)
        path = output / f"homedesk-{size}.png"
        image.save(path, optimize=True)
        generated[size] = path
        if size <= 256:
            images.append(image)
    images[-1].save(output / "homedesk.ico", format="ICO", append_images=images[:-1], sizes=[(size, size) for size in SIZES if size <= 256])
    return generated


def apply_client(repo_root: Path, source: Path, output: Path, generated: dict[int, Path]) -> None:
    client = repo_root / "client"
    copies = (
        (generated[512], client / "res" / "icon.png"),
        (generated[256], client / "res" / "128x128@2x.png"),
        (generated[128], client / "res" / "128x128.png"),
        (generated[64], client / "res" / "64x64.png"),
        (generated[32], client / "res" / "32x32.png"),
        (output / "homedesk.ico", client / "res" / "icon.ico"),
        (output / "homedesk.ico", client / "res" / "tray-icon.ico"),
        (output / "homedesk.ico", client / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico"),
        (output / "homedesk.ico", client / "flutter" / "assets" / "icon.ico"),
        (generated[256], client / "flutter" / "assets" / "icon.png"),
        (source, client / "res" / "scalable.svg"),
        (source, client / "flutter" / "assets" / "icon.svg"),
    )
    for source_path, destination in copies:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination)
    render_svg(source, 1024).save(client / 'flutter/macos/Runner/AppIcon.icns', format='ICNS')
    # Tray silhouettes retain the same bridge/cloud geometry at small sizes.
    tray = render_svg(source, 44)
    pixels = tray.load()
    for y in range(tray.height):
        for x in range(tray.width):
            r, g, b, a = pixels[x, y]
            pixels[x, y] = (0, 0, 0, a if min(r, g, b) > 220 else 0)
    tray.save(client / 'res/mac-tray-dark-x2.png', optimize=True)
    # HOMEDESK: Android launcher uses the same source, including adaptive icon safe padding.
    resources = client / "flutter/android/app/src/main/res"
    for density, pixels, foreground in (("mdpi", 48, 108), ("hdpi", 72, 162),
            ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)):
        directory = resources / ("mipmap-" + density)
        directory.mkdir(parents=True, exist_ok=True)
        image = render_svg(source, pixels)
        image.save(directory / "ic_launcher.png", optimize=True)
        image.save(directory / "ic_launcher_round.png", optimize=True)
        safe = Image.new("RGBA", (foreground, foreground), (0, 0, 0, 0))
        symbol_size = round(foreground * 0.60)
        symbol = render_svg(source, symbol_size)
        safe.alpha_composite(symbol, ((foreground-symbol_size)//2, (foreground-symbol_size)//2))
        safe.save(directory / "ic_launcher_foreground.png", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-client", action="store_true", help="同步至 client 的平台图标入口")
    args = parser.parse_args()
    asset_dir = Path(__file__).resolve().parent
    repo_root = asset_dir.parent.parent
    source = asset_dir / "homedesk.svg"
    output = asset_dir / "generated"
    generated = export(source, output)
    if args.apply_client:
        apply_client(repo_root, source, output, generated)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
