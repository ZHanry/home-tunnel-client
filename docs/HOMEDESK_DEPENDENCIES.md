# Native dependency review for 11.0.0-rc.1

The imported engine's lockfile predates published Rust security fixes. This
candidate updates compatible dependency versions before building release bytes:

| Dependency | Selected version | Relevant correction |
| --- | --- | --- |
| rustls | 0.23.45 | Current compatible TLS maintenance fixes |
| rustls-webpki | 0.103.15 | Malformed CRL panic and earlier certificate-validation fixes |
| openssl / openssl-sys | 0.10.81 / 0.9.117 | Reported bounds, callback and certificate parsing defects |
| quinn-proto | 0.11.19 | Transport-parameter panic and unbounded stream reassembly |
| bytes | 1.12.1 | Reported buffer defects |
| crossbeam-channel | 0.5.17 | Concurrent channel memory-safety correction |
| tracing-subscriber | 0.3.23 | ANSI/log output correction |
| time | 0.3.55 | Reported parsing defect in the 0.3 line |
| url / idna | 2.5.4 / 1.1.0 | Rejected invalid domain-name input |
| rand | 0.8.8 / 0.9.5 | Compatible maintenance fixes |

The exact versions and transitive checksums are in `client/Cargo.lock`. Builds
use the pinned Rust 1.96 toolchain and `--locked`. These changes retain the
original TLS trust verification, encryption and direct-only session policy.
The materials archive includes the resolved dependency sources and target
dependency trees, rather than only an advisory summary.

This is not a claim of a vulnerability-free source tree. GitHub also reports
issues in inherited Linux GUI dependencies (`users`, optional `fuser`, `glib`),
unused lockfile entries such as `libgit2-sys`, and an older workspace member's
standalone lockfile. The release's Windows and Android target graphs do not
include those Linux GUI packages or `libgit2-sys`. The workspace root lockfile
governs the member build; the old member lockfile does not. Linux/macOS native
GUI releases need a separate dependency update and runtime acceptance. The
cross-platform CLI/Agent is built from the independent Go stack.

Advisories and target coverage must be reviewed again for each subsequent
release. Dependency updates and successful builds do not substitute for the
cross-network, sustained-media and physical-device acceptance recorded in
`HOMEDESK_RELEASE.md`.
