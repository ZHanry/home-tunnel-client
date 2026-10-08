"""Keep locked Rust dependencies, native library source and plugin notices beside release evidence."""
from pathlib import Path
import json
import os
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
features = os.environ.get('FEATURES') or 'flutter,hwcodec'
tree = subprocess.check_output(['cargo', 'tree', '--locked', '--target', target,
                                '--features', features, '-e', 'normal,build'],
                               cwd=ROOT / 'client', text=True)
(destination / ('cargo-tree-' + target + '.txt')).write_text(tree, encoding='utf8')
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
(destination / 'README.txt').write_text('Corresponding repository source is in corresponding-source.zip. Rust dependencies are vendored with the lockfile; adjust the provided cargo directory path when extracting into a different layout. Native sources are the actual patched vcpkg inputs and their notices. dart-packages contains every resolved external Dart/Flutter package including its assets and license. Build tools/SDK versions and original download paths are pinned in the repository workflows.\n')
print(json.dumps({'materials': str(destination), 'rust_dependencies': 'locked vendor', 'native_sources': 'patched vcpkg build inputs'}))
