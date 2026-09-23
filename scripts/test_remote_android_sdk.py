"""Artifact policy fixtures; these do not execute or accept Android media."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("android_sdk", Path(__file__).with_name("package-remote-android-sdk.py"))
SDK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDK)


class AndroidSDKPolicy(unittest.TestCase):
    def test_pinned_header_volume_fits_but_the_file_limit_stays_bounded(self):
        entries = [zipfile.ZipInfo(f"include/header-{index}.h") for index in range(SDK.MAX_SDK_FILES)]
        bundle = SimpleNamespace(infolist=lambda: entries)
        self.assertEqual(len(SDK.checked_members(bundle)), SDK.MAX_SDK_FILES)
        entries.append(zipfile.ZipInfo("include/overflow.h"))
        with self.assertRaisesRegex(SystemExit, "oversized"):
            SDK.checked_members(bundle)

    def test_source_archive_order_and_bytes_are_reproducible_across_hosts(self):
        with tempfile.TemporaryDirectory() as temporary:
            hashes = []
            for name in ("first", "second"):
                output = Path(temporary) / name
                subprocess.run([sys.executable, SDK.ROOT / "scripts/package-remote-core.py", "--output", output],
                               check=True, stdout=subprocess.DEVNULL)
                record = json.loads((output / "remote-artifact.json").read_text())
                hashes.append(record["source_archive_sha256"])
                with tarfile.open(output / record["source_archive"], "r:gz") as archive:
                    names = archive.getnames()
                    self.assertEqual(names, sorted(names))
            self.assertEqual(hashes[0], hashes[1])

    def fixture(self, directory):
        version, revision = "8.0.0-rc.1", "a" * 40
        sources = SDK.source_files()
        tree = hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            for name in sources:
                data = (SDK.NATIVE / name).read_bytes()
                entry = tarfile.TarInfo("native/remote/" + name); entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        source = {"source_revision": revision, "source_tree_dirty": False, "source_files": sources,
                  "source_tree_sha256": tree, "header_sha256": sources["include/home_tunnel/remote.h"],
                  "source_archive": "native-source.tar.gz", "source_archive_sha256": hashlib.sha256(buffer.getvalue()).hexdigest()}
        engine_files = {"lib/arm64-v8a/libwebrtc.a": b"!<arch>\nfixture", "lib/arm64-v8a/libhome_tunnel_android_surface.a": b"!<arch>\nfixture",
                        "lib/arm64-v8a/libhome_tunnel_remote.so": b"fixture-not-executable", "LICENSE.md": b"fixture-notice",
                        "include/home_tunnel/remote.h": (SDK.NATIVE / "include/home_tunnel/remote.h").read_bytes(), "source-manifest.json": b"{}",
                        "PROJECT-LICENSE": (SDK.ROOT / "LICENSE").read_bytes(),
                        "source-license-inventory.json": json.dumps({"schema_version": 1, "dependencies": {},
                            "project": {"headers": ["include/home_tunnel/remote.h"], "notice": "PROJECT-LICENSE"}}).encode()}
        engine = {"source_revision": revision, "source_modified": False, "controller_backend_linked": True,
                  "target": "arm64-v8a", "android_api": 26, "available": False,
                  "gn_args": json.loads((SDK.NATIVE / "android/android-build.lock.json").read_text())["gn_args"],
                  "device_media_accepted": False, "source_files": sources, "source_tree_sha256": tree,
                  "upstream_lock_sha256": SDK.digest(SDK.NATIVE / "remote-deps.lock.json"),
                  "recipe_sha256": SDK.digest(SDK.NATIVE / "android/android-build.lock.json"),
                  "files": {key: hashlib.sha256(value).hexdigest() for key, value in engine_files.items()}}
        contents = {"android-webrtc-arm64/" + key: value for key, value in engine_files.items()}
        contents.update({"android-webrtc-arm64/android-webrtc-build.json": json.dumps(engine).encode(),
                         "source/remote-artifact.json": json.dumps(source).encode(), "source/native-source.tar.gz": buffer.getvalue(),
                         "PROJECT-LICENSE": (SDK.ROOT / "LICENSE").read_bytes()})
        self.write(directory, contents, version, revision)
        return version, revision, contents

    def write(self, directory, contents, version, revision):
        path = directory / SDK.archive_name(version)
        with zipfile.ZipFile(path, "w") as archive:
            for key, value in contents.items():
                archive.writestr(key, value)
        record = {"schema_version": 1, "repository": "ZHanry/home-tunnel-client", "source_revision": revision,
                  "source_modified": False, "version": version, "tag": "v" + version, "target": "arm64-v8a", "android_api": 26,
                  "device_media_accepted": False, "archive": path.name, "archive_sha256": SDK.digest(path), "archive_bytes": path.stat().st_size,
                  "files": {key: hashlib.sha256(value).hexdigest() for key, value in contents.items()}}
        (directory / SDK.PROVENANCE).write_text(json.dumps(record))

    def test_sdk_must_match_final_tag_and_original_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); version, revision, _ = self.fixture(directory)
            SDK.verify(directory, version, revision)
            with self.assertRaisesRegex(SystemExit, "tagged source"):
                SDK.verify(directory, version, "b" * 40)
            with (directory / SDK.archive_name(version)).open("ab") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(SystemExit, "archive bytes"):
                SDK.verify(directory, version, revision)

    def test_changed_library_cannot_reuse_an_older_build_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); version, revision, contents = self.fixture(directory)
            contents["android-webrtc-arm64/lib/arm64-v8a/libhome_tunnel_remote.so"] = b"changed bytes"
            self.write(directory, contents, version, revision)
            with self.assertRaisesRegex(SystemExit, "engine digest"):
                SDK.verify(directory, version, revision)

    def test_release_verifier_rejects_unattributed_headers_even_after_rehashing(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); version, revision, contents = self.fixture(directory)
            key = "android-webrtc-arm64/include/third_party/unlinked/header.h"
            contents[key] = b"Redistributed dependency header"
            engine_key = "android-webrtc-arm64/android-webrtc-build.json"
            engine = json.loads(contents[engine_key])
            engine["files"][key.removeprefix("android-webrtc-arm64/")] = hashlib.sha256(contents[key]).hexdigest()
            contents[engine_key] = json.dumps(engine).encode()
            self.write(directory, contents, version, revision)
            with self.assertRaisesRegex(SystemExit, "trace every redistributed header"):
                SDK.verify(directory, version, revision)

    def test_archive_paths_cannot_escape_or_alias(self):
        for name in ("../outside", "/absolute", "source/../alias", "source\\bad", "C:escape"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); version, revision, contents = self.fixture(directory)
                contents[name] = b"bad"
                self.write(directory, contents, version, revision)
                with self.assertRaisesRegex(SystemExit, "Unsafe|inventory"):
                    SDK.verify(directory, version, revision)


if __name__ == "__main__":
    unittest.main()
