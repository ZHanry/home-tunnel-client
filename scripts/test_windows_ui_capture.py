"""Offline safety/identity checks for the native final-package UI harness.

These are contract tests only; they do not count as running Windows or reading
screenshots. Actual native results come from the Windows CI/candidate workflow.
"""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PackagedWindowsUICaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = (ROOT / 'scripts/capture-windows-ui.ps1').read_text()
        cls.harness = (ROOT / 'scripts/test-windows-packaged-ui.mjs').read_text()

    def test_candidate_archive_and_embedded_version_are_verified_before_execution(self):
        capture = self.capture
        self.assertLess(capture.index("throw 'Input package archive hash mismatch'"), capture.index('Start-Process -FilePath $gui'))
        self.assertLess(capture.index('if ($version -ne $ExpectedVersion)'), capture.index('Start-Process -FilePath $gui'))
        self.assertIn('Candidate capture requires an exact archive SHA-256 and version', capture)
        self.assertIn('package_sha256 = $ExpectedSHA256', capture)
        self.assertIn('gui_sha256 = (Get-FileHash', capture)

    def test_historical_v10_capture_keeps_the_published_pin(self):
        self.assertIn('54dd75d7261000eab6e01c747e5e4545790f006b13646d892c01cb169ce85e34', self.capture)
        self.assertIn('releases/download/v10.0.0/HomeTunnel-Windows-10.0.0-x64.zip', self.capture)
        self.assertIn("$ExpectedVersion = '10.0.0'", self.capture)
        self.assertIn('windows-v10-signin.png', self.capture)

    def test_native_pixels_require_foreground_and_actual_window(self):
        self.assertIn('owner==process && IsWindowVisible(window)', self.capture)
        self.assertIn('GetForegroundWindow() -ne $window', self.capture)
        self.assertIn('CopyFromScreen(', self.capture)
        self.assertIn('Blank or incomplete rendered screenshot', self.capture)
        self.assertIn("$report.status='captured-pending-visual-review'", self.capture)

    def test_regression_uses_existing_webview_and_packaged_assets(self):
        self.assertIn("chromium.connectOverCDP('http://127.0.0.1:9223')", self.harness)
        self.assertNotIn('chromium.launch', self.harness)
        self.assertNotIn('internal/gui/web/', self.harness)
        self.assertIn("if (!url.pathname.startsWith('/local/')) return route.continue()", self.harness)
        self.assertIn("return route.abort()", self.harness)
        self.assertIn('Unhandled packaged-UI fixture request', self.harness)

    def test_no_private_url_or_trace_is_recorded(self):
        self.assertNotIn('tracing.start', self.harness)
        self.assertNotIn('console.log', self.harness)
        self.assertIn('error_type: error.name', self.harness)
        self.assertNotIn('error.message', self.harness)
        self.assertIn('Do not upload process output', self.capture)

    def test_limits_are_explicit_not_native_acceptance(self):
        for literal in ['backend_fixture: true', 'full_remote_session_acceptance: false',
                        'Live remote authentication handoff', 'Physical Windows DPI configurations',
                        'Native approval-popup lifecycle and separate popup HWND']:
            self.assertIn(literal, self.harness)
        self.assertIn('main HWND', self.harness)
        self.assertNotIn('client-acceptance', self.harness)

    def test_required_regression_cases_are_present(self):
        for name in ['login_readable_at_native_minimum', 'login_failure_retry_and_single_submission',
                     'settings_immediate_server_and_embedded_updates', 'rename_local_device_cancel_failure_and_save',
                     'self_connection_rejected_before_native_dispatch', 'theme_language_and_repeated_navigation',
                     'packaged_popup_page_request_and_session_rendering', 'no_script_errors_or_unexpected_network']:
            self.assertIn(f"check('{name}'", self.harness)

    def test_candidate_and_ci_run_the_final_zip_without_acceptance_bypass(self):
        for name in ['client-candidate.yml', 'ci.yml']:
            text = (ROOT / '.github/workflows' / name).read_text()
            self.assertIn('capture-windows-ui.ps1 -ArchivePath', text)
            self.assertIn('-ExpectedSHA256 $sha -ExpectedVersion', text)
            self.assertIn('-Regression', text)
            self.assertNotIn('continue-on-error', text)
        self.assertIn('not an accepted candidate', (ROOT / '.github/workflows/ci.yml').read_text())

    def test_standalone_candidate_capture_verifies_existing_immutable_artifact(self):
        text = (ROOT / '.github/workflows/windows-ui-capture.yml').read_text()
        for key in ['build_run_id:', 'artifact_id:', 'artifact_sha256:', 'revision:', 'version:']:
            self.assertIn(key, text)
        self.assertIn('scripts/fetch-client-candidate.py', text)
        self.assertIn('Specify all five candidate identity inputs or none', text)
        self.assertNotIn('--acceptance-revision', text)

    def test_javascript_syntax(self):
        for name in ['test-windows-packaged-ui.mjs', 'wait-windows-ui.mjs']:
            subprocess.run(['node', '--check', str(ROOT / 'scripts' / name)], check=True)


if __name__ == '__main__':
    unittest.main()
