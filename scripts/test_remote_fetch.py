"""Bounded upstream retries retain immutable source and checkout guards."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("webrtc_build", Path(__file__).with_name("build-remote-webrtc.py"))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)
REVISION = "a" * 40


class FetchRetryTests(unittest.TestCase):
    def fetch(self, results):
        with patch.object(BUILD.subprocess, "run", side_effect=results) as run, \
                patch.object(BUILD.time, "sleep") as sleep:
            BUILD.fetch_revision(REVISION, Path("source"), {})
        return run, sleep

    def test_success_does_not_retry(self):
        run, sleep = self.fetch([subprocess.CompletedProcess([], 0, "", "")])
        self.assertEqual(run.call_count, 1)
        sleep.assert_not_called()

    def test_transient_failure_retries_the_same_exact_command(self):
        for message in ("error: RPC failed; HTTP 502 curl 22 The requested URL returned error: 502",
                        "The requested URL returned error: 503", "The requested URL returned error: 504",
                        "Connection timed out", "Connection reset by peer"):
            with self.subTest(message=message):
                run, sleep = self.fetch([subprocess.CompletedProcess([], 128, "", message),
                                        subprocess.CompletedProcess([], 0, "", "")])
                self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args_list[0], run.call_args_list[1])
                self.assertEqual(run.call_args.args[0][-1], REVISION)
                sleep.assert_called_once_with(2)

    def test_persistent_timeout_still_fails_after_three_attempts(self):
        with patch.object(BUILD.subprocess, "run", return_value=subprocess.CompletedProcess([], 128, "", "Connection timed out")) as run, \
                patch.object(BUILD.time, "sleep") as sleep:
            with self.assertRaises(subprocess.CalledProcessError):
                BUILD.fetch_revision(REVISION, Path("source"), {})
            self.assertEqual(run.call_count, 3)
            self.assertEqual([call.args[0] for call in sleep.call_args_list], [2, 4])

    def test_authentication_revision_and_certificate_failures_are_not_retried(self):
        for message in ("Authentication failed", "not our ref", "SSL certificate problem", "unknown failure"):
            with self.subTest(message=message), \
                    patch.object(BUILD.subprocess, "run", return_value=subprocess.CompletedProcess([], 128, "", message)) as run, \
                    patch.object(BUILD.time, "sleep") as sleep:
                with self.assertRaises(subprocess.CalledProcessError):
                    BUILD.fetch_revision(REVISION, Path("source"), {})
                self.assertEqual(run.call_count, 1)
                sleep.assert_not_called()

    def test_checkout_still_rejects_wrong_origin_or_dirty_sources_before_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / ".git").mkdir()
            for outputs in (["other-origin"], ["expected-origin", " M source.cc", b"unreviewed diff"]):
                with patch.object(BUILD.subprocess, "check_output", side_effect=outputs), \
                        patch.object(BUILD, "fetch_revision") as fetch:
                    with self.assertRaises(SystemExit):
                        BUILD.checkout("expected-origin", REVISION, path, {})
                    fetch.assert_not_called()

    def test_failed_fetch_never_checks_out(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / ".git").mkdir()
            with patch.object(BUILD.subprocess, "check_output", side_effect=["expected-origin", "", b""]), \
                    patch.object(BUILD, "fetch_revision", side_effect=subprocess.CalledProcessError(128, "git")), \
                    patch.object(BUILD, "run") as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    BUILD.checkout("expected-origin", REVISION, path, {})
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
