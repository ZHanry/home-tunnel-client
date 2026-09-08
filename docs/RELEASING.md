# Independent client releases

Published 5.0.0 artifacts remain in the original project. The first release from this
repository must use a new version greater than 5.0.0. Do not overwrite historical tags
or replace already distributed binaries.

## Release steps

1. Update this component's source version and changelog. Leave sibling component versions alone.
2. Update the compatibility record when new version pairs have passed integration tests.
3. Merge to `main` and wait for its **Quality Gate** and security checks to pass.
4. Tag that commit `vX.Y.Z-rc.N` and push the tag. `release.yml` builds the complete component
   matrix once, retaining existing checksums, SBOMs and signing/provenance steps.
5. Verify the published RC on supported real devices. Tag the exact same commit `vX.Y.Z`.
   Stable verifies the RC manifest's identity, revision and every asset checksum, then
   publishes those identical bytes. It does not rebuild or replace an existing release.

The aggregate checksum manifest is signed with GitHub OIDC. Verify it against this
repository's `release.yml` identity and the **RC tag** recorded in `release-manifest.json`,
including when downloading a stable release. Do not verify against the former monorepo
workflow identity for newly built artifacts.

Component versions are independent. API v1 is the current protocol boundary, not a
guarantee that arbitrary future versions interoperate. Record and test supported pairs.

## Client specifics

Update `internal/model/model.go` and packaging version defaults together. The managed
Agent has its own reviewed version in `agent/build-agent.ps1`; only change it when
changing/rebuilding the Agent and verify its resource version and expected hash.

The client updater now reads `ZHanry/home-tunnel-client/releases/latest`. After a stable
client release, run the hub's `Mirror stable client release` workflow with the new version
to preserve updates for installed 5.0.0 clients. The mirror keeps legacy 5.0.0 assets
available for servers that link to fixed filenames under the old latest endpoint.
