"""Validate a clean Linux native build and stage only its production worker.

This prepares a candidate; Xvfb evidence does not claim physical Xorg acceptance.
No test executable, source-selected executable path or unverified library is copied.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/remote"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("Missing, linked or oversized native evidence: " + path.name)
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(build, version, revision, source_tree):
    """Validate bounded records before returning the exact allowlisted files."""
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-rc\.[1-9][0-9]*", version),
            "Linux remote candidates require a complete RC version")
    record = read(build / "remote-host-build.json")
    lock = read(NATIVE / "remote-deps.lock.json")
    recipe = read(NATIVE / "linux/linux-build.lock.json")
    require(record.get("schema_version") == 1 and record.get("version") == version and
            record.get("repository_revision") == revision and record.get("source_modified") is False and
            record.get("target_os") == "linux" and record.get("target_cpu") == "x64" and
            record.get("status") == "built-acceptance-required" and
            record.get("linux_source_tree_sha256") == source_tree,
            "Native worker is not a clean build of this exact Linux candidate source")
    require(record.get("webrtc_revision") == lock["webrtc"]["revision"] and
            record.get("deps_lock_sha256") == sha(NATIVE / "remote-deps.lock.json") and
            recipe.get("upstream_lock_sha256") == record["deps_lock_sha256"] and
            record.get("linux_recipe_sha256") == sha(NATIVE / "linux/linux-build.lock.json") and
            record.get("toolchain") == lock["toolchain"], "Native dependency or Linux recipe mismatch")
    require(all(record.get(key) == "passed" for key in
                ("authorization_tests", "clipboard_protocol_tests", "file_transfer_tests")),
            "Native authorization and data tests have not passed")
    worker = build / "home_tunnel_remote_host"
    require(worker.is_file() and not worker.is_symlink() and 64 <= worker.stat().st_size <= 256 * 1024 * 1024,
            "Missing production native worker")
    with worker.open("rb") as stream:
        header = stream.read(20)
    require(header[:6] == b"\x7fELF\x02\x01" and header[18:20] == b"\x3e\x00",
            "Production worker must be Linux x64 ELF")
    require(sha(worker) == record.get("sha256") and record.get("sha256") != record.get("xvfb_test_binary_sha256"),
            "Production worker hash mismatch or test worker substitution")
    files = {
        "home_tunnel_remote_host": "sha256",
        "LICENSE.md": "notices_sha256",
        "remote-source-manifest.json": "source_manifest_sha256",
        "linux-xvfb-evidence.json": "isolated_xvfb_evidence_sha256",
    }
    for name, key in files.items():
        path = build / name
        require(path.is_file() and not path.is_symlink() and sha(path) == record.get(key),
                "Native evidence hash mismatch: " + name)
    sources = read(build / "remote-source-manifest.json")
    require(sources.get("schema_version") == 1 and sources.get("repository") == "ZHanry/home-tunnel-client" and
            sources.get("revision") == revision and sources.get("worker_sha256") == record["sha256"] and
            sources.get("deps_lock") == lock, "Native corresponding-source manifest mismatch")
    evidence = read(build / "linux-xvfb-evidence.json")
    require(evidence.get("schema_version") == 1 and evidence.get("status") == "passed" and
            evidence.get("scope") == "isolated-xvfb" and evidence.get("physical_xorg_acceptance") is False and
            evidence.get("wayland_acceptance") is False and record.get("physical_xorg_acceptance") is False and
            evidence.get("production_worker_sha256") == record["sha256"] and
            evidence.get("test_worker_sha256") == record["xvfb_test_binary_sha256"] and
            evidence.get("recipe_sha256") == record["linux_recipe_sha256"],
            "Isolated evidence does not identify the candidate production/test boundary")
    require(evidence.get("production_ipc") == {"hello": "passed", "capability_boundary": "passed", "unsigned_authorization": "not_started"} and
            evidence.get("test_ipc") == {"hello": "passed", "capability_boundary": "passed", "unsigned_authorization": "rejected"},
            "Native IPC production/test boundary was not verified")
    input_evidence = evidence.get("input", {})
    require(input_evidence.get("status") == "passed" and
            input_evidence.get("scope") == "isolated-xvfb-real-xtest-input" and
            input_evidence.get("physical_xorg_acceptance") is False and
            input_evidence.get("unrelated_key_preserved") is True and
            input_evidence.get("already_held_key_preserved") is True and
            all(type(input_evidence.get(key)) is int and 0 <= input_evidence[key] <= 2000
                for key in ("heartbeat_release_ms", "worker_crash_release_ms")),
            "Missing isolated input preservation or measured two-second release evidence")
    for codec in ("H264", "VP8"):
        probe = evidence.get(codec, {})
        require(probe.get("status") == "passed" and probe.get("exit_code") == 0 and
                probe.get("requested_codec") == codec and probe.get("selected_pair") == "udp-host-host" and
                probe.get("dtls_connected") is True and probe.get("product_acceptance") is False and
                probe.get("video_frames_decoded", 0) >= 10 and
                probe.get("sender", {}).get("mime_type") == "video/" + codec and
                probe.get("receiver", {}).get("mime_type") == "video/" + codec,
                "Missing actual isolated " + codec + " decode evidence")
    return record


def stage(build, destination, record):
    destination.mkdir(parents=True, exist_ok=True)
    binary_dir = destination / "bin"
    evidence_dir = destination / "native-remote"
    binary_dir.mkdir(exist_ok=True)
    evidence_dir.mkdir(exist_ok=True)
    targets = [("home_tunnel_remote_host", binary_dir / "home_tunnel_remote_host", "sha256"),
               ("LICENSE.md", evidence_dir / "WEBRTC-THIRD-PARTY-NOTICES.md", "notices_sha256"),
               ("remote-source-manifest.json", evidence_dir / "remote-source-manifest.json", "source_manifest_sha256"),
               ("linux-xvfb-evidence.json", evidence_dir / "linux-xvfb-evidence.json", "isolated_xvfb_evidence_sha256")]
    require(not any(target.exists() for _, target, _ in targets) and not (evidence_dir / "remote-host-build.json").exists(),
            "Candidate staging directory already contains native files")
    for name, target, digest_key in targets:
        shutil.copyfile(build / name, target)
        require(sha(target) == record[digest_key], "Native evidence changed during staging: " + name)
    (binary_dir / "home_tunnel_remote_host").chmod(0o755)
    public = {key: value for key, value in record.items() if key != "executable"}
    (evidence_dir / "remote-host-build.json").write_text(json.dumps(public, indent=2) + "\n", encoding="utf-8")
    (evidence_dir / "worker.sha256").write_text(record["sha256"] + "  bin/home_tunnel_remote_host\n", encoding="ascii", newline="\n")
    require(sha(binary_dir / "home_tunnel_remote_host") == record["sha256"], "Worker changed during staging")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-record", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--stage", type=Path)
    args = parser.parse_args()
    require(args.build_record.name == "remote-host-build.json", "Use the original native build record")
    require(not subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).strip(),
            "Candidate packaging requires a clean client checkout")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    module_spec = importlib.util.spec_from_file_location("native_linux", ROOT / "scripts/build-native-linux.py")
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    record = validate(args.build_record.resolve().parent, args.version, revision, module.source_identity())
    if args.stage:
        stage(args.build_record.resolve().parent, args.stage.resolve(), record)
    print(record["sha256"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError) as error:
        raise SystemExit(str(error))
