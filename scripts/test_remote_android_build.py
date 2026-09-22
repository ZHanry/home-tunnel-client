"""Negative artifact boundary checks; these are not device/media acceptance."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("android_engine_build", Path(__file__).with_name("build-remote-android-webrtc.py"))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class AndroidArtifactPolicy(unittest.TestCase):
    def test_cipd_package_suffix_is_metadata_not_a_filesystem_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".gclient_entries"
            path.write_text("entries = {'src/buildtools/linux64:gn/gn/linux-amd64': 'https://chrome-infra-packages.appspot.com/p/gn/gn/linux-amd64@version:1'}\n")
            self.assertIn("src/buildtools/linux64:gn/gn/linux-amd64", BUILD.dependency_entries(path))

    def test_dependency_manifest_is_data_not_executable_code(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".gclient_entries"
            path.write_text("entries = {'src': 'https://example.invalid/repo@123'}\n__import__('os').abort()\n")
            with self.assertRaises(SystemExit):
                BUILD.dependency_entries(path)

    def test_dependency_manifest_cannot_escape_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".gclient_entries"
            path.write_text("entries = {'../outside': 'https://example.invalid/repo@123'}\n")
            with self.assertRaises(SystemExit):
                BUILD.dependency_entries(path)

    def test_build_output_cannot_claim_media_available(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "android-webrtc-build.json").write_text(json.dumps({"target": "arm64-v8a", "android_api": 26, "available": True}))
            with self.assertRaisesRegex(SystemExit, "capability"):
                BUILD.verify_artifact(path)

    def test_wrong_upstream_revision_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "android-webrtc-build.json").write_text(json.dumps({"target": "arm64-v8a", "android_api": 26, "available": False, "webrtc_revision": "0" * 40}))
            with self.assertRaisesRegex(SystemExit, "recipe"):
                BUILD.verify_artifact(path)


if __name__ == "__main__":
    unittest.main()
