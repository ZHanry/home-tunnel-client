"""构建隔离的 Windows 隧道助手，复用锁定上游源码与官方 Agent。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--package', required=True)
parser.add_argument('--go', required=True)
parser.add_argument('--executable', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
lock = json.loads((root / 'build/tunnel/runtime.lock.json').read_text())
source = Path(args.source).resolve()
package = Path(args.package).resolve()
go = Path(args.go).resolve()
if source.name != 'home-tunnel-client-' + lock['source_revision']:
    raise SystemExit('源码版本不匹配')
if hashlib.sha256(package.read_bytes()).hexdigest() != lock['windows_package_sha256']:
    raise SystemExit('发行包摘要不匹配')
if not args.executable.endswith('.exe') or any(c in args.executable for c in '/\\:'):
    raise SystemExit('程序名称无效')
target = root / 'client/target/tunnel-runtime'
target.mkdir(exist_ok=True)
with zipfile.ZipFile(package) as archive:
    for name in ['home-tunnel-agent.exe', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt']:
        (target / name).write_bytes(archive.read(name))
if hashlib.sha256((target / 'home-tunnel-agent.exe').read_bytes()).hexdigest() != lock['agent_sha256']:
    raise SystemExit('Agent 摘要不匹配')
helper_source = source / 'cmd/homedesk-tunnel-helper'
helper_source.mkdir(exist_ok=True)
for helper_file in (root / 'build/tunnel/helper').glob('*.go'):
    shutil.copy2(helper_file, helper_source / helper_file.name)
environment = os.environ.copy()
environment.update({'GOTOOLCHAIN':'local', 'CGO_ENABLED':'0', 'GOOS':'windows', 'GOARCH':'amd64'})
version = subprocess.check_output([str(go), 'version'], text=True, env=environment)
if lock['go_version'] not in version:
    raise SystemExit('Go 工具链版本不匹配')
output = target / 'homedesk-tunnel-helper.exe'
flags = '-s -w -X main.parentExecutable=' + args.executable + ' -X main.expectedAgentSHA256=' + lock['agent_sha256']
subprocess.run([str(go), 'test', '-mod=readonly', './cmd/homedesk-tunnel-helper'], cwd=source, env=environment, check=True)
subprocess.run([str(go), 'build', '-mod=readonly', '-trimpath', '-ldflags', flags,
                '-o', str(output), './cmd/homedesk-tunnel-helper'], cwd=source, env=environment, check=True)
manifest = {**lock, 'parent_executable':args.executable,
            'helper_sha256':hashlib.sha256(output.read_bytes()).hexdigest()}
(target / 'runtime.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps({'runtime_built':True, 'directory':str(target), 'helper_sha256':manifest['helper_sha256']}))
