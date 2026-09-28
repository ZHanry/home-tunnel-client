# API v1.4.0

Vendored from `ZHanry/home-tunnel-server` contract `api-v1.4.0`. `lock.json`
(REST) and `remote.lock.json` (remote desktop) record the exact server revision,
contract status and SHA-256 values; run `python scripts/check-repository.py`
after changes. Import with `scripts/import-remote-contract.py`; pass
`--published-ref api-v1.4.0` once the server tag exists so both locks record
`frozen`. Formal publication rejects a `proposed` contract.

`openapi.v1.json` describes REST requests and responses, `api.schema.json` provides
JSON Schema 2020-12 types, and `home-tunnel.v1.json` describes sync and realtime
envelopes. API tags and historical release tags must never move.

Existing tunnels keep 7.0 compatibility; remote desktop requires capability
discovery, signed authority and the remote protocol. Unknown capabilities and
errors must fail safely. See the server's docs/API.md.
