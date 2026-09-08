# Security repair and finding review

## Managed dependencies

Both the development Agent module and the FRP build locks select `go-ntlmssp v0.1.1`
and `golang.org/x/crypto v0.56.0`. These address CVE-2026-32952 and the SSH findings
GO-2026-6355, GO-2026-6354 and GO-2026-6303. The package scripts inspect the compiled
module versions and the Windows Agent hash is reproduced in CI.

The Go vulnerability database also identifies the discontinued OpenPGP package
inside the crypto module (GO-2026-5932, no fixed version). The client does not import
or link that package. Builds explicitly reject an OpenPGP dependency. An informational
module-level result must not be confused with a reachable package or symbol finding.

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

## Logging

Remote API error messages and malformed-response values are not stringified into
ordinary logs. CLI failures select fixed, actionable error categories. Regression
tests include password-like data returned by an untrusted server.
