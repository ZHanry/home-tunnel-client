"""Build, verify and publish a component; preserve sealed engineering evidence in Releases."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
PROJECT = json.loads((ROOT / "compatibility.json").read_text())
COMPONENT = PROJECT["component"]
REPO = os.environ["GITHUB_REPOSITORY"]
SHA = os.environ["GITHUB_SHA"]
TAG = os.environ["GITHUB_REF_NAME"]

def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None).stdout

def api(endpoint):
    return json.loads(run("gh", "api", endpoint, capture=True))

def local_version():
    if COMPONENT == "server":
        return json.loads((ROOT / "control-center/package.json").read_text())["version"]
    if COMPONENT == "client":
        return re.search(r'const Version = "([^"]+)"', (ROOT / "internal/model/model.go").read_text()).group(1)
    return re.search(r'^HOME_TUNNEL_VERSION_NAME=(.+)$', (ROOT / "gradle.properties").read_text(), re.M).group(1)

def validate_release_tag(tag, source_version, stage):
    if stage not in ("internal-testing", "public-release"):
        raise SystemExit("Unknown release stage; set compatibility.json explicitly")
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)(?:-rc\.([1-9]\d*))?", tag)
    if not match:
        raise SystemExit("Release tags must be vX.Y.Z or vX.Y.Z-rc.N")
    version, candidate = match.groups()
    if tag.removeprefix("v") != source_version:
        raise SystemExit("Tag does not match this component's source version")
    if stage == "internal-testing" and candidate is None:
        raise SystemExit("Internal testing publishes prereleases only; use vX.Y.Z-rc.N")
    return version, candidate

def metadata():
    version, candidate = validate_release_tag(TAG, local_version(), PROJECT.get("stage"))
    run("python3", "scripts/check-repository.py")
    run("git", "fetch", "--tags", "origin", "main")
    run("git", "merge-base", "--is-ancestor", SHA, "origin/main")
    checks = api(f"repos/{REPO}/commits/{SHA}/check-runs?per_page=100")["check_runs"]
    gates = [c for c in checks if c["name"] == "Quality Gate" and c.get("app", {}).get("slug") == "github-actions"]
    if not gates or max(gates, key=lambda c:c["id"])["conclusion"] != "success":
        raise SystemExit("The tagged commit must first pass its component CI Quality Gate on main")
    security_runs = api(f"repos/{REPO}/actions/runs?head_sha={SHA}&per_page=100")["workflow_runs"]
    for workflow_name in ("CodeQL", "Secret scan"):
        matching = [r for r in security_runs if r["name"] == workflow_name and r["head_sha"] == SHA]
        if not matching or max(matching, key=lambda r:r["id"])["conclusion"] != "success":
            raise SystemExit(f"The tagged commit must pass {workflow_name} before release")
    rc_tag = TAG
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in {"version":TAG.removeprefix('v'),"base-version":version,
                           "stable":str(not candidate).lower(),"rc-version":rc_tag.removeprefix('v'),"rc-tag":rc_tag}.items():
            output.write(f"{key}={value}\n")

def required_assets(directory):
    version = local_version()
    if COMPONENT == "client":
        expected = [f"HomeTunnel-Setup-{version}-x64.exe", f"HomeTunnel-Windows-{version}-x64.zip"]
        expected += [f"home-tunnel-{platform}-{version}-{arch}.tar.gz" for platform in ("linux","macos") for arch in ("amd64","arm64")]
        expected += ["agent-provenance.json", "windows-defender-scan.json", "windows-installer-smoke.json",
                     "remote-host-provenance.json", "remote-host-build.json", "windows-remote-native-acceptance.json"]
    elif COMPONENT == "android":
        expected = [f"HomeTunnel-Android-{version}-arm64-v8a.apk", f"HomeTunnel-Android-{version}.aab", "android-release-evidence.json"]
    else:
        expected = ["image-control-center.json", "image-traffic-gateway.json", "home-tunnel.v1.json"]
        for name in ("control-center", "traffic-gateway"):
            record = json.loads((directory / f"image-{name}.json").read_text())
            if record["revision"] != SHA or not re.fullmatch(r"sha256:[a-f0-9]{64}", record["digest"]):
                raise SystemExit("Invalid server image identity")
    for name in expected:
        if not (directory/name).is_file() or not (directory/name).stat().st_size:
            raise SystemExit(f"Missing release asset: {name}")
    if COMPONENT == "client":
        verify_windows_evidence(directory, version, SHA)
        verify_remote_evidence(directory, version, SHA)

def verify_windows_evidence(directory, version, revision):
    """Bind real antivirus and installer checks to the exact bytes being published."""
    from datetime import datetime, timedelta, timezone
    import zipfile
    scan = json.loads((directory / "windows-defender-scan.json").read_text())
    install = json.loads((directory / "windows-installer-smoke.json").read_text())
    for report in (scan, install):
        if report.get("status") != "passed" or report.get("version") != version or report.get("repository_revision") != revision:
            raise SystemExit("Windows release evidence is missing, failed or belongs to another build")
    if scan.get("engine") != "Microsoft Defender" or not scan.get("signature_version") or not scan.get("engine_version"):
        raise SystemExit("Windows antivirus engine identity is missing")
    now = datetime.now(timezone.utc)
    scanned = datetime.fromisoformat(scan["scanned_at"].replace("Z", "+00:00"))
    updated = datetime.fromisoformat(scan["signature_updated_at"].replace("Z", "+00:00"))
    if scanned.tzinfo is None or updated.tzinfo is None or not now - timedelta(days=1) <= scanned <= now + timedelta(minutes=5) or not scanned - timedelta(days=2) <= updated <= scanned + timedelta(minutes=5):
        raise SystemExit("Windows antivirus scan or signatures are stale")
    setup = f"HomeTunnel-Setup-{version}-x64.exe"
    archive = f"HomeTunnel-Windows-{version}-x64.zip"
    files = scan.get("files", [])
    records = {item["name"]: item for item in files}
    expected = {setup, archive, "home-tunnel-gui.exe", "home-tunnel-agent.exe", "home_tunnel_remote_host.exe"}
    if set(records) != expected or len(files) != len(expected) or any(item.get("exit_code") != 0 for item in files):
        raise SystemExit("Windows antivirus scan did not pass for every release component")
    for name in (setup, archive):
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != records[name].get("sha256"):
            raise SystemExit("Windows release bytes differ from the scanned files")
    with zipfile.ZipFile(directory / archive) as bundle:
        for name in ("home-tunnel-gui.exe", "home-tunnel-agent.exe", "home_tunnel_remote_host.exe"):
            if bundle.namelist().count(name) != 1:
                raise SystemExit("Windows archive must contain each executable exactly once")
            if hashlib.sha256(bundle.read(name)).hexdigest() != records[name].get("sha256"):
                raise SystemExit("Windows archive payload differs from the scanned files")
    if install.get("installer_sha256") != records[setup]["sha256"] or any(install.get(check) != "passed" for check in ("install", "payload_hashes", "uninstall", "embedded_icon", "gui_subsystem", "native_window_icon")):
        raise SystemExit("Windows installer lifecycle checks do not match this installer")


def verify_remote_evidence(directory, version, revision):
    """Refuse a core-only package, stale native report or changed signed worker."""
    import zipfile
    provenance = json.loads((directory / "remote-host-provenance.json").read_text())
    build = json.loads((directory / "remote-host-build.json").read_text())
    acceptance = json.loads((directory / "windows-remote-native-acceptance.json").read_text())
    lock_path = ROOT / 'native/remote/remote-deps.lock.json'
    dependency = json.loads(lock_path.read_text())
    server = json.loads((ROOT / 'tests/remote-native/server-lock.json').read_text())
    worker = provenance.get('worker', {})
    engine = provenance.get('engine', {})
    if (provenance.get('schema_version') != 1 or provenance.get('version') != version or
            provenance.get('repository_revision') != revision or provenance.get('abi_version') != 1 or
            provenance.get('build', {}).get('source_modified') is not False or
            provenance.get('build', {}).get('authorization_tests') != 'passed'):
        raise SystemExit('Native provenance does not describe this clean, verified build')
    if (engine.get('revision') != dependency['webrtc']['revision'] or
            engine.get('lock_sha256') != hashlib.sha256(lock_path.read_bytes()).hexdigest()):
        raise SystemExit('Native engine provenance differs from the reviewed dependency lock')
    if (server.get('repository') != 'ZHanry/home-tunnel-server' or
            not re.fullmatch(r'[0-9a-f]{40}', server.get('revision', '')) or
            provenance.get('server') != {key: server[key] for key in ('repository', 'revision')}):
        raise SystemExit('Native interoperability server is not the locked source')
    if (worker.get('name') != 'home_tunnel_remote_host.exe' or
            any(not re.fullmatch(r'[0-9a-f]{64}', worker.get(key, '')) for key in ('sha256', 'unsigned_sha256'))):
        raise SystemExit('Native worker identities are missing')
    expected_build = {'sha256': worker['unsigned_sha256'], 'version': version, 'repository_revision': revision,
                      'source_modified': False, 'target_os': 'win', 'target_cpu': 'x64',
                      'webrtc_revision': engine['revision'], 'deps_lock_sha256': engine['lock_sha256'],
                      'authorization_tests': 'passed', 'notices_sha256': provenance.get('notices_sha256')}
    if any(build.get(key) != value for key, value in expected_build.items()):
        raise SystemExit('Native pre-signing build does not match the final provenance')
    with zipfile.ZipFile(directory / f'HomeTunnel-Windows-{version}-x64.zip') as bundle:
        if bundle.namelist().count(worker['name']) != 1 or hashlib.sha256(bundle.read(worker['name'])).hexdigest() != worker['sha256']:
            raise SystemExit('Packaged native worker differs from its provenance')
        for name in ('remote-host-provenance.json', 'remote-host-build.json'):
            if bundle.namelist().count(name) != 1 or bundle.read(name) != (directory / name).read_bytes():
                raise SystemExit('Packaged native provenance differs from the published evidence')
        notice = 'WEBRTC-THIRD-PARTY-NOTICES.md'
        if (bundle.namelist().count(notice) != 1 or
                hashlib.sha256(bundle.read(notice)).hexdigest() != provenance.get('notices_sha256')):
            raise SystemExit('Packaged native dependency notices are missing or changed')
    if acceptance.get('status') != 'passed' or acceptance.get('input', {}).get('status') != 'passed':
        raise SystemExit('Real native video and input acceptance must both pass')
    if any(acceptance['input'].get(check) is not True for check in ('keyboard_down_up', 'unicode_text', 'pointer_down_up',
            'native_process_confinement', 'os_foreground_verified', 'released')):
        raise SystemExit('Native acceptance does not prove actual confined keyboard, Unicode and pointer input')
    if acceptance.get('worker_sha256') != worker['sha256']:
        raise SystemExit('Native acceptance must use the final distributed worker bytes')
    sources = acceptance.get('sources', {})
    for component, expected_revision in (('client', revision), ('server', server['revision'])):
        if sources.get(component, {}).get('commit') != expected_revision or sources.get(component, {}).get('modified') is not False:
            raise SystemExit('Native acceptance used a different or modified source tree')
    required = ('isolated_real_server', 'native_backend_ready', 'real_browser_identity', 'signed_pairing_and_code_match',
                'explicit_session_approval', 'real_continuing_video', 'selected_udp_and_dtls', 'clean_session_shutdown')
    if any(acceptance.get('checks', {}).get(check) is not True for check in required):
        raise SystemExit('Native acceptance is incomplete')
    media = acceptance.get('media', {})
    if (any(media.get(check) is not True for check in ('ready', 'peer_verified', 'host_path_verified', 'browser_udp_verified')) or
            media.get('closed') is not False or media.get('dtls_state') != 'connected' or
            type(media.get('frames_decoded')) is not int or media['frames_decoded'] < 5 or media.get('failures') != []):
        raise SystemExit('Native acceptance does not prove continuing authenticated UDP video')

def seal():
    directory = ROOT / "release"
    required_assets(directory)
    manifest={"component":COMPONENT,"version":local_version(),"repository":REPO,"revision":SHA,"api_major":1,"rc_tag":TAG}
    (directory/'release-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if COMPONENT == 'server':
        records = [json.loads((directory/f'image-{name}.json').read_text()) for name in ('control-center','traffic-gateway')]
        lines = ['services:']
        for record in records:
            lines += [f"  {record['name']}:", f"    image: {record['image']}@{record['digest']}"]
        (directory/'compose.release.yaml').write_text('\n'.join(lines)+'\n')
    lines=[]
    for path in sorted(directory.iterdir()):
        if path.is_file() and path.name not in ('SHA256SUMS.txt','SHA256SUMS.txt.sigstore.json'):
            lines.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
    (directory/'SHA256SUMS.txt').write_text(''.join(lines), encoding='utf-8')

def verify(directory, rc_tag):
    identity = f"https://github.com/{REPO}/.github/workflows/release.yml@refs/tags/{rc_tag}"
    run("cosign","verify-blob","--bundle",str(directory/'SHA256SUMS.txt.sigstore.json'),
        "--certificate-identity",identity,"--certificate-oidc-issuer","https://token.actions.githubusercontent.com",str(directory/'SHA256SUMS.txt'))
    listed = set()
    for line in (directory/'SHA256SUMS.txt').read_text().splitlines():
        checksum, name = line.split('  ',1)
        if Path(name).name != name or not re.fullmatch(r'[a-f0-9]{64}',checksum):
            raise SystemExit('Invalid checksum manifest path or hash')
        if hashlib.sha256((directory/name).read_bytes()).hexdigest() != checksum:
            raise SystemExit(f'Checksum mismatch: {name}')
        listed.add(name)
    actual={p.name for p in directory.iterdir() if p.is_file()}-{'SHA256SUMS.txt','SHA256SUMS.txt.sigstore.json'}
    if actual != listed:
        raise SystemExit('Unsealed or missing release assets')
    manifest=json.loads((directory/'release-manifest.json').read_text())
    for key,value in {'repository':REPO,'revision':SHA,'version':local_version(),'component':COMPONENT,'rc_tag':rc_tag}.items():
        if manifest.get(key)!=value: raise SystemExit(f'Release manifest mismatch: {key}')
    required_assets(directory)
    return identity

def public_asset_names(component, version):
    if component == "android":
        return [f"HomeTunnel-Android-{version}-arm64-v8a.apk"]
    if component == "client":
        return [f"HomeTunnel-Setup-{version}-x64.exe", f"HomeTunnel-Windows-{version}-x64.zip"] + [
            f"home-tunnel-{platform}-{version}-{arch}.tar.gz"
            for platform in ("linux", "macos") for arch in ("amd64", "arm64")]
    return [f"home-tunnel-server-{version}.tar.gz", "compose.release.yaml"]

def publish(stable=False):
    directory=ROOT/'release'
    stable = re.fullmatch(r"v\d+\.\d+\.\d+", TAG) is not None
    identity=verify(directory,TAG)
    if COMPONENT=='server' and stable:
        for name in ('control-center','traffic-gateway'):
            record=json.loads((directory/f'image-{name}.json').read_text())
            reference=f"{record['image']}@{record['digest']}"
            run('cosign','verify',reference,'--certificate-identity',identity,'--certificate-oidc-issuer','https://token.actions.githubusercontent.com',capture=True)
    import shutil
    public = ROOT/'release-public'
    public.mkdir(exist_ok=True)
    # Publish the exact sealed set, including SBOMs, scan results and signatures.
    # Keeping the signed checksum manifest unchanged makes evidence independently verifiable.
    selected=sorted(path.name for path in directory.iterdir() if path.is_file())
    missing=set(public_asset_names(COMPONENT,local_version()))-set(selected)
    if missing: raise SystemExit(f'Missing public deliverables: {missing}')
    for name in selected:
        shutil.copyfile(directory/name,public/name)
    packages=public_asset_names(COMPONENT,local_version())
    downloads='\n'.join(f'- [{name}](https://github.com/{REPO}/releases/download/{TAG}/{name})' for name in packages)
    checksums=''.join(f"{hashlib.sha256((public/name).read_bytes()).hexdigest()}  {name}\n" for name in packages)
    title=f'Home Tunnel {COMPONENT} {local_version()}' + ('' if stable else f' ({TAG.rsplit("-",1)[1]})')
    notes=ROOT/'release-notes.md'
    summary=(ROOT/'docs/RELEASE_NOTES.md').read_text(encoding='utf-8')
    run_url=f"https://github.com/{REPO}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    notes.write_text(summary + "\n\n## Downloads\n\n" + downloads + "\n\n```text\n" + checksums + "```\n" + f"\n\nSource: `{SHA}`. [Build, verification and signing evidence]({run_url}).\n\n" +
        "Packages and durable verification evidence are covered by SHA256SUMS.txt and its Sigstore bundle.\n",encoding='utf-8')
    created=False
    try:
        run('gh','release','create',TAG,'--repo',REPO,'--verify-tag','--target',SHA,'--draft','--title',title,'--notes-file',str(notes))
        created=True
        run('gh','release','upload',TAG,'--repo',REPO,*[str(p) for p in sorted(public.iterdir()) if p.is_file()])
        flags=['--draft=false','--latest=true'] if stable else ['--draft=false','--prerelease','--latest=false']
        run('gh','release','edit',TAG,'--repo',REPO,*flags)
    except BaseException:
        if created:
            current=json.loads(run('gh','release','view',TAG,'--repo',REPO,'--json','isDraft',capture=True))
            if current['isDraft']: run('gh','release','delete',TAG,'--repo',REPO,'--yes')
        raise

if __name__=='__main__':
    action=sys.argv[1]
    if action=='metadata': metadata()
    elif action=='seal': seal()
    elif action=='rc': publish()
    elif action=='stable': publish(stable=True)
    else: raise SystemExit('Unknown release action')
