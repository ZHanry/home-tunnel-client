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
PROJECT = json.loads((ROOT / "compatibility.json").read_text(encoding="utf-8"))
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
        return json.loads((ROOT / "control-center/package.json").read_text(encoding="utf-8"))["version"]
    if COMPONENT == "client":
        return re.search(r'const Version = "([^"]+)"', (ROOT / "internal/model/model.go").read_text(encoding="utf-8")).group(1)
    return re.search(r'^HOME_TUNNEL_VERSION_NAME=(.+)$', (ROOT / "gradle.properties").read_text(encoding="utf-8"), re.M).group(1)

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

def validate_frozen_contract(project, locks):
    """Candidates can use a draft; publication requires one frozen server source."""
    ref = project.get("contract_ref")
    number = r"(?:0|[1-9][0-9]*)"
    if (not isinstance(ref, str) or
            re.fullmatch(rf"api-v{number}\.{number}\.{number}(?:-rc\.[1-9][0-9]*)?", ref) is None or
            project.get("contract_status") != "frozen" or project.get("frozen_tag") != ref):
        raise SystemExit("Publication requires a frozen contract; proposed API contracts are candidate-only")
    if len(locks) != 2:
        raise SystemExit("Publication requires both API and remote contract locks")
    revisions = set()
    for lock in locks:
        if (lock.get("repository") != "ZHanry/home-tunnel-server" or lock.get("contract_status") != "frozen" or
                lock.get("frozen_tag") != ref or lock.get("published_contract_ref") != ref or
                lock.get("ref", ref) != ref or lock.get("source_tree_dirty") is not False or
                re.fullmatch(r"[0-9a-f]{40}", str(lock.get("source_revision", ""))) is None):
            raise SystemExit("Publication contract locks must pin the same frozen, clean server source")
        revisions.add(lock["source_revision"])
    if len(revisions) != 1:
        raise SystemExit("API and remote contract locks refer to different server commits")
    return ref, revisions.pop()


def check_frozen_contract():
    ref, revision = validate_frozen_contract(PROJECT, [
        json.loads((ROOT / "contracts" / name).read_text(encoding="utf-8"))
        for name in ("lock.json", "remote.lock.json")
    ])
    repository = "repos/ZHanry/home-tunnel-server"
    target = api(f"{repository}/git/ref/tags/{ref}").get("object", {})
    visited = set()
    for _ in range(8):
        if target.get("type") == "commit":
            if target.get("sha") != revision:
                raise SystemExit("Frozen contract tag does not identify the locked server commit")
            return
        digest = target.get("sha")
        if (target.get("type") != "tag" or not isinstance(digest, str) or
                re.fullmatch(r"[0-9a-f]{40}", digest) is None or digest in visited):
            break
        visited.add(digest)
        target = api(f"{repository}/git/tags/{digest}").get("object", {})
    raise SystemExit("Frozen contract tag could not be resolved to the locked server commit")


def candidate_metadata():
    """Build before tagging; refuse an unpinned or changed workflow checkout."""
    from client_release_candidate import CALLER, REPOSITORY, package_names
    requested = os.environ.get("CANDIDATE_REVISION", "")
    ref = os.environ.get("GITHUB_REF", "")
    if (REPO != REPOSITORY or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or
            not re.fullmatch(r"[0-9a-f]{40}", requested) or requested != SHA or
            not re.fullmatch(r"refs/heads/[^\s]+", ref) or
            os.environ.get("GITHUB_WORKFLOW_REF") != f"{REPO}/{CALLER}@{ref}" or
            run("git", "rev-parse", "HEAD", capture=True).strip() != SHA or
            run("git", "status", "--porcelain", capture=True).strip()):
        raise SystemExit("Candidate requires the exact clean branch SHA and the registered dispatch workflow")
    package_names(local_version())
    run(sys.executable, "scripts/check-repository.py")
    run(sys.executable, "scripts/sync-remote-contracts.py", "--check")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"version={local_version()}\n")


