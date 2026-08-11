import os
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "build"))
sys.path.insert(0, str(REPO_ROOT / "client"))

from brand_config import copy_branded_text, load_brand  # noqa: E402
from homedesk_package import stage_linux_package, validate_deb_arch  # noqa: E402


class BrandConfigTests(unittest.TestCase):
    def test_example_brand_values(self) -> None:
        config = load_brand(REPO_ROOT / "build" / "config.toml.example")
        self.assertEqual("HomeDesk", config.app_name)
        self.assertEqual("homedesk", config.executable_name)
        self.assertEqual("homedesk", config.package_name)

    def test_local_config_is_preferred(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "build").mkdir()
            (root / "build" / "config.toml.example").write_text(
                '[brand]\napp_name="Example"\nexecutable_name="example"\npackage_name="example"\n',
                encoding="utf-8",
            )
            (root / "build" / "config.toml").write_text(
                '[brand]\napp_name="Local"\nexecutable_name="local"\npackage_name="local"\n',
                encoding="utf-8",
            )
            config = load_brand(repo_root=root)
            self.assertEqual("Local", config.app_name)

    def test_brand_copy_replaces_only_selected_template(self) -> None:
        config = load_brand(REPO_ROOT / "build" / "config.toml.example")
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.desktop"
            destination = Path(directory) / "out.desktop"
            source.write_text("Name=RustDesk\nExec=rustdesk %u\n", encoding="utf-8")
            copy_branded_text(source, destination, config)
            self.assertEqual("Name=HomeDesk\nExec=homedesk %u\n", destination.read_text(encoding="utf-8"))

    def test_environment_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "brand.toml"
            path.write_text(
                '[brand]\napp_name="Override"\nexecutable_name="override"\npackage_name="override"\n',
                encoding="utf-8",
            )
            old_value = os.environ.get("HOMEDESK_CONFIG_PATH")
            os.environ["HOMEDESK_CONFIG_PATH"] = str(path)
            try:
                self.assertEqual("Override", load_brand().app_name)
            finally:
                if old_value is None:
                    os.environ.pop("HOMEDESK_CONFIG_PATH", None)
                else:
                    os.environ["HOMEDESK_CONFIG_PATH"] = old_value

    def test_linux_staging_uses_public_brand_names(self) -> None:
        config = load_brand(REPO_ROOT / "build" / "config.toml.example")
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            bundle = temporary / "bundle"
            bundle.mkdir()
            (bundle / "homedesk").write_text("launcher", encoding="utf-8")
            stage = temporary / "tmpdeb"
            stage_linux_package(REPO_ROOT / "client" / "res", stage, config, bundle)

            self.assertTrue((stage / "usr/share/homedesk/homedesk").is_file())
            self.assertTrue((stage / "usr/share/applications/homedesk.desktop").is_file())
            self.assertTrue((stage / "usr/share/homedesk/files/systemd/homedesk.service").is_file())
            postinst = (stage / "DEBIAN/postinst").read_text(encoding="utf-8")
            self.assertIn("/usr/share/homedesk/homedesk", postinst)
            self.assertNotIn("/usr/share/rustdesk/rustdesk", postinst)

    def test_deb_arch_rejects_shell_and_path_characters(self) -> None:
        self.assertEqual("arm64", validate_deb_arch("arm64"))
        for value in ("amd64;touch-x", "../amd64", "AMD64", "amd64 x"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    validate_deb_arch(value)


if __name__ == "__main__":
    unittest.main()
