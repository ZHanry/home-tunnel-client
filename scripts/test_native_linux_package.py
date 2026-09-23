"""Negative tests for Linux candidate evidence and production-only staging."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("package_linux", Path(__file__).with_name("package-native-linux.py"))
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class NativeLinuxPackage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ht-linux-package-")
        self.addCleanup(self.temporary.cleanup)
        self.build = Path(self.temporary.name) / "build"
        self.build.mkdir()
        self.revision = "a" * 40
        self.source = "b" * 64
        self.version = "8.0.0-rc.1"
        self.lock = PACKAGE.read(PACKAGE.NATIVE / "remote-deps.lock.json")
        header = bytearray(64)
        header[:6] = b"\x7fELF\x02\x01"
        header[18:20] = b"\x3e\x00"
        (self.build / "home_tunnel_remote_host").write_bytes(header + b"synthetic package validation fixture")
        (self.build / "home_tunnel_remote_host_xvfb").write_bytes(b"must never ship")
        (self.build / "LICENSE.md").write_text("Synthetic fixture notices\n")
        self.record = {"schema_version": 1, "status": "built-acceptance-required", "version": self.version,
                       "repository_revision": self.revision, "source_modified": False, "target_os": "linux",
                       "target_cpu": "x64", "linux_source_tree_sha256": self.source,
                       "webrtc_revision": self.lock["webrtc"]["revision"],
                       "deps_lock_sha256": PACKAGE.sha(PACKAGE.NATIVE / "remote-deps.lock.json"),
                       "linux_recipe_sha256": PACKAGE.sha(PACKAGE.NATIVE / "linux/linux-build.lock.json"),
                       "toolchain": self.lock["toolchain"], "authorization_tests": "passed",
                       "clipboard_protocol_tests": "passed", "file_transfer_tests": "passed",
                       "sha256": PACKAGE.sha(self.build / "home_tunnel_remote_host"),
                       "xvfb_test_binary_sha256": PACKAGE.sha(self.build / "home_tunnel_remote_host_xvfb"),
                       "notices_sha256": PACKAGE.sha(self.build / "LICENSE.md"),
                       "physical_xorg_acceptance": False, "executable": "/untrusted/path/never/copied"}
        self.sources = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "revision": self.revision,
                        "worker_sha256": self.record["sha256"], "deps_lock": self.lock}
        self.evidence = {"schema_version": 1, "status": "passed", "scope": "isolated-xvfb",
                         "physical_xorg_acceptance": False, "wayland_acceptance": False,
                         "production_worker_sha256": self.record["sha256"],
                         "test_worker_sha256": self.record["xvfb_test_binary_sha256"],
                         "recipe_sha256": self.record["linux_recipe_sha256"],
                         "production_ipc": {"hello": "passed", "capability_boundary": "passed", "unsigned_authorization": "not_started"},
                         "test_ipc": {"hello": "passed", "capability_boundary": "passed", "unsigned_authorization": "rejected"}}
        for codec in ("H264", "VP8"):
            self.evidence[codec] = {"status": "passed", "exit_code": 0, "requested_codec": codec,
                                    "selected_pair": "udp-host-host", "dtls_connected": True,
                                    "product_acceptance": False, "video_frames_decoded": 30,
                                    "sender": {"mime_type": "video/" + codec},
                                    "receiver": {"mime_type": "video/" + codec}}
        self.write()

    def write(self):
        for name, content, key in (("remote-source-manifest.json", self.sources, "source_manifest_sha256"),
                                    ("linux-xvfb-evidence.json", self.evidence, "isolated_xvfb_evidence_sha256")):
            (self.build / name).write_text(json.dumps(content))
            self.record[key] = PACKAGE.sha(self.build / name)
        (self.build / "remote-host-build.json").write_text(json.dumps(self.record))

    def validate(self):
        return PACKAGE.validate(self.build, self.version, self.revision, self.source)

    def test_stages_only_pinned_production_and_public_evidence(self):
        destination = Path(self.temporary.name) / "package"
        PACKAGE.stage(self.build, destination, self.validate())
        self.assertEqual((destination / "bin/home_tunnel_remote_host").read_bytes(),
                         (self.build / "home_tunnel_remote_host").read_bytes())
        self.assertFalse(any("xvfb" in path.name and path.suffix != ".json" for path in destination.rglob("*")))
        public = PACKAGE.read(destination / "native-remote/remote-host-build.json")
        self.assertNotIn("executable", public)
        self.assertEqual(len([path for path in destination.rglob("*") if path.is_file()]), 6)

    def test_refuses_dirty_stale_or_wrong_platform_record(self):
        original = copy.deepcopy(self.record)
        for key, value in (("source_modified", True), ("repository_revision", "c" * 40),
                           ("linux_source_tree_sha256", "0" * 64), ("target_os", "win"),
                           ("target_cpu", "arm64"), ("authorization_tests", "not_run"),
                           ("file_transfer_tests", "not_run"), ("linux_recipe_sha256", "0" * 64)):
            with self.subTest(key=key):
                self.record = dict(original, **{key: value})
                self.write()
                with self.assertRaises(ValueError):
                    self.validate()

    def test_detects_changed_worker_and_license(self):
        for name in ("home_tunnel_remote_host", "LICENSE.md"):
            with self.subTest(name=name):
                path = self.build / name
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaises(ValueError):
                    self.validate()
                path.write_bytes(original)

    def test_refuses_test_worker_substitution(self):
        self.record["xvfb_test_binary_sha256"] = self.record["sha256"]
        self.evidence["test_worker_sha256"] = self.record["sha256"]
        self.write()
        with self.assertRaises(ValueError):
            self.validate()

    def test_rejects_unverified_codec_or_wrong_ipc_boundary(self):
        original = copy.deepcopy(self.evidence)
        for key, value in (("video_frames_decoded", 0), ("selected_pair", "tcp-host-host"),
                           ("product_acceptance", True), ("dtls_connected", False)):
            with self.subTest(key=key):
                self.evidence = copy.deepcopy(original)
                self.evidence["H264"][key] = value
                self.write()
                with self.assertRaises(ValueError):
                    self.validate()
        self.evidence = copy.deepcopy(original)
        self.evidence["production_ipc"]["unsigned_authorization"] = "accepted"
        self.write()
        with self.assertRaises(ValueError):
            self.validate()

    def test_rejects_source_manifest_from_another_worker(self):
        self.sources["worker_sha256"] = "0" * 64
        self.write()
        with self.assertRaises(ValueError):
            self.validate()

    def test_refuses_stable_version_without_physical_acceptance(self):
        self.version = "8.0.0"
        with self.assertRaises(ValueError):
            self.validate()

    def test_staging_cannot_overwrite_existing_native_files(self):
        destination = Path(self.temporary.name) / "package"
        PACKAGE.stage(self.build, destination, self.validate())
        with self.assertRaises(ValueError):
            PACKAGE.stage(self.build, destination, self.validate())


if __name__ == "__main__":
    unittest.main()
