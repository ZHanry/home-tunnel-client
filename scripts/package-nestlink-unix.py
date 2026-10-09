"""Stage native GUI installers with the current managed tunnel runtime."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'build'), str(ROOT/'client')]
from brand_config import load_config
from homedesk_package import stage_linux_package

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--target', required=True, choices=['linux-x64','linux-arm64'])
args = parser.parse_args()
version = json.loads((ROOT/'compatibility.json').read_text())['version']
revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
changed=subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip()
if changed:
    raise SystemExit('Package only an exact clean source commit:\n'+changed)
spec = importlib.util.spec_from_file_location('runtime',ROOT/'build/tunnel/build-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
products = ROOT/'products'
products.mkdir(exist_ok=True)
stage = ROOT/'outputs'/args.target
stage.mkdir(parents=True, exist_ok=True)
config = load_config(ROOT/'build/config.toml.example')
arch = 'arm64' if args.target.endswith('arm64') else 'x64'
bundle = ROOT/f'client/flutter/build/linux/{arch}/release/bundle'
runtime.build_runtime(args.target,'homedesk',bundle/'tunnel-runtime')
deb = stage/'deb'
stage_linux_package(ROOT/'client/res',deb,config.brand,bundle)
version_deb = version.replace('-RC','~rc').replace('-rc.','~rc')
deb_arch = 'arm64' if arch == 'arm64' else 'amd64'
(deb/'DEBIAN/control').write_text(f'''Package: homedesk
Version: {version_deb}
Architecture: {deb_arch}
Maintainer: nestlink <https://github.com/ZHanry/home-tunnel-client>
Section: net
Priority: optional
Depends: libgtk-3-0, libasound2t64 | libasound2, libxdo3, libxtst6, libxrandr2, libxi6, libxcb-shape0, libxcb-xfixes0, libva2, libva-drm2, libva-x11-2, libayatana-appindicator3-1, libsecret-tools, gnome-keyring
Description: nestlink self-hosted tunnels and encrypted P2P remote control
''',encoding='utf-8')
output = products/f'NestLink-Linux-{version}-{arch}.deb'
subprocess.run(['dpkg-deb','--root-owner-group','--build',str(deb),str(output)],check=True)
evidence = ROOT/'material-input'
evidence.mkdir(exist_ok=True)
(evidence/(args.target+'-build.json')).write_text(json.dumps({'version':version,'revision':revision,'target':args.target,
    'artifact':output.name,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
    'signing':'DEB; same homedesk upgrade identity'},indent=2)+'\n',encoding='utf-8')
print(output)
