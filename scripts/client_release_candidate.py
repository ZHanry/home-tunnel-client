"""Immutable client candidates and separately reviewed, package-bound acceptance.

Receipt validation checks the recorded evidence contract. A maintainer must review
the raw VM logs, captures and measurements before committing a passed receipt.
An owner waiver records that a gate or case was not verified; it is never a pass
and carries no measured results.
"""
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import re

REPOSITORY = "ZHanry/home-tunnel-client"
CALLER = ".github/workflows/release.yml"
SIGNER = ".github/workflows/client-candidate.yml"
ACCEPTANCE_REPOSITORY = "ZHanry/home-tunnel"
MANIFEST = "client-candidate.json"
ACCEPTANCE = "client-acceptance.json"
GATES = {
    "remote_sessions": ("windows_to_windows", "web_to_windows", "android_to_windows", "local_approval",
        "one_time_password", "fixed_password", "unattended_local_consent", "scope_denial", "revoke", "emergency_disconnect"),
    "desktop_service": ("boot_without_login", "lock_screen", "login_screen", "uac_secure_desktop", "session_switch",
        "logout_restart", "restricted_ipc", "user_file_permissions"),
    "media_input": ("multiple_monitors", "dpi_mapping", "scaling", "chinese_input", "held_input_release"),
    "files_clipboard_audio": ("bidirectional_text", "bidirectional_multiple_files", "empty_file", "large_file",
        "cancel_cleanup", "integrity", "system_audio_playback"),
    "udp_network": ("lan", "traversable_nat", "double_nat", "udp_blocked", "ipv6", "latency_loss", "payload_capture", "reconnect"),
    "tunnel_management": ("http", "https", "tcp", "udp", "all_templates", "port_permissions", "lifecycle",
        "reconnect_sync", "mfa", "account_isolation", "quota", "multi_server", "batch", "updates", "diagnostics", "monitoring"),
    "gemini_screenshots": ("all_applicable_states", "keyboard_focus", "windows_dpi", "themes", "languages"),
    "stability": ("thirty_connections", "two_hour_active", "twenty_four_hour_online", "input_release", "recovery"),
    "upgrade_recovery": ("real_9_to_10_install", "server_data_migration", "backup", "restore", "rollback"),
    "performance": ("first_frame", "latency", "frame_rate", "resources", "throughput"),
    "other_desktop_builds": ("linux_amd64", "linux_arm64", "macos_amd64", "macos_arm64"),
    "windows_security": ("final_bytes_rescan", "installer_lifecycle", "installed_payload_hashes"),
}
# windows_security is backed by the real CI installer smoke and final Defender rescan; it must pass.
WAIVABLE_GATES = frozenset(GATES) - {"windows_security"}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def filename(name):
    if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", name) or
            name.endswith((".", " ")) or re.fullmatch(r"(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", name, re.I)):
        raise SystemExit("Unsafe release filename")
    return name


def local_file(directory, name):
    path = directory / filename(name)
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(directory.resolve()):
        raise SystemExit("Missing or linked release file: " + name)
    return path


def read_json(path):
    if not 0 < path.stat().st_size <= 16 * 1024**2:
        raise SystemExit("Empty or oversized release evidence")
    return json.loads(path.read_text(encoding="utf-8"))


def verify_files(files, directory):
    if (not isinstance(files, dict) or not 1 <= len(files) <= 256 or
            len({n.casefold() for n in files}) != len(files)):
        raise SystemExit("Invalid release file inventory")
    for name, item in files.items():
        path = local_file(directory, name)
        if (not isinstance(item, dict) or type(item.get("bytes")) is not int or item["bytes"] != path.stat().st_size or
                item["bytes"] < 1 or not re.fullmatch(r"[0-9a-f]{64}", str(item.get("sha256", ""))) or
                digest(path) != item["sha256"]):
            raise SystemExit("Release bytes differ: " + name)


def package_names(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[1-9][0-9]*)?", version):
        raise SystemExit("Invalid candidate version")
    return [f"HomeTunnel-Setup-{version}-x64.exe", f"HomeTunnel-Windows-{version}-x64.zip"] + [
        f"home-tunnel-{platform}-{version}-{arch}.tar.gz" for platform in ("linux", "macos") for arch in ("amd64", "arm64")]


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if result.tzinfo is not None:
            return result
    except (ValueError, TypeError, AttributeError):
        pass
    raise SystemExit("Evidence timestamp must include a timezone")


