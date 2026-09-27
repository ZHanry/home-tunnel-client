"""Package and verify a tagged Android controller SDK for one reviewed ABI.

arm64-v8a remains the default archive and provenance names. x86_64 is a second
production WebRTC controller from the same source and dependency lock, not a
security-core library or a rewritten emulator tree. Device acceptance is not implied.
"""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/remote"
MAX_SDK_FILES = 65536  # The pinned dependency snapshot currently contains about 40,000 headers.
ENGINE_SPEC = importlib.util.spec_from_file_location("android_engine_build", ROOT / "scripts/build-remote-android-webrtc.py")
ENGINE = importlib.util.module_from_spec(ENGINE_SPEC)
ENGINE_SPEC.loader.exec_module(ENGINE)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def archive_name(version, abi=ENGINE.DEFAULT_ABI):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[1-9][0-9]*)?", version):
        raise SystemExit("Invalid Android SDK version")
    profile = ENGINE.ABI_PROFILES[ENGINE.require_abi(abi)]
    return f"HomeTunnel-Remote-SDK-{version}-android-{profile['asset_token']}.zip"


def provenance_name(abi=ENGINE.DEFAULT_ABI):
    abi = ENGINE.require_abi(abi)
    if abi == ENGINE.DEFAULT_ABI:
        return "android-sdk-provenance.json"
    return f"android-sdk-{ENGINE.ABI_PROFILES[abi]['asset_token']}-provenance.json"


def sbom_name(abi=ENGINE.DEFAULT_ABI):
    abi = ENGINE.require_abi(abi)
    if abi == ENGINE.DEFAULT_ABI:
        return "android-sdk.spdx.json"
    return f"android-sdk-{ENGINE.ABI_PROFILES[abi]['asset_token']}.spdx.json"


def engine_prefix(abi=ENGINE.DEFAULT_ABI):
    return ENGINE.ABI_PROFILES[ENGINE.require_abi(abi)]["output_dir"]


def release_asset_names(version):
    names = []
    for abi in ENGINE.ABI_ORDER:
        archive = archive_name(version, abi)
        group = [archive, archive + ".sha256", provenance_name(abi), sbom_name(abi)]
        names.extend(group)
        names.extend(name + ".sigstore.json" for name in group)
    return names


def describe(version, abi):
    abi = ENGINE.require_abi(abi)
    profile = ENGINE.ABI_PROFILES[abi]
    archive = archive_name(version, abi)
    return {
        "abi": abi,
        "gn_cpu": profile["gn_cpu"],
        "elf_machine": profile["elf_machine"],
        "asset_token": profile["asset_token"],
        "archive": archive,
        "provenance": provenance_name(abi),
        "sbom": sbom_name(abi),
        "checksum": archive + ".sha256",
        "engine_prefix": engine_prefix(abi),
        "engine_dir": profile["output_dir"],
        "build_dir": profile["build_dir"],
        "library_dir": f"lib/{abi}",
        "android_api": ENGINE.ANDROID_API,
        "page_size": ENGINE.PAGE_SIZE,
        "default_abi": ENGINE.DEFAULT_ABI,
    }


def provenance_identity(version, revision, abi, archive, tree, upstream, android):
    abi = ENGINE.require_abi(abi)
    profile = ENGINE.ABI_PROFILES[abi]
    return {
        "schema_version": 1,
        "repository": "ZHanry/home-tunnel-client",
        "source_revision": revision,
        "source_modified": False,
        "source_tree_sha256": tree,
        "version": version,
        "tag": "v" + version,
        "target": abi,
        "elf_machine": profile["elf_machine"],
        "android_api": ENGINE.ANDROID_API,
        "page_size": ENGINE.PAGE_SIZE,
        "controller_backend_linked": True,
        "production_controller": True,
        "device_media_accepted": False,
        "archive": archive,
        "upstream_lock_sha256": android["upstream_lock_sha256"],
        "recipe_sha256": ENGINE.sha(ENGINE.ANDROID / "android-build.lock.json"),
        "gn_args": ENGINE.resolved_gn_args(android, abi),
        "compiler_lock": ENGINE.compiler_lock(upstream, android),
    }


