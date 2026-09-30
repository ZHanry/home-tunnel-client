"""Bounded same-machine validation of an already sealed Windows candidate.

This wrapper never builds a production worker, signs a release, publishes a
package, changes host trust, or uses deployed accounts. Its two subprocesses are
the existing, revision-pinned client acceptance harness.
"""
import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def source_state(path):
    return {
        "commit": subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True, timeout=15).strip(),
        "modified": bool(subprocess.check_output(["git", "-C", str(path), "status", "--porcelain"], timeout=15)),
    }


def require(value, message):
    if not value:
        raise RuntimeError(message)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def interactive_desktop():
    """Read session state and acquire only a read-objects input desktop handle."""
    statement = "[ordered]@{user_interactive=[Environment]::UserInteractive;session_id=[Diagnostics.Process]::GetCurrentProcess().SessionId} | ConvertTo-Json -Compress"
    state = json.loads(subprocess.check_output(["pwsh", "-NoProfile", "-NonInteractive", "-Command", statement],
                                              text=True, timeout=30))
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.OpenInputDesktop.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    user32.OpenInputDesktop.restype = wintypes.HANDLE
    user32.CloseDesktop.argtypes = [wintypes.HANDLE]
    user32.CloseDesktop.restype = wintypes.BOOL
    desktop = user32.OpenInputDesktop(0, False, 0x0001)  # DESKTOP_READOBJECTS only
    state["input_desktop_accessible"] = bool(desktop)
    if desktop:
        state["read_handle_closed"] = bool(user32.CloseDesktop(desktop))
    else:
        state["input_desktop_error"] = ctypes.get_last_error()
    return state


def defender_state():
    statement = "$ErrorActionPreference='Stop'; $s=Get-Service WinDefend; $m=Get-MpComputerStatus; [ordered]@{service_status=[string]$s.Status;start_type=[string]$s.StartType;am_service_enabled=[bool]$m.AMServiceEnabled;antivirus_enabled=[bool]$m.AntivirusEnabled} | ConvertTo-Json -Compress"
    return json.loads(subprocess.check_output(["pwsh", "-NoProfile", "-NonInteractive", "-Command", statement],
                                             text=True, timeout=30))


def prepare_scan_subjects(candidate, destination, version, validate_archive):
    """Copy sealed packages and extract only their four original PE payloads."""
    subjects = [f"HomeTunnel-Setup-{version}-x64.exe", f"HomeTunnel-Windows-{version}-x64.zip"]
    executables = ["home-tunnel-gui.exe", "home-tunnel-agent.exe", "home-tunnel-service.exe", "home_tunnel_remote_host.exe"]
    for name in subjects + ["windows-installer-smoke.json"]:
        shutil.copyfile(candidate / name, destination / name)
    with zipfile.ZipFile(candidate / subjects[1]) as bundle:
        validate_archive(bundle)
        for name in executables:
            require(bundle.namelist().count(name) == 1, "Ambiguous scan payload: " + name)
            with bundle.open(name) as source, (destination / name).open("xb") as target:
                shutil.copyfileobj(source, target)
    expected = {item["name"]: item["sha256"] for item in json.loads(
        (candidate / "windows-defender-scan.json").read_text(encoding="utf-8"))["files"]}
    actual = {name: digest(destination / name) for name in subjects + executables}
    require(actual == expected, "Scan staging differs from sealed original subject hashes")
    return actual


def verify_final_scan_time(scan, candidate):
    scanned = datetime.fromisoformat(scan["scanned_at"].replace("Z", "+00:00"))
    created = datetime.fromisoformat(candidate["created_at"].replace("Z", "+00:00"))
    require(scanned.tzinfo is not None and created.tzinfo is not None and scanned > created,
            "Final Defender scan must be strictly after candidate creation")


