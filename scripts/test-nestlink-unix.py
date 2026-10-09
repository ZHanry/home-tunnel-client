"""Install, launch and remove actual Unix GUI packages, and exercise operating-system credentials."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **options):
    return subprocess.run(args, check=True, **options)

def keychain_fixture(directory):
    original = (ROOT/'client/flutter/macos/Runner/MainFlutterWindow.swift').read_text()
    start = original.index('@available(macOS 10.15, *)')
    end = original.index('// Global state for relative mouse mode', start)
    code = 'import Foundation\nimport Security\nimport CryptoKit\n' + original[start:end]
    code += '''
let args = CommandLine.arguments
let entropy = Data(args[2].utf8)
let url = URL(fileURLWithPath: args[3])
let account = SHA256.hash(data: entropy).map { String(format: "%02x", $0) }.joined()
if args[1] == "protect" {
    let sealed = try NestLinkKeychain.crypt(Data("SyntheticFixtureNeverAuthenticates".utf8), entropy: entropy, encrypt: true)
    try sealed.write(to: url, options: .atomic)
} else {
    defer { SecItemDelete([kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"HomeDesk.Portal.Credentials", kSecAttrAccount as String:account] as CFDictionary) }
    let sealed = try Data(contentsOf: url)
    let opened = try NestLinkKeychain.crypt(sealed, entropy: entropy, encrypt: false)
    guard opened == Data("SyntheticFixtureNeverAuthenticates".utf8) else { fatalError("Cross-process Keychain restore failed") }
    var tampered = sealed; tampered[tampered.startIndex] ^= 1
    do { _ = try NestLinkKeychain.crypt(tampered, entropy: entropy, encrypt: false); fatalError("Tampered ciphertext accepted") } catch {}
    do { _ = try NestLinkKeychain.crypt(sealed, entropy: Data("WrongFixtureEntropy".utf8), encrypt: false); fatalError("Wrong entropy accepted") } catch {}
    print("Keychain AES-GCM, cross-process restore, ciphertext tampering and entropy binding passed")
}
'''
    source, binary = directory/'keychain.swift', directory/'keychain-fixture'
    source.write_text(code)
    run('swiftc', str(source), '-o', str(binary))
    token = 'NestLink-CI-' + directory.name
    run(str(binary), 'protect', token, str(directory/'sealed.bin'))
    run(str(binary), 'restore', token, str(directory/'sealed.bin'))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=['mac-x64','mac-arm64','linux-x64','linux-arm64'])
    args=parser.parse_args()
    version=json.loads((ROOT/'compatibility.json').read_text())['version']
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    record={'target':args.target,'version':version,'revision':revision,'status':'passed'}
    with tempfile.TemporaryDirectory(prefix='nestlink-unix-install-') as scratch:
        directory=Path(scratch)
        if args.target.startswith('mac'):
            package=ROOT/f'products/NestLink-macOS-{version}-{args.target.split("-")[1]}.dmg'
            mount=directory/'mount'; mount.mkdir()
            run('hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(package))
            app=directory/'installed/NestLink.app'
            try:
                shutil.copytree(mount/'NestLink.app', app)
            finally:
                run('hdiutil','detach',str(mount))
            info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
            assert info['CFBundleShortVersionString']=='12.0.0' and info['CFBundleVersion']=='1200.0.1'
            run('codesign','--verify','--deep','--strict',str(app))
            executable=app/'Contents/MacOS/NestLink'
            keychain_fixture(directory)
            record['credentials']='real Keychain AES-GCM with cross-process fixture'
        else:
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
                    if args.target.startswith('linux'):
                        windows=subprocess.check_output(['xwininfo','-root','-tree'],text=True)
                        assert re.search(r'"(?:NestLink|NestLink)',windows), 'Installed GUI did not create its branded window'
                    record['startup']='installed native GUI remained running and created a window (Linux); no media assertion'
                finally:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
            failures=('Failed to load dynamic library','Unhandled exception','error while loading shared libraries')
            assert not any(text in (directory/'startup.log').read_text() for text in failures), 'Installed GUI startup failed'
        finally:
            if args.target.startswith('linux'):
                run('sudo','dpkg','--purge','homedesk')
                assert not executable.exists(), 'DEB uninstall left its executable'
            else:
                shutil.rmtree(app)
                assert not app.exists(), 'App uninstall left its bundle'
        record['package_sha256']=hashlib.sha256(package.read_bytes()).hexdigest()
        record['scope']='actual package installation, protected credential fixture, startup and removal; physical-device permissions and media are separately verified'
    output=ROOT/'material-input'/f'{args.target}-installer.json'
    output.write_text(json.dumps(record,indent=2)+'\n')
    print(output)

if __name__=='__main__':main()
