"""Build independent CLI executables, retaining checksum-pinned 10.1.0 Agent bytes."""
from pathlib import Path
import hashlib
import io
import json
import os
import subprocess
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
value = json.loads((ROOT / 'compatibility.json').read_text())['version']
lock = json.loads((ROOT / 'packaging/agent-packages.lock.json').read_text())
stage = ROOT / 'outputs/cli'
stage.mkdir(parents=True, exist_ok=True)
products = ROOT / 'products'
products.mkdir(exist_ok=True)
records = []
archive = products / f'HomeTunnel-CLI-Agent-{value}.zip'


def write(bundle, name, data, executable=False):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = (0o100755 if executable else 0o100644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    bundle.writestr(info, data)


with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for package in lock['packages']:
        platform, arch = package['platform'], package['arch']
        binary = 'home-tunnel-agent' + ('.exe' if platform == 'windows' else '')
        cached = ROOT / '.downloads' / package['filename']
        cached.parent.mkdir(exist_ok=True)
        if not cached.is_file():
            with urllib.request.urlopen(package['url'], timeout=120) as response:
                cached.write_bytes(response.read(128 * 1024 * 1024 + 1))
        if hashlib.sha256(cached.read_bytes()).hexdigest() != package['sha256']:
            raise SystemExit('Original Agent package checksum mismatch')
        if platform == 'windows':
            with zipfile.ZipFile(cached) as original:
                agent = original.read(binary)
                notices = {name: original.read(name) for name in ('LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')}
        else:
            with tarfile.open(cached) as original:
                members = {Path(m.name).name: m for m in original.getmembers() if m.isfile()}
                agent = original.extractfile(members[binary]).read()
                notices = {n: original.extractfile(m).read() for n, m in members.items() if 'LICENSE' in n or 'NOTICE' in n}
        agent_sha = hashlib.sha256(agent).hexdigest()
        env = {**os.environ, 'CGO_ENABLED': '0', 'GOOS': 'darwin' if platform == 'macos' else platform,
               'GOARCH': arch, 'GOTOOLCHAIN': 'local'}
        cli_name = 'home-tunnel-client' + ('.exe' if platform == 'windows' else '')
        output = stage / f'{platform}-{arch}-{cli_name}'
        subprocess.run(['go', 'build', '-mod=readonly', '-trimpath', '-ldflags',
            '-s -w -X main.agentVersion=10.1.0 -X main.expectedAgentSHA256=' + agent_sha,
            '-o', str(output), './cmd/home-tunnel-client'], cwd=ROOT, env=env, check=True)
        prefix = f'{platform}-{arch}/'
        write(bundle, prefix + cli_name, output.read_bytes(), True)
        write(bundle, prefix + binary, agent, True)
        for name, data in notices.items():
            write(bundle, prefix + name, data)
        if platform == 'windows':
            write(bundle, prefix + 'independent-tunnel.ps1', (ROOT / 'packaging/windows/independent-tunnel.ps1').read_bytes())
        record = {**package, 'agent_version': '10.1.0', 'agent_sha256': agent_sha,
                  'cli_version': value, 'cli_sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
        records.append(record)
    for path in (ROOT / 'packaging/nas').rglob('*'):
        if path.is_file():
            write(bundle, 'packaging/nas/' + path.relative_to(ROOT / 'packaging/nas').as_posix(), path.read_bytes())
    write(bundle, 'README.md', (ROOT / 'docs/INDEPENDENT_TUNNEL.md').read_bytes())
    write(bundle, 'BUILD.json', (json.dumps({'cli_version': value, 'agent_version': '10.1.0',
        'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'go': subprocess.check_output(['go', 'version'], text=True).strip(), 'platforms': records}, indent=2) + '\n').encode())
evidence = ROOT / 'material-input'
evidence.mkdir(exist_ok=True)
(evidence / 'cli-build.json').write_text(json.dumps(records, indent=2) + '\n')
print(str(archive))