def rescan_candidate(args, candidate_dir, manifest, release, receipt):
    """Run the unchanged scanner against copied bytes; keep a separate receipt."""
    receipt["defender_before"] = defender_state()
    # The original scanner can start/enable services on CI. Require protection
    # already active and bypass only that branch through the child environment.
    state = receipt["defender_before"]
    require(state["service_status"] == "Running" and state["start_type"] != "Disabled" and
            state["am_service_enabled"] is True and state["antivirus_enabled"] is True,
            "Defender protection is not already active; service/security changes require separate authorization")
    original_scan = candidate_dir / "windows-defender-scan.json"
    original_hash = digest(original_scan)
    receipt["original_scan_sha256"] = original_hash
    receipt["candidate_created_at"] = manifest["created_at"]
    for name in ("windows-defender-scan.json", "windows-installer-smoke.json"):
        shutil.copyfile(candidate_dir / name, args.output / name)
    final_name = "windows-final-defender-scan.json"
    with tempfile.TemporaryDirectory(prefix="home-tunnel-final-defender-") as directory:
        staging = Path(directory)
        receipt["scan_subjects_before"] = prepare_scan_subjects(candidate_dir, staging, args.version, release.validate_windows_archive)
        report_path = staging / final_name
        env = dict(os.environ, GITHUB_SHA=args.revision, GITHUB_ACTIONS="false")
        receipt["scanner_context"] = {"package_revision": args.revision, "service_management_disabled": True}
        command = ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(args.client / "packaging/windows/scan-release.ps1"),
                   "-Directory", str(staging), "-Version", args.version, "-ReportPath", str(report_path), "-UpdateSignatures"]
        receipt["scan_started"] = True
        try:
            with (args.output / "defender-console.log").open("w", encoding="utf-8") as stream:
                child = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
                try:
                    code = child.wait(timeout=900)
                except subprocess.TimeoutExpired:
                    subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"], check=False, timeout=30,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    child.wait(timeout=30)
                    raise RuntimeError("Final Defender scan exceeded its 15-minute bound")
            receipt["scan_exit_code"] = code
            require(code == 0 and report_path.exists(), "Final Defender scanner did not complete successfully")
            release.verify_windows_evidence(staging, args.version, args.revision, scan_name=final_name)
            final_scan = json.loads(report_path.read_text(encoding="utf-8"))
            verify_final_scan_time(final_scan, manifest)
            receipt["scan_subjects_after"] = {name: digest(staging / name) for name in receipt["scan_subjects_before"]}
            require(receipt["scan_subjects_after"] == receipt["scan_subjects_before"], "Defender scan changed original bytes")
            receipt["defender_after"] = defender_state()
            require(receipt["defender_after"]["start_type"] == receipt["defender_before"]["start_type"],
                    "Defender startup type changed unexpectedly")
            receipt["scan"] = {"status": "passed", "report_sha256": digest(report_path),
                               "scanned_at": final_scan["scanned_at"], "signature_version": final_scan["signature_version"],
                               "signature_updated_at": final_scan["signature_updated_at"],
                               "publication_freshness": "Must be revalidated within one day of publication"}
            receipt["status"] = "passed"
        finally:
            if report_path.exists():
                shutil.copyfile(report_path, args.output / final_name)
            receipt["original_scan_unchanged"] = digest(original_scan) == original_hash
            require(receipt["original_scan_unchanged"], "Original build-time scan was changed")


