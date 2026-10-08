"""Build the managed helper from this repository; preserve the locked Agent bytes/provenance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--package', required=True, type=Path)
parser.add_argument('--go', default=shutil.which('go'))
parser.add_argument('--executable', default='homedesk.exe')
args = parser.parse_args()
lock = json.loads((root / 'build/tunnel/runtime.lock.json').read_text())
package = args.package.resolve()
if hashlib.sha256(package.read_bytes()).hexdigest() != lock['windows_package_sha256']:
    raise SystemExit('Locked Agent package checksum mismatch')
if not args.go or not args.executable.endswith('.exe') or any(c in args.executable for c in '/\\:'):
    raise SystemExit('Invalid compiler or parent executable')
target = root / 'client/target/tunnel-runtime'
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(package) as archive:
    for name in ['home-tunnel-agent.exe', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt']:
        (target / name).write_bytes(archive.read(name))
if hashlib.sha256((target / 'home-tunnel-agent.exe').read_bytes()).hexdigest() != lock['agent_sha256']:
    raise SystemExit('Locked Agent checksum mismatch')
environment = os.environ.copy()
environment.update({'GOTOOLCHAIN': 'local', 'CGO_ENABLED': '0', 'GOOS': 'windows', 'GOARCH': 'amd64'})
version = subprocess.check_output([args.go, 'version'], text=True, env=environment).strip()
if not version.startswith('go version go1.27.0 '):
    raise SystemExit('Helper builds require Go 1.27.0 (Agent retains its original Go provenance)')
output = target / 'homedesk-tunnel-helper.exe'
flags = '-s -w -X main.parentExecutable=' + args.executable + ' -X main.expectedAgentSHA256=' + lock['agent_sha256']
subprocess.run([args.go, 'test', '-mod=readonly', './cmd/homedesk-tunnel-helper'], cwd=root, env=environment, check=True)
subprocess.run([args.go, 'build', '-mod=readonly', '-trimpath', '-ldflags', flags,
                '-o', str(output), './cmd/homedesk-tunnel-helper'], cwd=root, env=environment, check=True)
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip())
manifest = {**lock, 'parent_executable': args.executable,
    'helper_source_revision': revision, 'helper_source_tree_dirty': dirty,
    'helper_go_version': version, 'helper_sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
(target / 'runtime.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'runtime_built': True, 'directory': str(target), 'helper_sha256': manifest['helper_sha256']}))
