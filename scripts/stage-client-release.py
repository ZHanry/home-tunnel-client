"""Stage only verified candidate subjects and separately reviewed acceptance receipts."""
import argparse
import json
import shutil
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from client_release_candidate import ACCEPTANCE, MANIFEST, digest, local_file, read_json, verify_candidate, verify_acceptance


def stage(source, destination, revision, version):
    if destination.exists():
        raise SystemExit("Release staging requires a new directory")
    candidate_dir, acceptance_dir = source / "candidate", source / "acceptance"
    candidate = read_json(local_file(candidate_dir, MANIFEST))
    acceptance = read_json(local_file(acceptance_dir, ACCEPTANCE))
    downloaded = read_json(local_file(source, "client-candidate-download.json"))
    if (downloaded.get("source_revision") != revision or downloaded.get("signatures_verified") is not True or
            downloaded.get("run_attestations_verified") is not True or not downloaded.get("acceptance_revision") or
            downloaded.get("candidate_sha256") != digest(candidate_dir / MANIFEST)):
        raise SystemExit("Download verification is missing or stale")
    verify_candidate(candidate, candidate_dir, revision, version)
    verify_acceptance(acceptance, acceptance_dir, candidate, digest(candidate_dir / MANIFEST))
    subjects = set(candidate["files"]) | {MANIFEST}
    copies = {name: local_file(candidate_dir, name) for name in subjects | {MANIFEST + ".sigstore.json"}}
    copies.update({name: local_file(acceptance_dir, name) for name in set(acceptance["files"]) | {ACCEPTANCE, "client-acceptance-origin.json"}})
    copies["client-candidate-download.json"] = source / "client-candidate-download.json"
    for name in [MANIFEST, *candidate["packages"]]:
        verification = name + ".verification.json"
        copies[verification] = local_file(source / "verification", verification)
    destination.mkdir(parents=True)
    for name, original in copies.items():
        with original.open("rb") as src, (destination / name).open("xb") as dst:
            shutil.copyfileobj(src, dst)
    verify_candidate(read_json(destination / MANIFEST), destination, revision, version)
    verify_acceptance(read_json(destination / ACCEPTANCE), destination, candidate, digest(destination / MANIFEST))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    stage(args.source, args.output, args.revision, args.version)
    print("Staged the accepted original packages, SBOMs, signatures and acceptance receipts without rebuilding")


if __name__ == "__main__":
    main()
