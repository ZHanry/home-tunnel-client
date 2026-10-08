"""HomeDesk-specific package staging kept separate from the upstream build script."""

# HOMEDESK: This module transforms only copied packaging templates, never upstream sources.
from __future__ import annotations

import shutil
import stat
from pathlib import Path


def _copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def validate_deb_arch(value: str) -> str:
    valid = (
        bool(value)
        and len(value) <= 32
        and all(
            character.isascii()
            and (character.islower() or character.isdigit() or character in ("-", "_"))
            for character in value
        )
    )
    if not valid:
        raise ValueError(
            "DEB_ARCH must contain only lowercase ASCII letters, digits, '-' or '_'"
        )
    return value


def stage_linux_package(resource_root: Path, stage_root: Path, brand, bundle_root: Path) -> None:
    executable_name = brand.executable_name
    share_root = stage_root / "usr" / "share" / executable_name

    if stage_root.exists():
        shutil.rmtree(stage_root)
    shutil.copytree(bundle_root, share_root)

    from brand_config import copy_branded_text

    copy_branded_text(
        resource_root / "rustdesk.service",
        share_root / "files" / "systemd" / f"{executable_name}.service",
        brand,
    )
    _copy(
        resource_root / "128x128@2x.png",
        stage_root / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps" / f"{executable_name}.png",
    )
    _copy(
        resource_root / "scalable.svg",
        stage_root / "usr" / "share" / "icons" / "hicolor" / "scalable" / "apps" / f"{executable_name}.svg",
    )
    copy_branded_text(
        resource_root / "rustdesk.desktop",
        stage_root / "usr" / "share" / "applications" / f"{executable_name}.desktop",
        brand,
    )
    copy_branded_text(
        resource_root / "rustdesk-link.desktop",
        stage_root / "usr" / "share" / "applications" / f"{executable_name}-link.desktop",
        brand,
    )

    config_root = stage_root / "etc" / executable_name
    config_root.mkdir(parents=True, exist_ok=True)
    _copy(resource_root / "startwm.sh", config_root / "startwm.sh")
    _copy(resource_root / "xorg.conf", config_root / "xorg.conf")
    pam_root = stage_root / "etc" / "pam.d"
    pam_root.mkdir(parents=True, exist_ok=True)
    _copy(resource_root / "pam.d" / "rustdesk.debian", pam_root / executable_name)

    debian_root = stage_root / "DEBIAN"
    shutil.copytree(resource_root / "DEBIAN", debian_root, dirs_exist_ok=True)
    debian_root.chmod(0o755)
    for script in ("postinst", "postrm", "preinst", "prerm"):
        destination = debian_root / script
        copy_branded_text(resource_root / "DEBIAN" / script, destination, brand)
        destination.chmod(0o755)
    control = debian_root / "control"
    if control.is_file():
        control.chmod(0o644)

    polkit = share_root / "files" / "polkit"
    polkit.write_text("#!/bin/sh\n", encoding="utf-8", newline="\n")
    polkit.chmod(polkit.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
