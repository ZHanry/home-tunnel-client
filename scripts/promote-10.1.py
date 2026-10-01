"""One-version dispatch wrapper; all existing candidate/publication gates still run."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

REPO = 'ZHanry/home-tunnel-client'
SOURCE = '41c0e21fbb3a4c634fbc9d63fcd7453337e4d029'
ACCEPTANCE = '558a103e13d25e9ac11720d15f925c792b2fc954'
TAG = 'v10.1.0'


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True, timeout=120)


def api(path):
    return json.loads(gh('api', f'repos/{REPO}/{path}'))


def main():
    if os.environ.get('GITHUB_REPOSITORY') != REPO or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise SystemExit('This reviewed dispatch wrapper runs only on the client main branch')
    notes = Path('docs/RELEASE_10_1_STABLE.md')
    if not notes.is_file() or not notes.read_text().startswith('# Home Tunnel Client 10.1.0\n'):
        raise SystemExit('Missing reviewed 10.1 publication notes')
    refs = api('git/matching-refs/tags/' + TAG)
    existing = [item for item in refs if item['ref'] == 'refs/tags/' + TAG]
    if existing:
        if len(existing) != 1 or existing[0]['object'] != {'sha': SOURCE, 'type': 'commit', 'url': f'https://api.github.com/repos/{REPO}/git/commits/{SOURCE}'}:
            raise SystemExit('Existing stable tag does not identify the accepted source; never move it')
    else:
        gh('api', '--method', 'POST', f'repos/{REPO}/git/refs', '-f', 'ref=refs/tags/' + TAG, '-f', 'sha=' + SOURCE)
    # No build, source rewrite or acceptance-policy change happens here.
    # The tagged workflow performs every original source, CI, artifact, signature,
    # attestation, Windows security and reviewed-receipt check before publication.
    started = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    gh('workflow', 'run', 'release.yml', '--repo', REPO, '--ref', TAG,
       '-f', 'candidate=false', '-f', 'revision=', '-f', 'build_run_id=36795202532',
       '-f', 'artifact_id=11135066756',
       '-f', 'artifact_sha256=dbf59ff6d73e6e3ce0082a313087f41e26382d8b70324acb8b3a6be1e1c08b62',
       '-f', 'acceptance_revision=' + ACCEPTANCE)
    for _ in range(240):
        runs = api('actions/workflows/release.yml/runs?event=workflow_dispatch&head_sha=' + SOURCE + '&per_page=30')['workflow_runs']
        matches = [r for r in runs if r['created_at'] >= started and r['head_sha'] == SOURCE and r['head_branch'] == TAG]
        if len(matches) > 1:
            raise SystemExit('Ambiguous publication runs; inspect without republishing')
        if matches:
            run = matches[0]
            print(run['html_url'], run['status'], run['conclusion'], flush=True)
            if run['status'] == 'completed':
                if run['conclusion'] != 'success':
                    raise SystemExit('Existing release verifier did not succeed; no gate was bypassed')
                release = api('releases/tags/' + TAG)
                if release['draft'] or release['prerelease'] or release['target_commitish'] != SOURCE:
                    raise SystemExit('Published release identity differs')
                # Preserve the immutable source docs and every sealed asset. Only the
                # public release body uses the current truthful coverage summary.
                gh('release', 'edit', TAG, '--repo', REPO, '--notes-file', str(notes))
                actual = api('releases/tags/' + TAG)
                if actual['body'].replace('\r\n', '\n').strip() != notes.read_text().strip():
                    raise SystemExit('Published release-note readback differs')
                print('Verified original candidate published with current 10.1 coverage notes', actual['html_url'])
                return
        time.sleep(10)
    raise SystemExit('Publication still pending; inspect the existing run before retrying')


if __name__ == '__main__':
    main()
