"""Copy sealed candidate originals into convenient Actions transport artifacts.

This does not build, sign, repackage, accept, or publish a product. The complete
candidate-assets archive remains authoritative for full candidate verification.
"""
import argparse
import json
from pathlib import Path
import shutil

from client_release_candidate import MANIFEST, digest, local_file, read_json, verify_candidate, verify_files

METADATA_FILES = (
    "windows-exe-smoke.json", "windows-defender-scan.json", "windows-installer-smoke.json",
    "windows-platform-signing.json", "agent-provenance.json", "agent-provenance.json.sigstore.json",
    "remote-host-provenance.json", "remote-host-build.json", "remote-source-manifest.json",
    "remote-sdk-provenance.json", "WEBRTC-THIRD-PARTY-NOTICES.md",
)
# Leave ample room for Actions ZIP headers below the 32 MiB retrieval limit.
MAX_METADATA_BYTES = 28 * 1024 * 1024


def stage(source, output, revision, version):
    source, output = source.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(source) or source.is_relative_to(output):
        raise SystemExit("Transport output must be a new directory outside the sealed candidate")
    candidate = verify_candidate(read_json(local_file(source, MANIFEST)), source, revision, version)
    installer = f"HomeTunnel-Setup-{version}-x64.exe"
    portable = f"HomeTunnel-Windows-{version}-x64.zip"
    metadata = set(METADATA_FILES) | {
        installer + ".sigstore.json", portable + ".sigstore.json",
        portable + ".sha256", portable + ".sha256.sigstore.json",
        portable + ".spdx.json", portable + ".spdx.json.sigstore.json",
    }
    if not metadata <= candidate["files"].keys():
        raise SystemExit("Sealed candidate is missing required transport metadata")
    manifest_names = {MANIFEST, MANIFEST + ".sigstore.json"}
    # The inventory and its signature cannot hash themselves. Preserve their
    # exact source bytes; their existing Sigstore/Actions proofs stay separate.
    expected = {name: candidate["files"][name] for name in metadata | {installer, portable}}
    expected.update({name: {"sha256": digest(local_file(source, name)),
                            "bytes": local_file(source, name).stat().st_size} for name in manifest_names})
    if any(expected[name]["bytes"] < 1 for name in manifest_names):
        raise SystemExit("Candidate inventory or its signature is empty")
    if sum(expected[name]["bytes"] for name in metadata | manifest_names) > MAX_METADATA_BYTES:
        raise SystemExit("Candidate metadata exceeds the small transport artifact limit")
    groups = {"metadata": metadata | manifest_names, "windows-installer": {installer},
              "windows-portable": {portable}}
    output.mkdir(parents=True)
    for group, names in groups.items():
        target = output / group
        target.mkdir()
        for name in sorted(names):
            shutil.copyfile(local_file(source, name), target / name)
        verify_files({name: expected[name] for name in names}, target)
    # Detect accidental changes to the sealed originals.
    verify_candidate(read_json(local_file(source, MANIFEST)), source, revision, version)
    verify_files({name: expected[name] for name in manifest_names}, source)
    return {group: {name: expected[name] for name in sorted(names)} for group, names in groups.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    print(json.dumps(stage(args.source, args.output, args.revision, args.version), indent=2))


if __name__ == "__main__":
    main()