def run_case(command, log_path):
    """Keep the original report and kill only this owned tree on hard timeout."""
    with log_path.open("w", encoding="utf-8") as stream:
        child = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
        try:
            return child.wait(timeout=600)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"], check=False, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            child.wait(timeout=30)
            return 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("client", "server", "verified", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--server-revision", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--phase", choices=("rescan", "native"), default="native")
    args = parser.parse_args()
    args.client, args.server, args.verified, args.output = (path.resolve() for path in
        (args.client, args.server, args.verified, args.output))
    require(os.name == "nt", "An interactive Windows runner is required")
    require(not args.output.exists(), "Evidence output must be a new directory")
    args.output.mkdir(parents=True)
    receipt = {
        "schema_version": 1, "status": "not_verified", "started_at": datetime.now(timezone.utc).isoformat(),
        "phase": args.phase,
        "scope": "Post-seal Microsoft Defender scan of six original Windows subjects" if args.phase == "rescan" else
                 "Two bounded, same-machine native Windows worker to Chromium fixture cases",
        "production_worker_rebuilt": False, "deployed_server_tested": False,
        "validation_run": {
            "repository": os.environ.get("GITHUB_REPOSITORY"), "revision": os.environ.get("GITHUB_SHA"),
            "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        },
        "environment": {"platform": platform.platform(), "python": platform.python_version()},
        "cases": {}, "limitations": [
            "Does not establish Windows-to-Windows, Android, cross-network traversal, or long-duration stability.",
            "Server JavaScript and the test host are built from pinned clean source; deployed server images are not executed.",
            "Fixture files use confined selectors and origin-private storage, not user-facing file pickers.",
            "Website input invokes production DOM handlers while native injection is confined to a disposable target process.",
            "HTTPS uses a private loopback certificate and test-context trust only; host trust and production policy are unchanged.",
        ],
    }
    worker_path = None
    package = None
    worker_hash = None
    try:
        require(os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted",
                "Validation requires an isolated GitHub-hosted Windows test runner")
        receipt["sources_before"] = {"client": source_state(args.client), "server": source_state(args.server)}
        require(receipt["sources_before"] == {
            "client": {"commit": args.revision, "modified": False},
            "server": {"commit": args.server_revision, "modified": False}}, "Source checkout is dirty or differs from the pinned revision")
        downloaded = json.loads((args.verified / "client-candidate-download.json").read_text(encoding="utf-8"))
        require(downloaded.get("source_revision") == args.revision and downloaded.get("signatures_verified") is True and
                downloaded.get("run_attestations_verified") is True, "Verified original-candidate receipt is required")
        candidate_dir = args.verified / "candidate"
        manifest = json.loads((candidate_dir / "client-candidate.json").read_text(encoding="utf-8"))
        require(digest(candidate_dir / "client-candidate.json") == downloaded["candidate_sha256"], "Candidate manifest changed")
        locked_server = json.loads((args.client / "tests/remote-native/server-lock.json").read_text(encoding="utf-8"))
        require(manifest["server"] == locked_server and locked_server["revision"] == args.server_revision, "Candidate server differs")
        package_name = f"HomeTunnel-Windows-{args.version}-x64.zip"
        package = candidate_dir / package_name
        require(digest(package) == manifest["packages"][package_name]["sha256"], "Portable package changed after verification")
        sys.path.insert(0, str(args.client / "scripts"))
        spec = importlib.util.spec_from_file_location("candidate_release", args.client / "scripts/release.py")
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        worker, server = release.verify_remote_build(candidate_dir, args.version, args.revision)
        worker_hash = worker["sha256"]
        receipt["candidate"] = downloaded
        receipt["package"] = {"name": package_name, **manifest["packages"][package_name]}
        receipt["worker_sha256"] = worker_hash
        receipt["server"] = server
        for name in ("client-candidate.json", "remote-host-provenance.json", "remote-host-build.json"):
            shutil.copyfile(candidate_dir / name, args.output / name)
        shutil.copyfile(args.verified / "client-candidate-download.json", args.output / "client-candidate-download.json")
        if args.phase == "rescan":
            rescan_candidate(args, candidate_dir, manifest, release, receipt)
            require(digest(package) == receipt["package"]["sha256"] and
                    {"client": source_state(args.client), "server": source_state(args.server)} == receipt["sources_before"],
                    "Rescan changed original package or source bytes")
            return
        receipt["interactive_desktop"] = interactive_desktop()
        desktop = receipt["interactive_desktop"]
        require(desktop.get("user_interactive") is True and desktop.get("session_id", 0) > 0 and
                desktop.get("input_desktop_accessible") is True and desktop.get("read_handle_closed") is True,
                "Runner has no accessible interactive input desktop; native cases remain not verified")
        receipt["environment"].update({
            "node": subprocess.check_output(["node", "--version"], text=True, timeout=15).strip(),
            "go": subprocess.check_output(["go", "version"], text=True, timeout=15).strip(),
        })
        with tempfile.TemporaryDirectory(prefix="home-tunnel-final-native-") as directory:
            private = Path(directory)
            worker_path = private / worker["name"]
            with zipfile.ZipFile(package) as bundle:
                with bundle.open(worker["name"]) as source, worker_path.open("xb") as target:
                    shutil.copyfileobj(source, target)
            require(digest(worker_path) == worker_hash, "Extracted production worker differs")
            goroot = subprocess.check_output(["go", "env", "GOROOT"], text=True, timeout=15).strip()
            subprocess.run(["go", "run", str(Path(goroot) / "src/crypto/tls/generate_cert.go"),
                            "-host", "127.0.0.1", "-ca", "-ecdsa-curve", "P256", "-duration", "1h"],
                           cwd=private, check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            common = ["node", str(args.client / "scripts/test-remote-native.mjs"), "--worker", str(worker_path),
                      "--sha256", worker_hash, "--server-root", str(args.server), "--server-source", "locked",
                      "--input", "chromium"]
            cases = [
                ("same-account-input-files", ["--mode", "same-account", "--files", "fixture"]),
                ("website-temporary-assistance", ["--mode", "cross-account-assist", "--controller", "website",
                    "--ca", str(private / "cert.pem"), "--cert", str(private / "cert.pem"), "--key", str(private / "key.pem")]),
            ]
            for name, flags in cases:
                require(digest(worker_path) == worker_hash, "Worker changed before the next case")
                destination = args.output / name
                destination.mkdir()
                code = run_case(common + flags + ["--report-dir", str(destination)], destination / "console.log")
                case = {"exit_code": code, "worker_unchanged": digest(worker_path) == worker_hash,
                        "status": "not_verified"}
                report_path = destination / "report.json"
                if report_path.exists():
                    report = json.loads(report_path.read_text(encoding="utf-8"))
                    case.update({"status": report.get("status"), "report_sha256": digest(report_path),
                                 "source_modified": {key: value["modified"] for key, value in report.get("sources", {}).items()}})
                    if "failure" in report:
                        case["failure"] = report["failure"]
                receipt["cases"][name] = case
                write_json(args.output / "validation.json", receipt)
                print(json.dumps({"case": name, **case}), flush=True)
                require(code == 0 and case["status"] == "passed" and case["worker_unchanged"], "Native runtime case did not pass: " + name)
                require(report.get("release_eligible") is True and report["worker_sha256"] == worker_hash,
                        "Harness did not retain clean, pinned provenance")
            receipt["worker_unchanged_after"] = digest(worker_path) == worker_hash
        receipt["package_unchanged_after"] = digest(package) == receipt["package"]["sha256"]
        receipt["sources_after"] = {"client": source_state(args.client), "server": source_state(args.server)}
        require(receipt["sources_after"] == receipt["sources_before"] and receipt["package_unchanged_after"] and
                receipt["worker_unchanged_after"], "Test changed sources or sealed bytes")
        receipt["status"] = "passed"
    except BaseException as error:
        receipt["status"] = "failed" if receipt["cases"] or receipt.get("scan_started") else "not_verified"
        receipt["failure"] = str(error)
        raise
    finally:
        if package is not None and "package" in receipt:
            receipt["package_unchanged_after"] = digest(package) == receipt["package"]["sha256"]
        receipt["sources_after"] = {"client": source_state(args.client), "server": source_state(args.server)}
        receipt["finished_at"] = datetime.now(timezone.utc).isoformat()
        write_json(args.output / "validation.json", receipt)


if __name__ == "__main__":
    main()
