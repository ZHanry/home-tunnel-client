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
NOTICE_INVENTORY = "source-license-inventory.json"
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
# This fixed Chromium test notice predates UTF-8. Pin its original Git blob,
# accepting Git's CRLF checkout conversion while preserving the actual bytes.
LATIN1_NOTICE = ("third_party/blink/web_tests/svg/W3C-SVG-1.1/resources/copyright-documents-19990405.html",
                "6206bc1b5bee83bce73d788a13ebe5f65a08125af67d9b32243dc848a017fa1b")
INHERITED_NOTICES = {"src/third_party/libFuzzer/src": (
    "third_party/libFuzzer/LICENSE.TXT", "third_party/libFuzzer/README.chromium")}
# Chromium's split Git mirrors omit the original repository's root LICENSE.
# The origin revisions below are their exact GitOrigin-RevId trailers. Each
# original root LICENSE was fetched and verified to have this same byte digest.
CHROMIUM_LICENSE_SHA256 = "368cca1106be99d39ecd32a38d8305585d802a475effb66380b91ffc9bcf709b"
CHROMIUM_LICENSE_PATH = "source-licenses/chromium/LICENSE"
CHROMIUM_MIRRORS = {
    "src/testing": ("6f55acdadefd12ad87e386cab5cee31ae610ed7e", "6a5a7bde528fb0d0a3cff46e4e10fb6885acc1c7"),
    "src/build": ("0a2808e883f9443b41ed1f49eb0aa4da0cfe3cf6", "41e5cf5e71b16fdde8ae211bb6d39d5e871134a1"),
    "src/tools": ("c60db23bebc8938b6bfa250eee92fefee66bd571", "41e5cf5e71b16fdde8ae211bb6d39d5e871134a1"),
    "src/third_party": ("e7b072867dcb5c59a461d58b853a498f938f8f96", "17a3918979e73d9a840546b79c3f5a7c0a49d35f"),
}


def chromium_notice(entry, upstream):
    if entry not in CHROMIUM_MIRRORS:
        return None
    mirror, origin = CHROMIUM_MIRRORS[entry]
    expected = f"https://chromium.googlesource.com/chromium/{entry}@{mirror}"
    if upstream != expected:
        raise SystemExit("Chromium mirror revision has no reviewed original root license")
    return {"path": CHROMIUM_LICENSE_PATH, "sha256": CHROMIUM_LICENSE_SHA256,
            "source": f"https://chromium.googlesource.com/chromium/src/+/{origin}/LICENSE"}


def chromium_license_bytes():
    content = (ROOT / "scripts/licenses/CHROMIUM-LICENSE").read_bytes()
    if hashlib.sha256(content).hexdigest() != CHROMIUM_LICENSE_SHA256:
        raise SystemExit("Pinned original Chromium license bytes changed")
    return content


def chromium_license_record(sources):
    return {entry: {"upstream": upstream, **notice} for entry, upstream in sorted(sources.items())
            if (notice := chromium_notice(entry, upstream)) is not None}


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command, cwd, env, capture=False):
    result = subprocess.run([str(value) for value in command], cwd=cwd, env=env,
                            check=True, text=True, encoding="utf-8", stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def require_regular_archive(path):
    if not path.is_file():
        raise SystemExit(f"Expected Android engine archive is missing: {path.name}")
    with path.open("rb") as stream:
        signature = stream.read(8)
    if signature != b"!<arch>\n" or path.stat().st_size < 1000:
        raise SystemExit(f"Android SDK requires a real, non-thin archive: {path.name}")


def sdk_header_source(path, source, tracked_headers):
    """Materialize upstream header aliases without exporting filesystem links."""
    if not path.is_relative_to(source):
        raise SystemExit("Engine header path escapes the pinned checkout")
    name = path.relative_to(source).as_posix()
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError):
        raise SystemExit(f"Missing/unresolvable engine header: {name}") from None
    # Perfetto publishes header aliases for its Rust SDK. Only a real tracked
    # header in this exact Git dependency is permitted as the resolved target.
    if not resolved.is_relative_to(source) or resolved not in tracked_headers or not resolved.is_file():
        raise SystemExit(f"Unsafe/untracked engine header target: {name}")
    return resolved


