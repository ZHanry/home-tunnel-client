# Bounded Windows candidate validation

The `Validate sealed Windows candidate` workflow first performs the required
post-seal Defender rescan, then runs the existing client
`scripts/test-remote-native.mjs` against the selected sealed 10.1.0 worker.
The reviewed QA harness is recorded separately and receives an explicit clean
candidate source root. Website checks use real rendering, decoded-frame and
playback-time progression, native input evidence and UDP/DTLS statistics rather
than localized status labels. Candidate application source remains unchanged.
It is additional candidate evidence, not a publication or full acceptance gate.
The stable download records remain unchanged.

## Post-seal Windows security check

Before any native runtime case, the workflow verifies the complete original
candidate artifact and copies the unchanged installer, portable ZIP and four PE
payloads into new scan staging. It invokes the pinned candidate's unchanged
`packaging/windows/scan-release.ps1 -UpdateSignatures`. Defender must already be
running with antivirus protection enabled. The child environment disables the
scanner's CI service-management branch; no service/startup, protection,
exclusion, remediation or security settings are changed.

The new `windows-final-defender-scan.json` must pass the existing
`release.verify_windows_evidence` validator, identify the exact package revision,
follow candidate creation strictly, and match every original subject hash. The
original build-time scan remains unchanged. The validation receipt separately
records the actual QA workflow source/run. Publication must recheck the scan's
one-day freshness limit rather than treating it as permanently valid.

The `windows-final-defender-<run>-<attempt>` artifact is uploaded before native
cases. Its result remains independently available if a later runtime case fails
or cannot run. A missing/inactive Defender installation blocks scanning without
attempting service or security-setting changes.

## Bounded native cases

1. Same-account real UDP/DTLS video, native keyboard/pointer/Unicode input,
   stale-input-epoch rejection, heartbeat release, worker-crash release, and
   bidirectional empty and approximately 1 MiB fixture files with byte/hash checks
2. Temporary-password assistance through the production website on private
   loopback HTTPS/WSS, with continuing video and confined native input

The cases run serially on one disposable Windows 2022 runner. Each case has a
10-minute hard cap. The workflow uses read-only contents/actions access, pinned
actions and tools, fixed clean client/server checkouts, and the original client
download verifier. The sealed ZIP, manifest, native provenance and worker digest
must all agree before execution. The worker is never rebuilt; it is checked again
after each case. Source cleanliness and package immutability are also rechecked.

The fixture builds only the test host and server JavaScript. It creates disposable
accounts and files, binds to IPv4 loopback, and confines native input to its own
target browser process. Its short-lived HTTPS certificate stays in a temporary
directory and is trusted only by the existing test context and host client.
It is never installed in the Windows root store. No firewall or security settings
are changed. Each harness cleans up its processes, state, keys and fixture files.

## Evidence and limits

The run retains the separate Defender artifact and
`windows-final-native-<run>-<attempt>` for 30 days. It includes
`validation.json`, each original `report.json`, sanitized harness summaries,
candidate identity and verification receipts. No passwords, private keys,
account tokens, SDP, network addresses, desktop recordings or existing user
files are retained. A failed or unavailable desktop is reported honestly.

This cannot establish Windows-to-Windows or Android sessions, cross-network NAT
traversal, real user-facing file pickers, lock/login/UAC desktops, audio,
clipboard, or two-hour activity. The user explicitly excluded 24-hour stability
testing from this task; it is not run or claimed as passed. Server
images are not executed by this workflow. Further real-device testing must use
the same sealed packages and the matching pinned server.

The historical candidate identity remains committed unchanged in
[final-candidate-10.1.json](../tests/remote-native/final-candidate-10.1.json).
The [paired candidate guide](V10_1_PAIRED_CANDIDATE_TEST_GUIDE.md) describes the
separate environment and remaining verification work.

## Rebuilding and selecting repaired bytes

