# Windows native → Chromium acceptance

This opt-in test runs the actual Windows WebRTC worker through `internal/remoteengine` and
`internal/remotehost`, starts a temporary instance of the production control center, and
loads its production browser modules in Chromium. It creates a new account, host identity,
browser identity, signed pairing, grant and approved session on every run. It uses no fake
engine, synthetic media stream, recorded video, persistent account or deployed server.

Requirements: an unlocked interactive Windows desktop, Go from `go.mod`, Node 24, the client
Playwright Chromium installation, a built sibling server checkout (`control-center/dist`),
and a real native worker built from the reviewed source. Pin the expected worker SHA-256
from its build output; the runner does not trust a worker merely because it exists.

```powershell
node scripts/test-remote-native.mjs `
  --worker D:\path\to\home_tunnel_remote_host.exe `
  --sha256 <expected-64-character-sha256> `
  --server-root D:\path\to\home-tunnel-server
```

The default report is `outputs/remote-native-acceptance/report.json`. Exit zero means the
**view-only, same-machine** acceptance passed: native capabilities were ready, both pairing
codes matched, local session approval was bound to its epoch/version, production peer proofs
passed, both endpoints verified direct UDP, Chromium connected DTLS, and real decoded video
frames continued increasing. A missing/unready worker produces `not_verified` and a nonzero
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
The separate target page is reserved for input acceptance. Input stays `not_verified` and
the runner performs **no input injection** until the native engine has a target-window
confinement contract. Audio, clipboard, files and Android remain outside this report's scope.
This report must not be presented as full 8.0 feature acceptance.

The Go helper is guarded by `windows && remote_native_e2e`; ordinary `go test ./...` and the
mock browser UI tests do not execute it or count it as media evidence.
