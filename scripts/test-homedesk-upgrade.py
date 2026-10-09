"""Run the real Inno upgrade preflight in isolated, unregistered Windows fixtures."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--iscc', required=True)
parser.add_argument('--evidence', type=Path)
args = parser.parse_args()
if os.name != 'nt':
    raise SystemExit('These real installer and loaded-file tests require Windows')

current = (ROOT / 'packaging/windows/HomeDesk.iss').read_text(encoding='utf8').split('[Code]\n', 1)[1]
original = subprocess.check_output([
    'git', 'show', '902607575789479ec9b328583690425420b8e6f4:packaging/windows/HomeDesk.iss'
], cwd=ROOT, text=True, encoding='utf8').split('[Code]\n', 1)[1]
results = []

with tempfile.TemporaryDirectory(prefix='homedesk-upgrade-test-') as scratch:
    root = Path(scratch)
    stub_source = root / 'service-fixture.go'
    stub_source.write_text('''package main
import ("os"; "path/filepath"; "time")
func main() {
    if len(os.Args) > 1 && os.Args[1] == "stop" {
        os.WriteFile(filepath.Join(filepath.Dir(os.Args[0]), "stop-attempted.txt"), []byte("fixture only"), 0600)
        os.Exit(1)
    }
    for { time.Sleep(time.Second) }
}
''', encoding='utf8')
    stub = root / 'service-fixture.exe'
    subprocess.run(['go', 'build', '-ldflags', '-H=windowsgui -s -w', '-o', str(stub), str(stub_source)], cwd=ROOT, check=True)
    payload = root / 'installed.txt'
    payload.write_bytes(b'isolated installation payload')

    def fixture(name, code, *, legacy=False, running=None, expected=0):
        folder = root / name
        destination = folder / 'Home Tunnel'
        destination.mkdir(parents=True)
        state = destination / 'state.json'
        state.write_bytes(b'preserve existing account and tunnel state')
        before = hashlib.sha256(state.read_bytes()).hexdigest()
        if legacy:
            shutil.copy2(stub, destination / 'home-tunnel-service.exe')
        child = None
        try:
            if running:
                target = destination / running
                if not target.exists():
                    shutil.copy2(stub, target)
                child = subprocess.Popen([str(target)], creationflags=subprocess.CREATE_NO_WINDOW,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                # Wait for the actual image mapping without racing process startup.
                import time
                time.sleep(0.5)
                assert child.poll() is None
            source = folder / 'fixture.iss'
            source.write_text(f'''[Setup]
AppId=HomeDeskUpgradeFixture-{uuid.uuid4()}
AppName=HomeDesk Upgrade Fixture
AppVersion=0.0.0
DefaultDirName={destination}
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir={folder}
OutputBaseFilename=fixture
PrivilegesRequired=lowest
Uninstallable=no
CreateUninstallRegKey=no
CloseApplications=no
RestartApplications=no
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"
[Files]
Source: "{payload}"; DestDir: "{{app}}"
[InstallDelete]
Type: files; Name: "{{app}}\\home-tunnel-service.exe"
[Code]
{code}
''', encoding='utf8')
            build = subprocess.run([args.iscc, '/Qp', str(source)], capture_output=True, text=True, encoding='utf8')
            assert build.returncode == 0, build.stdout + build.stderr
            install = subprocess.run([str(folder / 'fixture.exe'), '/VERYSILENT', '/SUPPRESSMSGBOXES',
                                      '/NORESTART', '/NOICONS', '/SP-', '/CURRENTUSER', '/LANG=chinesesimplified',
                                      '/LOG=' + str(folder / 'install.log')],
                                     creationflags=subprocess.CREATE_NO_WINDOW, timeout=30)
            assert install.returncode == expected, (name, install.returncode, (folder / 'install.log').read_text(errors='replace'))
            assert hashlib.sha256(state.read_bytes()).hexdigest() == before, name
            if expected == 0:
                assert (destination / payload.name).read_bytes() == payload.read_bytes(), name
                assert not (destination / 'home-tunnel-service.exe').exists(), name
                assert not (destination / 'stop-attempted.txt').exists(), 'Unlocked legacy files must not request service control'
            else:
                assert not (destination / payload.name).exists(), name
                if legacy:
                    assert (destination / 'home-tunnel-service.exe').read_bytes() == stub.read_bytes()
            if child:
                assert child.poll() is None, 'Installer must not forcibly terminate the running fixture'
            results.append({'case': name, 'expected_exit': expected, 'actual_exit': install.returncode,
                            'state_preserved': True, 'running_process_preserved': bool(child)})
            print(name + ': real installer preflight and state preservation passed')
        finally:
            # This child is a disposable fixture started here, never a user application.
            if child:
                child.terminate()
                child.wait(timeout=5)

    fixture('original RC1 reproduces false block', original, legacy=True, expected=7)
    fixture('unregistered legacy executable upgrades', current, legacy=True)
    fixture('fresh install', current)
    fixture('running legacy service remains blocked', current, legacy=True, running='home-tunnel-service.exe', expected=7)
    fixture('running HomeDesk remains blocked', current, running='homedesk.exe', expected=7)

if args.evidence:
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    args.evidence.write_text(json.dumps({'revision': revision, 'status': 'passed', 'cases': results,
        'scope': 'Real Inno preflight and loaded-file checks in isolated, unregistered fixtures; no real service, account migration or remote media acceptance'}, indent=2) + '\n', encoding='utf8')
print('Five isolated Inno cases passed; no real service, user registration or application was modified.')
