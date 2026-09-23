"""Package and verify the tagged Android controller SDK; no device acceptance is implied."""
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
PROVENANCE = "android-sdk-provenance.json"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def archive_name(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[1-9][0-9]*)?", version):
        raise SystemExit("Invalid Android SDK version")
    return f"HomeTunnel-Remote-SDK-{version}-android-arm64.zip"


def source_files():
    return {path.relative_to(NATIVE).as_posix(): digest(path) for path in sorted(NATIVE.rglob("*")) if path.is_file() and
            (path.suffix in {".cpp", ".hpp", ".h", ".json", ".md", ".patch", ".gn", ".exports"} or path.name in {"CMakeLists.txt", "DEPS", "WEBRTC-LICENSE"})}


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
                entry.file_size > 1024 ** 3 or total > 3 * 1024 ** 3 or len(result) >= 30000):
            raise SystemExit("Unsafe, duplicate or oversized Android SDK member")
        result[name] = entry
    return result


def verify(directory, version, revision):
    record = json.loads((directory / PROVENANCE).read_text(encoding="utf-8"))
    name = archive_name(version)
    expected = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "source_revision": revision,
                "source_modified": False, "version": version, "tag": "v" + version, "target": "arm64-v8a",
                "android_api": 26, "device_media_accepted": False, "archive": name}
    if any(record.get(key) != value for key, value in expected.items()):
        raise SystemExit("Android SDK release identity differs from the tagged source")
    path = directory / name
    if digest(path) != record.get("archive_sha256") or path.stat().st_size != record.get("archive_bytes"):
        raise SystemExit("Android SDK archive bytes differ from provenance")
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
        engine = read_json("android-webrtc-arm64/android-webrtc-build.json")
        source = read_json("source/remote-artifact.json")
        actual = source_files()
        tree = hashlib.sha256(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        recipe = json.loads((NATIVE / "android/android-build.lock.json").read_text())
        if (engine.get("source_revision") != revision or engine.get("source_modified") is not False or
                engine.get("target") != "arm64-v8a" or engine.get("android_api") != 26 or engine.get("available") is not False or
                engine.get("gn_args") != recipe["gn_args"] or
                engine.get("controller_backend_linked") is not True or engine.get("device_media_accepted") is not False or
                engine.get("source_files") != actual or engine.get("source_tree_sha256") != tree or
                engine.get("upstream_lock_sha256") != digest(NATIVE / "remote-deps.lock.json") or
                engine.get("recipe_sha256") != digest(NATIVE / "android/android-build.lock.json") or
                source.get("source_revision") != revision or source.get("source_tree_dirty") is not False or
                source.get("source_files") != actual or source.get("source_tree_sha256") != tree or
                source.get("header_sha256") != actual.get("include/home_tunnel/remote.h")):
            raise SystemExit("Android SDK engine/source/dependency identity mismatch")
        required = {"lib/arm64-v8a/libwebrtc.a", "lib/arm64-v8a/libhome_tunnel_android_surface.a",
                    "lib/arm64-v8a/libhome_tunnel_remote.so", "include/home_tunnel/remote.h", "LICENSE.md", "source-manifest.json"}
        if not required.issubset(engine.get("files", {})):
            raise SystemExit("Android SDK omits required engine/source/license files")
        if {"android-webrtc-arm64/" + key for key in engine["files"]} != {key for key in members if key.startswith("android-webrtc-arm64/")} - {"android-webrtc-arm64/android-webrtc-build.json"}:
            raise SystemExit("Android SDK engine inventory changed")
        for key, checksum in engine["files"].items():
            if record["files"].get("android-webrtc-arm64/" + key) != checksum:
                raise SystemExit("Android SDK engine digest differs from its build manifest")
        for key in ("libwebrtc.a", "libhome_tunnel_android_surface.a"):
            with bundle.open("android-webrtc-arm64/lib/arm64-v8a/" + key) as stream:
                if stream.read(8) != b"!<arch>\n":
                    raise SystemExit("Android SDK cannot redistribute thin archives")
        source_name = "source/" + source["source_archive"]
        if source_name not in members or members[source_name].file_size > 8 * 1024 * 1024 or record["files"][source_name] != source.get("source_archive_sha256"):
            raise SystemExit("Android SDK source archive mismatch")
        contents = set()
        with tarfile.open(fileobj=io.BytesIO(bundle.read(source_name)), mode="r:gz") as archive:
            for entry in archive:
                name = entry.name.removeprefix("native/remote/")
                if entry.name != "native/remote/" + name or not entry.isfile() or entry.size > 4 * 1024 * 1024 or name not in actual or name in contents:
                    raise SystemExit("Unsafe or unexpected Android SDK source member")
                contents.add(name)
                if hashlib.sha256(archive.extractfile(entry).read()).hexdigest() != actual[name]:
                    raise SystemExit("Android SDK source bytes differ from the tagged source")
        if contents != set(actual) or bundle.read("PROJECT-LICENSE") != (ROOT / "LICENSE").read_bytes():
            raise SystemExit("Android SDK source or project license is incomplete")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        verify(args.output, args.version, args.revision)
        print("Tagged Android SDK archive, source tree and dependency identity verified; device acceptance remains required")
        return
    if not args.sdk or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() != args.revision or subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise SystemExit("Android SDK packaging requires its exact clean source commit")
    spec = importlib.util.spec_from_file_location("android_engine", ROOT / "scripts/build-remote-android-webrtc.py")
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    engine.verify_artifact(args.sdk)
    args.output.mkdir(parents=True, exist_ok=True)
    name = archive_name(args.version)
    path = args.output / name
    if path.exists() or (args.output / PROVENANCE).exists():
        raise SystemExit("Existing Android SDK release artifacts are never overwritten")
    with tempfile.TemporaryDirectory() as temporary:
        source_dir = Path(temporary)
        subprocess.run([sys.executable, ROOT / "scripts/package-remote-core.py", "--output", source_dir], check=True)
        mapping = {"android-webrtc-arm64/" + p.relative_to(args.sdk).as_posix(): p for p in args.sdk.rglob("*") if p.is_file()}
        mapping.update({"source/" + p.name: p for p in source_dir.iterdir() if p.is_file()})
        mapping["PROJECT-LICENSE"] = ROOT / "LICENSE"
        with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for member, original in sorted(mapping.items()):
                bundle.write(original, member)
        record = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "source_revision": args.revision,
                  "source_modified": False, "version": args.version, "tag": "v" + args.version,
                  "target": "arm64-v8a", "android_api": 26, "device_media_accepted": False,
                  "archive": name, "archive_sha256": digest(path), "archive_bytes": path.stat().st_size,
                  "files": {member: digest(original) for member, original in sorted(mapping.items())}}
        (args.output / PROVENANCE).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    verify(args.output, args.version, args.revision)
    (args.output / (name + ".sha256")).write_text(f"{digest(path)}  {name}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
