"""Wrapper unit checks; these are never native media acceptance evidence."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("validate_windows_candidate", ROOT / "scripts/validate-windows-candidate.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class WindowsCandidateWrapperTests(unittest.TestCase):
    def scan_fixture(self, directory):
        candidate = directory / "candidate"
        candidate.mkdir()
        version = "10.1.0"
        payloads = {name: name.encode() for name in ("home-tunnel-gui.exe", "home-tunnel-agent.exe", "home-tunnel-service.exe", "home_tunnel_remote_host.exe")}
        archive = candidate / f"HomeTunnel-Windows-{version}-x64.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            for name, data in payloads.items():
                bundle.writestr(name, data)
        setup = candidate / f"HomeTunnel-Setup-{version}-x64.exe"
        setup.write_bytes(b"test-only-installer")
        expected = {name: hashlib.sha256(data).hexdigest() for name, data in payloads.items()}
        expected.update({archive.name: validation.digest(archive), setup.name: validation.digest(setup)})
        validation.write_json(candidate / "windows-defender-scan.json", {"files": [{"name": n, "sha256": h} for n, h in expected.items()]})
        validation.write_json(candidate / "windows-installer-smoke.json", {"test_only": True})
        return candidate, expected

    def test_scan_staging_uses_only_six_original_subjects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, expected = self.scan_fixture(root)
            destination = root / "staging"
            destination.mkdir()
            original = validation.digest(candidate / "windows-defender-scan.json")
            self.assertEqual(validation.prepare_scan_subjects(candidate, destination, "10.1.0", Mock()), expected)
            self.assertEqual(set(p.name for p in destination.iterdir()), set(expected) | {"windows-installer-smoke.json"})
            self.assertEqual(validation.digest(candidate / "windows-defender-scan.json"), original)

    def test_modified_scan_subject_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, _ = self.scan_fixture(root)
            (candidate / "HomeTunnel-Setup-10.1.0-x64.exe").write_bytes(b"changed")
            destination = root / "staging"
            destination.mkdir()
            with self.assertRaisesRegex(RuntimeError, "differs"):
                validation.prepare_scan_subjects(candidate, destination, "10.1.0", Mock())

    def test_scan_must_strictly_follow_candidate_creation(self):
        candidate = {"created_at": "2026-09-30T10:00:00Z"}
        validation.verify_final_scan_time({"scanned_at": "2026-09-30T10:00:01Z"}, candidate)
        for value in ("2026-09-30T10:00:00Z", "2026-09-30T09:59:59Z", "2026-09-30T10:00:01"):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                validation.verify_final_scan_time({"scanned_at": value}, candidate)

    def test_inactive_defender_cannot_trigger_service_changes(self):
        states = [
            {"service_status": "Stopped", "start_type": "Automatic", "am_service_enabled": False, "antivirus_enabled": False},
            {"service_status": "Stopped", "start_type": "Disabled", "am_service_enabled": False, "antivirus_enabled": False},
        ]
        for state in states:
            with self.subTest(state=state), patch.object(validation, "defender_state", return_value=state), patch.object(subprocess, "Popen") as launch:
                with self.assertRaisesRegex(RuntimeError, "not already active"):
                    validation.rescan_candidate(None, None, None, None, {})
                launch.assert_not_called()

    def test_scanner_environment_is_child_only_and_does_not_manage_services(self):
        source = (ROOT / "scripts/validate-windows-candidate.py").read_text()
        self.assertIn('env = dict(os.environ, GITHUB_SHA=args.revision, GITHUB_ACTIONS="false")', source)
        self.assertIn('scan_name=final_name', source)
        self.assertNotIn('os.environ["GITHUB_SHA"] =', source)
        workflow = (ROOT / ".github/workflows/validate-windows-candidate.yml").read_text()
        self.assertLess(workflow.index("Rescan the exact post-seal"), workflow.index("Run two bounded"))
        self.assertLess(workflow.index("windows-final-defender-${{"), workflow.index("Run two bounded"))

    def test_hash_is_computed_from_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "payload"
            path.write_bytes(b"original")
            first = validation.digest(path)
            self.assertEqual(first, hashlib.sha256(b"original").hexdigest())
            path.write_bytes(b"changed")
            self.assertNotEqual(first, validation.digest(path))

    def test_source_state_never_assumes_clean(self):
        with patch.object(subprocess, "check_output", side_effect=["a" * 40 + "\n", b" M changed\n"]):
            self.assertEqual(validation.source_state(Path("source")), {"commit": "a" * 40, "modified": True})

    def test_missing_source_state_fails(self):
        with patch.object(subprocess, "check_output", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                validation.source_state(Path("missing"))

    def test_timeout_kills_only_owned_process_tree(self):
        child = Mock(pid=12345)
        child.wait.side_effect = [subprocess.TimeoutExpired("owned", 600), 1]
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(subprocess, "Popen", return_value=child), patch.object(subprocess, "run") as kill:
                self.assertEqual(validation.run_case(["owned"], Path(directory) / "console.log"), 124)
                self.assertEqual(kill.call_args.args[0], ["taskkill", "/PID", "12345", "/T", "/F"])

    def test_case_exit_code_is_preserved(self):
        child = Mock(pid=12345)
        child.wait.return_value = 1
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(subprocess, "Popen", return_value=child), patch.object(subprocess, "run") as kill:
                self.assertEqual(validation.run_case(["owned"], Path(directory) / "console.log"), 1)
                kill.assert_not_called()

    def test_json_evidence_written_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "case" / "report.json"
            validation.write_json(path, {"status": "not_verified"})
            self.assertEqual(json.loads(path.read_text()), {"status": "not_verified"})

    def test_workflow_is_read_only_and_sources_are_immutable(self):
        workflow = (ROOT / ".github/workflows/validate-windows-candidate.yml").read_text()
        self.assertNotIn(": write", workflow)
        self.assertEqual(workflow.count("persist-credentials: false"), 3)
        self.assertIn("ref: 9b3dbb751942fee040049f9901ea61e95e60c10c", workflow)
        self.assertIn("ref: 194ae805f3569dc16d94b7fda71367e5d68fdff5", workflow)
        self.assertNotIn("build-native-windows", workflow)


class StabilityReceiptTests(unittest.TestCase):
    """Synthetic receipt fixtures test rejection only; they are not runtime evidence."""
    def fixture(self, destination):
        samples = []
        for n in range(1441):
            samples.append({"sample": n + 1, "elapsed_ms": n * 5000, "wall_ms": 10000000 + n * 5000,
                "media_state": {**{key: True for key in ("peer_verified", "host_path_verified", "browser_udp_verified", "input_enabled", "lease_valid", "signal_authenticated")}, "connection_state": "connected", "dtls_state": "connected"},
                **{key: n + 1 for key in ("frames_decoded", "frames_presented", "bytes_received", "video_time", "input_frames_sent", "native_input_accepted", "native_frames_encoded")},
                "lease_sequence": 1 + n // 48, "controller_token_refreshes": n // 120,
                "input_events": [{"type": kind, "trusted": True, "target_matches": True} for kind in ("keydown", "keyup", "pointerdown", "pointerup")]})
        report = {"input": {"heartbeat_watchdog": {"passed": True, "release_ms": 1600}, "worker_crash": {"passed": True, "key_release_ms": 100, "button_release_ms": 100}},
            "stability": {"status": "passed", "actual_connections": 30,
                "sessions": [{"ordinal": n + 1, "pairing_started_elapsed_ms": n * 15000, "session_id_sha256": str(n), "signed_pairing": True, "live_media": True, "trusted_input": True, "clean_close": True, "fresh_pairing_to_input_ms": 3000} for n in range(30)],
                "active_window": {"status": "passed", "actual_active_seconds": 7200, "samples": len(samples)},
                "post_crash_explicit_restart": {"status": "passed", "clean_close": True, "crash_to_live_input_ms": 5000}}}
        self.save_samples(report, destination, samples)
        return report, samples

    def save_samples(self, report, destination, samples):
        path = destination / "stability-samples.jsonl"
        path.write_text("".join(json.dumps(value) + "\n" for value in samples))
        report["stability"]["samples_sha256"] = validation.digest(path)

    def test_valid_fixture_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report, _ = self.fixture(root)
            validation.verify_stability_report(report, root)

    def test_missing_or_inflated_results_are_rejected(self):
        changes = [
            lambda r, s: r["stability"].update(actual_connections=29),
            lambda r, s: r["stability"]["sessions"][1].update(session_id_sha256="0"),
            lambda r, s: r["stability"]["sessions"][1].update(clean_close=False),
            lambda r, s: r["stability"]["sessions"][1].update(pairing_started_elapsed_ms=14999),
            lambda r, s: r["stability"]["sessions"][1].update(fresh_pairing_to_input_ms=30001),
            lambda r, s: r["stability"]["active_window"].update(actual_active_seconds=7199),
            lambda r, s: s[-1].update(elapsed_ms=7199999),
            lambda r, s: s[-1].update(lease_sequence=1),
            lambda r, s: s[1].update(frames_decoded=s[0]["frames_decoded"]),
            lambda r, s: s[1]["input_events"][0].update(trusted=False),
            lambda r, s: s[1]["media_state"].update(browser_udp_verified=False),
            lambda r, s: s[1].update(wall_ms=20000000),
            lambda r, s: r["input"]["heartbeat_watchdog"].update(release_ms=2001),
            lambda r, s: r["stability"]["post_crash_explicit_restart"].update(crash_to_live_input_ms=30001),
        ]
        for index, change in enumerate(changes):
            with self.subTest(case=index), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                report, samples = self.fixture(root)
                change(report, samples)
                self.save_samples(report, root, samples)
                with self.assertRaises(RuntimeError):
                    validation.verify_stability_report(report, root)

    def test_original_samples_hash_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report, _ = self.fixture(root)
            (root / "stability-samples.jsonl").write_text("changed")
            with self.assertRaisesRegex(RuntimeError, "samples changed"):
                validation.verify_stability_report(report, root)

    def test_long_case_is_bounded_and_only_owned_tree_is_killed(self):
        child = Mock(pid=12345)
        child.wait.side_effect = [subprocess.TimeoutExpired("owned", 10800), 1]
        with tempfile.TemporaryDirectory() as directory, patch.object(subprocess, "Popen", return_value=child), patch.object(subprocess, "run") as kill:
            self.assertEqual(validation.run_case(["owned"], Path(directory) / "console.log", timeout_seconds=10800), 124)
            self.assertEqual(child.wait.call_args_list[0].kwargs, {"timeout": 10800})
            self.assertEqual(kill.call_args.args[0], ["taskkill", "/PID", "12345", "/T", "/F"])

    def test_arbitrary_timeout_is_rejected(self):
        with patch.object(subprocess, "Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "Unsupported native case timeout"):
                validation.run_case([], None, timeout_seconds=86400)
            launch.assert_not_called()

    def test_long_mode_requires_explicit_dispatch(self):
        source = (ROOT / ".github/workflows/validate-windows-candidate.yml").read_text()
        self.assertIn("default: short", source)
        self.assertIn("options: [short, stability]", source)
        self.assertIn("if: github.event_name == 'workflow_dispatch' && inputs.validation_scope == 'stability'", source)
        self.assertIn("timeout-minutes: 185", source)
        self.assertIn("--phase stability", source)


if __name__ == "__main__":
    unittest.main()
