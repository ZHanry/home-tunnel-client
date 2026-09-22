"""Archive the real built Windows WebRTC library, headers and pinned sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/native-windows-build")
    args = parser.parse_args()
    build, output = args.build.resolve(), args.output.resolve()
    source = build.parents[1]
    record = json.loads((build / "remote-host-build.json").read_text(encoding="utf-8"))
    engine = json.loads((build / "remote-webrtc-build.json").read_text(encoding="utf-8"))
    lock_path = ROOT / "native/remote/remote-deps.lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    library = build / "obj/webrtc.lib"
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?", record["version"]):
        raise SystemExit("Invalid native SDK version")
    if record["target_os"] != "win" or record["target_cpu"] != "x64" or record["deps_lock_sha256"] != sha256(lock_path):
        raise SystemExit("Native build target or dependency lock changed")
    if sha256(library) != engine["artifact_sha256"] or library.stat().st_size != engine["artifact_bytes"]:
        raise SystemExit("Native library differs from its actual build record")
    for name, key in [("LICENSE.md", "notices_sha256"), ("remote-source-manifest.json", "source_manifest_sha256")]:
        if sha256(build / name) != record[key]:
            raise SystemExit("Native dependency source or license record changed")
    # LICENSE.md is generated from the actual linked GN dependency graph. Do not
    # redistribute unrelated downloaded compiler, Android or Rust toolchains.
    linked_modules = set(re.findall(r"^# ([a-zA-Z0-9_+./-]+)\n```", (build / "LICENSE.md").read_text(encoding="utf-8"), re.MULTILINE))
    linked_modules.discard("webrtc")
    # libc++ public headers reference this sibling C++ ABI runtime's headers.
    linked_modules.add("libc++abi")
    module_paths = {Path(name) for name in linked_modules if (source / "third_party" / name).is_dir()}
    if not {Path("abseil-cpp"), Path("libc++"), Path("libvpx")}.issubset(module_paths):
        raise SystemExit("Native linked dependency notice set is incomplete")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"HomeTunnel-Remote-SDK-{record['version']}-windows-x64.zip"
    staging = archive.with_suffix(".zip.tmp")
    bundled_record = dict(record)
    bundled_record.pop("executable", None)
    bundled_record["library"] = {"name": "lib/webrtc.lib", "sha256": engine["artifact_sha256"], "bytes": engine["artifact_bytes"]}
    bundled_record["applied_patches"] = lock["patches"]
    bundled_record["header_dependency_modules"] = sorted(path.as_posix() for path in module_paths)
    gn_args = dict(engine["gn_args"])
    for key in ("visual_studio_path", "windows_sdk_path", "wdk_path"):
        if key in gn_args:
            gn_args[key] = "<resolved-by-prepare-remote-windows-sdk.py>"
    bundled_record["gn_args"] = gn_args
    readme = """# Home Tunnel Windows native dependency SDK

This archive contains the actual pinned Windows x64 WebRTC static library and
its source/generated headers. The Go desktop app uses a separately packaged,
hash-pinned home_tunnel_remote_host.exe. The public C ABI header is included for
shared core consumers; its generic media backend is not an implemented host.

Rebuild: check out the exact client revision in remote-sdk-build.json and run
scripts/build-native-windows.ps1. It fetches immutable WebRTC/depot_tools/DEPS,
verifies the reviewed patches, provisions the pinned SDK locally and records the
actual compiler/library identities. Use that pinned compiler and its C++ runtime
when consuming this library; C++ WebRTC does not promise a cross-version ABI.

Headers mirror the upstream checkout under include/webrtc. Generated build
headers are under include/generated. Native public ABI headers are under
native/include. GN target dependency include directories and flags remain those
of the pinned source build; this is not a replacement for its build system.

remote-source-manifest.json lists the corresponding dependency source locations,
versions and build recipe. WEBRTC-THIRD-PARTY-NOTICES.md contains the actual linked
dependency notices. Optional H.264/HEVC code in the pinned engine is not an
advertised or verified codec of the Windows host profile; it negotiates VP8 only.

This SDK does not establish Android, macOS or Linux media interoperability.
"""
    headers = 0
    license_files = 0
    with zipfile.ZipFile(staging, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as bundle:
        print("Archiving the verified native library and source headers", flush=True)
        bundle.write(library, "lib/webrtc.lib")
        for base, directories, files in os.walk(source):
            directories[:] = sorted(name for name in directories if name not in (".git", ".hg", "out", "node_modules", "home_tunnel_remote"))
            relative_base = Path(base).relative_to(source)
            if relative_base == Path("third_party") or Path("third_party") in relative_base.parents:
                relative_module = relative_base.relative_to("third_party")
                directories[:] = [name for name in directories if any(
                    relative_module / name == module or relative_module / name in module.parents or module in (relative_module / name).parents
                    for module in module_paths)]
            for name in sorted(files):
                path = Path(base) / name
                relative = path.relative_to(source)
                is_notice = name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT", "PATENTS", "AUTHORS")) or name in ("README.chromium", "CREDITS.chromium")
                is_header = path.suffix.lower() in (".h", ".hpp", ".inc", ".inl") or "third_party/libc++/src/include/" in relative.as_posix()
                if not is_header and not is_notice:
                    continue
                if path.is_symlink():
                    continue
                bundle.write(path, "include/webrtc/" + relative.as_posix())
                headers += int(is_header)
                license_files += int(is_notice)
                if is_header and headers % 5000 == 0:
                    print(f"Archived {headers} dependency headers", flush=True)
        generated = build / "gen"
        for path in sorted(generated.rglob("*")):
            if path.is_file() and path.suffix.lower() in (".h", ".hpp", ".inc", ".inl"):
                bundle.write(path, "include/generated/" + path.relative_to(generated).as_posix())
        for path in sorted((ROOT / "native/remote/include").rglob("*")):
            if path.is_file():
                bundle.write(path, "native/include/" + path.relative_to(ROOT / "native/remote/include").as_posix())
        bundle.write(lock_path, "remote-deps.lock.json")
        for patch in lock["patches"]:
            path = ROOT / "native/remote" / patch["path"]
            if sha256(path) != patch["sha256"]:
                raise SystemExit("Reviewed source patch changed")
            bundle.write(path, "upstream/" + path.name)
        bundle.write(build / "remote-source-manifest.json", "remote-source-manifest.json")
        bundle.write(build / "LICENSE.md", "WEBRTC-THIRD-PARTY-NOTICES.md")
        bundle.writestr("remote-sdk-build.json", json.dumps(bundled_record, indent=2) + "\n")
        bundle.writestr("README.md", readme)
    if headers < 100 or license_files < 10 or not library.stat().st_size:
        raise SystemExit("Native SDK library/header set is incomplete")
    staging.replace(archive)
    provenance = {"schema_version": 1, "version": record["version"], "repository_revision": record["repository_revision"],
                  "source_modified": record["source_modified"], "target_os": "win", "target_cpu": "x64", "abi_version": 1,
                  "engine": {"revision": record["webrtc_revision"], "lock_sha256": record["deps_lock_sha256"]},
                  "archive": {"name": archive.name, "sha256": sha256(archive)}, "library": bundled_record["library"],
                  "source_manifest_sha256": record["source_manifest_sha256"], "notices_sha256": record["notices_sha256"]}
    (output / "remote-sdk-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"REMOTE_SDK={archive}")
    print(f"REMOTE_SDK_SHA256={provenance['archive']['sha256']}")


if __name__ == "__main__":
    main()