def seal_candidate():
    from datetime import datetime, timezone
    from client_release_candidate import CALLER, SIGNER, MANIFEST, digest, package_names, verify_candidate
    if (not os.environ.get("GITHUB_REF", "").startswith("refs/heads/") or
            run("git", "rev-parse", "HEAD", capture=True).strip() != SHA or
            run("git", "status", "--porcelain", capture=True).strip()):
        raise SystemExit("Candidate sealing requires the clean untagged build source")
    directory = ROOT / "release"
    if (directory / MANIFEST).exists():
        raise SystemExit("Candidate inventory already exists; never replace it")
    required_assets(directory, for_publication=False)
    files = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in directory.iterdir() if p.is_file()}
    candidate = {"schema_version": 1, "repository": REPO, "revision": SHA, "version": local_version(),
        "verification_stage": "candidate", "tag_published": False, "acceptance_complete": False, "source_modified": False,
        "created_at": datetime.now(timezone.utc).isoformat(), "files": files,
        "packages": {name: files[name] for name in package_names(local_version())},
        "server": json.loads((ROOT / "tests/remote-native/server-lock.json").read_text()),
        "build": {"repository": REPO, "caller_workflow": CALLER, "signer_workflow": SIGNER,
                  "run_id": os.environ["GITHUB_RUN_ID"], "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
                  "source_ref": os.environ["GITHUB_REF"]}}
    verify_candidate(candidate, directory, SHA, local_version())
    with (directory / MANIFEST).open("x", encoding="utf-8") as output:
        output.write(json.dumps(candidate, indent=2) + "\n")


def metadata():
    if os.environ.get("GITHUB_REF") != f"refs/tags/{TAG}" or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
        raise SystemExit("Publication requires an explicit dispatch at the accepted version tag")
    version, candidate = validate_release_tag(TAG, local_version(), PROJECT.get("stage"))
    check_frozen_contract()
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

