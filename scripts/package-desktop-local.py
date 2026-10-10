"""Package an explicitly local desktop build; record the source and runtime used."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--iscc', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--source-snapshot', type=Path, required=True)
args = parser.parse_args()
compatibility = json.loads((ROOT / 'compatibility.json').read_text())
version = compatibility['version']
if args.output.exists():
    raise SystemExit('Use a fresh output directory for each local package.')
snapshot = json.loads(args.source_snapshot.read_text())
for relative, digest in snapshot.items():
    if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != digest:
        raise SystemExit(f'The working source changed after staging: {relative}')
runtime = json.loads((args.runtime / 'runtime.json').read_text())
if (compatibility['target_combination']['client'] != version or
        runtime['version'] != compatibility['target_combination']['agent']):
    raise SystemExit('Runtime version does not match the approved desktop/Agent combination.')
for filename, field in [('home-tunnel-agent.exe', 'agent_sha256'),
                        ('homedesk-tunnel-helper.exe', 'helper_sha256'),
                        ('nestlink-browser-helper.exe', 'browser_helper_sha256')]:
    if hashlib.sha256((args.runtime / filename).read_bytes()).hexdigest() != runtime[field]:
        raise SystemExit(f'Runtime provenance/hash mismatch: {filename}')
if not (args.bundle / 'homedesk.exe').is_file() or not (args.bundle / 'librustdesk.dll').is_file():
    raise SystemExit('The real Flutter and native desktop bundle is required.')
payload = args.output / 'payload'
shutil.copytree(args.bundle, payload)
for item in payload.rglob('*.pdb'):
    item.unlink()
runtime_payload = payload / 'tunnel-runtime'
runtime_payload.mkdir()
for name in ('home-tunnel-agent.exe', 'homedesk-tunnel-helper.exe',
             'nestlink-browser-helper.exe', 'runtime.json', 'LICENSE.txt',
             'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt'):
    shutil.copy2(args.runtime / name, runtime_payload / name)
vswhere = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
visual_studio = subprocess.check_output([str(vswhere), '-latest', '-products', '*',
    '-property', 'installationPath'], text=True).strip()
redist = sorted((Path(visual_studio) / 'VC/Redist/MSVC').glob('*/x64/Microsoft.VC143.CRT'))
if not redist:
    raise SystemExit('Microsoft Visual C++ runtime is missing.')
for library in redist[-1].glob('*.dll'):
    shutil.copy2(library, payload / library.name)
for name in ('LICENSE', 'LICENSE-RUSTDESK'):
    shutil.copy2(ROOT / name, payload / name)
shutil.copy2(ROOT / 'client/res/icon.ico', payload / 'NestLink.ico')
(payload / 'README.md').write_text(f'# NestLink {version}\n\nLocal desktop development build. Purple grouped device workspace.\n'
    'Uses the frozen API v2 and the coordinated 14.0.0 tunnel/browser runtime. Local package output is not a GitHub release.\n'
    'Clean installation removes the previous configuration; sign in to your own service again.\n', encoding='utf-8')
(payload / 'VCRUNTIME-NOTICES.txt').write_text('Microsoft Visual C++ Runtime redistributables from the installed Visual Studio 2022 toolchain. Copyright Microsoft Corporation. Redistributed under the Visual Studio license.\n', encoding='utf-8')
subprocess.run([str(args.iscc), '/DAppVersion=' + version,
    '/DSourceDir=' + str(payload.resolve()), '/DOutputDir=' + str(args.output.resolve()),
    str(ROOT / 'packaging/windows/HomeDesk.iss')], check=True)
installer = args.output / f'NestLink-Setup-{version}-x64.exe'
receipt = dict(version=version, scope='local-desktop-development',
    source_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    source_tree_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
    source_snapshot_sha256=hashlib.sha256(args.source_snapshot.read_bytes()).hexdigest(),
    runtime_version=runtime['version'], runtime_source_revision=runtime['source_revision'],
    installer_sha256=hashlib.sha256(installer.read_bytes()).hexdigest(),
    payload_sha256={p.relative_to(payload).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in payload.rglob('*') if p.is_file()})
(args.output / 'local-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'installer': str(installer.resolve()), 'build_receipt': str((args.output / 'local-build.json').resolve())}))
