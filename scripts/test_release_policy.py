"""Release-stage regressions; these tests do not contact GitHub or publish artifacts."""
from pathlib import Path
import importlib.util
import os
import json
import hashlib
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import patch

script = Path(__file__).with_name("release.py")
spec = importlib.util.spec_from_file_location("release_policy_under_test", script)
module = importlib.util.module_from_spec(spec)
previous_directory = Path.cwd()
try:
    with patch.dict(os.environ, {"GITHUB_REPOSITORY": "ZHanry/home-tunnel-test", "GITHUB_SHA": "test-commit", "GITHUB_REF_NAME": "v0.1.0-rc.1"}):
        spec.loader.exec_module(module)
finally:
    os.chdir(previous_directory)

class ReleasePolicyTests(unittest.TestCase):
    def windows_fixture(self, directory):
        version = "6.0.1"
        setup = "HomeTunnel-Setup-6.0.1-x64.exe"
        archive = "HomeTunnel-Windows-6.0.1-x64.zip"
        payload = {"home-tunnel-gui.exe": b"gui", "home-tunnel-agent.exe": b"agent", "home_tunnel_remote_host.exe": b"native worker fixture",
                   "remote-host-provenance.json": b'{}', "remote-host-build.json": b'{}', 'remote-source-manifest.json': b'{}',
                   'WEBRTC-THIRD-PARTY-NOTICES.md': b'fixture notices'}
        (directory/setup).write_bytes(b"installer")
        with zipfile.ZipFile(directory/archive, "w") as bundle:
            for name, data in payload.items(): bundle.writestr(name, data)
        installed_payloads = [{'name': name, 'sha256': hashlib.sha256(data).hexdigest()} for name, data in payload.items()]
        payload = {name: data for name, data in payload.items() if name.endswith('.exe')}
        payload.update({setup:(directory/setup).read_bytes(), archive:(directory/archive).read_bytes()})
        now = datetime.now(timezone.utc)
        scan = {"status":"passed", "version":version, "repository_revision":"revision", "engine":"Microsoft Defender", "engine_version":"engine", "signature_version":"signature", "scanned_at":now.isoformat(), "signature_updated_at":now.isoformat(), "files":[{"name":name,"sha256":hashlib.sha256(data).hexdigest(),"exit_code":0} for name,data in payload.items()]}
        install = {"status":"passed","version":version,"repository_revision":"revision","installer_sha256":hashlib.sha256(b"installer").hexdigest(),"install":"passed","payload_hashes":"passed","uninstall":"passed","embedded_icon":"passed","gui_subsystem":"passed","native_window_icon":"passed", 'installed_payloads': installed_payloads}
        (directory/'windows-defender-scan.json').write_text(json.dumps(scan))
        (directory/'windows-installer-smoke.json').write_text(json.dumps(install))
        return scan

    def remote_fixture(self, directory):
        self.windows_fixture(directory)
        lock_path = module.ROOT / 'native/remote/remote-deps.lock.json'
        dependency = json.loads(lock_path.read_text())
        server = json.loads((module.ROOT / 'tests/remote-native/server-lock.json').read_text())
        digest = hashlib.sha256(b'native worker fixture').hexdigest()
        provenance = {'schema_version': 1, 'version': '6.0.1', 'repository_revision': 'revision', 'abi_version': 1,
                      'worker': {'name': 'home_tunnel_remote_host.exe', 'sha256': digest, 'unsigned_sha256': digest},
                      'engine': {'revision': dependency['webrtc']['revision'], 'lock_sha256': hashlib.sha256(lock_path.read_bytes()).hexdigest()},
                      'server': {key: server[key] for key in ('repository', 'revision')},
                      'build': {'source_modified': False, 'authorization_tests': 'passed'},
                      'notices_sha256': hashlib.sha256(b'fixture notices').hexdigest(),
                      'source_manifest_sha256': hashlib.sha256(b'{}').hexdigest()}
        build = {'sha256': digest, 'version': '6.0.1', 'repository_revision': 'revision', 'source_modified': False,
                 'target_os': 'win', 'target_cpu': 'x64', 'webrtc_revision': provenance['engine']['revision'],
                 'deps_lock_sha256': provenance['engine']['lock_sha256'], 'authorization_tests': 'passed',
                 'notices_sha256': provenance['notices_sha256'], 'source_manifest_sha256': provenance['source_manifest_sha256']}
        report = {'status': 'passed', 'input': {'status': 'passed', **{key: True for key in ('keyboard_down_up', 'unicode_text', 'pointer_down_up',
                  'native_process_confinement', 'os_foreground_verified', 'released')}}, 'worker_sha256': digest,
                  'sources': {'client': {'commit': 'revision', 'modified': False}, 'server': {'commit': server['revision'], 'modified': False}},
                  'server_build': {'fresh': True, 'source_commit': server['revision'], 'command': 'pnpm run build',
                                   'dist': {'file_count': 1, 'sha256': hashlib.sha256(b'fixture build').hexdigest()}},
                  'checks': {key: True for key in ('isolated_real_server', 'native_backend_ready', 'real_browser_identity', 'signed_pairing_and_code_match',
                             'explicit_session_approval', 'real_continuing_video', 'selected_udp_and_dtls', 'clean_session_shutdown')},
                  'media': {'ready': True, 'peer_verified': True, 'host_path_verified': True, 'browser_udp_verified': True,
                            'closed': False, 'dtls_state': 'connected', 'frames_decoded': 20, 'failures': []}}
        (directory / 'remote-host-provenance.json').write_text(json.dumps(provenance))
        (directory / 'remote-host-build.json').write_text(json.dumps(build))
        (directory / 'remote-source-manifest.json').write_bytes(b'{}')
        (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
        with zipfile.ZipFile(directory / 'HomeTunnel-Windows-6.0.1-x64.zip', 'w') as bundle:
            bundle.writestr('home_tunnel_remote_host.exe', b'native worker fixture')
            bundle.writestr('WEBRTC-THIRD-PARTY-NOTICES.md', b'fixture notices')
            for name in ('remote-host-provenance.json', 'remote-host-build.json', 'remote-source-manifest.json'):
                bundle.writestr(name, (directory / name).read_bytes())
        return provenance, report

    def test_native_acceptance_binds_final_signed_worker_and_clean_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.remote_fixture(directory)
            module.verify_remote_evidence(directory, '6.0.1', 'revision')
            with zipfile.ZipFile(directory / 'HomeTunnel-Windows-6.0.1-x64.zip', 'w') as bundle:
                bundle.writestr('home_tunnel_remote_host.exe', b'rebuilt or newly signed bytes')
            with self.assertRaisesRegex(SystemExit, 'Packaged native worker'):
                module.verify_remote_evidence(directory, '6.0.1', 'revision')

    def test_view_only_dirty_stale_or_failed_native_runs_block_publication(self):
        changes = [
            lambda p, r: r['input'].update(status='not_verified'),
            lambda p, r: r['input'].update(unicode_text=False),
            lambda p, r: r['sources']['client'].update(modified=True),
            lambda p, r: r['sources']['server'].update(commit='a' * 40),
            lambda p, r: r['server_build'].update(fresh=False),
            lambda p, r: r['server_build'].update(source_commit='a' * 40),
            lambda p, r: r.update(worker_sha256='b' * 64),
            lambda p, r: r['checks'].update(clean_session_shutdown=False),
            lambda p, r: r['media'].update(browser_udp_verified=False),
            lambda p, r: r['media'].update(closed=True),
            lambda p, r: r['media'].update(frames_decoded=0),
            lambda p, r: r['media'].update(failures=['RD_MEDIA_FAILED']),
            lambda p, r: p['engine'].update(lock_sha256='c' * 64),
            lambda p, r: p['build'].update(source_modified=True),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for change in changes:
                with self.subTest(change=change):
                    provenance, report = self.remote_fixture(directory)
                    change(provenance, report)
                    (directory / 'remote-host-provenance.json').write_text(json.dumps(provenance))
                    (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
                    with self.assertRaises(SystemExit):
                        module.verify_remote_evidence(directory, '6.0.1', 'revision')

    def test_windows_extraction_aliases_cannot_replace_the_verified_worker(self):
        for alias in ('HOME_TUNNEL_REMOTE_HOST.EXE', 'home_tunnel_remote_host.exe.',
                      '../home_tunnel_remote_host.exe', 'home_tunnel_remote_host.exe:stream', 'C:/payload.exe'):
            with self.subTest(alias=alias), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                self.remote_fixture(directory)
                with zipfile.ZipFile(directory / 'HomeTunnel-Windows-6.0.1-x64.zip', 'a') as bundle:
                    bundle.writestr(alias, b'unverified replacement')
                with self.assertRaisesRegex(SystemExit, 'Windows archive'):
                    module.verify_remote_build(directory, '6.0.1', 'revision')

    def test_publication_requires_scanned_bytes_and_successful_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.windows_fixture(directory)
            module.verify_windows_evidence(directory, "6.0.1", "revision")
            (directory/'HomeTunnel-Setup-6.0.1-x64.exe').write_bytes(b"replaced after scan")
            with self.assertRaisesRegex(SystemExit, "differ from the scanned"):
                module.verify_windows_evidence(directory, "6.0.1", "revision")

    def test_installer_payload_must_be_the_same_worker_as_portable_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.windows_fixture(directory)
            path = directory / 'windows-installer-smoke.json'
            report = json.loads(path.read_text())
            worker = next(item for item in report['installed_payloads'] if item['name'] == 'home_tunnel_remote_host.exe')
            worker['sha256'] = hashlib.sha256(b'other installer worker').hexdigest()
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(SystemExit, 'installer payload differs'):
                module.verify_windows_evidence(directory, '6.0.1', 'revision')

    def test_prepared_build_can_never_be_published_as_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = {'repository': module.REPO, 'revision': module.SHA, 'version': module.local_version(),
                        'component': module.COMPONENT, 'rc_tag': module.TAG, 'verification_stage': 'prepared'}
            path = directory / 'release-manifest.json'
            path.write_text(json.dumps(manifest))
            (directory / 'SHA256SUMS.txt').write_text(hashlib.sha256(path.read_bytes()).hexdigest() + '  release-manifest.json\n')
            with patch.object(module, 'run'), self.assertRaisesRegex(SystemExit, 'verification_stage'):
                module.verify(directory, module.TAG)

    def test_native_report_cannot_select_another_build_or_workflow(self):
        source = {'head_sha': module.SHA, 'event': 'push', 'conclusion': 'success',
                  'path': '.github/workflows/release.yml', 'repository': {'full_name': module.REPO}}
        for key, value in (('head_sha', 'other'), ('event', 'pull_request'), ('conclusion', 'failure'), ('path', 'other.yml')):
            with self.subTest(key=key), patch.dict(os.environ, {'NATIVE_BUILD_RUN_ID': '123', 'NATIVE_ACCEPTANCE_JSON': '{}'}), \
                    patch.object(module, 'api', return_value={**source, key: value}), \
                    self.assertRaisesRegex(SystemExit, 'exact tag commit'):
                module.import_native_acceptance()

    def test_failed_partial_stale_and_wrong_revision_scans_block_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for kind in ("failed", "partial", "stale", "wrong revision"):
                with self.subTest(kind=kind):
                    scan = self.windows_fixture(directory)
                    if kind == "failed": scan['files'][0]['exit_code'] = 2
                    if kind == "partial": scan['files'].pop()
                    if kind == "stale": scan['scanned_at'] = (datetime.now(timezone.utc)-timedelta(days=3)).isoformat()
                    if kind == "wrong revision": scan['repository_revision'] = 'another-build'
                    (directory/'windows-defender-scan.json').write_text(json.dumps(scan))
                    with self.assertRaises(SystemExit): module.verify_windows_evidence(directory, "6.0.1", "revision")

    def test_first_project_version_is_allowed_as_a_test_build(self):
        self.assertEqual(module.validate_release_tag("v0.1.0-rc.1", "0.1.0-rc.1", "internal-testing"), ("0.1.0", "1"))

    def test_candidate_identity_cannot_change_between_source_and_tag(self):
        for tag, source in (("v8.0.0-rc.2", "8.0.0-rc.1"), ("v8.0.0", "8.0.0-rc.1"), ("v8.0.0-rc.1", "8.0.0")):
            with self.subTest(tag=tag, source=source), self.assertRaisesRegex(SystemExit, "source version"):
                module.validate_release_tag(tag, source, "internal-testing")

    def test_candidate_number_is_positive_and_canonical(self):
        for candidate in ('0', '01'):
            with self.assertRaises(SystemExit):
                module.validate_release_tag('v8.0.0-rc.' + candidate, '8.0.0-rc.' + candidate, 'internal-testing')

    def test_internal_testing_cannot_publish_a_stable_tag(self):
        with self.assertRaisesRegex(SystemExit, "prereleases only"):
            module.validate_release_tag("v0.1.0", "0.1.0", "internal-testing")

    def test_source_version_must_match(self):
        with self.assertRaisesRegex(SystemExit, "source version"):
            module.validate_release_tag("v0.2.0-rc.1", "0.1.0", "internal-testing")

    def test_public_release_requires_an_explicit_stage(self):
        self.assertEqual(module.validate_release_tag("v1.0.0", "1.0.0", "public-release"), ("1.0.0", None))
        with self.assertRaisesRegex(SystemExit, "Unknown release stage"):
            module.validate_release_tag("v1.0.0", "1.0.0", "publc-release")

    def test_public_asset_list_keeps_only_installable_deliverables(self):
        self.assertEqual(module.public_asset_names("android", "6.0.0"), ["HomeTunnel-Android-6.0.0-arm64-v8a.apk"])
        client = module.public_asset_names("client", "6.0.0")
        self.assertEqual(len(client), 6)
        self.assertTrue(all(name.endswith((".exe", ".zip", ".tar.gz")) for name in client))
        self.assertEqual(module.public_asset_names("server", "6.0.0"), ["home-tunnel-server-6.0.0.tar.gz", "compose.release.yaml"])

if __name__ == "__main__":
    unittest.main()
