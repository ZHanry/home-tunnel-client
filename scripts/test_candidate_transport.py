"""Transport-only fixtures; no production signature or runtime pass is asserted."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import client_release_candidate as policy
from test_client_candidate import fixture, load

transport = load("candidate_transport_under_test", "stage-candidate-transport.py")


def transport_fixture(source):
    candidate = fixture(source)
    portable = "HomeTunnel-Windows-10.0.0-x64.zip"
    for name in (*transport.METADATA_FILES, portable + ".sha256", portable + ".sha256.sigstore.json"):
        (source / name).write_bytes(b"transport policy fixture: " + name.encode())
        candidate["files"][name] = {"bytes": (source / name).stat().st_size,
                                    "sha256": policy.digest(source / name)}
    (source / policy.MANIFEST).write_text(json.dumps(candidate), encoding="utf-8")
    return candidate


class CandidateTransportTests(unittest.TestCase):
    def test_every_copy_is_original_and_source_inventory_stays_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"
            candidate = transport_fixture(source)
            originals = {p.name: p.read_bytes() for p in source.iterdir()}
            result = transport.stage(source, root / "transport", "a" * 40, "10.0.0")
            self.assertEqual(set(result), {"metadata", "windows-installer", "windows-portable"})
            self.assertEqual(len(result["windows-installer"]), 1)
            self.assertEqual(len(result["windows-portable"]), 1)
            for group, files in result.items():
                for name, item in files.items():
                    self.assertEqual((root / "transport" / group / name).read_bytes(), originals[name])
                    if name in candidate["files"]:
                        self.assertEqual(item, candidate["files"][name])
            self.assertEqual({p.name: p.read_bytes() for p in source.iterdir()}, originals)
            copied = json.loads((root / "transport/metadata" / policy.MANIFEST).read_text())
            self.assertIs(copied["acceptance_complete"], False)
            self.assertFalse(any(name.endswith((".exe", ".zip")) for name in result["metadata"]))

    def test_changed_source_report_fails_before_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; transport_fixture(source)
            (source / "windows-defender-scan.json").write_bytes(b"changed report")
            with self.assertRaisesRegex(SystemExit, "Release bytes differ"):
                transport.stage(source, root / "transport", "a" * 40, "10.0.0")
            self.assertFalse((root / "transport").exists())

    def test_unsealed_metadata_fails_before_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; candidate = transport_fixture(source)
            del candidate["files"]["windows-installer-smoke.json"]
            (source / policy.MANIFEST).write_text(json.dumps(candidate))
            with self.assertRaisesRegex(SystemExit, "missing required transport metadata"):
                transport.stage(source, root / "transport", "a" * 40, "10.0.0")

    def test_corrupted_destination_copy_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; transport_fixture(source)
            with patch.object(transport.shutil, "copyfile", side_effect=lambda src, dst: dst.write_bytes(b"corrupt")):
                with self.assertRaisesRegex(SystemExit, "Release bytes differ"):
                    transport.stage(source, root / "transport", "a" * 40, "10.0.0")

    def test_source_version_and_revision_must_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; transport_fixture(source)
            for revision, version in (("b" * 40, "10.0.0"), ("a" * 40, "10.1.0")):
                with self.subTest(revision=revision, version=version), self.assertRaises(SystemExit):
                    transport.stage(source, root / "transport", revision, version)

    def test_metadata_has_a_safe_size_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; transport_fixture(source)
            with patch.object(transport, "MAX_METADATA_BYTES", 1):
                with self.assertRaisesRegex(SystemExit, "small transport artifact limit"):
                    transport.stage(source, root / "transport", "a" * 40, "10.0.0")
            self.assertFalse((root / "transport").exists())

    def test_reused_or_overlapping_output_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "release"; transport_fixture(source)
            existing = root / "existing"; existing.mkdir()
            for output in (existing, source, source / "transport", root):
                with self.subTest(output=output), self.assertRaisesRegex(SystemExit, "new directory outside"):
                    transport.stage(source, output, "a" * 40, "10.0.0")

    def test_workflow_keeps_full_candidate_upload_and_stages_after_sealing(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/client-candidate.yml").read_text()
        original = ("        name: candidate-assets\n        path: release/*\n"
                    "        retention-days: 90\n        if-no-files-found: error\n")
        self.assertEqual(workflow.count(original), 1)
        self.assertLess(workflow.index("subject-path: release/client-candidate.json"), workflow.index(original))
        self.assertLess(workflow.index(original), workflow.index("scripts/stage-candidate-transport.py"))
        for name in ("candidate-metadata", "windows-candidate-installer", "windows-candidate-portable"):
            self.assertEqual(workflow.count("        name: " + name + "\n"), 1)


if __name__ == "__main__":
    unittest.main()