The workflow's `candidate_identity` selects only two reviewed pin filenames:
`original-10.1` selects the historical file above; `repaired-10.1` selects
`tests/remote-native/repaired-candidate-10.1.json`. Pull requests always select
the repaired identity, and dispatch defaults to it. An absent repaired pin
**fails validation**. There is no automatic fallback, latest-run lookup, skipped
probe, or passing status derived from the historical package.

1. Finish the product repair and applicable local checks on a clean branch.
   Dispatch **Release client** (`release.yml`) on that branch with
   `candidate=true` and `revision=<exact 40-character branch SHA>`. Keep source
   version `10.1.0`. This builds and seals a new untagged candidate, not a public
   release; leave all publication-only inputs empty.
2. Wait for the complete build to succeed, including Windows packaging, native
   UI regression, Defender, installation, signatures, attestations, and sealing.
   Record the actual run ID/attempt and `candidate-assets` artifact ID/SHA-256.
   Do not use a Windows CI package or partial build as a sealed candidate.
3. Add the new reviewed `repaired-candidate-10.1.json` with the same strict schema
   as the historical pin, exact repaired source SHA, manifest's server SHA,
   version `10.1.0`, run ID/attempt and artifact ID/digest. The new revision,
   run, artifact and artifact digest must all differ from the historical ones.
   Never replace the historical pin, package or failed evidence. The pin commit
   follows the sealed build commit; the candidate does not need to contain its
   own subsequently recorded artifact ID.
4. Pull-request validation resolves that pin before checking out client/server
   source, downloads the immutable artifact with the candidate's existing
   verifier, verifies signatures and run-bound attestations, and checks the
   download receipt's exact run attempt and identity against the pin. It then
   rescans and executes the bounded restart probe and both short native cases.
   Explicit `candidate_identity=original-10.1` remains available to reproduce
   the historical result. Explicit `validation_scope=restart-probe` selects
   only the rescan and bounded recovery case; it does not run a long soak.

Every validation artifact includes `selected-candidate-pin.json`, recording
the selected identity and pin-file digest. Same-version filenames alone never
identify the repaired package: use its source SHA, build run and sealed hashes.
The source lock and candidate manifest must agree on the server revision; this
workflow does not silently overlay a different server or rewrite frozen tags.

The native worker executable is extracted from the verified new ZIP and is
never rebuilt during validation. The QA Go host is compiled using that
candidate's actual production Go packages. Its existing overlay replaces only
the opt-in test host file for fixture lifetime/identity reuse; it does not replace
`internal/remotehost`, `internal/remoteengine` or packaged worker bytes. This is
sealed-worker plus pinned-production-source recovery evidence, not a claim that
the packaged GUI or service executable itself performed the restart.

Historical run `36711184781` retains its overall **failed** outcome: its original
worker completed 30 sessions and 7200.6602421 seconds of active media/input
(1391 raw samples), then failed at post-crash restart. Those partial successes
remain historical coverage for candidate run `36696397157`; they do not become
a repaired-candidate two-hour pass. No 24-hour test is run or claimed.

## Explicit bounded stability mode

The workflow dispatch input `validation_scope=stability` runs a separate strict
acceptance phase against the **selected sealed worker bytes**. Pull requests
run the bounded restart probe and two short cases; a `short` dispatch runs the
two short cases. The job
has a 300-minute ceiling, the native subprocess a hard 10800-second ceiling,
and the native step 185 minutes. The wrapper kills only its owned process tree
on timeout and uploads the partial sanitized observations on failure.

The strict command uses `--phase stability` and `--stability 30x7200`; neither
accepts a shorter duration or a smaller connection target:

1. Create 29 distinct, real, same-account sessions using signed pairing, local
   approval, a live UDP/DTLS video path, and fresh trusted native keyboard and
   pointer events. Each must close cleanly. Start pairings at least 15 seconds
   apart without changing the production 5/minute and 30/hour session limits.
