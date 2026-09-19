# API v1.1.0

Vendored from `ZHanry/home-tunnel-server`, immutable tag `api-v1.1.0`. `lock.json`
records every SHA-256. Run `python scripts/check-repository.py` after changes.

`openapi.v1.json` describes REST requests and responses, `api.schema.json` provides
JSON Schema 2020-12 types, and the unchanged `home-tunnel.v1.json` describes sync
and realtime envelopes. API tags and historical release tags must never move.

Home Tunnel 7.0 requires a 7.0 server. New paginated device/connection catalogs,
MFA, enrollment, metadata and batch operations are covered by consumer tests.
Unknown capabilities and errors must fail safely. See the server's docs/API.md.
