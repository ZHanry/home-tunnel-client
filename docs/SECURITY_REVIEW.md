# Security repair and finding review

## Managed dependencies

The 14.0.0 desktop helper and browser P2P module select `golang.org/x/crypto v0.57.0`,
`golang.org/x/net v0.60.0` and their required `golang.org/x/sys v0.48.0`.
The independent Agent module and FRP build locks also select `go-ntlmssp v0.1.1`
and `golang.org/x/crypto v0.57.0`. These address CVE-2026-32952 and the SSH findings
GO-2026-6355, GO-2026-6354 and GO-2026-6303. The package scripts inspect the compiled
module versions and the Windows Agent hash is reproduced in CI.

The Go vulnerability database also identifies the discontinued OpenPGP package
inside the crypto module (GO-2026-5932, no fixed version). The client does not import
or link that package. Builds explicitly reject an OpenPGP dependency. An informational
module-level result must not be confused with a reachable package or symbol finding.

The browser-test dependency lock selects `brace-expansion 5.0.12`, which repairs
GHSA-q2hr-2g5m-vwhr. This tooling is excluded from installed client packages.

The build and CodeQL workflows select Go 1.27.2. Its standard-library repairs and
the `x/net v0.60.0` HTTP/2 repairs cover the October 2026 advisory set
GO-2026-6599 through GO-2026-6617. Symbol-level `govulncheck` is run against the
actual helper and Agent packages; module-only OpenPGP findings remain subject to
the excluded-package check above.

## Local management boundary

The desktop interface requires a random per-launch token for every `/local/` API.
The token is passed to the native window through its URL fragment and kept in a
private same-user session file for singleton signaling; it is not included in public
HTML or routine logs. The server checks literal-loopback Host, loopback peer,
browser Origin and fetch metadata, JSON mutation requests and frame isolation.

`internal/gui/local_security_test.go` covers cross-site requests, DNS rebinding,
different sessions, native singleton requests and private token lifecycle.

## User-selected control-center origin

`api.Discover` is expected to contact the HTTPS server chosen by the local owner.
Both public and private self-hosted addresses must be supported. The CLI runs with
that owner's authority; the embedded HTTP interface requires the private desktop
session before settings can reach this function. It is not a public server fetching
arbitrary URLs on behalf of remote users.

The generic CodeQL `go/request-forgery` finding at this connection-setup call is
therefore reviewed as a false positive for this authority model. This classification
does not suppress the rule or allow another caller to bypass the local boundary.
`internal/api/security_test.go` covers redirect rejection with injected transports,
credential replay prevention, API-origin/path escapes and reflected secret errors.
Changing the callers or exposing this functionality remotely requires a fresh review.

## User-selected local service diagnostic

`POST /local/connection-check` is an explicit desktop-user operation that checks a
service before publishing a tunnel. Loopback and private LAN targets are required
features. The request originates on the user's computer under the local management
boundary above; an enrolled device is also required. It does not originate from the
public control center and cannot be invoked using another user's server session.

The endpoint accepts at most 4 KiB of strict JSON: a hostname or IP address, a bounded
port, a fixed transport and an HTTP/HTTPS scheme. It rejects URL syntax, credentials,
unknown fields and extra JSON values. HTTP uses an unauthenticated HEAD request,
ignores environment proxies, does not follow redirects, verifies TLS certificates
and has a three-second deadline. TCP checks only whether the port accepts a
connection. UDP remains a manual application-level check, never a synthetic pass.

CodeQL alert #4 (`go/request-forgery`, the HEAD call in
`internal/diagnostics/doctor.go`, source `0eecacc803b39f3a8d53c778c4abdc3502cd07c6`)
was reviewed as a false positive for this deliberately authorized local diagnostic.
The rule, queries and quality gate remain enabled. `tunnel_check_test.go` covers
enrollment, input limits, redirect and credential behavior, UDP and TLS failures.
`tunnel_check_trust_test.go` uses a real listening target to verify that ten hostile
request variants cause zero target connections, followed by an authorized request
that performs the expected HEAD. It covers rebinding, remote peers, foreign/local/
opaque origins, cross-site metadata, missing/wrong tokens, forms and wrong methods.

Public exposure, removal of desktop-session checks, ambient credentials, proxy use
or redirect following would change this authority model and require a fresh review.

## Logging

Remote API error messages and malformed-response values are not stringified into
ordinary logs. CLI failures select fixed, actionable error categories. Regression
tests include password-like data returned by an untrusted server.
