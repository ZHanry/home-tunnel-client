"""Export immutable core sources and optionally a built ABI library for consumers."""
from pathlib import Path
import argparse
import gzip
import hashlib
import io
import json
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/remote"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/remote-artifacts")
    parser.add_argument("--library", type=Path)
    parser.add_argument("--target", default="source")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    paths = sorted(path for path in NATIVE.rglob("*") if path.is_file() and
                   (path.suffix in {".cpp", ".hpp", ".h", ".json", ".md", ".patch"} or path.name in {"CMakeLists.txt", "DEPS", "WEBRTC-LICENSE"}))
    entries = {path.relative_to(NATIVE).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    identity = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    source = args.output / f"home-tunnel-remote-source-{identity[:12]}.tar.gz"
    with source.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped, tarfile.open(fileobj=zipped, mode="w") as archive:
        for path in paths:
            content = path.read_bytes()
            entry = tarfile.TarInfo("native/remote/" + path.relative_to(NATIVE).as_posix())
            entry.size = len(content)
            entry.mode = 0o644
            archive.addfile(entry, io.BytesIO(content))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--", "native/remote"], cwd=ROOT, text=True))
    manifest = {"schema_version": 1, "abi": 1, "status": "security-core-only-media-unavailable", "target": args.target,
                "source_revision": revision, "source_tree_dirty": dirty, "source_tree_sha256": identity,
                "source_archive": source.name, "source_archive_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "source_files": entries,
                "deps_lock_sha256": hashlib.sha256((NATIVE / "remote-deps.lock.json").read_bytes()).hexdigest(),
                "header_sha256": entries["include/home_tunnel/remote.h"], "available": False}
    header = args.output / "include/home_tunnel/remote.h"
    header.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(NATIVE / "include/home_tunnel/remote.h", header)
    if args.library:
        if not args.library.is_file() or args.library.stat().st_size == 0:
            raise SystemExit("Expected a real compiled ABI library")
        destination = args.output / args.target / args.library.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.library, destination)
        manifest.update({"library": destination.relative_to(args.output).as_posix(),
                         "library_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
    (args.output / "remote-artifact.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if args.library:
        (args.output / args.target / "remote-artifact.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"source_archive": str(source), "source_sha256": manifest["source_archive_sha256"], "status": manifest["status"]}))


if __name__ == "__main__":
    main()