def required_assets(directory, *, for_publication=True):
    version = local_version()
    if COMPONENT == "client":
        expected = [f"HomeTunnel-Setup-{version}-x64.exe", f"HomeTunnel-Windows-{version}-x64.zip"]
        expected += [f"home-tunnel-{platform}-{version}-{arch}.tar.gz" for platform in ("linux","macos") for arch in ("amd64","arm64")]
        expected += ["agent-provenance.json", "windows-defender-scan.json", "windows-installer-smoke.json",
                     "remote-host-provenance.json", "remote-host-build.json", "remote-source-manifest.json",
                     f"HomeTunnel-Remote-SDK-{version}-windows-x64.zip", "remote-sdk-provenance.json"]
        expected += android_controller_sdk_assets(version)
        if for_publication:
            expected += ["windows-remote-native-acceptance.json", "windows-final-defender-scan.json",
                         "client-candidate.json", "client-candidate.json.sigstore.json", "client-acceptance.json",
                         "client-candidate-download.json", "client-acceptance-origin.json"]
    elif COMPONENT == "android":
        expected = [f"HomeTunnel-Android-{version}-arm64-v8a.apk", f"HomeTunnel-Android-{version}.aab", "android-release-evidence.json"]
    else:
        expected = ["image-control-center.json", "image-traffic-gateway.json", "home-tunnel.v1.json"]
        for name in ("control-center", "traffic-gateway"):
            record = json.loads((directory / f"image-{name}.json").read_text(encoding="utf-8"))
            if record["revision"] != SHA or not re.fullmatch(r"sha256:[a-f0-9]{64}", record["digest"]):
                raise SystemExit("Invalid server image identity")
    for name in expected:
        if not (directory/name).is_file() or not (directory/name).stat().st_size:
            raise SystemExit(f"Missing release asset: {name}")
    if COMPONENT == "client":
        # Validate the original Linux package on preparation and publication.
        # A tunnel-only tarball or a test-mode worker must never become the x64 RC.
        run(sys.executable, str(ROOT / "scripts/package-native-linux.py"), "--verify-archive",
            str(directory / f"home-tunnel-linux-{version}-amd64.tar.gz"), "--version", version, "--revision", SHA)
        if for_publication:
            from client_release_candidate import MANIFEST, ACCEPTANCE, digest, read_json, timestamp, verify_candidate, verify_acceptance
            candidate = verify_candidate(read_json(directory / MANIFEST), directory, SHA, version)
            verify_acceptance(read_json(directory / ACCEPTANCE), directory, candidate, digest(directory / MANIFEST))
            server = json.loads((ROOT / "tests/remote-native/server-lock.json").read_text())
            if candidate["server"] != server:
                raise SystemExit("Candidate and release lock different server sources")
            downloaded = read_json(directory / "client-candidate-download.json")
            origin = read_json(directory / "client-acceptance-origin.json")
            if (downloaded.get("source_revision") != SHA or downloaded.get("candidate_sha256") != digest(directory / MANIFEST) or
                    downloaded.get("signatures_verified") is not True or downloaded.get("run_attestations_verified") is not True or
                    not re.fullmatch(r"[0-9a-f]{40}", str(downloaded.get("acceptance_revision", ""))) or
                    origin.get("revision") != downloaded["acceptance_revision"] or origin.get("repository") != "ZHanry/home-tunnel" or
                    origin.get("manifest_sha256") != digest(directory / ACCEPTANCE)):
                raise SystemExit("Verified candidate download or reviewed acceptance origin is missing")
            # A 24-hour soak must not invalidate the immutable build-time scan.
            verify_windows_evidence(directory, version, SHA, validation_time=timestamp(candidate["created_at"]))
            verify_windows_evidence(directory, version, SHA, scan_name="windows-final-defender-scan.json")
            final_scan = read_json(directory / "windows-final-defender-scan.json")
            if timestamp(final_scan["scanned_at"]) < timestamp(candidate["created_at"]):
                raise SystemExit("Final Windows rescan must follow candidate creation")
        else:
            verify_windows_evidence(directory, version, SHA)
        verify_remote_sdk(directory, version, SHA)
        for abi in ("arm64-v8a", "x86_64"):
            run(sys.executable, str(ROOT / "scripts/package-remote-android-sdk.py"), "--verify", "--abi", abi, "--output", str(directory), "--version", version, "--revision", SHA)
        if for_publication:
            verify_remote_evidence(directory, version, SHA)
        else:
            verify_remote_build(directory, version, SHA)

def validate_windows_archive(bundle):
    """Windows extraction must not replace a verified payload via a path alias."""
    seen = set()
    for item in bundle.infolist():
        name = item.filename
        if not name or '\\' in name or ':' in name or name.startswith('/') or any(ord(c) < 32 for c in name):
            raise SystemExit('Unsafe Windows archive path')
        parts = name.rstrip('/').split('/')
        if any(not part or part in ('.', '..') or part.endswith((' ', '.')) or
               re.fullmatch(r'(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', part, re.I) for part in parts):
            raise SystemExit('Unsafe Windows archive path')
        normalized = '/'.join(parts).casefold()
        if normalized in seen or (item.external_attr >> 16) & 0o170000 == 0o120000:
            raise SystemExit('Aliased or linked Windows archive payload')
        seen.add(normalized)


