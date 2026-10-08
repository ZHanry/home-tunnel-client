import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(REPO_ROOT / "build"), str(REPO_ROOT / "client")]

from brand_config import load_brand  # noqa: E402
from homedesk_package import stage_linux_package  # noqa: E402


@unittest.skipUnless(shutil.which("dpkg-deb"), "dpkg-deb is required")
class LinuxPackageTests(unittest.TestCase):
    def test_dpkg_build_contains_branded_paths(self) -> None:
        brand = load_brand(REPO_ROOT / "build" / "config.toml.example")
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            bundle = temporary / "bundle"
            bundle.mkdir()
            launcher = bundle / brand.executable_name
            launcher.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            launcher.chmod(0o755)

            stage = temporary / "stage"
            stage_linux_package(REPO_ROOT / "client" / "res", stage, brand, bundle)
            control = stage / "DEBIAN" / "control"
            control.write_text(
                "\n".join(
                    (
                        f"Package: {brand.package_name}",
                        "Version: 1.4.9",
                        "Section: net",
                        "Priority: optional",
                        "Architecture: amd64",
                        f"Maintainer: {brand.app_name} <info@rustdesk.com>",
                        f"Description: {brand.app_name} remote desktop client.",
                        "",
                    )
                ),
                encoding="utf-8",
            )
            control.chmod(0o644)

            artifact = temporary / "homedesk_1.4.9_amd64.deb"
            subprocess.run(
                ["dpkg-deb", "--root-owner-group", "--build", str(stage), str(artifact)],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            )
            fields = subprocess.run(
                ["dpkg-deb", "--field", str(artifact), "Package", "Version", "Architecture"],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout
            contents = subprocess.run(
                ["dpkg-deb", "--contents", str(artifact)],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout

            self.assertIn("homedesk", fields)
            self.assertIn("1.4.9", fields)
            self.assertIn("amd64", fields)
            self.assertIn("./usr/share/homedesk/homedesk", contents)
            self.assertIn("./usr/share/applications/homedesk.desktop", contents)
            self.assertIn("./usr/share/homedesk/files/systemd/homedesk.service", contents)


if __name__ == "__main__":
    unittest.main()
