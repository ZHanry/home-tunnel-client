# Bounded Windows candidate validation

The `Validate sealed Windows candidate` workflow first performs the required
post-seal Defender rescan, then runs the existing client
`scripts/test-remote-native.mjs` against the original sealed 10.1.0 worker.
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

The candidate identity is committed in [final-candidate-10.1.json](../tests/remote-native/final-candidate-10.1.json).
The [paired candidate guide](V10_1_PAIRED_CANDIDATE_TEST_GUIDE.md) describes the
separate environment and remaining verification work.

## Explicit bounded stability mode

The workflow dispatch input `validation_scope=stability` runs a separate strict
acceptance phase against the **same originally sealed worker bytes**. Pull
requests and the default `short` dispatch remain the two short cases. The job
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
