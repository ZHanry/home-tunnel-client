"""Build the pinned Android arm64 engine and native Surface renderer on Linux.

The output is an internal engine SDK, not an installable/accepted Android media
backend. Never change app capabilities from the existence of this archive.
"""
from pathlib import Path, PurePosixPath
import argparse
import ast
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/remote"
ANDROID = NATIVE / "android"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command, cwd, env, capture=False):
    result = subprocess.run([str(value) for value in command], cwd=cwd, env=env,
                            check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def locks():
    upstream = json.loads((NATIVE / "remote-deps.lock.json").read_text())
    android = json.loads((ANDROID / "android-build.lock.json").read_text())
    if android["schema_version"] != 1 or android["upstream_lock_sha256"] != sha(NATIVE / "remote-deps.lock.json"):
        raise SystemExit("Android engine recipe must be reviewed against the exact upstream lock")
    if android["target"] != "arm64-v8a" or android["android_api"] != 26:
        raise SystemExit("Unreviewed Android ABI/API requirement")
    for name, expected in [("DEPS", upstream["webrtc"]["deps_sha256"]), ("WEBRTC-LICENSE", upstream["webrtc"]["license_sha256"])]:
        if sha(NATIVE / "upstream" / name) != expected:
            raise SystemExit("Pinned upstream source snapshot mismatch")
    return upstream, android


def dependency_entries(path):
    parsed = ast.parse(path.read_text(encoding="utf-8"))
    if len(parsed.body) != 1 or not isinstance(parsed.body[0], ast.Assign):
        raise SystemExit("Unexpected gclient source manifest")
    result = ast.literal_eval(parsed.body[0].value)
    if not isinstance(result, dict) or not all(isinstance(k, str) and isinstance(v, str) and v.startswith(("https://", "gs://")) for k, v in result.items()):
        raise SystemExit("Unexpected gclient source entry")
    for name in result:
        # gclient records CIPD/CAS packages as "checkout/path:package/name".
        # Only the part before ':' is a filesystem path. The suffix stays data.
        checkout_path, separator, package = name.partition(":")
        relative = PurePosixPath(checkout_path)
        if relative.is_absolute() or ".." in relative.parts or "\\" in name or relative.parts[0] != "src" or (separator and (not package or ":" in package)):
            raise SystemExit("Unsafe gclient source path")
    return result


def verify_artifact(directory):
    directory = directory.resolve()
    manifest = json.loads((directory / "android-webrtc-build.json").read_text())
    upstream, android = locks()
    if manifest.get("target") != android["target"] or manifest.get("android_api") != 26 or manifest.get("available") is not False:
        raise SystemExit("Unexpected engine artifact capability/ABI")
    if manifest.get("webrtc_revision") != upstream["webrtc"]["revision"] or manifest.get("recipe_sha256") != sha(ANDROID / "android-build.lock.json"):
        raise SystemExit("Engine artifact was built from a different reviewed recipe")
    if manifest.get("upstream_lock_sha256") != android["upstream_lock_sha256"] or manifest.get("gn_args") != android["gn_args"]:
        raise SystemExit("Engine artifact build configuration mismatch")
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        raise SystemExit("Missing engine artifact file inventory")
    actual = {path.relative_to(directory).as_posix() for path in directory.rglob("*") if path.is_file() and path != directory / "android-webrtc-build.json"}
    if set(files) != actual:
        raise SystemExit("Engine artifact file set mismatch")
    for name, expected in files.items():
        path = directory / name
        if not path.resolve().is_relative_to(directory) or path.is_symlink() or not re.fullmatch(r"[0-9a-f]{64}", expected) or sha(path) != expected:
            raise SystemExit("Engine artifact hash/path mismatch")
    required = {"lib/arm64-v8a/libwebrtc.a", "lib/arm64-v8a/libhome_tunnel_android_surface.a", "LICENSE.md", "source-manifest.json", "include/api/peer_connection_interface.h", "include/home_tunnel/remote.h"}
    if not required.issubset(files):
        raise SystemExit("Engine artifact omits a required library/header/license/source manifest")
    print("Android engine library/header/license hashes verified; device media acceptance remains required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--build-existing", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".downloads/remote-webrtc-android")
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/android-webrtc-arm64")
    parser.add_argument("--verify-artifact", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    upstream, android = locks()
    if args.verify_artifact:
        verify_artifact(args.verify_artifact)
        return
    if not args.build and not args.build_existing:
        print("Android arm64/API 26 engine recipe matches the immutable upstream lock")
        return
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise SystemExit("Pinned Android WebRTC builds require a Linux x64 host; no host settings are changed")
    if args.build == args.build_existing or not 1 <= args.jobs <= 64:
        parser.error("Choose exactly one build mode and 1..64 jobs")
    revision = run(["git", "rev-parse", "HEAD"], ROOT, os.environ, True).strip()
    dirty = bool(run(["git", "status", "--porcelain"], ROOT, os.environ, True).strip())
    if dirty:
        raise SystemExit("Commit the reviewed integration source before producing an engine artifact")
    cache = args.cache.resolve()
    source, depot = cache / "checkout/src", cache / "depot_tools"
    env = dict(os.environ, DEPOT_TOOLS_UPDATE="0", DEPOT_TOOLS_WIN_TOOLCHAIN="0", PYTHONUTF8="1")
    env["PATH"] = str(depot) + os.pathsep + env["PATH"]
    if args.build:
        run([sys.executable, ROOT / "scripts/build-remote-webrtc.py", "--fetch", "--target-os", "android", "--target-cpu", "arm64", "--cache", cache], ROOT, env)
        run([sys.executable, depot / "gclient.py", "runhooks"], source.parent, env)
    for folder, expected in [(source, upstream["webrtc"]["revision"]), (depot, upstream["depot_tools"]["revision"]),
                             (source / "tools", upstream["toolchain"]["chromium_tools_revision"]), (source / "build", upstream["toolchain"]["chromium_build_revision"])]:
        if run(["git", "rev-parse", "HEAD"], folder, env, True).strip() != expected or run(["git", "status", "--porcelain", "--untracked-files=no"], folder, env, True).strip():
            raise SystemExit("Android dependency source is modified or differs from the immutable revision")
    if sha(source / "DEPS") != upstream["webrtc"]["deps_sha256"] or sha(source / "tools/clang/scripts/update.py") != upstream["toolchain"]["clang_update_script_sha256"]:
        raise SystemExit("Android DEPS/compiler identity mismatch")
    entries = dependency_entries(source.parent / ".gclient_entries")
    # Dependencies are revision-pinned by DEPS; record the resolved source inventory.
    entries["src"] = upstream["webrtc"]["repository"] + "@" + upstream["webrtc"]["revision"]
    overlay = source / "home_tunnel_remote"
    overlay.mkdir(exist_ok=True)
    for path in NATIVE.rglob("*"):
        if path.is_file():
            destination = overlay / path.relative_to(NATIVE)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
    build = source / "out/home_tunnel_android_arm64"
    build.mkdir(parents=True, exist_ok=True)
    (build / "args.gn").write_text("\n".join(f"{key} = {json.dumps(value)}" for key, value in android["gn_args"].items()) + "\n")
    gn = source / "buildtools/linux64/gn"
    root_target = "--root-target=//home_tunnel_remote/android"
    run([gn, "gen", build, root_target], source, env)
    log = build / "android-build.log"
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run([sys.executable, str(depot / "autoninja.py"), "-C", str(build), "-j", str(args.jobs), "webrtc", "home_tunnel_android_surface"], cwd=source, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-100:]))
        raise SystemExit(result.returncode)
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit("Choose a new empty artifact output directory; existing artifacts are never overwritten")
    output.mkdir(parents=True, exist_ok=True)
    library_dir = output / "lib/arm64-v8a"
    library_dir.mkdir(parents=True)
    readelf = source / "third_party/llvm-build/Release+Asserts/bin/llvm-readelf"
    for library in [build / "obj/libwebrtc.a", build / "obj/home_tunnel_remote/android/libhome_tunnel_android_surface.a"]:
        if not library.is_file() or library.stat().st_size < 1000:
            raise SystemExit("Expected real Android engine archive was not produced")
        architecture = run([readelf, "--file-headers", library], source, env, True)
        machines = {value.strip() for value in re.findall(r"Machine:\s*(.+)", architecture)}
        if not machines or machines != {"AArch64"}:
            raise SystemExit("Engine archive contains unexpected architecture objects")
        shutil.copyfile(library, library_dir / library.name)
    # Collect headers from each pinned Git source, excluding generated build trees.
    # Preserve paths exactly so the inventory can be compared with source revisions.
    header_bytes = 0
    for entry in sorted(entries):
        if ":" in entry:
            continue  # Binary package metadata does not identify a Git checkout.
        folder = source.parent / entry
        if not folder.is_dir() or not (folder / ".git").exists():
            continue
        for name in run(["git", "ls-files", "-z", "--", "*.h", "*.hpp", "*.inc"], folder, env, True).split("\0"):
            if not name:
                continue
            path = folder / name
            if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(source):
                raise SystemExit("Unsafe/missing engine header path")
            header_bytes += path.stat().st_size
            if header_bytes > 512 * 1024 * 1024:
                raise SystemExit("Engine header inventory exceeds its bounded size")
            destination = output / "include" / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
    public = output / "include/home_tunnel/remote.h"
    public.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(NATIVE / "include/home_tunnel/remote.h", public)
    # Use upstream's mapping against these exact GN targets. An unknown license
    # stops packaging rather than silently omitting a dependency's notice.
    spec = importlib.util.spec_from_file_location("pinned_android_licenses", source / "tools_webrtc/libs/generate_licenses.py")
    licenses = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(licenses)
    licenses.LicenseBuilder._run_gn = staticmethod(lambda directory, target: run([gn, "desc", root_target, "--all", "--format=json", directory, target], source, env, True))
    licenses.LicenseBuilder([str(build)], ["//:webrtc", "//home_tunnel_remote/android:home_tunnel_android_surface"]).generate_license_text(str(output))
    source_manifest = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "revision": revision, "source_modified": False,
                       "dependency_sources": entries, "upstream_lock": upstream, "android_recipe": android,
                       "rebuild": "Use Linux x64 and run python3 scripts/build-remote-android-webrtc.py --build from the exact clean client revision."}
    (output / "source-manifest.json").write_text(json.dumps(source_manifest, indent=2, sort_keys=True) + "\n")
    files = {path.relative_to(output).as_posix(): sha(path) for path in sorted(output.rglob("*")) if path.is_file()}
    manifest = {"schema_version": 1, "status": "engine-built-controller-integration-and-device-acceptance-required", "available": False,
                "target": "arm64-v8a", "android_api": 26, "source_revision": revision, "source_modified": False,
                "webrtc_revision": upstream["webrtc"]["revision"], "upstream_lock_sha256": android["upstream_lock_sha256"],
                "recipe_sha256": sha(ANDROID / "android-build.lock.json"), "gn_args": android["gn_args"], "files": files}
    (output / "android-webrtc-build.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    verify_artifact(output)


if __name__ == "__main__":
    main()
