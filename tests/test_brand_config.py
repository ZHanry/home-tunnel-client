import os
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "build"))
sys.path.insert(0, str(REPO_ROOT / "client"))

from brand_config import copy_branded_text, load_brand, load_config  # noqa: E402
from homedesk_package import stage_linux_package, validate_deb_arch  # noqa: E402


class BrandConfigTests(unittest.TestCase):
    @staticmethod
    def _valid_build_config() -> str:
        return """[brand]
app_name = "HomeDesk"
executable_name = "homedesk"
package_name = "homedesk"

[server]
host = "192.168.50.10"
key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

[net]
whitelist_cidr = "192.168.50.0/24"
pure_lan_default = true
"""

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

    def test_private_server_and_whitelist_are_loaded(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text(self._valid_build_config(), encoding="utf-8")
            config = load_config(path)
            self.assertEqual("192.168.50.10", config.server.host)
            self.assertEqual("192.168.50.0/24", config.net.whitelist_cidr)
            self.assertTrue(config.net.pure_lan_default)

    def test_public_server_and_overbroad_whitelist_are_rejected(self) -> None:
        cases = (
            self._valid_build_config().replace("192.168.50.10", "8.8.8.8"),
            self._valid_build_config().replace("192.168.50.0/24", "192.168.0.0/8"),
            self._valid_build_config().replace("pure_lan_default = true", "pure_lan_default = false"),
        )
        for content in cases:
            with self.subTest(content=content):
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "config.toml"
                    path.write_text(content, encoding="utf-8")
                    with self.assertRaises(ValueError):
                        load_config(path)

    def test_placeholder_example_cannot_produce_client_artifact(self) -> None:
        with self.assertRaises(ValueError):
            load_config(REPO_ROOT / "build" / "config.toml.example")

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