2. Establish the 30th session and keep it actively observed for at least 7200
   actual monotonic seconds. Every approximately five seconds, require newly
   presented/decoded/encoded frames, media-time and byte progression, increased
   native accepted-input counts, and four fresh trusted key/pointer events in
   the confined target process. Gaps above 15 seconds, wall-clock anomalies,
   counter regressions, missing activity, or lost authentication fail closed.
3. Require actual remote lease-sequence and controller signaling-token renewal
   progression. Production lease duration and renewal logic are unchanged.
4. Verify heartbeat-stop and worker-crash input release at most 2000 ms. After
   the two-hour observation has moved the original sessions outside the hourly
   limit, separately measure an explicit owned-host restart plus new signed
   pairing and live input at most 30000 ms after the crash. This is an explicit
   test-host restart, not automatic production restart or network restoration.

The 30-session count excludes the additional intentional crash and recovered
sessions. Individual `fresh_pairing_to_*_ms` values begin at the new pairing
attempt and exclude the intentional rate-limit pacing. Only distinct sessions
with verified media, trusted input and clean shutdown count toward 30/30.

The long phase builds only the existing Go **test host**, using a Go overlay
whose QA source hash is retained separately. It extends the opt-in test-host
lifetime and one-session test grant from four/three minutes to three hours and
lets the explicit restart reuse its disposable fixture identity. The original
client checkout and production worker are never edited or rebuilt. The private
loopback fixture uses `ACCESS_TOKEN_SECONDS=10800`; its disposable account
credential stays in memory/private process pipes and is never an artifact.
The three-hour one-session grant and account-token lifetimes are stated in the
report. Server source, rate limits, remote leases, security settings, trust,
firewall policy and production defaults remain unchanged.

Raw `stability-samples.jsonl`, per-connection `stability-connections.json`, and
`report.json` are retained with hashes in `validation.json`, including partial
results on failure. These prove the explicitly stated same-machine native
worker/Chromium fixture scope only. They do **not** establish full GUI two-hour
acceptance, independent Windows endpoints, website/cross-account two-hour
stability, account-token refresh, a controlled network-outage recovery, or
24-hour idle stability. `network_restore_30s` stays `not_verified`.

## Bounded post-crash restart probe

`validation_scope=restart-probe` / `--phase restart-probe` diagnoses the same
owned-host restart path independently. Every eligible pull request also runs it
before the unchanged short cases, in its own step with a separate
`windows-restart-probe-*` artifact. The native subprocess is capped at **600
seconds**; the step allows 13 minutes for wrapper setup, owned-tree cleanup and
failure reporting. The short cases keep their own original 25-minute step and
still run after a probe failure when dependency setup succeeded.

The probe creates one real signed session, verifies native media, holds actual
confined keyboard/pointer input, kills only the worker owned by the test host,
and measures release. It then follows the exact existing same-identity host
restart, new signed pairing, live media, fresh trusted input and clean-close
path. Before stopping the crashed host, it observes the exact crashed session
through the production read-only session API and requires server state `closed`
and host idle within the bounded acknowledgement observation. `closing`, local
UI teardown, swallowed close errors, and eventual lease expiration cannot pass.
The recovered session must also be server-closed and host-idle. These checks do
not submit additional cleanup calls or retry session creation. The three-hour
disposable fixture policy and hashed QA host overlay are
retained for identical restart semantics; the wrapper's ten-minute bound is
unchanged. No product worker is rebuilt and no deployed account is used.

The report is classified as `restart_probe`, never `stability`. It cannot supply
30-session or 7200-second acceptance evidence, account-token refresh, automatic
product restart, or network-outage recovery. Original failed-run evidence stays
unchanged. Restart awaits have distinct substages. Failure details add only a
fixed exception-type label and allowlisted source basenames with numeric
line/column coordinates; raw error messages/stacks, URLs, credentials and
fixture content are not retained.
