# Windows native → Chromium acceptance

This opt-in test runs the actual Windows WebRTC worker through `internal/remoteengine` and
`internal/remotehost`, starts a temporary instance of the production control center, and
loads its production browser modules in Chromium. It creates a new account, host identity,
browser identity, signed pairing, grant and approved session on every run. It uses no fake
engine, synthetic media stream, recorded video, persistent account or deployed server.

Requirements: an unlocked interactive Windows desktop without system screen pickers or
overlays, Go from `go.mod`, Node 24, pnpm, the client Playwright Chromium installation,
a clean server checkout at `server-lock.json` with its frozen dependencies installed,
and a real native worker built from the reviewed source. The runner removes only the
server's generated `control-center/dist`, performs a fresh production build and records its
file-tree hash. Dirty or mismatched server source fails before any worker starts.
Pin the expected worker SHA-256
from its build output; the runner does not trust a worker merely because it exists.

```powershell
node scripts/test-remote-native.mjs `
  --worker D:\path\to\home_tunnel_remote_host.exe `
  --sha256 <expected-64-character-sha256> `
  --server-root D:\path\to\home-tunnel-server
```

Add `--input chromium` to verify keyboard down/up, Unicode text and pointer buttons in a
second, dedicated Chromium process. The runner passes that process ID through the opt-in
test host configuration. The native worker checks the foreground window belongs to that
process before new key/button presses, pointer movement and text, and confines pointer
coordinates to its client area. Releases remain independent of foreground focus so losing
focus cannot leave a key or button held.
The controller remains in a separate browser process. The test checks actual trusted DOM
events and exact Unicode field contents in the target page. It then rejects an old input
epoch, proves current input still works, and holds a real key while withholding browser
input heartbeats. The release must be observed within 2000 ms of the trusted keydown.
After a normal session closure, a second signed pairing and approved session holds both a
key and a mouse button, then terminates only the exact worker process owned by the Go
adapter. Both trusted release events must arrive within 2000 ms of the pre-termination
target-page clock reading. The independent release guard is never terminated by the test.
A missing capability, obscured target, lost focus, absent input event or slow release fails
the requested run. Setup uses a CDP event probe only to check target instrumentation; those
events are cleared before actual native measurements and cannot count as passing evidence.

The default report is `outputs/remote-native-acceptance/report.json`. Exit zero and
`status: "passed"` mean the requested **same-machine** acceptance passed: native capabilities were ready, both pairing
codes matched, local session approval was bound to its epoch/version, production peer proofs
passed, both endpoints verified direct UDP, Chromium connected DTLS, and real decoded video
frames continued increasing. An input run additionally requires `input.status: "passed"`
and actual keyboard, pointer, Unicode, stale-epoch, heartbeat-watchdog and worker-crash
evidence. Reports bind source commits and the exact worker SHA-256; release validation also
requires the client checkout to be clean and the worker bytes to match the signed artifact.
A missing/unready worker produces `not_verified` and a nonzero
exit. Later protocol/media failures produce `failed`, never a pass or a skipped test.

The fixture binds only `127.0.0.1` on a random port and enables the Go service's existing
explicit `AllowInsecureLoopback` test flag. Chromium treats loopback as a secure context.
Production HTTPS validation is unchanged; this run does **not** validate deployed HTTPS/WSS,
cross-network NAT traversal or relay rejection on an adversarial network. Temporary account
tokens pass only through inherited process pipes and browser evaluation, never command-line
arguments or reports. The host store uses the real Windows protection layer. All processes,
keys, protected state and the temporary server are disposed at the end.

No screenshots, recordings, SDP, candidate addresses, JWTs, keys or passwords are written to
the report. Real desktop pixels do traverse this local test session; run on a test desktop.
Without `--input chromium`, input stays `not_verified` and the runner performs no injection.
Audio, clipboard and Android remain outside this report's scope.

Add `--files fixture` for actual bidirectional file DataChannel acceptance. The runner
creates empty and multi-chunk files only in its temporary directory, grants both file
permissions through the real signed pairing, and explicitly enables both features. A
test-only local selector calls the production Go consent service; the browser writes
to its real origin-private filesystem. Both receivers must save the exact byte count
and SHA-256, the sender must receive completion acknowledgments, and video must continue
after the file features are disabled. This proves the actual native/browser transfer
path and disk writes, **not** the Windows or browser user-facing file picker. No existing
user files or clipboard content are read. The fixture selector is compiled only with
`windows && remote_native_e2e` and accepts only fixed generated filenames.

Use `--codec H264` or `--codec VP8` for separate baseline codec acceptance. The
isolated browser page constrains its real video transceiver to that codec (H.264
uses constrained baseline `42e01f`, packetization mode 1). The report requires
actual browser decode statistics and matching native encoder statistics. This
does not mock the media path or establish hardware encoding. Omit the option to
exercise normal product negotiation.
This report must not be presented as full 8.0 feature acceptance.

The Go helper is guarded by `windows && remote_native_e2e`; ordinary `go test ./...` and the
mock browser UI tests do not execute it or count it as media evidence.

Run `node --test tests/remote-native/policy.test.mjs` for the negative preflight checks.
Those tests cannot substitute for the real native acceptance command.
