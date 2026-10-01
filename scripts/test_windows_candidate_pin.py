"""Identity policy tests; synthetic fixtures are never native acceptance."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import windows_candidate_pin as pins


ROOT = Path(__file__).resolve().parents[1]


class CandidatePinTests(unittest.TestCase):
    def repaired(self):
        return {**pins.ORIGINAL, "revision": "a" * 40, "run_id": "123", "artifact_id": "456",
                "artifact_sha256": "b" * 64, "run_attempt": 2}

    def fixture(self, root):
        directory = root / "tests/remote-native"
        directory.mkdir(parents=True)
        (directory / pins.PIN_FILES["original-10.1"]).write_text(json.dumps(pins.ORIGINAL))
        return directory

    def receipt(self, pin):
        return {"repository": pin["repository"], "source_revision": pin["revision"],
                **{key: pin[key] for key in ("run_id", "run_attempt", "artifact_id", "artifact_sha256")},
                "candidate_sha256": "c" * 64, "signatures_verified": True,
                "run_attestations_verified": True}

    def test_historical_pin_is_exact_and_preserved(self):
        pin, path = pins.load_pin(ROOT, "original-10.1")
        self.assertEqual(pin, pins.ORIGINAL)
        self.assertEqual(path.name, "final-candidate-10.1.json")
        for key, value in self.repaired().items():
            if value != pins.ORIGINAL[key]:
                with self.subTest(key=key), self.assertRaises(ValueError):
                    pins.validate_pin({**pins.ORIGINAL, key: value}, "original-10.1")

    def test_missing_repaired_pin_never_falls_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with self.assertRaisesRegex(ValueError, "absent"):
                pins.load_pin(root, "repaired-10.1")

    def test_only_fixed_reviewed_pin_paths_are_accepted(self):
        for identity in ("../original-10.1", "main", "latest", "", "other"):
            with self.subTest(identity=identity), self.assertRaisesRegex(ValueError, "Unknown"):
                pins.load_pin(ROOT, identity)

    def test_new_pin_requires_new_source_run_artifact_and_digest(self):
        self.assertEqual(pins.validate_pin(self.repaired(), "repaired-10.1"), self.repaired())
        for field in ("revision", "run_id", "artifact_id", "artifact_sha256"):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "new source"):
                pins.validate_pin({**self.repaired(), field: pins.ORIGINAL[field]}, "repaired-10.1")

    def test_pin_schema_and_fields_are_strict(self):
        mutations = [lambda p: p.update(schema_version=True), lambda p: p.update(version="10.1"),
                     lambda p: p.update(repository="other/repository"), lambda p: p.update(revision="a" * 7),
                     lambda p: p.update(server_revision="B" * 40), lambda p: p.update(run_id=123),
                     lambda p: p.update(run_id="01"), lambda p: p.update(artifact_id="123\nrevision=bad"),
                     lambda p: p.update(artifact_sha256="b" * 63), lambda p: p.update(run_attempt=True),
                     lambda p: p.update(run_attempt=0), lambda p: p.update(extra="unsealed"),
                     lambda p: p.pop("server_revision")]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), self.assertRaises(ValueError):
                pin = self.repaired()
                mutate(pin)
                pins.validate_pin(pin, "repaired-10.1")

    def test_loading_new_pin_also_checks_preserved_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = self.fixture(root)
            (destination / pins.PIN_FILES["repaired-10.1"]).write_text(json.dumps(self.repaired()))
            self.assertEqual(pins.load_pin(root, "repaired-10.1")[0], self.repaired())
            (destination / pins.PIN_FILES["original-10.1"]).write_text(json.dumps(self.repaired()))
            with self.assertRaisesRegex(ValueError, "Historical"):
                pins.load_pin(root, "repaired-10.1")

    def test_duplicate_json_fields_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pin.json"
            path.write_text('{"revision":"first","revision":"second"}')
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                pins.read_json(path)

    def test_download_requires_exact_run_attempt_and_verified_identity(self):
        pin = self.repaired()
        receipt = self.receipt(pin)
        pins.verify_download(pin, receipt)
        for field, value in [("run_attempt", 1), ("run_attempt", True), ("artifact_id", "789"),
                             ("source_revision", pins.ORIGINAL["revision"]),
                             ("artifact_sha256", "d" * 64), ("candidate_sha256", "short"),
                             ("signatures_verified", False), ("run_attestations_verified", False)]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                changed = copy.deepcopy(receipt)
                changed[field] = value
                pins.verify_download(pin, changed)

    def test_pr_and_default_dispatch_target_repair_without_skip(self):
        source = (ROOT / ".github/workflows/validate-windows-candidate.yml").read_text()
        self.assertIn("default: repaired-10.1", source)
        self.assertIn("github.event_name == 'pull_request' && 'repaired-10.1' || inputs.candidate_identity", source)
        self.assertIn("options: [repaired-10.1, original-10.1]", source)
        self.assertIn("ref: ${{ steps.candidate.outputs.revision }}", source)
        self.assertIn("ref: ${{ steps.candidate.outputs.server_revision }}", source)
        self.assertIn("--receipt verified-candidate/client-candidate-download.json", source)
        self.assertLess(source.index("Resolve reviewed immutable"), source.index("Check out immutable client"))
        self.assertNotIn("continue-on-error", source)
        self.assertNotIn(": write", source)


if __name__ == "__main__":
    unittest.main()
