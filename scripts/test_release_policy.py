"""Release-stage regressions; these tests do not contact GitHub or publish artifacts."""
from pathlib import Path
import importlib.util
import runpy
import copy
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
    def frozen_contract_fixture(self):
        project = {"contract_ref": "api-v1.4.0", "contract_status": "frozen", "frozen_tag": "api-v1.4.0"}
        lock = {"repository": "ZHanry/home-tunnel-server", "contract_status": "frozen",
                "frozen_tag": "api-v1.4.0", "published_contract_ref": "api-v1.4.0",
                "source_revision": "a" * 40, "source_tree_dirty": False}
        return project, [dict(lock, ref="api-v1.4.0"), dict(lock)]

    def test_proposed_or_missing_freeze_cannot_enter_publication(self):
        project, locks = self.frozen_contract_fixture()
        self.assertEqual(module.validate_frozen_contract(project, locks), ("api-v1.4.0", "a" * 40))
        for key, value in (("contract_status", "proposed"), ("frozen_tag", None), ("contract_ref", "main")):
            with self.subTest(key=key), self.assertRaisesRegex(SystemExit, "frozen contract"):
                module.validate_frozen_contract(dict(project, **{key: value}), locks)
        for index in (0, 1):
            for key, value in (("contract_status", "proposed"), ("published_contract_ref", None),
                               ("frozen_tag", None), ("source_tree_dirty", True), ("source_revision", "main"),
                               ("repository", "somebody/other-server")):
                altered = copy.deepcopy(locks); altered[index][key] = value
                with self.subTest(index=index, key=key), self.assertRaises(SystemExit):
                    module.validate_frozen_contract(project, altered)
        locks[1]["source_revision"] = "b" * 40
        with self.assertRaisesRegex(SystemExit, "different server commits"):
            module.validate_frozen_contract(project, locks)

    def test_contract_tag_must_resolve_to_the_pinned_revision(self):
        project, locks = self.frozen_contract_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / "contracts").mkdir()
            for name, lock in zip(("lock.json", "remote.lock.json"), locks):
                (root / "contracts" / name).write_text(json.dumps(lock), encoding="utf-8")
            with patch.object(module, "ROOT", root), patch.object(module, "PROJECT", project):
                with patch.object(module, "api", return_value={"object": {"type": "commit", "sha": "a" * 40}}):
                    module.check_frozen_contract()
                with patch.object(module, "api", side_effect=[{"object": {"type": "tag", "sha": "b" * 40}},
                                                               {"object": {"type": "commit", "sha": "a" * 40}}]) as query:
                    module.check_frozen_contract()
                    self.assertEqual(query.call_args.args[0], "repos/ZHanry/home-tunnel-server/git/tags/" + "b" * 40)
                for response in ({"type": "commit", "sha": "b" * 40}, {"type": "tree", "sha": "a" * 40},
                                 {"type": "tag", "sha": "b" * 40}):
                    with self.subTest(response=response), patch.object(module, "api", return_value={"object": response}):
                        with self.assertRaisesRegex(SystemExit, "Frozen contract tag"):
                            module.check_frozen_contract()
                with patch.object(module, "PROJECT", dict(project, contract_status="proposed")), patch.object(module, "api") as query:
                    with self.assertRaisesRegex(SystemExit, "candidate-only"):
                        module.check_frozen_contract()
                    query.assert_not_called()


    def test_contract_snapshot_accepts_candidates_but_never_moving_or_ambiguous_refs(self):
        validator = runpy.run_path(str(Path(__file__).with_name("check-repository.py")))["valid_contract_ref"]
        for ref in ("api-v0.0.0", "api-v1.1.0", "api-v1.2.0-rc.1", "api-v10.20.30-rc.123"):
            with self.subTest(ref=ref):
                self.assertTrue(validator(ref))
        for ref in (None, 12, "main", "refs/tags/api-v1.2.0", "v1.2.0", "api-v01.2.0",
                    "api-v1.02.0", "api-v1.2.00", "api-v1.2.0-rc.0", "api-v1.2.0-rc.01",
                    "api-v1.2.0-rc.-1", "api-v1.2.0-beta.1", "api-v1.2.0+build",
                    "api-v1.2.0-rc.1/other", "api-v1.2.0\n", "api-v\u0661.2.0", "api-v1.2.0-rc.\u0661"):
            with self.subTest(ref=ref):
                self.assertFalse(validator(ref))

    def windows_fixture(self, directory):
        version = "6.0.1"
        setup = "HomeTunnel-Setup-6.0.1-x64.exe"
        archive = "HomeTunnel-Windows-6.0.1-x64.zip"
        payload = {"home-tunnel-gui.exe": b"gui", "home-tunnel-agent.exe": b"agent", "home-tunnel-service.exe": b"service", "home_tunnel_remote_host.exe": b"native worker fixture",
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
                  'native_process_confinement', 'os_foreground_verified', 'released', 'stale_epoch_rejected')},
                  'heartbeat_watchdog': {'passed': True, 'release_ms': 1750},
                  'worker_crash': {'passed': True, 'key_release_ms': 100, 'button_release_ms': 100}}, 'worker_sha256': digest,
                  'sources': {'client': {'commit': 'revision', 'modified': False}, 'server': {'commit': server['revision'], 'modified': False}},
                  'server_build': {'fresh': True, 'source_commit': server['revision'], 'command': 'pnpm run build',
                                   'dist': {'file_count': 1, 'sha256': hashlib.sha256(b'fixture build').hexdigest()}},
                  'checks': {key: True for key in ('isolated_real_server', 'native_backend_ready', 'real_browser_identity', 'signed_pairing_and_code_match',
                             'session_approval_verified', 'one_time_grant_auto_approval', 'real_continuing_video',
                             'selected_udp_and_dtls', 'clean_session_shutdown')},
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

    def waived_native_report(self, directory, provenance, **changes):
        waiver = {'approved_by': 'owner', 'approved_at': '2026-09-29T00:40:00Z',
                  'reason': 'Owner shipped 10.0.0 without the native VM acceptance run.', 'disclosed_in': 'docs/RELEASE_NOTES.md'}
        report = {'status': 'waived', 'worker_sha256': provenance['worker']['sha256'], 'waiver': waiver}
        for key, value in changes.items():
            if value is None:
                waiver.pop(key, None); report.pop(key, None)
            elif key in waiver:
                waiver[key] = value
            else:
                report[key] = value
        (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
        return report

    def test_waived_native_acceptance_requires_valid_owner_waiver_and_final_worker(self):
        future = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            provenance, _ = self.remote_fixture(directory)
            self.waived_native_report(directory, provenance)
            module.verify_remote_evidence(directory, '6.0.1', 'revision')
            for changes in ({'worker_sha256': 'f' * 64}, {'worker_sha256': None}, {'approved_by': 'maintainer'},
                            {'approved_at': future}, {'reason': ''}, {'disclosed_in': None}, {'waiver': None}):
                with self.subTest(changes=changes):
                    self.waived_native_report(directory, provenance, **changes)
                    with self.assertRaises(SystemExit):
                        module.verify_remote_evidence(directory, '6.0.1', 'revision')
            # A waiver still cannot bless a rebuilt or re-signed worker.
            self.waived_native_report(directory, provenance)
            with zipfile.ZipFile(directory / 'HomeTunnel-Windows-6.0.1-x64.zip', 'w') as bundle:
                bundle.writestr('home_tunnel_remote_host.exe', b'rebuilt or newly signed bytes')
            with self.assertRaisesRegex(SystemExit, 'Packaged native worker'):
                module.verify_remote_evidence(directory, '6.0.1', 'revision')

    def test_other_native_statuses_keep_the_strict_acceptance_checks(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            _, report = self.remote_fixture(directory)
            for status in ('skipped', 'failed', 'accepted_with_waivers', None):
                altered = dict(report, status=status)
                (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(altered))
                with self.subTest(status=status), self.assertRaisesRegex(SystemExit, 'must both pass'):
                    module.verify_remote_evidence(directory, '6.0.1', 'revision')

    def test_stable_notes_disclose_every_owner_waiver(self):
        import client_release_candidate as policy
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assertEqual(module.waiver_notes(directory), '')
            waiver = {'approved_by': 'owner', 'approved_at': '2026-09-29T00:40:00Z', 'disclosed_in': 'docs/RELEASE_NOTES.md'}
            coverage = {gate: {'status': 'passed', 'evidence': f'client-acceptance-{gate}.json'} for gate in policy.GATES}
            for gate in ('stability', 'desktop_service'):
                coverage[gate]['status'] = 'waived'
                cases = {name: 'waived' for name in policy.GATES[gate]}
                if gate == 'desktop_service':
                    cases['boot_without_login'] = 'passed'
                (directory / f'client-acceptance-{gate}.json').write_text(json.dumps(
                    {'gate': gate, 'status': 'waived', 'cases': cases, 'waiver': dict(waiver, reason=f'{gate} removed.')}))
            (directory / policy.ACCEPTANCE).write_text(json.dumps({'status': 'accepted_with_waivers', 'coverage': coverage}))
            (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(
                {'status': 'waived', 'waiver': dict(waiver, reason='Native VM run not performed.')}))
            notes = module.waiver_notes(directory)
            self.assertIn('## Not verified (owner waivers)', notes)
            self.assertIn('- `stability`: stability removed. Waived cases: `thirty_connections`', notes)
            self.assertIn('`lock_screen`', notes)
            self.assertNotIn('`boot_without_login`', notes)
            self.assertIn('Native VM run not performed.', notes)
            self.assertNotIn('udp_network', notes)
            (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps({'status': 'passed'}))
            coverage = {gate: dict(item, status='passed') for gate, item in coverage.items()}
            (directory / policy.ACCEPTANCE).write_text(json.dumps({'status': 'passed', 'coverage': coverage}))
            self.assertEqual(module.waiver_notes(directory), '')

    def sdk_fixture(self, directory):
        provenance, _ = self.remote_fixture(directory)
        spec = importlib.util.spec_from_file_location('sdk_notice_policy', module.ROOT / 'scripts/build-remote-android-webrtc.py')
        policy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(policy)
        sources = {entry: f'https://chromium.googlesource.com/chromium/{entry}@{mirror}'
                   for entry, (mirror, _) in policy.CHROMIUM_MIRRORS.items()}
        (directory / 'remote-source-manifest.json').write_text(json.dumps({'dependency_sources': sources}))
        root = module.ROOT / 'native/remote'
        lock = json.loads((root / 'remote-deps.lock.json').read_text())
        payloads = {'lib/webrtc.lib': b'real library is built separately, this is only a policy fixture',
                    'include/webrtc/api/peer_connection_interface.h': b'header fixture',
                    'native/include/home_tunnel/remote.h': (root / 'include/home_tunnel/remote.h').read_bytes(),
                    'remote-deps.lock.json': (root / 'remote-deps.lock.json').read_bytes(),
                    'remote-source-manifest.json': (directory / 'remote-source-manifest.json').read_bytes(),
                    'WEBRTC-THIRD-PARTY-NOTICES.md': b'fixture notices',
                    'source-license-inventory.json': json.dumps(policy.chromium_license_record(sources)).encode(),
                    policy.CHROMIUM_LICENSE_PATH: policy.chromium_license_bytes()}
        for item in lock['patches']: payloads[item['path']] = (root / item['path']).read_bytes()
        name = 'HomeTunnel-Remote-SDK-6.0.1-windows-x64.zip'
        (directory / 'WEBRTC-THIRD-PARTY-NOTICES.md').write_bytes(payloads['WEBRTC-THIRD-PARTY-NOTICES.md'])
        self.write_sdk(directory / name, payloads)
        evidence = {'schema_version': 1, 'version': '6.0.1', 'repository_revision': 'revision',
                    'source_modified': False, 'target_os': 'win', 'target_cpu': 'x64', 'abi_version': 1,
                    'engine': provenance['engine'],
                    'archive': {'name': name, 'sha256': hashlib.sha256((directory / name).read_bytes()).hexdigest()},
                    'library': {'name': 'lib/webrtc.lib', 'sha256': hashlib.sha256(payloads['lib/webrtc.lib']).hexdigest(),
                                'bytes': len(payloads['lib/webrtc.lib'])},
                    'source_manifest_sha256': hashlib.sha256(payloads['remote-source-manifest.json']).hexdigest(), 'notices_sha256': provenance['notices_sha256']}
        (directory / 'remote-sdk-provenance.json').write_text(json.dumps(evidence))
        return payloads, evidence

    def write_sdk(self, path, payloads):
        with zipfile.ZipFile(path, 'w') as bundle:
            for name, data in payloads.items(): bundle.writestr(name, data)

    def test_native_sdk_requires_exact_library_patches_abi_and_source_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.sdk_fixture(directory)
            module.verify_remote_sdk(directory, '6.0.1', 'revision')
            patch_path = json.loads((module.ROOT / 'native/remote/remote-deps.lock.json').read_text())['patches'][0]['path']
            for field in ('lib/webrtc.lib', 'native/include/home_tunnel/remote.h', 'remote-deps.lock.json',
                          'remote-source-manifest.json', 'WEBRTC-THIRD-PARTY-NOTICES.md',
                          'source-licenses/chromium/LICENSE', patch_path):
                with self.subTest(field=field):
                    payloads, evidence = self.sdk_fixture(directory)
                    payloads[field] += b'changed'
                    archive = directory / evidence['archive']['name']
                    self.write_sdk(archive, payloads)
                    # Even an archive re-sealed after tampering must fail its inner source/library checks.
                    evidence['archive']['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
                    (directory / 'remote-sdk-provenance.json').write_text(json.dumps(evidence))
                    with self.assertRaises(SystemExit): module.verify_remote_sdk(directory, '6.0.1', 'revision')
            payloads, evidence = self.sdk_fixture(directory)
            inventory = json.loads(payloads['source-license-inventory.json'])
            inventory['src/testing']['source'] += '-changed'
            payloads['source-license-inventory.json'] = json.dumps(inventory).encode()
            archive = directory / evidence['archive']['name']
            self.write_sdk(archive, payloads)
            evidence['archive']['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
            (directory / 'remote-sdk-provenance.json').write_text(json.dumps(evidence))
            with self.assertRaisesRegex(SystemExit, 'original root license'):
                module.verify_remote_sdk(directory, '6.0.1', 'revision')
            payloads, evidence = self.sdk_fixture(directory)
            payloads.pop('include/webrtc/api/peer_connection_interface.h')
            archive = directory / evidence['archive']['name']
            self.write_sdk(archive, payloads)
            evidence['archive']['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
            (directory / 'remote-sdk-provenance.json').write_text(json.dumps(evidence))
            with self.assertRaisesRegex(SystemExit, 'public headers'): module.verify_remote_sdk(directory, '6.0.1', 'revision')

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
            lambda p, r: r['checks'].update(session_approval_verified=False),
            lambda p, r: r['checks'].update(one_time_grant_auto_approval=False),
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

    def test_held_input_safety_requires_measured_deadlines_and_stale_epoch_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for field, metrics in (('heartbeat_watchdog', ('release_ms',)),
                                   ('worker_crash', ('key_release_ms', 'button_release_ms'))):
                for metric in metrics:
                    for invalid in (None, False, True, -1, 2001, '100', float('nan'), float('inf')):
                        with self.subTest(field=field, metric=metric, invalid=invalid):
                            _, report = self.remote_fixture(directory)
                            report['input'][field][metric] = invalid
                            (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
                            with self.assertRaisesRegex(SystemExit, 'two seconds'):
                                module.verify_remote_evidence(directory, '6.0.1', 'revision')
                _, report = self.remote_fixture(directory)
                del report['input'][field]
                (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
                with self.assertRaisesRegex(SystemExit, 'two seconds'):
                    module.verify_remote_evidence(directory, '6.0.1', 'revision')
            _, report = self.remote_fixture(directory)
            report['input']['stale_epoch_rejected'] = False
            (directory / 'windows-remote-native-acceptance.json').write_text(json.dumps(report))
            with self.assertRaisesRegex(SystemExit, 'confined keyboard'):
                module.verify_remote_evidence(directory, '6.0.1', 'revision')

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

    def test_service_binary_requires_successful_scan_and_identical_installed_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for failure in ('missing scan', 'failed scan', 'changed scan', 'duplicate scan', 'missing installed', 'changed installed', 'missing archive'):
                with self.subTest(failure=failure):
                    scan = self.windows_fixture(directory)
                    service = next(item for item in scan['files'] if item['name'] == 'home-tunnel-service.exe')
                    install_path = directory / 'windows-installer-smoke.json'
                    install = json.loads(install_path.read_text())
                    if failure == 'missing scan': scan['files'].remove(service)
                    if failure == 'failed scan': service['exit_code'] = 2
                    if failure == 'changed scan': service['sha256'] = hashlib.sha256(b'other service').hexdigest()
                    if failure == 'duplicate scan': scan['files'].append(dict(service))
                    if failure == 'missing installed': install['installed_payloads'] = [item for item in install['installed_payloads'] if item['name'] != 'home-tunnel-service.exe']
                    if failure == 'changed installed':
                        next(item for item in install['installed_payloads'] if item['name'] == 'home-tunnel-service.exe')['sha256'] = hashlib.sha256(b'other service').hexdigest()
                    if failure == 'missing archive':
                        archive = directory / 'HomeTunnel-Windows-6.0.1-x64.zip'
                        with zipfile.ZipFile(archive) as bundle:
                            payloads = {name: bundle.read(name) for name in bundle.namelist() if name != 'home-tunnel-service.exe'}
                        with zipfile.ZipFile(archive, 'w') as bundle:
                            for name, data in payloads.items(): bundle.writestr(name, data)
                        next(item for item in scan['files'] if item['name'] == archive.name)['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
                    install_path.write_text(json.dumps(install))
                    (directory / 'windows-defender-scan.json').write_text(json.dumps(scan))
                    with self.assertRaises(SystemExit): module.verify_windows_evidence(directory, '6.0.1', 'revision')

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

    def test_inline_acceptance_cannot_bypass_reviewed_receipts(self):
        with patch.object(module, 'api') as query, self.assertRaisesRegex(SystemExit, 'Inline acceptance was removed'):
            module.import_native_acceptance()
        query.assert_not_called()

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

    def test_long_soak_preserves_build_scan_and_requires_a_fresh_separate_rescan(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            scan = self.windows_fixture(directory)
            built = datetime.now(timezone.utc) - timedelta(days=3)
            scan['scanned_at'] = built.isoformat()
            scan['signature_updated_at'] = built.isoformat()
            original = json.dumps(scan).encode()
            (directory / 'windows-defender-scan.json').write_bytes(original)
            module.verify_windows_evidence(directory, '6.0.1', 'revision', validation_time=built)
            with self.assertRaisesRegex(SystemExit, 'stale'):
                module.verify_windows_evidence(directory, '6.0.1', 'revision')
            write_scan = dict(scan, scanned_at=datetime.now(timezone.utc).isoformat(),
                              signature_updated_at=datetime.now(timezone.utc).isoformat())
            (directory / 'windows-final-defender-scan.json').write_text(json.dumps(write_scan))
            module.verify_windows_evidence(directory, '6.0.1', 'revision', scan_name='windows-final-defender-scan.json')
            self.assertEqual((directory / 'windows-defender-scan.json').read_bytes(), original)
            (directory / 'HomeTunnel-Setup-6.0.1-x64.exe').write_bytes(b'changed after soak')
            with self.assertRaisesRegex(SystemExit, 'differ from the scanned'):
                module.verify_windows_evidence(directory, '6.0.1', 'revision', scan_name='windows-final-defender-scan.json')

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

    def test_client_candidate_seals_both_android_controller_sdks(self):
        assets = module.android_controller_sdk_assets("9.0.0")
        self.assertEqual(assets[:4], [
            "HomeTunnel-Remote-SDK-9.0.0-android-arm64.zip",
            "HomeTunnel-Remote-SDK-9.0.0-android-arm64.zip.sha256",
            "android-sdk-provenance.json",
            "android-sdk.spdx.json",
        ])
        self.assertIn("HomeTunnel-Remote-SDK-9.0.0-android-x86_64.zip", assets)
        self.assertIn("android-sdk-x86_64-provenance.json.sigstore.json", assets)
        self.assertEqual(len(assets), 16)
        self.assertNotIn("HomeTunnel-Remote-SDK-9.0.0-android-x86_64.zip", module.public_asset_names("client", "9.0.0"))

if __name__ == "__main__":
    unittest.main()
