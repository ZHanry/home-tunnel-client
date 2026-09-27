"""Artifact policy fixtures; these do not execute or accept Android media."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
import zipfile

import yaml

SPEC = importlib.util.spec_from_file_location("android_sdk", Path(__file__).with_name("package-remote-android-sdk.py"))
SDK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDK)
SEAL_SPEC = importlib.util.spec_from_file_location("android_sdk_candidate", Path(__file__).with_name("seal-remote-android-sdk-candidate.py"))
SEAL = importlib.util.module_from_spec(SEAL_SPEC)
SEAL_SPEC.loader.exec_module(SEAL)


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

    def fixture(self, directory, abi="arm64-v8a"):
        version, revision = "8.0.0-rc.1", "a" * 40
        sources = SDK.source_files()
        tree = SDK.source_tree_sha256(sources)
        upstream, android = SDK.ENGINE.locks()
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            for name in sources:
                data = (SDK.NATIVE / name).read_bytes()
                entry = tarfile.TarInfo("native/remote/" + name); entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        source = {"source_revision": revision, "source_tree_dirty": False, "source_files": sources,
                  "source_tree_sha256": tree, "header_sha256": sources["include/home_tunnel/remote.h"],
                  "source_archive": "native-source.tar.gz", "source_archive_sha256": hashlib.sha256(buffer.getvalue()).hexdigest()}
        library = f"lib/{abi}"
        engine_files = {f"{library}/libwebrtc.a": b"!<arch>\nfixture", f"{library}/libhome_tunnel_android_surface.a": b"!<arch>\nfixture",
                        f"{library}/libhome_tunnel_remote.so": b"fixture-not-executable", "LICENSE.md": b"fixture-notice",
                        "include/home_tunnel/remote.h": (SDK.NATIVE / "include/home_tunnel/remote.h").read_bytes(), "source-manifest.json": b"{}",
                        "PROJECT-LICENSE": (SDK.ROOT / "LICENSE").read_bytes(),
                        "source-license-inventory.json": json.dumps({"schema_version": 1, "dependencies": {},
                            "project": {"headers": ["include/home_tunnel/remote.h"], "notice": "PROJECT-LICENSE"}}).encode()}
        engine = {"schema_version": 1, "status": SDK.ENGINE.PRODUCTION_STATUS, "available": False,
                  "controller_backend_linked": True, "production_controller": True, "device_media_accepted": False,
                  "source_modified": False, "test_only": False, "target": abi,
                  "elf_machine": SDK.ENGINE.ABI_PROFILES[abi]["elf_machine"], "android_api": 26, "page_size": 16384,
                  "gn_args": SDK.ENGINE.resolved_gn_args(android, abi), "source_revision": revision,
                  "source_files": sources, "source_tree_sha256": tree,
                  "webrtc_revision": upstream["webrtc"]["revision"], "upstream_lock_sha256": android["upstream_lock_sha256"],
                  "recipe_sha256": SDK.ENGINE.sha(SDK.ENGINE.ANDROID / "android-build.lock.json"),
                  "compiler_lock": SDK.ENGINE.compiler_lock(upstream, android),
                  "files": {key: hashlib.sha256(value).hexdigest() for key, value in engine_files.items()}}
        prefix = SDK.engine_prefix(abi)
        contents = {prefix + "/" + key: value for key, value in engine_files.items()}
        contents.update({prefix + "/android-webrtc-build.json": json.dumps(engine).encode(),
                         "source/remote-artifact.json": json.dumps(source).encode(), "source/native-source.tar.gz": buffer.getvalue(),
                         "PROJECT-LICENSE": (SDK.ROOT / "LICENSE").read_bytes()})
        self.write(directory, contents, version, revision, abi)
        return version, revision, contents

    def write(self, directory, contents, version, revision, abi="arm64-v8a"):
        path = directory / SDK.archive_name(version, abi)
        with zipfile.ZipFile(path, "w") as archive:
            for key, value in contents.items():
                archive.writestr(key, value)
        upstream, android = SDK.ENGINE.locks()
        record = SDK.provenance_identity(version, revision, abi, path.name, SDK.source_tree_sha256(), upstream, android)
        record.update({"archive_sha256": SDK.digest(path), "archive_bytes": path.stat().st_size,
                       "files": {key: hashlib.sha256(value).hexdigest() for key, value in contents.items()}})
        (directory / SDK.provenance_name(abi)).write_text(json.dumps(record))
        (directory / (path.name + ".sha256")).write_text(f"{record['archive_sha256']}  {path.name}\n", encoding="utf-8")

    def test_sdk_must_match_final_tag_and_original_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); version, revision, _ = self.fixture(directory)
            SDK.verify(directory, version, revision)
            with self.assertRaisesRegex(SystemExit, "tagged source"):
                SDK.verify(directory, version, "b" * 40)
            checksum = directory / (SDK.archive_name(version) + ".sha256")
            checksum.write_text("0" * 64 + "  " + SDK.archive_name(version) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "checksum"):
                SDK.verify(directory, version, revision)
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

    def test_default_arm64_names_stay_compatible_and_x86_64_is_explicit(self):
        self.assertEqual(SDK.archive_name("9.0.0"), "HomeTunnel-Remote-SDK-9.0.0-android-arm64.zip")
        self.assertEqual(SDK.provenance_name(), "android-sdk-provenance.json")
        self.assertEqual(SDK.sbom_name(), "android-sdk.spdx.json")
        self.assertEqual(SDK.engine_prefix(), "android-webrtc-arm64")
        described = SDK.describe("9.0.0", "x86_64")
        self.assertEqual(described["archive"], "HomeTunnel-Remote-SDK-9.0.0-android-x86_64.zip")
        self.assertEqual(described["provenance"], "android-sdk-x86_64-provenance.json")
        self.assertEqual(described["sbom"], "android-sdk-x86_64.spdx.json")
        self.assertEqual(described["engine_dir"], "android-webrtc-x86_64")
        self.assertEqual(described["build_dir"], "home_tunnel_android_x64")
        self.assertEqual(described["library_dir"], "lib/x86_64")
        self.assertEqual(described["gn_cpu"], "x64")
        assets = SDK.release_asset_names("9.0.0")
        self.assertEqual(assets[:4], [
            "HomeTunnel-Remote-SDK-9.0.0-android-arm64.zip",
            "HomeTunnel-Remote-SDK-9.0.0-android-arm64.zip.sha256",
            "android-sdk-provenance.json",
            "android-sdk.spdx.json",
        ])
        self.assertIn("HomeTunnel-Remote-SDK-9.0.0-android-x86_64.zip", assets)
        self.assertIn("android-sdk-x86_64-provenance.json", assets)
        self.assertIn("android-sdk-x86_64.spdx.json", assets)
        self.assertEqual(len(assets), 16)

    def test_each_abi_verifies_only_its_own_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, _ = self.fixture(directory, "arm64-v8a")
            self.fixture(directory, "x86_64")
            arm = SDK.verify(directory, version, revision)
            intel = SDK.verify(directory, version, revision, "x86_64")
            self.assertEqual(arm["target"], "arm64-v8a")
            self.assertEqual(arm["archive"], f"HomeTunnel-Remote-SDK-{version}-android-arm64.zip")
            self.assertTrue(arm["production_controller"])
            self.assertFalse(arm["device_media_accepted"])
            self.assertEqual(intel["target"], "x86_64")
            self.assertEqual(intel["elf_machine"], "Advanced Micro Devices X86-64")
            self.assertEqual(intel["gn_args"]["target_cpu"], "x64")
            self.assertEqual(arm["source_tree_sha256"], intel["source_tree_sha256"])
            self.assertEqual(arm["compiler_lock"], intel["compiler_lock"])
            self.assertNotEqual(arm["gn_args"], intel["gn_args"])

    def test_unknown_abi_and_cross_selection_are_rejected(self):
        for value in ("x64", "arm64", "armeabi-v7a", "../x86_64", "x86_64 "):
            with self.subTest(value=value), self.assertRaisesRegex(SystemExit, "Unsupported Android ABI"):
                SDK.archive_name("8.0.0", value)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, _ = self.fixture(directory)
            with self.assertRaisesRegex(SystemExit, "provenance"):
                SDK.verify(directory, version, revision, "x86_64")

    def test_emulator_and_security_core_packages_are_not_production(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, contents = self.fixture(directory, "x86_64")
            prefix = "android-webrtc-x86_64/android-webrtc-build.json"
            engine = json.loads(contents[prefix])
            engine.update(test_only=True, source_modified=True, status="emulator-test-only", production_controller=False)
            contents[prefix] = json.dumps(engine).encode()
            self.write(directory, contents, version, revision, "x86_64")
            with self.assertRaisesRegex(SystemExit, "production"):
                SDK.verify(directory, version, revision, "x86_64")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, contents = self.fixture(directory, "x86_64")
            prefix = "android-webrtc-x86_64/android-webrtc-build.json"
            engine = json.loads(contents[prefix])
            engine.update(status="security-core-only-media-unavailable", controller_backend_linked=False, production_controller=False)
            library = "lib/x86_64/libwebrtc.a"
            del engine["files"][library]
            del contents["android-webrtc-x86_64/" + library]
            contents[prefix] = json.dumps(engine).encode()
            self.write(directory, contents, version, revision, "x86_64")
            with self.assertRaisesRegex(SystemExit, "production"):
                SDK.verify(directory, version, revision, "x86_64")

    def test_relabeled_controller_without_webrtc_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, contents = self.fixture(directory, "arm64-v8a")
            prefix = "android-webrtc-arm64/android-webrtc-build.json"
            engine = json.loads(contents[prefix])
            library = "lib/arm64-v8a/libwebrtc.a"
            del engine["files"][library]
            del contents["android-webrtc-arm64/" + library]
            contents[prefix] = json.dumps(engine).encode()
            self.write(directory, contents, version, revision)
            with self.assertRaisesRegex(SystemExit, "omits required"):
                SDK.verify(directory, version, revision)

    def test_source_tree_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, contents = self.fixture(directory)
            prefix = "android-webrtc-arm64/android-webrtc-build.json"
            engine = json.loads(contents[prefix])
            engine["source_files"] = dict(engine["source_files"])
            engine["source_files"]["include/home_tunnel/remote.h"] = "0" * 64
            contents[prefix] = json.dumps(engine).encode()
            self.write(directory, contents, version, revision)
            with self.assertRaisesRegex(SystemExit, "identity mismatch"):
                SDK.verify(directory, version, revision)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, _ = self.fixture(directory)
            provenance = directory / SDK.provenance_name()
            record = json.loads(provenance.read_text())
            record["source_tree_sha256"] = "ab" * 32
            provenance.write_text(json.dumps(record))
            with self.assertRaisesRegex(SystemExit, "tagged source"):
                SDK.verify(directory, version, revision)

    def sign_candidate(self, directory, version, abi):
        sbom = directory / SDK.sbom_name(abi)
        if not sbom.exists():
            sbom.write_text('{"spdxVersion":"SPDX-2.3","documentNamespace":"fixture"}\n', encoding="utf-8")
        archive = SDK.archive_name(version, abi)
        for name in (archive, archive + ".sha256", SDK.provenance_name(abi), sbom.name):
            (directory / (name + ".sigstore.json")).write_text('{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n', encoding="utf-8")

    def test_candidate_seals_both_abis_without_publishing_or_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, _ = self.fixture(directory, "arm64-v8a")
            self.fixture(directory, "x86_64")
            for abi in SDK.ENGINE.ABI_ORDER:
                self.sign_candidate(directory, version, abi)
            record = SEAL.candidate_record(directory, version, revision, "123456789")
            self.assertEqual(record["verification_stage"], "candidate")
            self.assertEqual(record["status"], "sdk-candidate-device-acceptance-required")
            self.assertFalse(record["tag_published"])
            self.assertFalse(record["stable_release"])
            self.assertFalse(record["device_media_accepted"])
            self.assertEqual(record["native_device_acceptance"], "not_run")
            self.assertEqual(record["source_revision"], revision)
            self.assertEqual(record["workflow_run_id"], "123456789")
            self.assertEqual(record["workflow"], ".github/workflows/android-sdk-candidate.yml")
            self.assertEqual(record["signer_workflow"], SEAL.SIGNER_WORKFLOW)
            self.assertEqual(record["caller_workflow"], SEAL.CALLER_WORKFLOW)
            self.assertEqual(record["caller_event"], "workflow_dispatch")
            self.assertEqual(set(record["abis"]), {"arm64-v8a", "x86_64"})
            self.assertEqual(record["abis"]["arm64-v8a"]["source_tree_sha256"], record["abis"]["x86_64"]["source_tree_sha256"])
            self.assertEqual(record["abis"]["arm64-v8a"]["upstream_lock_sha256"], record["abis"]["x86_64"]["upstream_lock_sha256"])
            self.assertEqual(record["abis"]["arm64-v8a"]["gn_args"]["target_cpu"], "arm64")
            self.assertEqual(record["abis"]["x86_64"]["gn_args"]["target_cpu"], "x64")
            self.assertEqual(record["abis"]["arm64-v8a"]["archive"], f"HomeTunnel-Remote-SDK-{version}-android-arm64.zip")
            self.assertEqual(record["abis"]["x86_64"]["provenance"], "android-sdk-x86_64-provenance.json")
            path = SEAL.write_candidate(directory, record)
            self.assertEqual(json.loads(path.read_text())["workflow_run_id"], "123456789")
            with self.assertRaisesRegex(SystemExit, "never overwritten"):
                SEAL.write_candidate(directory, record)

    def test_candidate_rejects_bad_identity_missing_signature_and_sbom(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            version, revision, _ = self.fixture(directory, "arm64-v8a")
            self.fixture(directory, "x86_64")
            for abi in SDK.ENGINE.ABI_ORDER:
                self.sign_candidate(directory, version, abi)
            for run_id in ("", "0", "01", "12a", "run-1"):
                with self.subTest(run_id=run_id), self.assertRaisesRegex(SystemExit, "run ID"):
                    SEAL.candidate_record(directory, version, revision, run_id)
            with self.assertRaisesRegex(SystemExit, "source SHA"):
                SEAL.candidate_record(directory, version, "A" * 40, "99")
            with self.assertRaisesRegex(SystemExit, "signer"):
                SEAL.candidate_record(directory, version, revision, "99", ".github/workflows/android-webrtc.yml")
            with self.assertRaisesRegex(SystemExit, "registered android-webrtc"):
                SEAL.candidate_record(directory, version, revision, "99", caller_workflow=".github/workflows/release.yml")
            bundle = directory / (SDK.archive_name(version, "arm64-v8a") + ".sigstore.json")
            bundle.unlink()
            with self.assertRaisesRegex(SystemExit, "unsigned"):
                SEAL.candidate_record(directory, version, revision, "99")
            bundle.write_text("{}\n", encoding="utf-8")
            (directory / SDK.sbom_name("x86_64")).write_bytes(b"")
            with self.assertRaisesRegex(SystemExit, "SBOM"):
                SEAL.candidate_record(directory, version, revision, "99")

    def test_candidate_cli_rejects_pull_requests_and_dirty_checkouts(self):
        script = SDK.ROOT / "scripts/seal-remote-android-sdk-candidate.py"
        with tempfile.TemporaryDirectory() as temporary:
            command = [sys.executable, script, "--output", temporary, "--version", "9.0.0", "--revision", "a" * 40, "--run-id", "99"]
            denied = os.environ.copy()
            denied["GITHUB_EVENT_NAME"] = "pull_request"
            result = subprocess.run(command, cwd=SDK.ROOT, env=denied, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("workflow_dispatch", result.stderr)
            self.assertFalse((Path(temporary) / SEAL.CANDIDATE).exists())
            dispatched = os.environ.copy()
            dispatched["GITHUB_EVENT_NAME"] = "workflow_dispatch"
            result = subprocess.run(command, cwd=SDK.ROOT, env=dispatched, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean source", result.stderr)
            self.assertFalse((Path(temporary) / SEAL.CANDIDATE).exists())
            foreign = os.environ.copy()
            foreign["GITHUB_EVENT_NAME"] = "workflow_dispatch"
            foreign["GITHUB_WORKFLOW_REF"] = "ZHanry/home-tunnel-client/.github/workflows/release.yml@refs/heads/main"
            result = subprocess.run(command, cwd=SDK.ROOT, env=foreign, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("registered android-webrtc", result.stderr)
            registered = os.environ.copy()
            registered["GITHUB_EVENT_NAME"] = "workflow_dispatch"
            registered["GITHUB_WORKFLOW_REF"] = "ZHanry/home-tunnel-client/.github/workflows/android-webrtc.yml@refs/heads/codex/v10-overhaul"
            result = subprocess.run(command, cwd=SDK.ROOT, env=registered, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean source", result.stderr)

    def load_workflow(self, name):
        data = yaml.safe_load((SDK.ROOT / ".github/workflows" / name).read_text(encoding="utf-8"))
        if True in data and "on" not in data:
            data["on"] = data.pop(True)
        return data

    def test_candidate_dispatch_stays_on_the_registered_read_only_caller(self):
        caller = self.load_workflow("android-webrtc.yml")
        called = self.load_workflow("android-sdk-candidate.yml")
        self.assertEqual(set(caller["on"]), {"workflow_dispatch", "push"})
        self.assertNotIn("pull_request", caller["on"])
        self.assertNotIn("pull_request_target", caller["on"])
        candidate_input = caller["on"]["workflow_dispatch"]["inputs"]["candidate"]
        self.assertEqual(candidate_input["type"], "boolean")
        self.assertIs(candidate_input["default"], False)
        self.assertEqual(caller["permissions"], {"contents": "read"})
        for name in ("policy", "engine"):
            job = caller["jobs"][name]
            self.assertNotIn("permissions", job)
            self.assertIn("workflow_dispatch", job["if"])
            self.assertIn("inputs.candidate", job["if"])
        seal_job = caller["jobs"]["candidate"]
        self.assertIn("workflow_dispatch", seal_job["if"])
        self.assertIn("inputs.candidate", seal_job["if"])
        self.assertEqual(seal_job["permissions"], {
            "contents": "read", "id-token": "write", "attestations": "write"})
        self.assertEqual(seal_job["uses"], "./.github/workflows/android-sdk-candidate.yml")
        self.assertNotIn("secrets", seal_job)
        self.assertEqual(set(called["on"]), {"workflow_call"})
        for forbidden in ("workflow_dispatch", "pull_request", "pull_request_target", "push"):
            self.assertNotIn(forbidden, called["on"])
        self.assertNotIn("permissions", called)
        self.assertEqual(called["jobs"]["guard"]["permissions"], {"contents": "read"})
        guard_script = called["jobs"]["guard"]["steps"][0]["run"]
        self.assertIn("workflow_dispatch", guard_script)
        self.assertIn(SEAL.CALLER_WORKFLOW, guard_script)
        for name in ("build", "seal"):
            job = called["jobs"][name]
            self.assertIn("guard", job["needs"] if isinstance(job["needs"], list) else [job["needs"]])
            self.assertEqual(job["permissions"], {
                "contents": "read", "id-token": "write", "attestations": "write"})
            self.assertNotEqual(job["permissions"].get("contents"), "write")
        seal_step = next(step for step in called["jobs"]["seal"]["steps"] if "seal-remote-android-sdk-candidate.py" in step.get("run", ""))
        self.assertIn("--workflow .github/workflows/android-sdk-candidate.yml", seal_step["run"])
        self.assertIn("--caller-workflow .github/workflows/android-webrtc.yml", seal_step["run"])

    def test_security_core_exporter_rejects_unknown_targets(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "core"
            result = subprocess.run([sys.executable, SDK.ROOT / "scripts/package-remote-core.py", "--target", "armeabi-v7a", "--output", directory],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unsupported native target", result.stderr + result.stdout)
            library = Path(temporary) / "libhome_tunnel_remote.so"
            library.write_bytes(b"fixture")
            output = Path(temporary) / "packaged"
            subprocess.run([sys.executable, SDK.ROOT / "scripts/package-remote-core.py", "--target", "x86_64", "--library", library, "--output", output],
                           check=True, stdout=subprocess.DEVNULL)
            record = json.loads((output / "remote-artifact.json").read_text())
            self.assertEqual(record["status"], "security-core-only-media-unavailable")
            self.assertFalse(record["production_controller"])
            self.assertFalse(record["controller_backend_linked"])
            self.assertFalse(record["available"])
            self.assertEqual(record["target"], "x86_64")

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
