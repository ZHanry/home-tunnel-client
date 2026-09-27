"""A published RD snapshot must match a clean checkout of the exact version tag."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("remote_contract_import", Path(__file__).with_name("import-remote-contract.py"))
IMPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORT)


class PublishedContractImport(unittest.TestCase):
    def test_published_tag_must_point_to_exact_clean_head(self):
        with patch.object(IMPORT.subprocess, "check_output", return_value="a" * 40 + "\n") as git:
            self.assertEqual(IMPORT.validate_published_ref(Path("."), "api-v1.2.0-rc.1", "a" * 40, False), "api-v1.2.0-rc.1")
            self.assertIn("refs/tags/api-v1.2.0-rc.1^{commit}", git.call_args.args[0])
            with self.assertRaisesRegex(SystemExit, "exact source HEAD"):
                IMPORT.validate_published_ref(Path("."), "api-v1.2.0-rc.1", "b" * 40, False)
            with self.assertRaisesRegex(SystemExit, "clean source"):
                IMPORT.validate_published_ref(Path("."), "api-v1.2.0-rc.1", "a" * 40, True)

    def test_unknown_or_unversioned_tag_cannot_claim_publication(self):
        with patch.object(IMPORT.subprocess, "check_output", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaisesRegex(SystemExit, "absent"):
                IMPORT.validate_published_ref(Path("."), "api-v1.2.0-rc.1", "a" * 40, False)
        for value in ("main", "api-v1.2.0-rc.0", "api-v1.2.0-rc.01", "api-v1.2.0\n"):
            with self.subTest(value=value), self.assertRaisesRegex(SystemExit, "exact stable or RC"):
                IMPORT.validate_published_ref(Path("."), value, "a" * 40, False)

    def test_development_snapshot_does_not_claim_publication(self):
        with patch.object(IMPORT.subprocess, "check_output") as git:
            self.assertIsNone(IMPORT.validate_published_ref(Path("."), None, "a" * 40, True))
            git.assert_not_called()


if __name__ == "__main__":
    unittest.main()