def is_sdk_notice(name):
    path = PurePosixPath(name)
    return (bool(re.match(r"^(?:LICENSE|LICENCE|COPYING|COPYRIGHTS?|NOTICES?|AUTHORS|UNLICENSE)(?:$|[._-])", path.name.upper())) or
            path.name == "README.chromium" or any(part.upper() in ("LICENSES", "LICENCES") for part in path.parts[:-1]))


def notice_bytes(path, source, tracked):
    original = sdk_header_source(path, source, tracked)
    if original.stat().st_size > 4 * 1024 * 1024:
        raise SystemExit(f"Dependency notice is oversized: {path.relative_to(source).as_posix()}")
    content = original.read_bytes()
    if any(value < 32 and value not in (9, 10, 12, 13) or value == 127 for value in content):
        raise SystemExit(f"Binary/control bytes are not dependency notices: {path.relative_to(source).as_posix()}")
    try:
        content.decode("utf-8")
    except UnicodeDecodeError:
        if (path.relative_to(source).as_posix(), hashlib.sha256(content.replace(b"\r\n", b"\n")).hexdigest()) != LATIN1_NOTICE:
            raise SystemExit(f"Unreviewed dependency notice encoding: {path.relative_to(source).as_posix()}") from None
    return content


def collect_sdk_sources(source, entries, output, env):
    """Redistributed headers carry the notices of every pinned source provider."""
    providers = {}; notice_outputs = {}; total_bytes = 0; total_notices = 0; source_count = 0
    for entry in sorted(entries):
        if ":" in entry:
            continue
        folder = source.parent / entry
        if not folder.is_dir() or not (folder / ".git").exists():
            continue
        names = [name for name in run(["git", "ls-files", "-z"], folder, env, True).split("\0") if name]
        headers = {name for name in names if PurePosixPath(name).suffix in {".h", ".hpp", ".inc"}}
        if not headers:
            continue
        notices = {name for name in names if is_sdk_notice(name)}
        selected = headers | notices
        source_count += len(selected)
        if source_count > 65000:
            raise SystemExit("SDK source inventory exceeds its bounded file count")
        tracked = {folder / name for name in selected}
        provider = {"upstream": entries[entry], "headers": [], "notices": []}
        for name in sorted(selected):
            path = folder / name
            original = sdk_header_source(path, source, tracked)
            content = notice_bytes(path, source, tracked) if name in notices else None
            size = len(content) if content is not None else original.stat().st_size
            total_bytes += size
            if content is not None:
                total_notices += size
            if total_bytes > 512 * 1024 * 1024 or total_notices > 64 * 1024 * 1024:
                raise SystemExit("SDK header/notice inventory exceeds its bounded size")
            destination = output / "include" / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if content is None:
                shutil.copyfile(original, destination)
            else:
                destination.write_bytes(content)
            exported = destination.relative_to(output).as_posix()
            if name in headers:
                provider["headers"].append(exported)
            if name in notices:
                provider["notices"].append(exported)
                notice_outputs[path.relative_to(source).as_posix()] = exported
        providers[entry] = provider
    for entry, provider in providers.items():
        original_notice = chromium_notice(entry, provider["upstream"])
        if original_notice:
            destination = output / original_notice["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(chromium_license_bytes())
            provider["original_root_license"] = original_notice
            provider["notices"].append(original_notice["path"])
        if entry in INHERITED_NOTICES:
            try:
                provider["notices"].extend(notice_outputs[name] for name in INHERITED_NOTICES[entry])
            except KeyError:
                raise SystemExit("Pinned dependency wrapper notices are missing") from None
        if not any((output / name).stat().st_size and re.match(r"^(?:LICENSE|LICENCE|COPYING|COPYRIGHTS?|NOTICES?|UNLICENSE)(?:$|[._-])", PurePosixPath(name).name.upper())
                   for name in provider["notices"]):
            raise SystemExit(f"Redistributed dependency has no license notice: {entry}")
    return {"schema_version": 1, "dependencies": providers,
            "project": {"headers": ["include/home_tunnel/remote.h"], "notice": "PROJECT-LICENSE"}}


def verify_notice_record(inventory, source_manifest, files):
    sources = source_manifest.get("dependency_sources", {})
    git_sources = {entry for entry, origin in sources.items() if ":" not in entry and origin.startswith("https://")}
    if inventory.get("schema_version") != 1 or inventory.get("project") != {"headers": ["include/home_tunnel/remote.h"], "notice": "PROJECT-LICENSE"}:
        raise SystemExit("SDK source notice schema/project binding mismatch")
    headers = {"include/home_tunnel/remote.h"}; notices = {"PROJECT-LICENSE"}
    for entry, provider in inventory.get("dependencies", {}).items():
        parts = PurePosixPath(entry).parts
        if (not parts or parts[0] != "src" or ".." in parts or "\\" in entry or ":" in entry or
                entry not in sources or provider.get("upstream") != sources[entry] or
                not provider.get("headers") or not provider.get("notices")):
            raise SystemExit("SDK header provider has no pinned source/notices")
        prefix = "include/" + ("/".join(parts[1:]) + "/" if len(parts) > 1 else "")
        for name in provider["headers"]:
            if name in headers or name not in files or not name.startswith(prefix) or PurePosixPath(name).suffix not in {".h", ".hpp", ".inc"}:
                raise SystemExit("SDK header provenance is incomplete or duplicated")
            source_path = PurePosixPath("src") / PurePosixPath(name).relative_to("include")
            owner = next((parent.as_posix() for parent in source_path.parents if parent.as_posix() in git_sources), None)
            if owner != entry:
                raise SystemExit("SDK header is attributed to the wrong pinned provider")
            headers.add(name)
        inherited = {"include/" + name for name in INHERITED_NOTICES.get(entry, ())}
        original_notice = chromium_notice(entry, provider["upstream"])
        if original_notice:
            if (provider.get("original_root_license") != original_notice or
                    files.get(original_notice["path"]) != original_notice["sha256"] or
                    original_notice["path"] not in provider["notices"]):
                raise SystemExit("Chromium headers omit their pinned original root license")
            inherited.add(original_notice["path"])
        elif "original_root_license" in provider:
            raise SystemExit("Unexpected original root license on a dependency")
        for name in provider["notices"]:
            if name not in files or (not name.startswith(prefix) and name not in inherited) or not is_sdk_notice(name):
                raise SystemExit("SDK dependency notice is missing from its hashed inventory")
            notices.add(name)
        if not any(files[name] != EMPTY_SHA256 and re.match(r"^(?:LICENSE|LICENCE|COPYING|COPYRIGHTS?|NOTICES?|UNLICENSE)(?:$|[._-])", PurePosixPath(name).name.upper())
                   for name in provider["notices"]):
            raise SystemExit("SDK dependency has no license notice")
    actual_headers = {name for name in files if name.startswith("include/") and PurePosixPath(name).suffix in {".h", ".hpp", ".inc"}}
    actual_sources = {name for name in files if name.startswith("include/")}
    if headers != actual_headers or actual_sources != {name for name in headers | notices if name.startswith("include/")} or any(name not in files for name in notices):
        raise SystemExit("SDK does not trace every redistributed header to source notices")


def verify_notice_inventory(directory, files):
    path = directory / NOTICE_INVENTORY
    if not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise SystemExit("SDK source notice inventory is missing or oversized")
    verify_notice_record(json.loads(path.read_text(encoding="utf-8")),
                         json.loads((directory / "source-manifest.json").read_text()), files)
    if (directory / "PROJECT-LICENSE").read_bytes() != (ROOT / "LICENSE").read_bytes():
        raise SystemExit("SDK project license differs from its source")


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
    for patch in upstream["patches"]:
        if sha(NATIVE / patch["path"]) != patch["sha256"]:
            raise SystemExit("Reviewed upstream patch differs from the source lock")
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
        if not relative.parts or relative.is_absolute() or ".." in relative.parts or "\\" in name or relative.parts[0] != "src" or (separator and (not package or ":" in package)):
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
    source_files = manifest.get("source_files")
    if not isinstance(source_files, dict) or not source_files or hashlib.sha256(json.dumps(source_files, sort_keys=True, separators=(",", ":")).encode()).hexdigest() != manifest.get("source_tree_sha256"):
        raise SystemExit("Engine artifact has no immutable controller source identity")
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
    required = {"lib/arm64-v8a/libwebrtc.a", "lib/arm64-v8a/libhome_tunnel_android_surface.a", "lib/arm64-v8a/libhome_tunnel_remote.so", "LICENSE.md", "PROJECT-LICENSE", NOTICE_INVENTORY, "source-manifest.json", "include/api/peer_connection_interface.h", "include/home_tunnel/remote.h"}
    if not required.issubset(files):
        raise SystemExit("Engine artifact omits a required library/header/license/source manifest")
    verify_notice_inventory(directory, files)
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
        reviewed = "".join((NATIVE / patch["path"]).read_text(encoding="utf-8") for patch in upstream["patches"] if source / patch["repository"] == folder)
        difference = run(["git", "diff", "--binary"], folder, env, True)
        if (run(["git", "rev-parse", "HEAD"], folder, env, True).strip() != expected or
                run(["git", "diff", "--cached", "--name-only"], folder, env, True).strip() or (difference and difference != reviewed)):
            raise SystemExit("Android dependency source is modified or differs from the immutable revision")
    if sha(source / "DEPS") != upstream["webrtc"]["deps_sha256"] or sha(source / "tools/clang/scripts/update.py") != upstream["toolchain"]["clang_update_script_sha256"]:
        raise SystemExit("Android DEPS/compiler identity mismatch")
    for patch in upstream["patches"]:
        repository = source / patch["repository"]
        patch_file = NATIVE / patch["path"]
        if run(["git", "diff", "--cached", "--name-only"], repository, env, True).strip():
            raise SystemExit("Refusing staged changes in an upstream patch repository")
        difference = run(["git", "diff", "--binary"], repository, env, True)
        if not difference:
            run(["git", "apply", "--check", patch_file], repository, env)
            run(["git", "apply", patch_file], repository, env)
            difference = run(["git", "diff", "--binary"], repository, env, True)
        if difference != patch_file.read_text(encoding="utf-8"):
            raise SystemExit("Android upstream changes differ from the reviewed patch")
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
        result = subprocess.run([sys.executable, str(depot / "autoninja.py"), "-C", str(build), "-j", str(args.jobs), "webrtc", "home_tunnel_android_surface", "home_tunnel_android_controller"], cwd=source, env=env, stdout=stream, stderr=subprocess.STDOUT)
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
        require_regular_archive(library)
        architecture = run([readelf, "--file-headers", library], source, env, True)
        machines = {value.strip() for value in re.findall(r"Machine:\s*(.+)", architecture)}
        if not machines or machines != {"AArch64"}:
            raise SystemExit("Engine archive contains unexpected architecture objects")
        shutil.copyfile(library, library_dir / library.name)
    controller = build / "libhome_tunnel_remote.so"
    architecture = run([readelf, "--file-headers", controller], source, env, True)
    if set(value.strip() for value in re.findall(r"Machine:\s*(.+)", architecture)) != {"AArch64"}:
        raise SystemExit("Controller shared library is not AArch64")
    segments = run([readelf, "--wide", "--program-headers", controller], source, env, True)
    alignments = [int(value, 16) for value in re.findall(r"^\s*LOAD\s+.*\s+(0x[0-9a-fA-F]+)\s*$", segments, re.MULTILINE)]
    if not alignments or any(value < 16384 or value % 16384 for value in alignments):
        raise SystemExit("Controller shared library does not support 16 KiB Android pages")
    dynamic = run([readelf, "--dynamic", controller], source, env, True)
    dependencies = set(re.findall(r"Shared library: \[(.*?)\]", dynamic))
    if "TEXTREL" in dynamic or dependencies - {"libandroid.so", "liblog.so", "libdl.so", "libm.so", "libc.so"}:
        raise SystemExit("Controller leaked a C++ runtime or unexpected native dependency across the app ABI")
    nm = readelf.with_name("llvm-nm")
    exported = run([nm, "--dynamic", "--defined-only", controller], source, env, True)
    symbols = {line.split()[-1].split("@")[0] for line in exported.splitlines() if line.strip()}
    expected = {"ht_rd_abi_version", "ht_rd_create", "ht_rd_get_capabilities", "ht_rd_start", "ht_rd_on_signal", "ht_rd_submit_input", "ht_rd_set_surface", "ht_rd_pause", "ht_rd_close", "ht_rd_release"}
    if symbols - {"HT_REMOTE_ANDROID_1"} != expected:
        raise SystemExit("Controller exported symbols differ from the reviewed C ABI")
    shutil.copyfile(controller, library_dir / controller.name)
    # GN's linked-library summary does not cover headers from unlinked source
    # dependencies. Preserve all pinned header providers' original notices too.
    notice_inventory = collect_sdk_sources(source, entries, output, env)
    shutil.copyfile(ROOT / "LICENSE", output / "PROJECT-LICENSE")
    (output / NOTICE_INVENTORY).write_text(json.dumps(notice_inventory, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    public = output / "include/home_tunnel/remote.h"
    public.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(NATIVE / "include/home_tunnel/remote.h", public)
    # Use upstream's mapping against these exact GN targets. An unknown license
    # stops packaging rather than silently omitting a dependency's notice.
    spec = importlib.util.spec_from_file_location("pinned_android_licenses", source / "tools_webrtc/libs/generate_licenses.py")
    licenses = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(licenses)
    licenses.LicenseBuilder._run_gn = staticmethod(lambda directory, target: run([gn, "desc", root_target, "--all", "--format=json", directory, target], source, env, True))
    licenses.LicenseBuilder([str(build)], ["//:webrtc", "//home_tunnel_remote/android:home_tunnel_android_controller"]).generate_license_text(str(output))
    source_manifest = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "revision": revision, "source_modified": False,
                       "dependency_sources": entries, "upstream_lock": upstream, "android_recipe": android,
                       "reviewed_upstream_patches": upstream["patches"],
                       "rebuild": "Use Linux x64 and run python3 scripts/build-remote-android-webrtc.py --build from the exact clean client revision."}
    (output / "source-manifest.json").write_text(json.dumps(source_manifest, indent=2, sort_keys=True) + "\n")
    files = {path.relative_to(output).as_posix(): sha(path) for path in sorted(output.rglob("*")) if path.is_file()}
    source_files = {path.relative_to(NATIVE).as_posix(): sha(path) for path in sorted(NATIVE.rglob("*")) if path.is_file() and
                    (path.suffix in {".cpp", ".hpp", ".h", ".json", ".md", ".patch", ".gn", ".exports"} or path.name in {"CMakeLists.txt", "DEPS", "WEBRTC-LICENSE"})}
    manifest = {"schema_version": 1, "status": "controller-built-device-acceptance-required", "available": False,
                "controller_backend_linked": True, "device_media_accepted": False,
                "target": "arm64-v8a", "android_api": 26, "source_revision": revision, "source_modified": False,
                "source_files": source_files, "source_tree_sha256": hashlib.sha256(json.dumps(source_files, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                "webrtc_revision": upstream["webrtc"]["revision"], "upstream_lock_sha256": android["upstream_lock_sha256"],
                "recipe_sha256": sha(ANDROID / "android-build.lock.json"), "gn_args": android["gn_args"], "files": files}
    (output / "android-webrtc-build.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    verify_artifact(output)


if __name__ == "__main__":
    main()