def verify_windows_evidence(directory, version, revision, *, validation_time=None, scan_name="windows-defender-scan.json"):
    """Bind real antivirus and installer checks to the exact bytes being published."""
    from datetime import datetime, timedelta, timezone
    import zipfile
    scan = json.loads((directory / scan_name).read_text(encoding="utf-8"))
    install = json.loads((directory / "windows-installer-smoke.json").read_text(encoding="utf-8"))
    for report in (scan, install):
        if report.get("status") != "passed" or report.get("version") != version or report.get("repository_revision") != revision:
            raise SystemExit("Windows release evidence is missing, failed or belongs to another build")
    if scan.get("engine") != "Microsoft Defender" or not scan.get("signature_version") or not scan.get("engine_version"):
        raise SystemExit("Windows antivirus engine identity is missing")
    now = validation_time or datetime.now(timezone.utc)
    scanned = datetime.fromisoformat(scan["scanned_at"].replace("Z", "+00:00"))
    updated = datetime.fromisoformat(scan["signature_updated_at"].replace("Z", "+00:00"))
    if scanned.tzinfo is None or updated.tzinfo is None or not now - timedelta(days=1) <= scanned <= now + timedelta(minutes=5) or not scanned - timedelta(days=2) <= updated <= scanned + timedelta(minutes=5):
        raise SystemExit("Windows antivirus scan or signatures are stale")
    setup = f"HomeTunnel-Setup-{version}-x64.exe"
    archive = f"HomeTunnel-Windows-{version}-x64.zip"
    files = scan.get("files", [])
    records = {item["name"]: item for item in files}
    executables = ("home-tunnel-gui.exe", "home-tunnel-agent.exe", "home-tunnel-service.exe", "home_tunnel_remote_host.exe")
    expected = {setup, archive, *executables}
    if set(records) != expected or len(files) != len(expected) or any(item.get("exit_code") != 0 for item in files):
        raise SystemExit("Windows antivirus scan did not pass for every release component")
    for name in (setup, archive):
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != records[name].get("sha256"):
            raise SystemExit("Windows release bytes differ from the scanned files")
    with zipfile.ZipFile(directory / archive) as bundle:
        validate_windows_archive(bundle)
        for name in executables:
            if bundle.namelist().count(name) != 1:
                raise SystemExit("Windows archive must contain each executable exactly once")
            if hashlib.sha256(bundle.read(name)).hexdigest() != records[name].get("sha256"):
                raise SystemExit("Windows archive payload differs from the scanned files")
        installed = install.get('installed_payloads', [])
        installed_by_name = {item['name']: item.get('sha256') for item in installed}
        required_payloads = {*executables,
                             'remote-host-provenance.json', 'remote-host-build.json', 'remote-source-manifest.json', 'WEBRTC-THIRD-PARTY-NOTICES.md'}
        if len(installed_by_name) != len(installed) or not required_payloads <= installed_by_name.keys():
            raise SystemExit('Windows installer evidence omits actual installed payload identities')
        for name in required_payloads:
            if bundle.namelist().count(name) != 1 or hashlib.sha256(bundle.read(name)).hexdigest() != installed_by_name[name]:
                raise SystemExit('Windows installer payload differs from the verified portable package')
    if install.get("installer_sha256") != records[setup]["sha256"] or any(install.get(check) != "passed" for check in ("install", "payload_hashes", "uninstall", "embedded_icon", "gui_subsystem", "native_window_icon")):
        raise SystemExit("Windows installer lifecycle checks do not match this installer")


