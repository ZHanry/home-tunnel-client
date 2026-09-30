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