def verify_waiver(waiver, label):
    """An owner waiver must say who approved skipping what, when, why and where it is disclosed."""
    if not isinstance(waiver, dict) or waiver.get("approved_by") != "owner":
        raise SystemExit("Waiver must be approved by the owner: " + label)
    if timestamp(waiver.get("approved_at")) > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise SystemExit("Waiver approval time is in the future: " + label)
    for key in ("reason", "disclosed_in"):
        if not isinstance(waiver.get(key), str) or not waiver[key].strip():
            raise SystemExit(f"Waiver {key} is missing: {label}")
    return waiver


def verify_candidate(record, directory, revision, version):
    expected = {"schema_version": 1, "repository": REPOSITORY, "revision": revision, "version": version,
        "verification_stage": "candidate", "tag_published": False, "acceptance_complete": False, "source_modified": False}
    if (not re.fullmatch(r"[0-9a-f]{40}", revision) or
            any(type(record.get(k)) is not type(v) or record.get(k) != v for k, v in expected.items())):
        raise SystemExit("Not the original immutable client candidate")
    build = record.get("build", {})
    if (build.get("repository") != REPOSITORY or build.get("caller_workflow") != CALLER or build.get("signer_workflow") != SIGNER or
            not re.fullmatch(r"[1-9][0-9]*", str(build.get("run_id", ""))) or
            type(build.get("run_attempt")) is not int or build["run_attempt"] < 1 or
            not re.fullmatch(r"refs/heads/[^\s]+", str(build.get("source_ref", "")))):
        raise SystemExit("Candidate build invocation must identify an untagged branch run")
    if timestamp(record.get("created_at")) > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise SystemExit("Candidate creation time is in the future")
    verify_files(record.get("files"), directory)
    packages = record.get("packages", {})
    if set(packages) != set(package_names(version)) or any(packages[n] != record["files"].get(n) for n in packages):
        raise SystemExit("Candidate package inventory is incomplete or inconsistent")
    for name in packages:
        if name + ".sigstore.json" not in record["files"]:
            raise SystemExit("Candidate omits a package signature")
        sbom = name + ".spdx.json"
        # The installer and portable archive share the Windows payload SBOM.
        if name.endswith(".exe"):
            sbom = f"HomeTunnel-Windows-{version}-x64.zip.spdx.json"
        if sbom not in record["files"] or sbom + ".sigstore.json" not in record["files"]:
            raise SystemExit("Candidate omits an original package SBOM or its signature")
    server = record.get("server", {})
    if server.get("repository") != "ZHanry/home-tunnel-server" or not re.fullmatch(r"[0-9a-f]{40}", str(server.get("revision", ""))):
        raise SystemExit("Candidate server source is not pinned")
    forbidden = {ACCEPTANCE, "windows-remote-native-acceptance.json", "release-manifest.json", "SHA256SUMS.txt"}
    if forbidden & set(record["files"]) or any(n.startswith("client-acceptance-") for n in record["files"]):
        raise SystemExit("Candidates must not contain publication or preapproved acceptance")
    return record


def acceptance_bindings(candidate, candidate_sha):
    return {"repository": REPOSITORY, "revision": candidate["revision"],
        "candidate_sha256": candidate_sha, "packages": candidate["packages"], "server": candidate["server"]}


