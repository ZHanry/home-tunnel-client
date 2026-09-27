"""Seal both Android controller SDK ABIs as a pre-tag candidate.

The candidate binds the exact source SHA, GitHub Actions run, and archive digests.
It does not create a tag or GitHub Release and does not record device acceptance.
workflow_dispatch is the only Actions event allowed to invoke this seal.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = "android-sdk-candidate.json"
WORKFLOW = ".github/workflows/android-sdk-candidate.yml"
SPEC = importlib.util.spec_from_file_location("android_sdk_package", ROOT / "scripts/package-remote-android-sdk.py")
SDK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDK)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_clean_dispatch(revision):
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event and event != "workflow_dispatch":
        raise SystemExit("Android SDK candidates are sealed only from a trusted workflow_dispatch")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("Candidate SDK requires the exact source SHA")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    if head != revision or dirty:
        raise SystemExit("Candidate seal requires the exact clean source commit")


def signed_subject(directory, name):
    path = directory / name
    bundle = directory / (name + ".sigstore.json")
    if not path.is_file() or path.stat().st_size < 1 or not bundle.is_file() or not 1 <= bundle.stat().st_size <= 1024 * 1024:
        raise SystemExit(f"Android SDK candidate subject is unsigned or empty: {name}")
    return {"name": name, "sha256": digest(path), "bytes": path.stat().st_size,
            "sigstore_bundle": bundle.name, "sigstore_sha256": digest(bundle)}


def candidate_record(directory, version, revision, run_id, workflow=WORKFLOW):
    if workflow != WORKFLOW:
        raise SystemExit("Candidate SDK workflow identity is not the trusted dispatch workflow")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("Candidate SDK requires the exact source SHA")
    if not re.fullmatch(r"[1-9][0-9]{0,19}", str(run_id)):
        raise SystemExit("Candidate SDK requires the GitHub Actions run ID")
    abis = {}
    for abi in SDK.ENGINE.ABI_ORDER:
        provenance = SDK.verify(directory, version, revision, abi)
        if provenance.get("device_media_accepted") is not False or provenance.get("production_controller") is not True or provenance.get("target") != abi:
            raise SystemExit("Candidate SDK provenance is not a production controller awaiting acceptance")
        archive = SDK.archive_name(version, abi)
        sbom_name = SDK.sbom_name(abi)
        sbom = directory / sbom_name
        if not sbom.is_file() or not 1 <= sbom.stat().st_size <= 32 * 1024 * 1024:
            raise SystemExit("Android SDK candidate SBOM is missing or oversized")
        subjects = [signed_subject(directory, name) for name in (archive, archive + ".sha256", SDK.provenance_name(abi), sbom_name)]
        if subjects[0]["sha256"] != provenance["archive_sha256"]:
            raise SystemExit("Candidate archive digest differs from its provenance")
        abis[abi] = {
            "archive": archive,
            "archive_sha256": provenance["archive_sha256"],
            "archive_bytes": provenance["archive_bytes"],
            "provenance": SDK.provenance_name(abi),
            "provenance_sha256": digest(directory / SDK.provenance_name(abi)),
            "sbom": sbom_name,
            "sbom_sha256": digest(sbom),
            "source_tree_sha256": provenance["source_tree_sha256"],
            "upstream_lock_sha256": provenance["upstream_lock_sha256"],
            "recipe_sha256": provenance["recipe_sha256"],
            "compiler_lock": provenance["compiler_lock"],
            "gn_args": provenance["gn_args"],
            "elf_machine": provenance["elf_machine"],
            "controller_backend_linked": True,
            "production_controller": True,
            "device_media_accepted": False,
            "subjects": subjects,
        }
    if set(abis) != set(SDK.ENGINE.ABI_ORDER):
        raise SystemExit("Candidate SDK must seal both arm64-v8a and x86_64")
    trees = {item["source_tree_sha256"] for item in abis.values()}
    locks = {item["upstream_lock_sha256"] for item in abis.values()}
    if len(trees) != 1 or len(locks) != 1:
        raise SystemExit("Candidate ABIs were not built from the same source and dependency lock")
    return {
        "schema_version": 1,
        "status": "sdk-candidate-device-acceptance-required",
        "verification_stage": "candidate",
        "repository": "ZHanry/home-tunnel-client",
        "source_revision": revision,
        "source_tree_sha256": next(iter(trees)),
        "upstream_lock_sha256": next(iter(locks)),
        "version": version,
        "intended_tag": "v" + version,
        "tag_published": False,
        "stable_release": False,
        "workflow": workflow,
        "workflow_run_id": str(run_id),
        "device_media_accepted": False,
        "native_device_acceptance": "not_run",
        "abis": abis,
    }


def write_candidate(directory, record):
    path = directory / CANDIDATE
    if path.exists():
        raise SystemExit("Existing Android SDK candidate evidence is never overwritten")
    path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--workflow", default=WORKFLOW)
    args = parser.parse_args()
    require_clean_dispatch(args.revision)
    record = candidate_record(args.output, args.version, args.revision, args.run_id, args.workflow)
    write_candidate(args.output, record)
    print(f"Sealed Android SDK candidate for {args.revision} run {args.run_id}; device acceptance remains required")


if __name__ == "__main__":
    main()
