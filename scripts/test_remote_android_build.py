"""Negative artifact boundary checks; these are not device/media acceptance."""
import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("android_engine_build", Path(__file__).with_name("build-remote-android-webrtc.py"))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class AndroidArtifactPolicy(unittest.TestCase):
    def test_notice_selection_does_not_collect_unrelated_binaries(self):
        for name in ("LICENSE", "LICENSE.txt", "COPYING.LESSER", "NOTICE.md", "README.chromium", "LICENSES/MIT.txt"):
            self.assertTrue(BUILD.is_sdk_notice(name), name)
        for name in ("libwebrtc.a", "program.exe", "licenses.cpp", "authorstuff.txt", "README.md"):
            self.assertFalse(BUILD.is_sdk_notice(name), name)

    def test_notice_content_is_bounded_text_with_an_exact_legacy_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory).resolve(); notice = source / "LICENSE"
            for content in (b"x" * (4 * 1024 * 1024 + 1), b"MZ\0binary", b"control\x7f", b"unreviewed\xff"):
                notice.write_bytes(content)
                with self.assertRaises(SystemExit):
                    BUILD.notice_bytes(notice, source, {notice})
            notice.write_bytes(b"")
            self.assertEqual(BUILD.notice_bytes(notice, source, {notice}), b"")
            content = b"Legacy copyright: \xa9\n"; notice.write_bytes(content)
            with patch.object(BUILD, "LATIN1_NOTICE", ("LICENSE", hashlib.sha256(content).hexdigest())):
                self.assertEqual(BUILD.notice_bytes(notice, source, {notice}), content)
                notice.write_bytes(content + b"changed")
                with self.assertRaisesRegex(SystemExit, "encoding"):
                    BUILD.notice_bytes(notice, source, {notice})
            notice.write_bytes(b"Copyright Example\n")
            with self.assertRaisesRegex(SystemExit, "untracked"):
                BUILD.notice_bytes(notice, source, set())

    def test_collector_carries_unlinked_header_licenses_and_pinned_wrapper_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); source = root / "src"; output = root / "output"
            repos = {"src": {"api/engine.h": b"header", "LICENSE": b"Engine license", "tool.exe": b"MZ\0not collected"},
                     "src/third_party": {"stub.h": b"header", "LICENSE": b"Third party license",
                         "libFuzzer/LICENSE.TXT": b"Fuzzer license", "libFuzzer/README.chromium": b"License File: LICENSE.TXT"},
                     "src/third_party/libFuzzer/src": {"Fuzzer.h": b"header"},
                     "src/third_party/zstd/src": {"lib/zstd.h": b"header", "LICENSE": b"Zstd license", "COPYING": b"Zstd copying", "NOTICE": b""}}
            entries = {entry: "https://example.invalid/" + entry + "@" + "a" * 40 for entry in repos}
            for entry, files in repos.items():
                folder = root / entry; folder.mkdir(parents=True, exist_ok=True); (folder / ".git").mkdir()
                for name, content in files.items():
                    path = folder / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(content)
            def listing(command, folder, env, capture):
                self.assertEqual(command, ["git", "ls-files", "-z"])
                return "\0".join(repos[folder.relative_to(root).as_posix()]) + "\0"
            with patch.object(BUILD, "run", side_effect=listing):
                record = BUILD.collect_sdk_sources(source, entries, output, {})
            public = output / "include/home_tunnel/remote.h"; public.parent.mkdir(parents=True); public.write_bytes(b"project header")
            (output / "PROJECT-LICENSE").write_bytes(b"project license")
            files = {path.relative_to(output).as_posix(): BUILD.sha(path) for path in output.rglob("*") if path.is_file()}
            BUILD.verify_notice_record(record, {"dependency_sources": entries}, files)
            self.assertEqual((output / "include/third_party/zstd/src/COPYING").read_bytes(), b"Zstd copying")
            self.assertFalse((output / "include/tool.exe").exists())
            self.assertEqual(record["dependencies"]["src/third_party/libFuzzer/src"]["notices"],
                             ["include/third_party/libFuzzer/LICENSE.TXT", "include/third_party/libFuzzer/README.chromium"])
            for mutation in ("missing_notice", "duplicate_header", "missing_header", "wrong_provider", "untracked_file", "empty_license", "inherited_header"):
                altered = json.loads(json.dumps(record)); altered_files = dict(files)
                provider = altered["dependencies"]["src/third_party/zstd/src"]
                if mutation == "missing_notice":
                    del altered_files["include/third_party/zstd/src/COPYING"]
                elif mutation == "duplicate_header":
                    provider["headers"].append(provider["headers"][0])
                elif mutation == "missing_header":
                    del altered["dependencies"]["src/third_party/zstd/src"]
                elif mutation == "wrong_provider":
                    provider["upstream"] += "changed"
                elif mutation == "empty_license":
                    for name in provider["notices"]:
                        altered_files[name] = BUILD.EMPTY_SHA256
                elif mutation == "inherited_header":
                    altered["dependencies"]["src"]["headers"].extend(provider["headers"])
                    del altered["dependencies"]["src/third_party/zstd/src"]
                else:
                    altered_files["include/private.bin"] = "0" * 64
                with self.subTest(mutation=mutation), self.assertRaises(SystemExit):
                    BUILD.verify_notice_record(altered, {"dependency_sources": entries}, altered_files)
            del repos["src/third_party"]["libFuzzer/LICENSE.TXT"]
            with patch.object(BUILD, "run", side_effect=listing), self.assertRaisesRegex(SystemExit, "wrapper notices"):
                BUILD.collect_sdk_sources(source, entries, root / "missing-wrapper", {})
            repos["src/third_party/libFuzzer/src"] = {}
            repos["src/third_party/zstd/src"] = {"lib/zstd.h": b"header", "README.chromium": b"Not a license"}
            (source / "third_party/zstd/src/README.chromium").write_bytes(b"Not a license")
            with patch.object(BUILD, "run", side_effect=listing), self.assertRaisesRegex(SystemExit, "no license notice"):
                BUILD.collect_sdk_sources(source, entries, root / "missing-license", {})

    def test_regular_header_must_be_tracked_inside_the_pinned_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); source = root / "source"; source.mkdir()
            header = source / "real.h"; header.write_text("#pragma once\n")
            self.assertEqual(BUILD.sdk_header_source(header, source, {header}), header)
            with self.assertRaisesRegex(SystemExit, "untracked"):
                BUILD.sdk_header_source(header, source, set())
            with self.assertRaisesRegex(SystemExit, "escapes"):
                BUILD.sdk_header_source(root / "private.h", source, {root / "private.h"})

    def test_header_alias_is_materialized_only_from_a_tracked_internal_header(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); source = root / "source"; source.mkdir()
            header = source / "real.h"; header.write_text("#pragma once\n")
            alias = source / "alias.h"
            try:
                alias.symlink_to(header)
            except OSError as error:
                if getattr(error, "winerror", None) == 1314:
                    self.skipTest("Windows account cannot create symlinks; Linux build CI executes this boundary test")
                raise
            resolved = BUILD.sdk_header_source(alias, source, {alias, header})
            self.assertEqual(resolved, header)
            self.assertFalse(resolved.is_symlink())
            with self.assertRaisesRegex(SystemExit, "untracked"):
                BUILD.sdk_header_source(alias, source, {alias})
            alias.unlink(); outside = root / "outside.h"; outside.write_text("private\n")
            alias.symlink_to(outside)
            with self.assertRaisesRegex(SystemExit, "Unsafe"):
                BUILD.sdk_header_source(alias, source, {alias, outside})
            outside.unlink()
            with self.assertRaisesRegex(SystemExit, "Missing"):
                BUILD.sdk_header_source(alias, source, {alias, outside})

    def test_redistributed_archive_cannot_reference_build_tree_objects(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "surface.a"
            path.write_bytes(b"!<thin>\n" + b"x" * 2000)
            with self.assertRaisesRegex(SystemExit, "non-thin"):
                BUILD.require_regular_archive(path)
            path.write_bytes(b"!<arch>\n")
            with self.assertRaisesRegex(SystemExit, "non-thin"):
                BUILD.require_regular_archive(path)
            path.write_bytes(b"!<arch>\n" + b"x" * 2000)
            BUILD.require_regular_archive(path)  # ELF member architecture is checked separately by readelf.

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
