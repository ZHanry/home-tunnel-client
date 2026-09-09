"""Release-stage regressions; these tests do not contact GitHub or publish artifacts."""
from pathlib import Path
import importlib.util
import os
import json
import hashlib
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import patch

script = Path(__file__).with_name("release.py")
spec = importlib.util.spec_from_file_location("release_policy_under_test", script)
module = importlib.util.module_from_spec(spec)
previous_directory = Path.cwd()
try:
    with patch.dict(os.environ, {"GITHUB_REPOSITORY": "ZHanry/home-tunnel-test", "GITHUB_SHA": "test-commit", "GITHUB_REF_NAME": "v0.1.0-rc.1"}):
        spec.loader.exec_module(module)
finally:
    os.chdir(previous_directory)

class ReleasePolicyTests(unittest.TestCase):
    def windows_fixture(self, directory):
        version = "6.0.1"
        setup = "HomeTunnel-Setup-6.0.1-x64.exe"
        archive = "HomeTunnel-Windows-6.0.1-x64.zip"
        payload = {"home-tunnel-gui.exe": b"gui", "home-tunnel-agent.exe": b"agent"}
        (directory/setup).write_bytes(b"installer")
        with zipfile.ZipFile(directory/archive, "w") as bundle:
            for name, data in payload.items(): bundle.writestr(name, data)
        payload.update({setup:(directory/setup).read_bytes(), archive:(directory/archive).read_bytes()})
        now = datetime.now(timezone.utc)
        scan = {"status":"passed", "version":version, "repository_revision":"revision", "engine":"Microsoft Defender", "engine_version":"engine", "signature_version":"signature", "scanned_at":now.isoformat(), "signature_updated_at":now.isoformat(), "files":[{"name":name,"sha256":hashlib.sha256(data).hexdigest(),"exit_code":0} for name,data in payload.items()]}
        install = {"status":"passed","version":version,"repository_revision":"revision","installer_sha256":hashlib.sha256(b"installer").hexdigest(),"install":"passed","payload_hashes":"passed","uninstall":"passed"}
        (directory/'windows-defender-scan.json').write_text(json.dumps(scan))
        (directory/'windows-installer-smoke.json').write_text(json.dumps(install))
        return scan

    def test_publication_requires_scanned_bytes_and_successful_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.windows_fixture(directory)
            module.verify_windows_evidence(directory, "6.0.1", "revision")
            (directory/'HomeTunnel-Setup-6.0.1-x64.exe').write_bytes(b"replaced after scan")
            with self.assertRaisesRegex(SystemExit, "differ from the scanned"):
                module.verify_windows_evidence(directory, "6.0.1", "revision")

    def test_failed_partial_stale_and_wrong_revision_scans_block_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for kind in ("failed", "partial", "stale", "wrong revision"):
                with self.subTest(kind=kind):
                    scan = self.windows_fixture(directory)
                    if kind == "failed": scan['files'][0]['exit_code'] = 2
                    if kind == "partial": scan['files'].pop()
                    if kind == "stale": scan['scanned_at'] = (datetime.now(timezone.utc)-timedelta(days=3)).isoformat()
                    if kind == "wrong revision": scan['repository_revision'] = 'another-build'
                    (directory/'windows-defender-scan.json').write_text(json.dumps(scan))
                    with self.assertRaises(SystemExit): module.verify_windows_evidence(directory, "6.0.1", "revision")

    def test_first_project_version_is_allowed_as_a_test_build(self):
        self.assertEqual(module.validate_release_tag("v0.1.0-rc.1", "0.1.0", "internal-testing"), ("0.1.0", "1"))

    def test_internal_testing_cannot_publish_a_stable_tag(self):
        with self.assertRaisesRegex(SystemExit, "prereleases only"):
            module.validate_release_tag("v0.1.0", "0.1.0", "internal-testing")

    def test_source_version_must_match(self):
        with self.assertRaisesRegex(SystemExit, "source version"):
            module.validate_release_tag("v0.2.0-rc.1", "0.1.0", "internal-testing")

    def test_public_release_requires_an_explicit_stage(self):
        self.assertEqual(module.validate_release_tag("v1.0.0", "1.0.0", "public-release"), ("1.0.0", None))
        with self.assertRaisesRegex(SystemExit, "Unknown release stage"):
            module.validate_release_tag("v1.0.0", "1.0.0", "publc-release")

    def test_public_asset_list_keeps_only_installable_deliverables(self):
        self.assertEqual(module.public_asset_names("android", "6.0.0"), ["HomeTunnel-Android-6.0.0-arm64-v8a.apk"])
        client = module.public_asset_names("client", "6.0.0")
        self.assertEqual(len(client), 6)
        self.assertTrue(all(name.endswith((".exe", ".zip", ".tar.gz")) for name in client))
        self.assertEqual(module.public_asset_names("server", "6.0.0"), ["home-tunnel-server-6.0.0.tar.gz", "compose.release.yaml"])

if __name__ == "__main__":
    unittest.main()
