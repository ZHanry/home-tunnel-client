"""Stage the real Flutter/native runtime and produce the small Windows installer."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--iscc', required=True)
args = parser.parse_args()
version = json.loads((ROOT / 'compatibility.json').read_text())['version']
runtime = ROOT / 'client/target/tunnel-runtime'
manifest = json.loads((runtime / 'runtime.json').read_text())
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
if manifest['helper_source_revision'] != revision or manifest['helper_source_tree_dirty']:
    raise SystemExit('Rebuild the helper from the exact clean release commit')
payload = ROOT / 'outputs/windows-payload'
if payload.exists():
    raise SystemExit('Use a fresh staging directory')
shutil.copytree(ROOT / 'client/flutter/build/windows/x64/runner/Release', payload)
# HOMEDESK: Flutter/plugins use the Microsoft runtime on clean Windows machines.
installer = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
location = subprocess.check_output([str(installer), '-latest', '-products', '*', '-property', 'installationPath'], text=True).strip()
redist = sorted((Path(location)/'VC/Redist/MSVC').glob('*/x64/Microsoft.VC143.CRT'))
if not redist:
    raise SystemExit('Missing licensed Microsoft Visual C++ redistributable runtime')
for library in redist[-1].glob('*.dll'):
    shutil.copy2(library, payload/library.name)
(payload/'VCRUNTIME-NOTICES.txt').write_text('Microsoft Visual C++ Runtime redistributables from the installed Visual Studio 2022 toolchain. Copyright Microsoft Corporation. Redistributed with this C++ application under the Visual Studio license. https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files\n')
for name in ('home-tunnel-agent.exe', 'homedesk-tunnel-helper.exe', 'runtime.json', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt'):
    (payload / 'tunnel-runtime').mkdir(exist_ok=True)
    shutil.copy2(runtime / name, payload / 'tunnel-runtime' / name)
for name in ('LICENSE', 'LICENSE-RUSTDESK', 'README.md'):
    shutil.copy2(ROOT / name, payload / name)
shutil.copy2(ROOT / 'client/res/icon.ico', payload / 'HomeDesk.ico')
shutil.copy2(ROOT / 'packaging/windows/independent-tunnel.ps1', payload)
shutil.copy2(runtime / 'home-tunnel-agent.exe', payload / 'home-tunnel-agent.exe')
agent_sha = manifest['agent_sha256']
subprocess.run(['go', 'build', '-mod=readonly', '-trimpath', '-ldflags',
    '-s -w -X main.expectedAgentSHA256=' + agent_sha,
    '-o', str(payload / 'home-tunnel-client.exe'), './cmd/home-tunnel-client'], cwd=ROOT, check=True)
products = ROOT / 'products'
products.mkdir(exist_ok=True)
subprocess.run([args.iscc, '/DAppVersion=' + version, '/DSourceDir=' + str(payload),
    '/DOutputDir=' + str(products), str(ROOT / 'packaging/windows/HomeDesk.iss')], check=True)
evidence = ROOT / 'material-input'
evidence.mkdir(exist_ok=True)
build = {'revision': revision, 'version': version, 'architecture': 'windows-x64',
         'engine_origin_version': '1.4.9', 'agent_version': version,
         'policy': 'require_direct', 'authenticode': 'unsigned',
         'payload_sha256': {p.relative_to(payload).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in payload.rglob('*') if p.is_file()}}
(evidence / 'windows-build.json').write_text(json.dumps(build, indent=2) + '\n')
shutil.copy2(runtime / 'runtime.json', evidence)
print(json.dumps({'installer': f'NestLink-Setup-{version}-x64.exe', 'revision': revision}))