def verify_acceptance(record, directory, candidate, candidate_sha):
    expected = acceptance_bindings(candidate, candidate_sha)
    if (record.get("schema_version") != 1 or record.get("acceptance_complete") is not True or
            any(record.get(k) != v for k, v in expected.items())):
        raise SystemExit("Acceptance is incomplete or bound to other packages/source")
    names = {f"client-acceptance-{gate}.json" for gate in GATES}
    names |= {"windows-remote-native-acceptance.json", "windows-final-defender-scan.json"}
    if set(record.get("files", {})) != names or set(record.get("coverage", {})) != set(GATES):
        raise SystemExit("Every required client acceptance receipt must be present")
    verify_files(record["files"], directory)
    statuses = {}
    for gate in GATES:
        coverage = record["coverage"][gate]
        status = coverage.get("status") if isinstance(coverage, dict) else None
        if status not in ("passed", "waived") or coverage != {"status": status, "evidence": f"client-acceptance-{gate}.json"}:
            raise SystemExit("Acceptance gate neither passed nor waived: " + gate)
        if status == "waived" and gate not in WAIVABLE_GATES:
            raise SystemExit("Acceptance gate cannot be waived: " + gate)
        statuses[gate] = status
    overall = "passed" if all(s == "passed" for s in statuses.values()) else "accepted_with_waivers"
    if record.get("status") != overall:
        raise SystemExit("Acceptance status must be " + overall)
    for gate, required_cases in GATES.items():
        name, status = f"client-acceptance-{gate}.json", statuses[gate]
        receipt = read_json(local_file(directory, name))
        if (any(receipt.get(k) != v for k, v in expected.items()) or receipt.get("gate") != gate or
                receipt.get("status") != status or not isinstance(receipt.get("reviewed_by"), str) or
                not receipt["reviewed_by"].strip()):
            raise SystemExit("Receipt source, package, status or reviewer missing: " + gate)
        cases = receipt.get("cases", {})
        if (not isinstance(cases, dict) or not set(required_cases) <= cases.keys() or
                any(v not in ("passed", "waived") for v in cases.values())):
            raise SystemExit("Required cases are missing, failed or skipped: " + gate)
        environment = receipt.get("environment")
        if status == "passed":
            if any(v != "passed" for v in cases.values()):
                raise SystemExit("A passed gate cannot contain waived cases: " + gate)
            if not isinstance(environment, dict) or not environment:
                raise SystemExit("Receipt test environment missing: " + gate)
        else:
            if "waived" not in cases.values():
                raise SystemExit("A waived gate must name its waived cases: " + gate)
            verify_waiver(receipt.get("waiver"), gate)
            if environment is not None and not isinstance(environment, dict):
                raise SystemExit("Receipt test environment is malformed: " + gate)
        raw = receipt.get("raw_evidence", [])
        if (not isinstance(raw, list) or ("passed" in cases.values() and not raw) or
                any(not isinstance(r, dict) or not r.get("location") or
                    not re.fullmatch(r"[0-9a-f]{64}", str(r.get("sha256", ""))) for r in raw)):
            raise SystemExit("Receipt must locate original hashed evidence: " + gate)
        if status == "waived":
            # A waiver carries no measured results; nothing here is a pass.
            continue
        metrics = receipt.get("metrics", {})
        if gate == "gemini_screenshots":
            total = metrics.get("applicable")
            if (type(total) is not int or total < 1 or metrics.get("reviewed") != total or metrics.get("approved") != total or
                    metrics.get("blocking") != 0 or metrics.get("major") != 0 or metrics.get("actual_images_read") is not True):
                raise SystemExit("Gemini must review every applicable actual screenshot")
        if gate == "stability":
            minimum = {"consecutive_connections": 30, "active_seconds": 7200, "online_seconds": 86400}
            if (any(type(metrics.get(k)) is not int or metrics[k] < v for k, v in minimum.items()) or
                    type(metrics.get("connection_failures")) is not int or metrics["connection_failures"] != 0 or
                    type(metrics.get("input_release_ms")) is not int or not 0 <= metrics["input_release_ms"] <= 2000 or
                    type(metrics.get("recovery_or_retry_ms")) is not int or not 0 <= metrics["recovery_or_retry_ms"] <= 30000):
                raise SystemExit("Stability measurements do not satisfy acceptance")
        if gate == "udp_network" and (type(metrics.get("server_relay_payload_bytes")) is not int or metrics["server_relay_payload_bytes"] != 0):
            raise SystemExit("Actual UDP-only payload evidence is required")
        if gate == "performance":
            baseline = metrics.get("baseline", {})
            if (baseline.get("version") != "9.0.0" or not re.fullmatch(r"[0-9a-f]{40}", str(baseline.get("revision", ""))) or
                    not re.fullmatch(r"[0-9a-f]{64}", str(baseline.get("package_sha256", ""))) or
                    not metrics.get("fixed_workload") or not isinstance(metrics.get("measurements"), dict) or
                    not set(required_cases) <= metrics["measurements"].keys()):
                raise SystemExit("Performance comparison must identify the real baseline and fixed workload")
    return record
