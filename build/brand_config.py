#!/usr/bin/env python3
"""读取 HomeDesk 构建期品牌配置并生成平台构建文件。"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path


_VALUE_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*")\s*$')
_SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{0,62}[a-z0-9]$|^[a-z]$")


@dataclass(frozen=True)
class BrandConfig:
    app_name: str
    executable_name: str
    package_name: str
    source: Path


def repository_root() -> Path:
    return Path(__file__).resolve().parent.parent


def resolve_config_path(repo_root: Path | None = None) -> Path:
    override = os.environ.get("HOMEDESK_CONFIG_PATH")
    if override:
        return Path(override).expanduser().resolve()

    root = (repo_root or repository_root()).resolve()
    local_config = root / "build" / "config.toml"
    if local_config.is_file():
        return local_config
    return root / "build" / "config.toml.example"


def _strip_comment(line: str) -> str:
    quoted = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quoted:
            escaped = True
            continue
        if char == '"':
            quoted = not quoted
        elif char == "#" and not quoted:
            return line[:index]
    return line


def _validate(config: BrandConfig) -> BrandConfig:
    if not config.app_name or len(config.app_name) > 64:
        raise ValueError("brand.app_name 必须为 1 到 64 个字符")
    if any(ord(char) < 32 for char in config.app_name):
        raise ValueError("brand.app_name 不能包含控制字符")
    if config.app_name != config.app_name.strip() or any(
        char in '<>:"/\\|?*' for char in config.app_name
    ):
        raise ValueError("brand.app_name 不能包含文件名保留字符或首尾空白")
    for key, value in (
        ("executable_name", config.executable_name),
        ("package_name", config.package_name),
    ):
        if not _SLUG_RE.fullmatch(value):
            raise ValueError(f"brand.{key} 必须为小写字母开头的 kebab-case 名称")
    return config


def load_brand(path: Path | None = None, repo_root: Path | None = None) -> BrandConfig:
    source = (path or resolve_config_path(repo_root)).resolve()
    if not source.is_file():
        raise FileNotFoundError(f"品牌配置不存在：{source}")

    section = ""
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        line = _strip_comment(raw_line).strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section != "brand":
            continue
        match = _VALUE_RE.fullmatch(line)
        if not match:
            raise ValueError(f"{source}:{line_number} 不是受支持的 brand 字符串配置")
        key, encoded_value = match.groups()
        if key in values:
            raise ValueError(f"{source}:{line_number} brand.{key} 重复定义")
        try:
            values[key] = json.loads(encoded_value)
        except json.JSONDecodeError as error:
            raise ValueError(f"{source}:{line_number} brand 字符串转义无效") from error

    required = ("app_name", "executable_name", "package_name")
    missing = [key for key in required if key not in values]
    if missing:
        raise ValueError(f"{source} 缺少 brand 配置：{', '.join(missing)}")
    return _validate(
        BrandConfig(
            app_name=values["app_name"],
            executable_name=values["executable_name"],
            package_name=values["package_name"],
            source=source,
        )
    )


def _c_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _cmake_escape(value: str) -> str:
    return _c_escape(value).replace(";", "\\;").replace("$", "\\$")


def write_cmake(config: BrandConfig, output: Path) -> None:
    content = (
        f'set(HOMEDESK_APP_NAME "{_cmake_escape(config.app_name)}")\n'
        f'set(HOMEDESK_EXECUTABLE_NAME "{_cmake_escape(config.executable_name)}")\n'
        f'set(HOMEDESK_PACKAGE_NAME "{_cmake_escape(config.package_name)}")\n'
        f'set(HOMEDESK_BRAND_SOURCE "{_cmake_escape(config.source.as_posix())}")\n'
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8", newline="\n")


def write_c_header(config: BrandConfig, output: Path) -> None:
    app_name = _c_escape(config.app_name)
    executable_name = _c_escape(config.executable_name)
    content = (
        "#pragma once\n"
        f'#define HOMEDESK_APP_NAME "{app_name}"\n'
        f'#define HOMEDESK_APP_NAME_WIDE L"{app_name}"\n'
        f'#define HOMEDESK_EXECUTABLE_NAME "{executable_name}"\n'
        f'#define HOMEDESK_ORIGINAL_FILENAME "{executable_name}.exe"\n'
        f'#define HOMEDESK_FILE_DESCRIPTION "{app_name} Remote Desktop"\n'
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8", newline="\n")


def copy_branded_text(source: Path, destination: Path, config: BrandConfig) -> None:
    content = source.read_text(encoding="utf-8")
    content = content.replace("RustDesk", config.app_name)
    content = content.replace("rustdesk", config.executable_name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content, encoding="utf-8", newline="\n")
    shutil.copymode(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="覆盖默认品牌配置路径")
    parser.add_argument("--cmake-out", type=Path, help="生成 CMake 变量文件")
    parser.add_argument("--header-out", type=Path, help="生成 C/C++/RC 头文件")
    parser.add_argument("--print-json", action="store_true", help="输出解析结果")
    args = parser.parse_args()

    config = load_brand(args.config)
    if args.cmake_out:
        write_cmake(config, args.cmake_out)
    if args.header_out:
        write_c_header(config, args.header_out)
    if args.print_json:
        print(
            json.dumps(
                {
                    "app_name": config.app_name,
                    "executable_name": config.executable_name,
                    "package_name": config.package_name,
                    "source": str(config.source),
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
