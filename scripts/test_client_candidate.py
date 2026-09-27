"""Policy fixtures only: no actual package or device acceptance is asserted here."""
import base64
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import client_release_candidate as policy


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetch = load("fetch_client_under_test", "fetch-client-candidate.py")
stage = load("stage_client_under_test", "stage-client-release.py")


def write_json(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")


def fixture(directory):
    directory.mkdir()
    version, revision = "10.0.0", "a" * 40
    for name in policy.package_names(version):
        (directory / name).write_bytes(b"policy fixture, not an installable package")
        (directory / (name + ".sigstore.json")).write_bytes(b"signature fixture, not a valid signature")
        sbom = name + ".spdx.json" if not name.endswith(".exe") else f"HomeTunnel-Windows-{version}-x64.zip.spdx.json"
        (directory / sbom).write_bytes(b"SBOM fixture")
        (directory / (sbom + ".sigstore.json")).write_bytes(b"signature fixture")
    files = {p.name: {"sha256": policy.digest(p), "bytes": p.stat().st_size} for p in directory.iterdir()}
    candidate = {"schema_version": 1, "repository": policy.REPOSITORY, "revision": revision, "version": version,
        "verification_stage": "candidate", "tag_published": False, "acceptance_complete": False, "source_modified": False,
        "created_at": datetime.now(timezone.utc).isoformat(), "files": files,
        "packages": {n: files[n] for n in policy.package_names(version)},
        "server": {"repository": "ZHanry/home-tunnel-server", "revision": "b" * 40},
        "build": {"repository": policy.REPOSITORY, "caller_workflow": policy.CALLER, "signer_workflow": policy.SIGNER,
            "run_id": "123", "run_attempt": 1, "source_ref": "refs/heads/codex/v10-overhaul"}}
    write_json(directory / policy.MANIFEST, candidate)
    (directory / (policy.MANIFEST + ".sigstore.json")).write_bytes(b"signature fixture")
    return candidate


def acceptance_fixture(directory, candidate, candidate_sha):
    directory.mkdir()
    expected = policy.acceptance_bindings(candidate, candidate_sha)
    for gate, cases in policy.GATES.items():
        metrics = {}
        if gate == "gemini_screenshots":
            metrics = {"applicable": 2, "reviewed": 2, "approved": 2, "blocking": 0, "major": 0, "actual_images_read": True}
        elif gate == "stability":
            metrics = {"consecutive_connections": 30, "active_seconds": 7200, "online_seconds": 86400,
                       "connection_failures": 0, "input_release_ms": 1200, "recovery_or_retry_ms": 15000}
        elif gate == "udp_network":
            metrics = {"server_relay_payload_bytes": 0}
        elif gate == "performance":
            metrics = {"baseline": {"version": "9.0.0", "revision": "c" * 40, "package_sha256": "d" * 64},
                       "fixed_workload": "policy fixture", "measurements": {n: {"baseline": 1, "candidate": 1} for n in cases}}
        receipt = {**expected, "gate": gate, "environment": {"fixture": True}, "reviewed_by": "unit-test-only",
            "cases": {name: "passed" for name in cases}, "metrics": metrics,
            "raw_evidence": [{"location": "unit-test-fixture", "sha256": "e" * 64}]}
        write_json(directory / f"client-acceptance-{gate}.json", receipt)
    for name in ("windows-remote-native-acceptance.json", "windows-final-defender-scan.json"):
        write_json(directory / name, {"fixture": True})
    acceptance = {**expected, "schema_version": 1, "acceptance_complete": True,
        "files": {p.name: {"sha256": policy.digest(p), "bytes": p.stat().st_size} for p in directory.iterdir()},
        "coverage": {g: {"status": "passed", "evidence": f"client-acceptance-{g}.json"} for g in policy.GATES}}
    write_json(directory / policy.ACCEPTANCE, acceptance)
    return acceptance


class ClientCandidateTests(unittest.TestCase):
    def test_candidate_bytes_and_acceptance_are_immutable(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "candidate"
            candidate = fixture(directory)
            policy.verify_candidate(candidate, directory, "a" * 40, "10.0.0")
            for key, value in (("acceptance_complete", True), ("tag_published", True), ("source_modified", True),
                               ("revision", "b" * 40), ("version", "10.0.1"), ("verification_stage", "verified")):
                with self.subTest(key=key), self.assertRaises(SystemExit):
                    policy.verify_candidate(dict(candidate, **{key: value}), directory, "a" * 40, "10.0.0")
            name = next(iter(candidate["packages"]))
            (directory / name).write_bytes(b"replacement package")
            with self.assertRaisesRegex(SystemExit, "bytes differ"):
                policy.verify_candidate(candidate, directory, "a" * 40, "10.0.0")

    def test_candidate_cannot_use_another_workflow_or_a_tag(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "candidate"; candidate = fixture(directory)
            for key, value in (("source_ref", "refs/tags/v10.0.0"), ("run_attempt", 0), ("run_id", "main"),
                               ("caller_workflow", "other.yml"), ("signer_workflow", "other.yml")):
                altered = copy.deepcopy(candidate); altered["build"][key] = value
                with self.subTest(key=key), self.assertRaisesRegex(SystemExit, "build invocation"):
                    policy.verify_candidate(altered, directory, "a" * 40, "10.0.0")

    def test_unsigned_package_or_missing_sbom_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "candidate"; candidate = fixture(directory)
            for name in ("HomeTunnel-Setup-10.0.0-x64.exe.sigstore.json", "HomeTunnel-Windows-10.0.0-x64.zip.spdx.json"):
                altered = copy.deepcopy(candidate); del altered["files"][name]
                with self.subTest(name=name), self.assertRaises(SystemExit):
                    policy.verify_candidate(altered, directory, "a" * 40, "10.0.0")

    def test_all_cases_and_raw_evidence_are_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); candidate = fixture(root / "candidate")
            sha = policy.digest(root / "candidate" / policy.MANIFEST)
            record = acceptance_fixture(root / "acceptance", candidate, sha)
            policy.verify_acceptance(record, root / "acceptance", candidate, sha)
            name = "client-acceptance-desktop_service.json"
            original = policy.read_json(root / "acceptance" / name)
            for field, value in (("cases", {"lock_screen": "passed"}), ("raw_evidence", []), ("environment", {}), ("revision", "f" * 40)):
                receipt = dict(original, **{field: value}); write_json(root / "acceptance" / name, receipt)
                record["files"][name] = {"sha256": policy.digest(root / "acceptance" / name), "bytes": (root / "acceptance" / name).stat().st_size}
                with self.subTest(field=field), self.assertRaises(SystemExit):
                    policy.verify_acceptance(record, root / "acceptance", candidate, sha)

    def test_incomplete_ui_relay_and_insufficient_soak_block_release(self):
        changes = [("gemini_screenshots", "reviewed", 1), ("gemini_screenshots", "major", 1),
                   ("gemini_screenshots", "actual_images_read", False), ("stability", "online_seconds", 86399),
                   ("stability", "active_seconds", 7199), ("stability", "connection_failures", 1),
                   ("stability", "input_release_ms", 2001), ("stability", "recovery_or_retry_ms", 30001),
                   ("udp_network", "server_relay_payload_bytes", 1), ("udp_network", "server_relay_payload_bytes", False)]
        for gate, key, value in changes:
            with self.subTest(gate=gate, key=key), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); candidate = fixture(root / "candidate"); sha = policy.digest(root / "candidate" / policy.MANIFEST)
                record = acceptance_fixture(root / "acceptance", candidate, sha)
                name = f"client-acceptance-{gate}.json"; path = root / "acceptance" / name
                receipt = policy.read_json(path); receipt["metrics"][key] = value; write_json(path, receipt)
                record["files"][name] = {"sha256": policy.digest(path), "bytes": path.stat().st_size}
                with self.assertRaises(SystemExit):
                    policy.verify_acceptance(record, root / "acceptance", candidate, sha)

    def test_download_checks_exact_successful_run_artifact_and_digest(self):
        run = {"repository": {"full_name": policy.REPOSITORY}, "path": policy.CALLER, "event": "workflow_dispatch",
               "head_sha": "a" * 40, "id": 123, "status": "completed", "conclusion": "success", "run_attempt": 1}
        artifact = {"id": 456, "name": "candidate-assets", "expired": False, "digest": "sha256:" + "b" * 64,
                    "workflow_run": {"id": 123, "head_sha": "a" * 40}}
        fetch.verify_run(run, artifact, "a" * 40, "123", "456", "b" * 64)
        for field, value in (("head_sha", "c" * 40), ("conclusion", "failure"), ("event", "push"), ("path", policy.SIGNER)):
            with self.subTest(field=field), self.assertRaises(SystemExit):
                fetch.verify_run(dict(run, **{field: value}), artifact, "a" * 40, "123", "456", "b" * 64)
        for field, value in (("expired", True), ("id", 789), ("digest", "sha256:" + "c" * 64)):
            with self.subTest(field=field), self.assertRaises(SystemExit):
                fetch.verify_run(run, dict(artifact, **{field: value}), "a" * 40, "123", "456", "b" * 64)

    def test_archive_traversal_aliases_and_links_are_rejected(self):
        for name in ("../escape", "C:/escape", "foo/bar", "foo\\bar", "con.json", "FILE.", "file:stream"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); archive = root / "fixture.zip"
                with zipfile.ZipFile(archive, "w") as bundle: bundle.writestr(name, b"fixture")
                with self.assertRaises(SystemExit): fetch.extract(archive, root / "output")
                self.assertFalse((root / "output").exists())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root / "fixture.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("file.json", b"one"); bundle.writestr("FILE.json", b"two")
            with self.assertRaises(SystemExit): fetch.extract(archive, root / "output")

    def test_hub_receipts_use_distinct_source_and_review_revisions(self):
        content = b'{"fixture":true}'
        sha = hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest()
        responses = [{"type": "file", "path": f"validation/client/{'a' * 40}/client-acceptance.json", "sha": sha, "size": len(content)},
                     {"encoding": "base64", "sha": sha, "content": base64.b64encode(content).decode()}]
        with patch.object(fetch, "api", side_effect=responses) as query:
            self.assertEqual(fetch.read_hub_file("b" * 40, "a" * 40, policy.ACCEPTANCE, fetch=query), content)
            self.assertIn("?ref=" + "b" * 40, query.call_args_list[0].args[0])

    def test_run_attempt_attestation_cannot_be_reused_from_another_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); candidate = fixture(root / "candidate"); path = root / "candidate" / policy.MANIFEST
            statement = {"subject": [{"digest": {"sha256": policy.digest(path)}}],
                "predicate": {"runDetails": {"metadata": {"invocationId": f"https://github.com/{policy.REPOSITORY}/actions/runs/999/attempts/1"}}}}
            with patch.object(fetch.subprocess, "check_output", return_value=json.dumps([{"verificationResult": {"statement": statement}}]).encode()):
                with self.assertRaisesRegex(SystemExit, "run/attempt"):
                    fetch.verify_attestation(path, candidate["build"], candidate["revision"], root)

    def test_staging_preserves_every_original_byte_and_pending_candidate_flag(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "download"; source.mkdir()
            candidate = fixture(source / "candidate"); sha = policy.digest(source / "candidate" / policy.MANIFEST)
            acceptance = acceptance_fixture(source / "acceptance", candidate, sha)
            write_json(source / "client-candidate-download.json", {"source_revision": candidate["revision"],
                "signatures_verified": True, "run_attestations_verified": True, "acceptance_revision": "b" * 40,
                "candidate_sha256": sha})
            write_json(source / "acceptance/client-acceptance-origin.json", {"fixture": True})
            (source / "verification").mkdir()
            for name in [policy.MANIFEST, *candidate["packages"]]:
                write_json(source / "verification" / (name + ".verification.json"), {"fixture": True})
            stage.stage(source, root / "release", "a" * 40, "10.0.0")
            for path in (source / "candidate").iterdir():
                self.assertEqual((root / "release" / path.name).read_bytes(), path.read_bytes())
            self.assertIs(policy.read_json(root / "release" / policy.MANIFEST)["acceptance_complete"], False)
            self.assertIs(policy.read_json(root / "release" / policy.ACCEPTANCE)["acceptance_complete"], True)
            with self.assertRaisesRegex(SystemExit, "new directory"):
                stage.stage(source, root / "release", "a" * 40, "10.0.0")


if __name__ == "__main__":
    unittest.main()
