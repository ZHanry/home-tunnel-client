# Desktop host control plane

This package owns the explicitly enabled host endpoint, account reauthentication,
DPoP REST/WSS signaling, local pairing approval, signed grants, lease renewal and
native shutdown acknowledgments. `UnavailableEngine` fails closed. Registration
and enabling require a native engine whose capabilities report `available` and
`ready`; Go control-plane tests do not establish working capture or media.

The endpoint private key, initial server trust pin, verified keyset chain and
local revocation tombstones use Windows DPAPI, macOS Keychain or Linux Secret
Service. Linux requires `secret-tool` and an unlocked Secret Service session.
Account passwords and management/online tokens are not persisted. There is no
plaintext remote-desktop key fallback for headless NAS installations.

The UI calls `InitialKeyset` to preview public origin/instance/key information,
then approves that exact pin through `Config.InitialTrust` during enrollment.
It consumes `Approvals()` events: `pairing` requests local approval,
`pairing_display` retains the comparison code until the controller confirms,
`pairing_complete` removes the completed pairing. The exact one-session request
bound into a locally approved grant can start automatically; a failed automatic
start falls back to a visible `session` decision. A locally generated temporary
assistance password also auto-approves one cross-account pairing for `view` and
standard keyboard, pointer, text input and text clipboard; file and audio scopes require a visible
local decision. Revoking the invitation tombstones its local grants before the
network request. Only the invitation ID and expiry persist in the OS-protected
store across restart; the temporary password is never stored locally.
The stable nine-digit access ID supports a single host-approved request or an
Argon2id fixed password usable by any authenticated account on this server.
Both paths yield a short-lived, single-pairing invitation and reuse the signed
cross-account grant/session checks. The host persists a request approval before
activating it for the controller. Fixed-password pairing checks the current
profile revision; changing or disabling the password tombstones local grants
before notifying the server. The Windows tray process registers a configurable
Ctrl+Alt+Shift+X/Q/F12 emergency shortcut that locally closes the native session
and disables the host before waiting for network acknowledgement.
Persistent grants require a separate local administrator check before the host
enables unattended access or binds a controller. The binding is the signed
grant's exact endpoint ID and public-key thumbprint. Disabling unattended
access tombstones every persistent grant locally before any network request,
stops an active persistent session, and publishes the disabled capability.
The native engine must independently report unattended support; the current
production worker reports false, so this policy cannot be enabled yet.

`HostEngine.PrepareSession` must retain its own ephemeral key, DTLS fingerprint
and nonce. `Start` receives the original ticket, lease, host grant, protected
initial pin and keyset chain alongside expected participant/request/grant/display
bindings. Native code must independently verify them and compare the prepared
echo against its own state. Go never supplies a trusted/authenticated Boolean.
`verified_ready` is accepted only from native after peer-proof and selected UDP
path verification. Closing wins against concurrent approval and enabling; only
native `closed`, or the owning adapter's OS-confirmed exit of the entire native
producer after IPC failure, may acknowledge stopped media and release a leased
session slot. Pipe closure, signaling loss and unconfirmed process-wait errors
never establish stopped media. The independent input-release guard retains any
release debt. Exact signed close acknowledgments (including sequence zero when
approval is in flight) persist with the protected identity before HTTP waits.
Replacement host services retry them before advertising online, and reconcile a
concurrent decision/renewal only within the stopped epoch. HTTP 429, server errors
and network failures retain the debt. A disk-write error is reported while the
shared Store retains the proof for an in-process worker replacement.

Locally owned shutdown uses existing epoch/version-bound failure reports or
signed pending-session rejection, never an epoch-unbound `/close` request. Even
a delayed HTTP request from an old worker generation cannot close a replacement.
Only native closed or verified process exit supplies a stopped acknowledgment;
a failure report, timeout or cancellation does not release leased server slots.

The protected store's optional `close_acks` field is bounded to 64 exact signed
records and omitted when empty. Older clients with strict store schemas cannot
read an identity while this new field is present: settle outstanding debt with
the repaired version before rollback. Do not delete the identity or pending
proofs to bypass this fail-closed compatibility check.

Run package and race regressions with:

```powershell
go test -race ./internal/remotehost ./internal/realtime
```

For real backend protocol integration, build `control-center` in a sibling
`home-tunnel-server` checkout, select its supported Node runtime, then run:

```powershell
$env:HT_SERVER_ROOT = 'D:\home-tunnel\repos\home-tunnel-server'
go test -race ./internal/remotehost -run TestRealControlCenterInterop -count=1
```

The fixture starts an ephemeral loopback HTTP/WSS control center with an
in-memory SQLite database and randomly generated fixture keys. It checks real
enrollment, DPoP, pairing comparison, signed grant/authority bindings, exact peer
envelopes, readiness, renewal, reconnect and slot retention until native close.
It also forces a crashed producer’s close-ack to fail with HTTP 503, reopens the
protected identity in a replacement host Service, and verifies that replay frees
the old slots before a fresh pairing on that same endpoint.
Its fake engine is defined only in `_test.go`; it makes no claim about real
media, public-network direct paths or platform permissions. Without
`HT_SERVER_ROOT`, only this cross-repository test is skipped.
