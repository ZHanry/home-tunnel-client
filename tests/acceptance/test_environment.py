# HOMEDESK: 只验证准备工具的范围和错误拒绝；不联系Docker或生成业务账号。
import io
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from environment import ROOT, RUNTIME, run_scope
from prepare import extract_regular, fetch
from cleanup import validate_resource
from preflight import validate_compose


class EnvironmentTests(unittest.TestCase):
    def test_native_powershell_utf8_bom(self):
        # PS5不能可靠解释无BOM的中文PS1；曾导致首行注释吞掉param。
        for name in ['permissions.ps1', 'download.ps1']:
            self.assertTrue((ROOT / name).read_bytes().startswith(b'\xef\xbb\xbf'))
    def test_scope_rejects_outside_and_bad_name(self):
        with self.assertRaises(ValueError):
            run_scope(ROOT.parent, require_manifest=False)
        with self.assertRaises(ValueError):
            run_scope(RUNTIME / 'production', require_manifest=False)
        path, _ = run_scope(RUNTIME / 'hd-portal-acceptance-test', require_manifest=False)
        self.assertEqual(path.parent, RUNTIME.resolve())

    def test_archive_escape_and_links(self):
        RUNTIME.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=RUNTIME) as directory:
            root = Path(directory)
            archive = root / 'bad.tar.gz'
            with tarfile.open(archive, 'w:gz') as bundle:
                member = tarfile.TarInfo('../outside')
                member.size = 1
                bundle.addfile(member, io.BytesIO(b'x'))
            with self.assertRaises(ValueError):
                extract_regular(archive, root / 'bad')
            self.assertFalse((root / 'outside').exists())
            good = root / 'good.tar.gz'
            with tarfile.open(good, 'w:gz') as bundle:
                member = tarfile.TarInfo('bin/readme')
                member.size = 1
                bundle.addfile(member, io.BytesIO(b'x'))
                link = tarfile.TarInfo('bin/link')
                link.type = tarfile.SYMTYPE
                link.linkname = '../../outside'
                bundle.addfile(link)
            skipped = extract_regular(good, root / 'good')
            self.assertEqual(skipped, ['bin/link'])
            self.assertFalse((root / 'good/bin/link').exists())

    def test_download_only_fixed_release(self):
        with self.assertRaises(ValueError):
            fetch({'url': 'file:///existing-private-file', 'sha256': '0' * 64}, ROOT / 'never-created')
        with self.assertRaises(ValueError):
            fetch({'url': 'https://github.com/ZHanry/home-tunnel-server/releases/latest', 'sha256': '0' * 64}, ROOT / 'never-created')

    def test_cleanup_requires_both_labels_and_exact_resource(self):
        project = 'hd-portal-acceptance-test'
        labels = {'com.docker.compose.project': project, 'io.homedesk.acceptance.scope': project}
        validate_resource('volume', {'Name': project + '_sqlite-data', 'Labels': labels}, project)
        with self.assertRaises(ValueError):
            validate_resource('volume', {'Name': 'production_db', 'Labels': labels}, project)
        with self.assertRaises(ValueError):
            validate_resource('volume', {'Name': project + '_sqlite-data', 'Labels': {'com.docker.compose.project': project}}, project)
        with self.assertRaises(ValueError):
            validate_resource('container', {'Name': '/production', 'Config': {'Labels': labels}}, project)

    def test_compose_rejects_public_ports_external_volumes_and_changed_images(self):
        project = 'hd-portal-acceptance-test'
        lock = json.loads((ROOT / 'lock.json').read_text(encoding='utf-8'))
        services = {}
        for name in ['control-center', 'traffic-gateway', 'frps', 'caddy', 'fixture-backend']:
            services[name] = {'image': lock['images']['control-center' if name == 'fixture-backend' else name],
                              'labels': {'io.homedesk.acceptance.scope': project}}
        value = {'name': project, 'services': services}
        validate_compose(value, project)
        services['caddy']['ports'] = [{'host_ip': '0.0.0.0', 'published': '18443', 'protocol': 'tcp'}]
        with self.assertRaises(ValueError):
            validate_compose(value, project)
        del services['caddy']['ports']
        value['volumes'] = {'sqlite-data': {'external': True, 'name': 'production_db'}}
        with self.assertRaises(ValueError):
            validate_compose(value, project)
        del value['volumes']
        services['control-center']['image'] = 'unreviewed:latest'
        with self.assertRaises(ValueError):
            validate_compose(value, project)


if __name__ == '__main__':
    unittest.main()