def verify_remote_build(directory, version, revision):
    """Validate build identities only; this is insufficient to publish a release."""
    import zipfile
    provenance = json.loads((directory / "remote-host-provenance.json").read_text(encoding="utf-8"))
    build = json.loads((directory / "remote-host-build.json").read_text(encoding="utf-8"))
    lock_path = ROOT / 'native/remote/remote-deps.lock.json'
    dependency = json.loads(lock_path.read_text(encoding="utf-8"))
    server = json.loads((ROOT / 'tests/remote-native/server-lock.json').read_text(encoding="utf-8"))
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
                      'authorization_tests': 'passed', 'notices_sha256': provenance.get('notices_sha256'),
                      'source_manifest_sha256': provenance.get('source_manifest_sha256')}
    if any(build.get(key) != value for key, value in expected_build.items()):
        raise SystemExit('Native pre-signing build does not match the final provenance')
    with zipfile.ZipFile(directory / f'HomeTunnel-Windows-{version}-x64.zip') as bundle:
        validate_windows_archive(bundle)
        if bundle.namelist().count(worker['name']) != 1 or hashlib.sha256(bundle.read(worker['name'])).hexdigest() != worker['sha256']:
            raise SystemExit('Packaged native worker differs from its provenance')
        for name in ('remote-host-provenance.json', 'remote-host-build.json', 'remote-source-manifest.json'):
            if bundle.namelist().count(name) != 1 or bundle.read(name) != (directory / name).read_bytes():
                raise SystemExit('Packaged native provenance differs from the published evidence')
        notice = 'WEBRTC-THIRD-PARTY-NOTICES.md'
        if (bundle.namelist().count(notice) != 1 or
                hashlib.sha256(bundle.read(notice)).hexdigest() != provenance.get('notices_sha256')):
            raise SystemExit('Packaged native dependency notices are missing or changed')
        source_manifest_hash = hashlib.sha256(bundle.read('remote-source-manifest.json')).hexdigest()
        if source_manifest_hash != provenance.get('source_manifest_sha256'):
            raise SystemExit('Packaged native source manifest differs from its provenance')
    return worker, server


def verify_remote_evidence(directory, version, revision):
    """Refuse a core-only package, stale native report or changed signed worker."""
    worker, server = verify_remote_build(directory, version, revision)
    acceptance = json.loads((directory / "windows-remote-native-acceptance.json").read_text(encoding="utf-8"))
    if acceptance.get('status') != 'passed' or acceptance.get('input', {}).get('status') != 'passed':
        raise SystemExit('Real native video and input acceptance must both pass')
    if any(acceptance['input'].get(check) is not True for check in ('keyboard_down_up', 'unicode_text', 'pointer_down_up',
            'native_process_confinement', 'os_foreground_verified', 'released', 'stale_epoch_rejected')):
        raise SystemExit('Native acceptance does not prove actual confined keyboard, Unicode and pointer input')
    for name, timings in (('heartbeat_watchdog', ('release_ms',)),
                          ('worker_crash', ('key_release_ms', 'button_release_ms'))):
        result = acceptance['input'].get(name, {})
        if (not isinstance(result, dict) or result.get('passed') is not True or
                any(type(result.get(timing)) not in (int, float) or not 0 <= result[timing] <= 2000
                    for timing in timings)):
            raise SystemExit('Native acceptance must prove held input release within two seconds after heartbeat loss and worker crash')
    if acceptance.get('worker_sha256') != worker['sha256']:
        raise SystemExit('Native acceptance must use the final distributed worker bytes')
    sources = acceptance.get('sources', {})
    for component, expected_revision in (('client', revision), ('server', server['revision'])):
        if sources.get(component, {}).get('commit') != expected_revision or sources.get(component, {}).get('modified') is not False:
            raise SystemExit('Native acceptance used a different or modified source tree')
    server_build = acceptance.get('server_build', {})
    dist = server_build.get('dist', {})
    if (server_build.get('fresh') is not True or server_build.get('source_commit') != server['revision'] or
            server_build.get('command') != 'pnpm run build' or type(dist.get('file_count')) is not int or
            dist['file_count'] < 1 or not re.fullmatch(r'[0-9a-f]{64}', dist.get('sha256', ''))):
        raise SystemExit('Native acceptance must freshly build the locked server and identify its output')
    required = ('isolated_real_server', 'native_backend_ready', 'real_browser_identity', 'signed_pairing_and_code_match',
                'session_approval_verified', 'one_time_grant_auto_approval', 'real_continuing_video',
                'selected_udp_and_dtls', 'clean_session_shutdown')
    if any(acceptance.get('checks', {}).get(check) is not True for check in required):
        raise SystemExit('Native acceptance is incomplete')
    media = acceptance.get('media', {})
    if (any(media.get(check) is not True for check in ('ready', 'peer_verified', 'host_path_verified', 'browser_udp_verified')) or
            media.get('closed') is not False or media.get('dtls_state') != 'connected' or
            type(media.get('frames_decoded')) is not int or media['frames_decoded'] < 5 or media.get('failures') != []):
        raise SystemExit('Native acceptance does not prove continuing authenticated UDP video')


