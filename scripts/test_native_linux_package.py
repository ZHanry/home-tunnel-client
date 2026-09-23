"""Negative tests for Linux candidate evidence and production-only staging."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
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
                         "input": {"status": "passed", "scope": "isolated-xvfb-real-xtest-input",
                                   "physical_xorg_acceptance": False, "unrelated_key_preserved": True,
                                   "already_held_key_preserved": True, "heartbeat_release_ms": 1200,
                                   "worker_crash_release_ms": 20},
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

    def test_requires_measured_input_release_within_two_seconds(self):
        original = copy.deepcopy(self.evidence)
        for key in ("heartbeat_release_ms", "worker_crash_release_ms"):
            for value in (None, True, -1, 2001, "1200"):
                with self.subTest(key=key, value=value):
                    self.evidence = copy.deepcopy(original)
                    self.evidence["input"][key] = value
                    self.write()
                    with self.assertRaises(ValueError):
                        self.validate()

    def test_stable_version_preserves_recorded_acceptance_limits(self):
        self.version = "8.0.0"
        self.record["version"] = self.version
        self.write()
        self.assertFalse(self.validate()["physical_xorg_acceptance"])
        entries = self.archive_fixture()
        self.assertFalse(self.verify_archive(entries)["physical_xorg_acceptance"])
        with self.assertRaises(ValueError):
            self.verify_archive([(info, data + b"changed" if info.name.endswith("/bin/home_tunnel_remote_host") else data)
                                 for info, data in entries])

    def test_rejects_malformed_stable_and_rc_versions(self):
        for version in ("08.0.0", "8.00.0", "8.0.00", "8.0", "v8.0.0", "8.0.0-rc.0", "8.0.0-rc.01",
                        "8.0.0-rc.", "8.0.0-beta.1", "8.0.0+build", "8.0.0\n", "8.0.0-rc.1\n", "\u0668.0.0"):
            self.version = version
            self.record["version"] = version
            self.write()
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "canonical stable or RC"):
                self.validate()

    def test_stable_and_rc_record_versions_cannot_substitute_each_other(self):
        for expected, built in (("8.0.0", "8.0.0-rc.1"), ("8.0.0-rc.1", "8.0.0"), ("8.0.0", "8.0.1")):
            self.version = expected
            self.record["version"] = built
            self.write()
            with self.subTest(expected=expected, built=built), self.assertRaisesRegex(ValueError, "clean build"):
                self.validate()

    @unittest.skipUnless(sys.platform == "linux", "Linux packaging entry point")
    def test_entry_point_accepts_complete_versions_and_rejects_malformed_versions(self):
        packaging = Path(self.temporary.name) / "entry"
        packaging.mkdir()
        entry = packaging / "build-linux-remote-candidate.sh"
        shutil.copyfile(PACKAGE.ROOT / "packaging/build-linux-remote-candidate.sh", entry)
        (packaging / "build-release.sh").write_text('[[ "$ARCH" == amd64 && "$REMOTE_HOST_BUILD" == fixture ]]\n', newline="\n")
        for version, expected in (("8.0.0", 0), ("8.0.0-rc.1", 0), ("8.0.0-rc.22", 0),
                                  ("8.0.0-rc.0", 2), ("8.0.0-rc.01", 2), ("08.0.0", 2),
                                  ("8.0.0-beta.1", 2), ("8.0.0+build", 2), ("8.0.0\n", 2)):
            result = subprocess.run(["bash", str(entry)], env={**os.environ, "VERSION": version, "REMOTE_HOST_BUILD": "fixture"},
                                    capture_output=True, text=True)
            with self.subTest(version=version):
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_staging_cannot_overwrite_existing_native_files(self):
        destination = Path(self.temporary.name) / "package"
        PACKAGE.stage(self.build, destination, self.validate())
        with self.assertRaises(ValueError):
            PACKAGE.stage(self.build, destination, self.validate())

    def archive_fixture(self):
        """Synthetic ELF headers exercise archive policy, never runtime acceptance."""
        destination = Path(self.temporary.name) / "archive-stage"
        PACKAGE.stage(self.build, destination, self.validate())
        header = (self.build / "home_tunnel_remote_host").read_bytes()[:64]
        for name in ("bin/home-tunnel-gui", "bin/home-tunnel-client", "lib/home-tunnel-agent"):
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            suffix = self.record["sha256"].encode() if name.endswith("gui") else b"synthetic fixture"
            path.write_bytes(header + suffix)
        for name in ("install.sh", "LICENSE", "FRP-LICENSE.txt", "lib/systemd/system/home-tunnel-client.service",
                     "docs/PLATFORM_SECURITY.md"):
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic policy fixture\n")
        self.prefix = "home-tunnel-linux-" + self.version + "-amd64"
        entries = []
        for path in destination.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(destination).as_posix()
            info = tarfile.TarInfo(self.prefix + "/" + relative)
            info.mode = 0o755 if relative.startswith("bin/") or relative == "lib/home-tunnel-agent" else 0o644
            entries.append((info, path.read_bytes()))
        return entries

    def archive(self, entries):
        path = Path(self.temporary.name) / "candidate.tar.gz"
        with tarfile.open(path, "w:gz") as bundle:
            for info, content in entries:
                info = copy.copy(info)
                info.size = len(content)
                bundle.addfile(info, io.BytesIO(content))
        return path

    def verify_archive(self, entries):
        return PACKAGE.verify_archive(self.archive(entries), self.version, self.revision, self.source)

    def test_archive_accepts_complete_pinned_production_package(self):
        self.assertEqual(self.verify_archive(self.archive_fixture())["sha256"], self.record["sha256"])

    def test_archive_requires_worker_evidence_and_gui_pin(self):
        entries = self.archive_fixture()
        for suffix in ("bin/home_tunnel_remote_host", "native-remote/remote-host-build.json",
                       "native-remote/linux-xvfb-evidence.json", "native-remote/worker.sha256"):
            with self.subTest(missing=suffix), self.assertRaises(ValueError):
                self.verify_archive([(info, data) for info, data in entries if not info.name.endswith("/" + suffix)])
        for suffix in ("bin/home_tunnel_remote_host", "native-remote/worker.sha256",
                       "native-remote/WEBRTC-THIRD-PARTY-NOTICES.md"):
            with self.subTest(changed=suffix), self.assertRaises(ValueError):
                self.verify_archive([(info, data + b"tampered" if info.name.endswith("/" + suffix) else data)
                                     for info, data in entries])
        with self.assertRaisesRegex(ValueError, "pinned native worker digest"):
            self.verify_archive([(info, data[:64] if info.name.endswith("/bin/home-tunnel-gui") else data)
                                 for info, data in entries])

    def test_archive_rejects_stale_metadata_even_with_original_worker(self):
        entries = self.archive_fixture()
        for key, value in (("repository_revision", "c" * 40), ("source_modified", True),
                           ("linux_source_tree_sha256", "0" * 64), ("version", "8.0.0-rc.2")):
            changed = []
            for info, data in entries:
                if info.name.endswith("/remote-host-build.json"):
                    record = json.loads(data)
                    record[key] = value
                    data = json.dumps(record).encode()
                changed.append((info, data))
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_archive(changed)

    def test_archive_rejects_test_executables_paths_aliases_and_links(self):
        entries = self.archive_fixture()
        for name in ("home_tunnel_remote_host_xvfb", "home_tunnel_x11_input_tests", "home_tunnel_webrtc_probe",
                     "../escaped", "bin/../../escaped", "bin\\escaped", "bin/drive:name", "bin/control\x7f",
                     "bin/HOME_TUNNEL_REMOTE_HOST", "bin/home_tunnel_remote_host"):
            info = tarfile.TarInfo(self.prefix + "/" + name)
            info.mode = 0o755
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify_archive(entries + [(info, b"unexpected")])
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE):
            info = tarfile.TarInfo(self.prefix + "/linked")
            info.type = kind
            info.linkname = "bin/home_tunnel_remote_host"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.verify_archive(entries + [(info, b"")])
        info = tarfile.TarInfo(self.prefix + "/bin")
        with self.assertRaisesRegex(ValueError, "crosses a regular file"):
            self.verify_archive(entries + [(info, b"not a directory")])

    def test_archive_rejects_unsafe_modes_and_other_architectures(self):
        entries = self.archive_fixture()
        for mode in (0o644, 0o777, 0o4755, 0o2001):
            changed = copy.deepcopy(entries)
            for info, _ in changed:
                if info.name.endswith("/bin/home-tunnel-gui"):
                    info.mode = mode
            with self.subTest(mode=oct(mode)), self.assertRaises(ValueError):
                self.verify_archive(changed)
        with self.assertRaisesRegex(ValueError, "architecture mismatch"):
            self.verify_archive([(info, b"MZ" + data[2:] if info.name.endswith("/lib/home-tunnel-agent") else data)
                                 for info, data in entries])


if __name__ == "__main__":
    unittest.main()
