"""Build the Agent and managed helper from the current source for each native GUI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {'win-x64': ('windows', 'amd64'), 'mac-x64': ('darwin', 'amd64'),
           'mac-arm64': ('darwin', 'arm64'), 'linux-x64': ('linux', 'amd64'),
           'linux-arm64': ('linux', 'arm64')}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_identity():
    return {'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'source_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())}

def build_agent(target, output, go='go'):
    goos, goarch = TARGETS[target]
    env = {**os.environ, 'GOTOOLCHAIN': 'local', 'CGO_ENABLED': '0', 'GOOS': goos, 'GOARCH': goarch}
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([go, 'build', '-mod=readonly', '-trimpath', '-ldflags', '-s -w',
                    '-o', str(output), '.'], cwd=ROOT / 'agent', env=env, check=True)
    output.chmod(0o755)
    return {'version': json.loads((ROOT / 'compatibility.json').read_text())['version'],
            'target': target, **source_identity(), 'agent_sha256': digest(output),
            'agent_go_mod_sha256': digest(ROOT / 'agent/go.mod'), 'agent_go_sum_sha256': digest(ROOT / 'agent/go.sum'),
            'agent_go_version': subprocess.check_output([go, 'version'], env=env, text=True).strip(), 'frp_version': '0.70.1'}

def build_runtime(target, parent, output, go='go'):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    suffix = '.exe' if target == 'win-x64' else ''
    if Path(parent).name != parent or not parent or any(c in parent for c in '/\\:'):
        raise ValueError('Invalid parent executable')
    manifest = build_agent(target, output / ('home-tunnel-agent' + suffix), go)
    goos, goarch = TARGETS[target]
    env = {**os.environ, 'GOTOOLCHAIN': 'local', 'CGO_ENABLED': '0', 'GOOS': goos, 'GOARCH': goarch}
    helper = output / ('homedesk-tunnel-helper' + suffix)
    flags = '-s -w -X main.parentExecutable=' + parent + ' -X main.expectedAgentSHA256=' + manifest['agent_sha256']
    subprocess.run([go, 'build', '-mod=readonly', '-trimpath', '-ldflags', flags,
                    '-o', str(helper), './cmd/homedesk-tunnel-helper'], cwd=ROOT, env=env, check=True)
    helper.chmod(0o755)
    for src, name in [(ROOT/'LICENSE', 'LICENSE.txt'), (ROOT/'agent/FRP-LICENSE.txt', 'FRP-LICENSE.txt'),
                      (ROOT/'agent/THIRD-PARTY-NOTICES.txt', 'THIRD-PARTY-NOTICES.txt')]:
        shutil.copyfile(src, output / name)
    manifest.update({'parent_executable': parent, 'helper_sha256': digest(helper),
                     'helper_source_revision': manifest['source_revision'],
                     'helper_source_tree_dirty': manifest['source_tree_dirty'],
                     'helper_go_version': manifest['agent_go_version']})
    (output/'runtime.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    return manifest

if __name__ == '__main__':
    native = {'Windows': 'win', 'Darwin': 'mac', 'Linux': 'linux'}[platform.system()] + ('-arm64' if platform.machine().lower() in ('aarch64', 'arm64') else '-x64')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=TARGETS, default=native)
    parser.add_argument('--go', default=shutil.which('go'))
    parser.add_argument('--executable', default='homedesk.exe' if native == 'win-x64' else 'homedesk')
    parser.add_argument('--output', type=Path, default=ROOT/'client/target/tunnel-runtime')
    args = parser.parse_args()
    if not args.go: raise SystemExit('Go compiler is required')
    print(json.dumps(build_runtime(args.target, args.executable, args.output, args.go)))
