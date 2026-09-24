# API v1.3.0

Vendored from the immutable `ZHanry/home-tunnel-server` tag `api-v1.3.0`.
`lock.json` records the reviewed source revision and SHA-256 values; run
`python scripts/check-repository.py` after changes.

`openapi.v1.json` describes REST requests and responses, `api.schema.json` provides
JSON Schema 2020-12 types, and the unchanged `home-tunnel.v1.json` describes sync
and realtime envelopes. API tags and historical release tags must never move.

The 8.0 release retains 7.0 tunnel compatibility; remote desktop requires the
new capability discovery, signed authority and protocol. Paginated device/connection catalogs,
MFA, enrollment, metadata and batch operations are covered by consumer tests.
Unknown capabilities and errors must fail safely. See the server's docs/API.md.
