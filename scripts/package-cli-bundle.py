"""Build the five-platform NestLink CLI/NAS bundle and Agent from the same source."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('runtime', ROOT/'build/tunnel/build-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
version = json.loads((ROOT/'compatibility.json').read_text())['version']
stage = ROOT/'outputs/cli'
stage.mkdir(parents=True, exist_ok=True)
products = ROOT/'products'
products.mkdir(exist_ok=True)
records = []
archive = products / f'NestLink-CLI-Agent-{version}.zip'

def write(bundle, name, data, executable=False):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = (0o100755 if executable else 0o100644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    bundle.writestr(info, data)

with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for target, (goos, arch) in runtime.TARGETS.items():
        suffix = '.exe' if goos == 'windows' else ''
        agent = stage / target / ('home-tunnel-agent'+suffix)
        record = runtime.build_agent(target, agent)
        env = {**os.environ, 'CGO_ENABLED':'0', 'GOOS':goos, 'GOARCH':arch, 'GOTOOLCHAIN':'local'}
        cli = agent.parent / ('home-tunnel-client'+suffix)
        flags = '-s -w -X main.expectedAgentSHA256='+record['agent_sha256']
        subprocess.run(['go', 'build', '-mod=readonly', '-trimpath', '-ldflags', flags,
                        '-o', str(cli), './cmd/home-tunnel-client'], cwd=ROOT, env=env, check=True)
        prefix = ('macos' if goos == 'darwin' else goos)+'-'+arch+'/'
        write(bundle, prefix+cli.name, cli.read_bytes(), True)
        write(bundle, prefix+agent.name, agent.read_bytes(), True)
        for path, name in [(ROOT/'LICENSE', 'LICENSE.txt'), (ROOT/'agent/FRP-LICENSE.txt','FRP-LICENSE.txt'),
                           (ROOT/'agent/THIRD-PARTY-NOTICES.txt','THIRD-PARTY-NOTICES.txt')]:
            write(bundle, prefix+name, path.read_bytes())
        if goos == 'windows':
            write(bundle, prefix+'independent-tunnel.ps1', (ROOT/'packaging/windows/independent-tunnel.ps1').read_bytes())
        records.append({**record, 'cli_sha256': hashlib.sha256(cli.read_bytes()).hexdigest()})
    for path in (ROOT/'packaging/nas').rglob('*'):
        if path.is_file(): write(bundle, 'packaging/nas/'+path.relative_to(ROOT/'packaging/nas').as_posix(), path.read_bytes())
    write(bundle, 'README.md', (ROOT/'docs/INDEPENDENT_TUNNEL.md').read_bytes())
    write(bundle, 'BUILD.json', (json.dumps({'version':version, 'platforms':records}, indent=2)+'\n').encode())
evidence = ROOT/'material-input'
evidence.mkdir(exist_ok=True)
(evidence/'cli-build.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
print(archive)
