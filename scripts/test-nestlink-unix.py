"""Install, launch and remove actual Unix GUI packages, and exercise operating-system credentials."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **options):
    return subprocess.run(args, check=True, **options)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=['linux-x64','linux-arm64'])
    args=parser.parse_args()
    version=json.loads((ROOT/'compatibility.json').read_text())['version']
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    record={'target':args.target,'version':version,'revision':revision,'status':'passed'}
    with tempfile.TemporaryDirectory(prefix='nestlink-unix-install-') as scratch:
        directory=Path(scratch)
        arch='arm64' if args.target.endswith('arm64') else 'x64'
        package=ROOT/f'products/NestLink-Linux-{version}-{arch}.deb'
        run('sudo','dpkg','--install',str(package))
        executable=Path('/usr/share/homedesk/homedesk')
        run('dart','--packages='+str(ROOT/'client/flutter/.dart_tool/package_config.json'),str(ROOT/'tests/dart/unix_credentials_test.dart'))
        record['credentials']='real Secret Service protected record, cross-process consume, logout, corruption recovery'
        try:
            with (directory/'startup.log').open('w') as log:
                process=subprocess.Popen([str(executable)],stdout=log,stderr=subprocess.STDOUT,cwd=executable.parent)
                try:
                    time.sleep(10)
                    assert process.poll() is None, 'Installed native GUI exited during startup'
                    windows=subprocess.check_output(['xwininfo','-root','-tree'],text=True)
                    assert re.search(r'"nestlink"', windows), 'Installed GUI did not create its branded window'
                    record['startup']='installed native GUI remained running and created a window (Linux); no media assertion'
                finally:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
            failures=('Failed to load dynamic library','Unhandled exception','error while loading shared libraries')
            assert not any(text in (directory/'startup.log').read_text() for text in failures), 'Installed GUI startup failed'
        finally:
            run('sudo','dpkg','--purge','homedesk')
            assert not executable.exists(), 'DEB uninstall left its executable'
        record['package_sha256']=hashlib.sha256(package.read_bytes()).hexdigest()
        record['scope']='actual package installation, protected credential fixture, startup and removal; physical-device permissions and media are separately verified'
    output=ROOT/'material-input'/f'{args.target}-installer.json'
    output.write_text(json.dumps(record,indent=2)+'\n')
    print(output)

if __name__=='__main__':main()
