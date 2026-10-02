#!/usr/bin/env python3
"""读取 HomeDesk 构建期品牌配置并生成平台构建文件。"""

from __future__ import annotations

import argparse
import base64
import ipaddress
import json
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit


_VALUE_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*")\s*$')
_SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{0,62}[a-z0-9]$|^[a-z]$")


@dataclass(frozen=True)
class BrandConfig:
    app_name: str
    executable_name: str
    package_name: str
    source: Path


@dataclass(frozen=True)
class ServerConfig:
    host: str
    relay_host: str
    key: str


@dataclass(frozen=True)
class NetConfig:
    mode: str
    whitelist_cidr: str
    source_cidr: str


@dataclass(frozen=True)
class BuildConfig:
    brand: BrandConfig
    server: ServerConfig
    net: NetConfig
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


def _read_sections(source: Path, selected: set[str]) -> dict[str, dict[str, object]]:
    sections: dict[str, dict[str, object]] = {name: {} for name in selected}
    section = ""
    for line_number, raw_line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        line = _strip_comment(raw_line).strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section not in selected:
            continue
        match = _VALUE_RE.fullmatch(line)
        if match:
            key, encoded_value = match.groups()
            try:
                value: object = json.loads(encoded_value)
            except json.JSONDecodeError as error:
                raise ValueError(f"{source}:{line_number} 字符串转义无效") from error
        else:
            key, separator, raw_value = line.partition("=")
            key = key.strip()
            raw_value = raw_value.strip()
            if not separator or raw_value not in ("true", "false"):
                raise ValueError(f"{source}:{line_number} 不是受支持的 {section} 配置")
            value = raw_value == "true"
        if key in sections[section]:
            raise ValueError(f"{source}:{line_number} {section}.{key} 重复定义")
        sections[section][key] = value
    return sections


def _required_string(values: dict[str, object], section: str, key: str, source: Path) -> str:
    value = values.get(key)
    if not isinstance(value, str):
        raise ValueError(f"{source} 缺少字符串配置 {section}.{key}")
    return value


def _load_brand_from_values(values: dict[str, object], source: Path) -> BrandConfig:
    return _validate(
        BrandConfig(
            app_name=_required_string(values, "brand", "app_name", source),
            executable_name=_required_string(values, "brand", "executable_name", source),
            package_name=_required_string(values, "brand", "package_name", source),
            source=source,
        )
    )


_PRIVATE_NETWORKS = tuple(
    ipaddress.ip_network(cidr) for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)


