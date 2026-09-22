"""Prepare the locked Microsoft SDK in a private build cache, without installation.

Uses official SHA256-pinned NuGet SDK packages and an existing Visual Studio C++
installation. No registry, global PATH or upstream source changes are made.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def junction(path, target):
    if path.exists():
        if path.resolve() != target.resolve():
            raise SystemExit(f"Refusing to replace existing path: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cmd", "/d", "/c", "mklink", "/J", str(path), str(target)], check=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visual-studio", type=Path, required=True)
    parser.add_argument("--visual-studio-version", choices=["2022", "2026"], default="2022")
    parser.add_argument("--cache", type=Path, default=ROOT / ".downloads/remote-webrtc/windows-toolchain")
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("This helper requires Windows")
    visual_studio = args.visual_studio.resolve()
    msvc_versions = sorted((visual_studio / "VC/Tools/MSVC").glob("*"), key=lambda p: tuple(map(int, p.name.split("."))))
    if not msvc_versions:
        raise SystemExit("An installed Visual Studio C++ toolchain is required")
    msvc_version = msvc_versions[-1].name
    lock = json.loads((ROOT / "native/remote/remote-deps.lock.json").read_text())
    tc = lock["toolchain"]
    cache = args.cache.resolve()
    packages = cache / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    extracted = packages / "expanded"
    for package, digest in tc["windows_sdk_packages"].items():
        archive = packages / (package + ".nupkg")
        if not archive.exists():
            version = tc["windows_sdk_package_version"]
            url = f"https://api.nuget.org/v3-flatcontainer/{package}/{version}/{package}.{version}.nupkg"
            with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
                while data := response.read(1024 * 1024):
                    output.write(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
            raise SystemExit(f"SDK package digest mismatch: {package}")
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                if not entry.filename.startswith("c/") or entry.is_dir():
                    continue
                destination = extracted / entry.filename
                if not destination.resolve().is_relative_to(extracted.resolve()):
                    raise SystemExit("SDK package contains an unsafe path")
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(source.read(entry))
    sdk_source = extracted / "c"
    toolchain = cache / "root"
    sdk = toolchain / "Windows Kits/10"
    junction(toolchain / "VC", visual_studio / "VC")
    for directory in ["Include", "Redist", "References", "UnionMetadata"]:
        junction(sdk / directory, sdk_source / directory)
    version = tc["windows_sdk_version"]
    junction(sdk / "bin" / version, sdk_source / "bin" / version)
    for directory in ["um", "ucrt"]:
        junction(sdk / "Lib" / version / directory, sdk_source / directory)
    msvc = toolchain / "VC/Tools/MSVC" / msvc_version
    # Upstream supports explicit toolchains using SetEnv JSON and cmd files.
    # Both representations must agree; only ordinary compiler variables are set.
    values = {
        "VSINSTALLDIR": str(toolchain),
        "INCLUDE": ";".join(str(p) for p in [msvc / "include", *[sdk / "Include" / version / sub for sub in ["ucrt", "shared", "um", "winrt", "cppwinrt"]]]),
        "LIB": ";".join(str(p) for p in [msvc / "lib/x64", sdk / "Lib" / version / "um/x64", sdk / "Lib" / version / "ucrt/x64"]),
        "PATH": ";".join(str(p) for p in [msvc / "bin/Hostx64/x64", sdk / "bin" / version / "x64"]),
    }
    for key in ["INCLUDE", "LIB", "PATH"]:
        for path in values[key].split(";"):
            if not Path(path).is_dir():
                raise SystemExit(f"Missing compiler path: {path}")
    # Local paths are validated against CMD expansion/metacharacters before use.
    if any(any(char in value for char in '%!&|<>^"\r\n') for value in values.values()):
        raise SystemExit("Portable toolchain path contains unsupported shell characters")
    cmd = '@echo off\nif "%~1"=="/x64" goto x64\nif "%~1"=="/x86" goto x86\nexit /b 2\n'
    for cpu in ["x64", "x86"]:
        cpu_values = {key: value.replace("/x64", "/" + cpu).replace("\\x64", "\\" + cpu) if key in ["LIB", "PATH"] else value for key, value in values.items()}
        environment = {key: [[entry] for entry in value.split(";")] for key, value in cpu_values.items()}
        (sdk / f"bin/SetEnv.{cpu}.json").write_text(json.dumps({"env": environment}, indent=2) + "\n")
        cmd += ":" + cpu + "\n"
        for key, value in cpu_values.items():
            cmd += f'set "{key}={value}' + (';%PATH%' if key == 'PATH' else '') + '"\n'
        cmd += "exit /b 0\n"
    (sdk / "bin/SetEnv.cmd").write_text(cmd, encoding="utf-8")
    manifest = {"visual_studio_path": str(toolchain), "visual_studio_version": args.visual_studio_version,
                "windows_sdk_path": str(sdk), "windows_sdk_version": version,
                "wdk_path": str(sdk), "msvc_version": msvc_version,
                "sdk_package_sha256": tc["windows_sdk_packages"], "portable": True}
    destination = cache / "portable-toolchain.json"
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