def verify_remote_sdk(directory, version, revision):
    """Bind the reusable native dependency to the same reviewed source and lock."""
    import zipfile
    import importlib.util
    evidence = json.loads((directory / 'remote-sdk-provenance.json').read_text(encoding='utf-8'))
    lock_bytes = (ROOT / 'native/remote/remote-deps.lock.json').read_bytes()
    dependency = json.loads(lock_bytes)
    expected = {'schema_version': 1, 'version': version, 'repository_revision': revision,
                'source_modified': False, 'target_os': 'win', 'target_cpu': 'x64', 'abi_version': 1}
    if (any(evidence.get(key) != value or type(evidence.get(key)) is not type(value) for key, value in expected.items()) or
            evidence.get('engine') != {'revision': dependency['webrtc']['revision'],
                                       'lock_sha256': hashlib.sha256(lock_bytes).hexdigest()}):
        raise SystemExit('Native SDK source, target or dependency identity mismatch')
    name = f'HomeTunnel-Remote-SDK-{version}-windows-x64.zip'
    archive = evidence.get('archive', {})
    with (directory / name).open('rb') as stream:
        if archive.get('name') != name or hashlib.file_digest(stream, 'sha256').hexdigest() != archive.get('sha256'):
            raise SystemExit('Native SDK archive differs from its recorded bytes')
    library = evidence.get('library', {})
    if library.get('name') != 'lib/webrtc.lib' or type(library.get('bytes')) is not int or library['bytes'] < 1:
        raise SystemExit('Native SDK library identity is missing')
    with zipfile.ZipFile(directory / name) as bundle:
        validate_windows_archive(bundle)
        names = set(bundle.namelist())
        required = {'lib/webrtc.lib', 'include/webrtc/api/peer_connection_interface.h',
                    'native/include/home_tunnel/remote.h', 'remote-deps.lock.json',
                    'remote-source-manifest.json', 'WEBRTC-THIRD-PARTY-NOTICES.md',
                    'source-license-inventory.json', 'source-licenses/chromium/LICENSE'}
        if not required.issubset(names):
            raise SystemExit('Native SDK library, public headers or notices are missing')
        if bundle.getinfo('lib/webrtc.lib').file_size != library['bytes']:
            raise SystemExit('Native SDK library size differs')
        with bundle.open('lib/webrtc.lib') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != library.get('sha256'):
                raise SystemExit('Native SDK library digest differs')
        expected_files = {'remote-deps.lock.json': lock_bytes,
                          'native/include/home_tunnel/remote.h': (ROOT / 'native/remote/include/home_tunnel/remote.h').read_bytes()}
        for patch in dependency['patches']:
            data = (ROOT / 'native/remote' / patch['path']).read_bytes()
            if hashlib.sha256(data).hexdigest() != patch['sha256']:
                raise SystemExit('Native SDK patch lock is invalid')
            expected_files[patch['path']] = data
        for path, data in expected_files.items():
            if path not in names or bundle.read(path) != data:
                raise SystemExit('Native SDK ABI, dependency lock or reviewed patch differs')
        for path, field in (('remote-source-manifest.json', 'source_manifest_sha256'),
                            ('WEBRTC-THIRD-PARTY-NOTICES.md', 'notices_sha256')):
            data = bundle.read(path)
            if data != (directory / path).read_bytes() or hashlib.sha256(data).hexdigest() != evidence.get(field):
                raise SystemExit('Native SDK source manifest or notices differ from the worker build')
        spec = importlib.util.spec_from_file_location('sdk_notice_policy', ROOT / 'scripts/build-remote-android-webrtc.py')
        policy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(policy)
        sources = json.loads(bundle.read('remote-source-manifest.json')).get('dependency_sources', {})
        expected_licenses = policy.chromium_license_record(sources)
        if (set(expected_licenses) != set(policy.CHROMIUM_MIRRORS) or
                json.loads(bundle.read('source-license-inventory.json')) != expected_licenses or
                bundle.read(policy.CHROMIUM_LICENSE_PATH) != policy.chromium_license_bytes()):
            raise SystemExit('Native SDK Chromium headers omit their pinned original root license')