def _validate_server_net(
    server: ServerConfig, net: NetConfig, source: Path
) -> tuple[ServerConfig, NetConfig]:
    if net.mode not in ("lan_only", "self_hosted"):
        raise ValueError(f"{source} net.mode 仅允许 lan_only 或 self_hosted")
    for key, endpoint in (("server.host", server.host), ("server.relay_host", server.relay_host)):
        host, separator, port = endpoint.rpartition(":")
        if not separator:
            host, port = endpoint, ""
        if port and (not port.isdecimal() or not 1 <= int(port) <= 65535):
            raise ValueError(f"{source} {key} 端口无效")
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            valid = net.mode == "self_hosted" and "." in host and not all(c.isdigit() or c == "." for c in host) and not host.rsplit(".", 1)[-1].isdigit() and all(
                label and len(label) <= 63 and re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label)
                for label in host.split(".")
            )
        else:
            valid = isinstance(address, ipaddress.IPv4Address) and not (
                address.is_unspecified or address.is_loopback or address.is_link_local or address.is_multicast or int(address) >> 28 == 0xF
                or address in ipaddress.ip_network("100.64.0.0/10")
            ) and (net.mode == "self_hosted" or any(address in item for item in _PRIVATE_NETWORKS))
        if not valid:
            raise ValueError(f"{source} {key} 不符合 {net.mode} 网络边界")

    try:
        decoded_key = base64.b64decode(server.key, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError(f"{source} server.key 必须是有效的 hbbs Base64 公钥") from error
    if len(decoded_key) != 32:
        raise ValueError(f"{source} server.key 必须解码为 32 字节 hbbs 公钥")

    try:
        whitelist = ipaddress.ip_network(net.whitelist_cidr, strict=False)
    except ValueError as error:
        raise ValueError(f"{source} net.whitelist_cidr 必须是有效的 IPv4 CIDR") from error
    if not isinstance(whitelist, ipaddress.IPv4Network) or not any(
        whitelist.subnet_of(item) for item in _PRIVATE_NETWORKS
    ):
        raise ValueError(f"{source} net.whitelist_cidr 必须完全位于 RFC1918 内网范围")
    if net.source_cidr:
        try:
            source_net = ipaddress.ip_network(net.source_cidr, strict=False)
        except ValueError as error:
            raise ValueError(f"{source} net.source_cidr 必须是有效 IPv4 CIDR") from error
        if not isinstance(source_net, ipaddress.IPv4Network) or source_net.prefixlen == 0 or source_net.is_loopback or source_net.is_link_local or source_net.is_multicast or source_net.is_unspecified:
            raise ValueError(f"{source} net.source_cidr 不能允许全部来源")
    return server, net


def load_brand(path: Path | None = None, repo_root: Path | None = None) -> BrandConfig:
    source = (path or resolve_config_path(repo_root)).resolve()
    if not source.is_file():
        raise FileNotFoundError(f"品牌配置不存在：{source}")

    return _load_brand_from_values(_read_sections(source, {"brand"})["brand"], source)


def load_config(path: Path | None = None, repo_root: Path | None = None) -> BuildConfig:
    source = (path or resolve_config_path(repo_root)).resolve()
    if not source.is_file():
        raise FileNotFoundError(f"构建配置不存在：{source}")
    values = _read_sections(source, {"brand", "server", "net"})
    brand = _load_brand_from_values(values["brand"], source)
    server = ServerConfig(
        host=_required_string(values["server"], "server", "host", source),
        relay_host=str(values["server"].get("relay_host") or ""),
        key=_required_string(values["server"], "server", "key", source),
    )
    mode = values["net"].get("mode")
    legacy = values["net"].get("pure_lan_default")
    if mode is not None and legacy is not None:
        raise ValueError(f"{source} net.mode 与旧 net.pure_lan_default 不能同时配置")
    if mode is None:
        if legacy is False:
            raise ValueError(f"{source} 旧 net.pure_lan_default=false 不能隐式开启公网")
        mode = "lan_only"
    if not isinstance(mode, str):
        raise ValueError(f"{source} net.mode 必须是字符串")
    if not server.relay_host:
        host = server.host.rsplit(":", 1)[0] if ":" in server.host and server.host.rsplit(":", 1)[-1].isdigit() else server.host
        server = ServerConfig(host=server.host, relay_host=f"{host}:21117", key=server.key)
    net = NetConfig(
        mode=mode,
        whitelist_cidr=_required_string(values["net"], "net", "whitelist_cidr", source),
        source_cidr=str(values["net"].get("source_cidr") or ""),
    )
    _validate_server_net(server, net, source)
    console = _read_sections(source, {"console"})["console"]
    enabled = console.get("enabled", False)
    trusted_path = console.get("trusted_path", False)
    if not isinstance(enabled, bool):
        raise ValueError("console.enabled 必须为布尔值")
    if not isinstance(trusted_path, bool):
        raise ValueError("console.trusted_path 必须为布尔值")
    if enabled and (net.mode == "lan_only" or trusted_path):
        url = urlsplit(_required_string(console, "console", "url", source))
        try:
            address = ipaddress.ip_address(url.hostname or "")
            valid = isinstance(address, ipaddress.IPv4Address) and any(address in n for n in _PRIVATE_NETWORKS)
            valid = valid and url.scheme == "http" and url.port is not None and url.port > 0
            valid = valid and not url.username and not url.password and url.path in ("", "/") and not url.query and not url.fragment
        except ValueError:
            valid = False
        if not valid:
            raise ValueError("console.url 必须是显式端口的内网 HTTP 地址")
        token = _required_string(console, "console", "token", source)
        if not 32 <= len(token) <= 256 or not all(33 <= ord(c) <= 126 for c in token) or "REPLACE_WITH" in token:
            raise ValueError("console.token 必须为 32 至 256 位有效访问口令")
    return BuildConfig(brand=brand, server=server, net=net, source=source)


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

    build_config = load_config(args.config)
    config = build_config.brand
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
                    "server_host": build_config.server.host,
                    "relay_host": build_config.server.relay_host,
                    "server_key_configured": True,
                    "whitelist_cidr": build_config.net.whitelist_cidr,
                    "net_mode": build_config.net.mode,
                    "source_cidr": build_config.net.source_cidr,
                    "source": str(config.source),
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
