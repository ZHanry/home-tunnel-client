"""Missing identities are disclosed; partial or mandatory identities fail closed.

These cases never import a certificate, contact Apple or modify the keychain.
Actual publisher-signature verification still requires real release identities.
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SECRET_NAMES = (
    'WINDOWS_SIGNING_PFX_BASE64', 'WINDOWS_SIGNING_PFX_PASSWORD',
    'MACOS_DEVELOPER_ID_P12_BASE64', 'MACOS_DEVELOPER_ID_PASSWORD',
    'MACOS_SIGNING_IDENTITY', 'APPLE_NOTARY_KEY_P8_BASE64',
    'APPLE_NOTARY_KEY_ID', 'APPLE_NOTARY_ISSUER_ID', 'REQUIRE_PLATFORM_SIGNING',
)


class SigningConfiguration(unittest.TestCase):
    def invoke(self, settings):
        environment = {key: value for key, value in os.environ.items() if key not in SECRET_NAMES}
        environment.update(settings)
        if os.name == 'nt':
            command = ['pwsh', '-NoProfile', '-NonInteractive', '-File',
                       str(ROOT / 'packaging/windows/sign-release.ps1'), '-Files', 'unused.exe']
        else:
            command = ['bash', '-c', 'set -Eeuo pipefail; source "$1"; init_signing; cleanup_signing',
                       '--', str(ROOT / 'packaging/macos/signing.sh')]
        return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=20)

    def test_missing_identity_is_explicitly_unsigned(self):
        result = self.invoke({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('explicitly unsigned', result.stdout)

    def test_required_identity_fails(self):
        self.assertNotEqual(self.invoke({'REQUIRE_PLATFORM_SIGNING': 'true'}).returncode, 0)

    def test_password_without_certificate_fails(self):
        name = 'WINDOWS_SIGNING_PFX_PASSWORD' if os.name == 'nt' else 'MACOS_DEVELOPER_ID_PASSWORD'
        self.assertNotEqual(self.invoke({name: 'test-placeholder'}).returncode, 0)

    def test_certificate_without_password_fails(self):
        name = 'WINDOWS_SIGNING_PFX_BASE64' if os.name == 'nt' else 'MACOS_DEVELOPER_ID_P12_BASE64'
        self.assertNotEqual(self.invoke({name: 'not-a-certificate'}).returncode, 0)


if __name__ == '__main__':
    unittest.main()