def seal(*, for_publication=True):
    directory = ROOT / "release"
    required_assets(directory, for_publication=for_publication)
    manifest={"component":COMPONENT,"version":local_version(),"repository":REPO,"revision":SHA,"api_major":1,"rc_tag":TAG,
              "verification_stage": "verified" if for_publication else "prepared"}
    (directory/'release-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if COMPONENT == 'server':
        records = [json.loads((directory/f'image-{name}.json').read_text(encoding="utf-8")) for name in ('control-center','traffic-gateway')]
        lines = ['services:']
        for record in records:
            lines += [f"  {record['name']}:", f"    image: {record['image']}@{record['digest']}"]
        (directory/'compose.release.yaml').write_text('\n'.join(lines)+'\n')
    lines=[]
    for path in sorted(directory.iterdir()):
        if path.is_file() and path.name not in ('SHA256SUMS.txt','SHA256SUMS.txt.sigstore.json'):
            lines.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
    (directory/'SHA256SUMS.txt').write_text(''.join(lines), encoding='utf-8')

def verify_sealed_files(directory):
    listed = set()
    for line in (directory/'SHA256SUMS.txt').read_text(encoding="utf-8").splitlines():
        checksum, name = line.split('  ',1)
        if Path(name).name != name or not re.fullmatch(r'[a-f0-9]{64}',checksum):
            raise SystemExit('Invalid checksum manifest path or hash')
        if name in listed:
            raise SystemExit('Duplicate checksum manifest entry')
        if hashlib.sha256((directory/name).read_bytes()).hexdigest() != checksum:
            raise SystemExit(f'Checksum mismatch: {name}')
        listed.add(name)
    actual={p.name for p in directory.iterdir() if p.is_file()}-{'SHA256SUMS.txt','SHA256SUMS.txt.sigstore.json'}
    if actual != listed:
        raise SystemExit('Unsealed or missing release assets')


def verify(directory, rc_tag):
    identity = f"https://github.com/{REPO}/.github/workflows/release.yml@refs/tags/{rc_tag}"
    run("cosign","verify-blob","--bundle",str(directory/'SHA256SUMS.txt.sigstore.json'),
        "--certificate-identity",identity,"--certificate-oidc-issuer","https://token.actions.githubusercontent.com",str(directory/'SHA256SUMS.txt'))
    verify_sealed_files(directory)
    manifest=json.loads((directory/'release-manifest.json').read_text(encoding="utf-8"))
    for key,value in {'repository':REPO,'revision':SHA,'version':local_version(),'component':COMPONENT,'rc_tag':rc_tag,'verification_stage':'verified'}.items():
        if manifest.get(key)!=value: raise SystemExit(f'Release manifest mismatch: {key}')
    required_assets(directory)
    return identity


def import_native_acceptance():
    raise SystemExit("Inline acceptance was removed; import the pinned candidate and reviewed hub receipts")


def android_controller_sdk_assets(version):
    """Sealed client assets for both production Android controller ABIs."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("android_sdk_assets", ROOT / "scripts/package-remote-android-sdk.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.release_asset_names(version)

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
            record=json.loads((directory/f'image-{name}.json').read_text(encoding="utf-8"))
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
    elif action=='candidate-metadata': candidate_metadata()
    elif action in ('prepare', 'candidate-seal'): seal_candidate()
    elif action=='import-native-acceptance': import_native_acceptance()
    elif action=='seal': seal()
    elif action=='rc': publish()
    elif action=='stable': publish(stable=True)
    else: raise SystemExit('Unknown release action')
