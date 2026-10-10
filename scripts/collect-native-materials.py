"""Keep locked Rust dependencies, native library source and plugin notices beside release evidence."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
destination = ROOT / 'material-input/dependencies'
destination.mkdir(parents=True, exist_ok=True)
vendor = destination / 'rust-vendor'
configuration = subprocess.check_output(['cargo', 'vendor', '--locked', '--versioned-dirs', str(vendor)], cwd=ROOT / 'client', text=True)
(destination / 'cargo-vendor-config.toml').write_text(configuration.replace(str(vendor), '../dependencies/rust-vendor'), encoding='utf8')
# Record the actual selected build graph; the all-platform lockfile can also
# contain Linux-only packages and inherited entries outside the shipped targets.
target = os.environ.get('TARGET')
if not target:
    target = next(line.split(': ', 1)[1] for line in
                  subprocess.check_output(['rustc', '-vV'], text=True).splitlines()
                  if line.startswith('host: '))
features = os.environ.get('FEATURES') or (
    'flutter,hwcodec,unix-file-copy-paste'
    if '-unknown-linux-' in target else 'flutter,hwcodec'
)
tree = subprocess.check_output(['cargo', 'tree', '--locked', '--target', target,
                                '--features', features, '-e', 'normal,build'],
                               cwd=ROOT / 'client', text=True)
(destination / ('cargo-tree-' + target + '.txt')).write_text(tree, encoding='utf8')
# Preserve a machine-readable graph with the same selected target and features.
# Cargo's depth output omits presentation headings and keeps repeated edges.
graph_tree = subprocess.check_output(
    ['cargo', 'tree', '--locked', '--target', target, '--features', features,
     '-e', 'normal,build', '--prefix', 'depth', '--format', '{p}|{f}'],
    cwd=ROOT / 'client', text=True)
nodes, edges, stack = {}, set(), []
for line in graph_tree.splitlines():
    match = re.fullmatch(r'(\d+)(.+)\|(.*)', line)
    if not match:
        raise ValueError('Unexpected cargo graph line: ' + line)
    depth, package, selected = int(match[1]), match[2], match[3]
    selected = selected.removesuffix(' (*)')
    name, version = package.split(' v', 1)
    node = nodes.setdefault(package, {
        'id': package, 'name': name, 'version': version.split(' ', 1)[0],
        'features': [],
    })
    node['features'] = sorted(set(node['features']) | set(filter(None, selected.split(','))))
    stack = stack[:depth]
    if depth:
        if len(stack) != depth:
            raise ValueError('Unexpected cargo graph depth')
        edges.add((stack[-1], package))
    stack.append(package)
graph = {'target': target, 'features': features.split(','),
         'dependency_kinds': ['normal', 'build'],
         'nodes': [nodes[key] for key in sorted(nodes)],
         'edges': [{'from': parent, 'to': child} for parent, child in sorted(edges)]}
(destination / ('cargo-tree-' + target + '.json')).write_text(
    json.dumps(graph, indent=2) + '\n', encoding='utf8')
vcpkg = Path(os.environ['VCPKG_ROOT'])
for port in sorted((vcpkg / 'buildtrees').iterdir()):
    source = port / 'src'
    if source.is_dir():
        shutil.copytree(source, destination / 'native' / port.name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.git', '*.obj', '*.o', '*.pdb', 'CMakeFiles'))
for triplet in (vcpkg / 'installed').iterdir():
    if (triplet / 'share').is_dir():
        for copyright in (triplet / 'share').glob('*/copyright'):
            target = destination / 'notices' / triplet.name / copyright.parent.name
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(copyright, target / 'copyright')
packages = ROOT / 'client/flutter/.dart_tool/package_config.json'
if packages.is_file():
    data = json.loads(packages.read_text())
    for package in data['packages']:
        uri = urlparse(package['rootUri'])
        if uri.scheme == 'file':
            value = unquote(uri.path)
            if os.name == 'nt' and value.startswith('/'):
                value = value[1:]
            source = Path(value)
        else:
            source = (packages.parent / unquote(package['rootUri'])).resolve()
        if source.is_relative_to(ROOT):
            continue  # Exact repository/submodule bytes are in corresponding-source.zip.
        shutil.copytree(source, destination / 'dart-packages' / package['name'], dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.git', 'build', '.dart_tool'))
# The browser helper ships Pion and its locked Go graph as part of the desktop GUI.
go_vendor = destination / 'go-vendor'
subprocess.run(['go', 'mod', 'vendor', '-o', str(go_vendor)], cwd=ROOT, check=True)
(destination / 'go-modules.json').write_bytes(subprocess.check_output(['go', 'list', '-m', '-json', 'all'], cwd=ROOT))
(destination / 'README.txt').write_text('Corresponding repository source is in corresponding-source.zip. Rust dependencies are vendored with the lockfile; adjust the provided cargo directory path when extracting into a different layout. Native sources are the actual patched vcpkg inputs and their notices. dart-packages contains every resolved external Dart/Flutter package including its assets and license. Build tools/SDK versions and original download paths are pinned in the repository workflows.\n')
print(json.dumps({'materials': str(destination), 'rust_dependencies': 'locked vendor', 'native_sources': 'patched vcpkg build inputs'}))