def source_files():
    return {path.relative_to(NATIVE).as_posix(): digest(path) for path in sorted(NATIVE.rglob("*")) if path.is_file() and
            (path.suffix in {".cpp", ".hpp", ".h", ".json", ".md", ".patch", ".gn", ".exports"} or path.name in {"CMakeLists.txt", "DEPS", "WEBRTC-LICENSE"})}


def source_tree_sha256(files=None):
    actual = source_files() if files is None else files
    return hashlib.sha256(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def checked_members(bundle):
    result = {}
    total = 0
    for entry in bundle.infolist():
        name = entry.filename
        path = PurePosixPath(name)
        total += entry.file_size
        if (not name or name != path.as_posix() or path.is_absolute() or any(p in (".", "..") for p in name.split("/")) or
                "\\" in name or ":" in name or any(ord(c) < 32 for c in name) or entry.is_dir() or
                stat.S_ISLNK(entry.external_attr >> 16) or name in result or entry.flag_bits & 1 or
                entry.file_size > 1024 ** 3 or total > 3 * 1024 ** 3 or len(result) >= MAX_SDK_FILES):
            raise SystemExit("Unsafe, duplicate or oversized Android SDK member")
        result[name] = entry
    return result


def verify(directory, version, revision, abi=None):
    abi = ENGINE.require_abi(abi) if abi is not None else ENGINE.DEFAULT_ABI
    provenance_path = directory / provenance_name(abi)
    if not provenance_path.is_file():
        raise SystemExit("Android SDK provenance does not match the requested ABI")
    record = json.loads(provenance_path.read_text(encoding="utf-8"))
    name = archive_name(version, abi)
    actual = source_files()
    tree = source_tree_sha256(actual)
    upstream, android = ENGINE.locks()
    expected = provenance_identity(version, revision, abi, name, tree, upstream, android)
    if any(record.get(key) != value for key, value in expected.items()):
        raise SystemExit("Android SDK release identity differs from the tagged source")
    path = directory / name
    if digest(path) != record.get("archive_sha256") or path.stat().st_size != record.get("archive_bytes"):
        raise SystemExit("Android SDK archive bytes differ from provenance")
    checksum = directory / (name + ".sha256")
    if not checksum.is_file() or checksum.read_text(encoding="utf-8") != f"{record['archive_sha256']}  {name}\n":
        raise SystemExit("Android SDK checksum file differs from provenance")
    prefix = engine_prefix(abi)
    with zipfile.ZipFile(path) as bundle:
        members = checked_members(bundle)
        if set(members) != set(record.get("files", {})):
            raise SystemExit("Android SDK inventory differs from provenance")
        for member in members:
            with bundle.open(member) as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != record["files"][member]:
                    raise SystemExit("Android SDK member digest differs from provenance")
        def read_json(member):
            if member not in members or members[member].file_size > 8 * 1024 * 1024:
                raise SystemExit("Android SDK required manifest is missing or oversized")
            return json.loads(bundle.read(member))
        engine = read_json(f"{prefix}/android-webrtc-build.json")
        source = read_json("source/remote-artifact.json")
        ENGINE.production_controller_manifest(engine, upstream, android, abi)
        if (engine.get("source_revision") != revision or engine.get("source_files") != actual or engine.get("source_tree_sha256") != tree or
                source.get("source_revision") != revision or source.get("source_tree_dirty") is not False or
                source.get("source_files") != actual or source.get("source_tree_sha256") != tree or
                source.get("header_sha256") != actual.get("include/home_tunnel/remote.h")):
            raise SystemExit("Android SDK engine/source/dependency identity mismatch")
        required = {f"lib/{abi}/libwebrtc.a", f"lib/{abi}/libhome_tunnel_android_surface.a",
                    f"lib/{abi}/libhome_tunnel_remote.so", "include/home_tunnel/remote.h", "LICENSE.md", "source-manifest.json",
                    "PROJECT-LICENSE", "source-license-inventory.json"}
        if not required.issubset(engine.get("files", {})):
            raise SystemExit("Android SDK omits required engine/source/license files")
        if {prefix + "/" + key for key in engine["files"]} != {key for key in members if key.startswith(prefix + "/")} - {f"{prefix}/android-webrtc-build.json"}:
            raise SystemExit("Android SDK engine inventory changed")
        for key, checksum in engine["files"].items():
            if record["files"].get(prefix + "/" + key) != checksum:
                raise SystemExit("Android SDK engine digest differs from its build manifest")
        ENGINE.verify_notice_record(read_json(f"{prefix}/source-license-inventory.json"),
                                    read_json(f"{prefix}/source-manifest.json"), engine["files"])
        if bundle.read(f"{prefix}/PROJECT-LICENSE") != (ROOT / "LICENSE").read_bytes():
            raise SystemExit("Android SDK engine project license differs from source")
        for key in ("libwebrtc.a", "libhome_tunnel_android_surface.a"):
            with bundle.open(f"{prefix}/lib/{abi}/" + key) as stream:
                if stream.read(8) != b"!<arch>\n":
                    raise SystemExit("Android SDK cannot redistribute thin archives")
        source_name = "source/" + source["source_archive"]
        if source_name not in members or members[source_name].file_size > 8 * 1024 * 1024 or record["files"][source_name] != source.get("source_archive_sha256"):
            raise SystemExit("Android SDK source archive mismatch")
        contents = set()
        with tarfile.open(fileobj=io.BytesIO(bundle.read(source_name)), mode="r:gz") as archive:
            for entry in archive:
                member_name = entry.name.removeprefix("native/remote/")
                if entry.name != "native/remote/" + member_name or not entry.isfile() or entry.size > 4 * 1024 * 1024 or member_name not in actual or member_name in contents:
                    raise SystemExit("Unsafe or unexpected Android SDK source member")
                contents.add(member_name)
                if hashlib.sha256(archive.extractfile(entry).read()).hexdigest() != actual[member_name]:
                    raise SystemExit("Android SDK source bytes differ from the tagged source")
        if contents != set(actual) or bundle.read("PROJECT-LICENSE") != (ROOT / "LICENSE").read_bytes():
            raise SystemExit("Android SDK source or project license is incomplete")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--revision")
    parser.add_argument("--abi", help="arm64-v8a (default) or x86_64")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--describe", action="store_true")
    args = parser.parse_args()
    abi = ENGINE.require_abi(args.abi) if args.abi is not None else ENGINE.DEFAULT_ABI
    if args.describe:
        if not args.version:
            parser.error("--describe requires --version")
        print(json.dumps(describe(args.version, abi), indent=2, sort_keys=True))
        return
    if not args.output or not args.version or not args.revision:
        parser.error("--output, --version and --revision are required")
    if args.verify:
        verify(args.output, args.version, args.revision, abi)
        print(f"Tagged Android {abi} SDK archive, source tree and dependency identity verified; device acceptance remains required")
        return
    if not args.sdk or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() != args.revision or subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise SystemExit("Android SDK packaging requires its exact clean source commit")
    ENGINE.verify_artifact(args.sdk, abi)
    args.output.mkdir(parents=True, exist_ok=True)
    name = archive_name(args.version, abi)
    path = args.output / name
    provenance_path = args.output / provenance_name(abi)
    checksum_path = args.output / (name + ".sha256")
    if path.exists() or provenance_path.exists() or checksum_path.exists():
        raise SystemExit("Existing Android SDK release artifacts are never overwritten")
    with tempfile.TemporaryDirectory() as temporary:
        source_dir = Path(temporary)
        subprocess.run([sys.executable, ROOT / "scripts/package-remote-core.py", "--output", source_dir], check=True)
        prefix = engine_prefix(abi)
        mapping = {prefix + "/" + item.relative_to(args.sdk).as_posix(): item for item in args.sdk.rglob("*") if item.is_file()}
        mapping.update({"source/" + item.name: item for item in source_dir.iterdir() if item.is_file()})
        mapping["PROJECT-LICENSE"] = ROOT / "LICENSE"
        with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for member, original in sorted(mapping.items()):
                bundle.write(original, member)
        upstream, android = ENGINE.locks()
        record = provenance_identity(args.version, args.revision, abi, name, source_tree_sha256(), upstream, android)
        record.update({"archive_sha256": digest(path), "archive_bytes": path.stat().st_size,
                       "files": {member: digest(original) for member, original in sorted(mapping.items())}})
        provenance_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    checksum_path.write_text(f"{record['archive_sha256']}  {name}\n", encoding="utf-8", newline="\n")
    verify(args.output, args.version, args.revision, abi)


if __name__ == "__main__":
    main()
