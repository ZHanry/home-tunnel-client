# API v1.2.0 candidate

Vendored from `ZHanry/home-tunnel-server`, immutable tag `api-v1.2.0-rc.1`,
commit `9c54212b91d3bfac24aa5af4863dd2f8649fa5fe`. The remote annotated tag was
resolved to that checked main commit before import. `lock.json` records the
source revision and every actual SHA-256. Run `python scripts/check-repository.py`
after changes.

`openapi.v1.json` describes REST requests and responses, `api.schema.json` provides
JSON Schema 2020-12 types, and the unchanged `home-tunnel.v1.json` describes sync
and realtime envelopes. API tags and historical release tags must never move.

The 8.0 candidate retains 7.0 tunnel compatibility; remote desktop requires the
new capability discovery, signed authority and protocol. Paginated device/connection catalogs,
MFA, enrollment, metadata and batch operations are covered by consumer tests.
Unknown capabilities and errors must fail safely. See the server's docs/API.md.
