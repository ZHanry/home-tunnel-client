"""Download one pinned client candidate and reviewed receipts from an immutable hub commit."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess
import zipfile

from client_release_candidate import (REPOSITORY, CALLER, SIGNER, ACCEPTANCE_REPOSITORY, MANIFEST,
    ACCEPTANCE, GATES, digest, filename, local_file, read_json, verify_candidate, verify_acceptance)

ROOT = Path(__file__).resolve().parents[1]


def api(endpoint):
    return json.loads(subprocess.check_output(["gh", "api", endpoint], timeout=120))


def verify_run(run, artifact, revision, run_id, artifact_id, artifact_sha):
    if (run.get("repository", {}).get("full_name") != REPOSITORY or run.get("path") != CALLER or
            run.get("event") != "workflow_dispatch" or run.get("head_sha") != revision or
            str(run.get("id")) != run_id or run.get("status") != "completed" or run.get("conclusion") != "success" or
            type(run.get("run_attempt")) is not int or run["run_attempt"] < 1):
        raise SystemExit("Candidate run is not the successful, requested CI dispatch")
    if (str(artifact.get("id")) != artifact_id or artifact.get("name") != "candidate-assets" or
            artifact.get("expired") is not False or artifact.get("digest") != "sha256:" + artifact_sha or
            str(artifact.get("workflow_run", {}).get("id")) != run_id or artifact.get("workflow_run", {}).get("head_sha") != revision):
        raise SystemExit("Candidate artifact identity, source, run or digest differs")


def extract(archive, destination):
    if destination.exists():
        raise SystemExit("Candidate extraction requires a new directory")
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        names = [filename(item.filename) for item in members]
        if (not 1 <= len(names) <= 256 or len({n.casefold() for n in names}) != len(names) or
                sum(item.file_size for item in members) > 6 * 1024**3 or
                any(item.is_dir() or item.flag_bits & 1 or item.file_size > 3 * 1024**3 or
                    stat.S_IFMT(item.external_attr >> 16) not in (0, stat.S_IFREG) for item in members)):
            raise SystemExit("Unsafe, duplicate, linked or oversized candidate ZIP")
        destination.mkdir(parents=True)
        for item in members:
            with bundle.open(item) as source, (destination / item.filename).open("xb") as target:
                shutil.copyfileobj(source, target, 1024 * 1024)


def verify_attestation(path, build, revision, destination):
    result = subprocess.check_output(["gh", "attestation", "verify", str(path), "--repo", REPOSITORY,
        "--signer-workflow", REPOSITORY + "/" + SIGNER, "--source-digest", revision,
        "--source-ref", build["source_ref"], "--signer-digest", revision, "--deny-self-hosted-runners", "--format", "json"], timeout=120)
    invocation = f"https://github.com/{REPOSITORY}/actions/runs/{build['run_id']}/attempts/{build['run_attempt']}"
    matched = False
    for item in json.loads(result):
        statement = item.get("verificationResult", {}).get("statement", {})
        if (statement.get("predicate", {}).get("runDetails", {}).get("metadata", {}).get("invocationId") == invocation and
                any(s.get("digest", {}).get("sha256") == digest(path) for s in statement.get("subject", []))):
            matched = True
    if not matched:
        raise SystemExit("Attestation does not identify the candidate run/attempt")
    (destination / (path.name + ".verification.json")).write_bytes(result)


def verify_signatures(directory, candidate, cosign, evidence):
    build = candidate["build"]
    identity = f"https://github.com/{REPOSITORY}/{SIGNER}@{build['source_ref']}"
    expected = set(candidate["files"]) | {MANIFEST, MANIFEST + ".sigstore.json"}
    if {p.name for p in directory.iterdir()} != expected:
        raise SystemExit("Candidate archive has missing or unsealed files")
    evidence.mkdir(parents=True)
    subjects = {MANIFEST}
    for name in candidate["files"]:
        if name.endswith(".sigstore.json"):
            subject = name.removesuffix(".sigstore.json")
            if subject not in candidate["files"] or subject.endswith(".sigstore.json"):
                raise SystemExit("Orphaned or recursive candidate signature")
            subjects.add(subject)
    for name in sorted(subjects):
        subprocess.run([cosign, "verify-blob", "--bundle", str(local_file(directory, name + ".sigstore.json")),
            "--certificate-identity", identity, "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
            str(local_file(directory, name))], check=True, timeout=120)
    # This run-bound manifest covers every supporting subject and its original
    # signatures, including both same-source controller SDK ABIs.
    for name in [MANIFEST, *candidate["packages"]]:
        verify_attestation(directory / name, build, candidate["revision"], evidence)


def read_hub_file(hub_revision, revision, name, fetch=api):
    name = filename(name)
    path = f"validation/client/{revision}/{name}"
    item = fetch(f"repos/{ACCEPTANCE_REPOSITORY}/contents/{path}?ref={hub_revision}")
    if (item.get("type") != "file" or item.get("path") != path or not re.fullmatch(r"[0-9a-f]{40}", str(item.get("sha", ""))) or
            type(item.get("size")) is not int or not 0 < item["size"] <= 4 * 1024 * 1024):
        raise SystemExit("Acceptance receipt is missing, linked or oversized")
    blob = fetch(f"repos/{ACCEPTANCE_REPOSITORY}/git/blobs/{item['sha']}")
    if blob.get("encoding") != "base64":
        raise SystemExit("Unexpected receipt encoding")
    data = base64.b64decode("".join(blob.get("content", "").split()), validate=True)
    git_sha = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
    if len(data) != item["size"] or git_sha != item["sha"] or blob.get("sha") != git_sha:
        raise SystemExit("Acceptance receipt differs from its immutable Git object")
    return data


def fetch_acceptance(revision, candidate, candidate_sha, destination):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("Acceptance requires an exact hub commit SHA")
    compare = api(f"repos/{ACCEPTANCE_REPOSITORY}/compare/{revision}...main")
    if compare.get("status") not in ("ahead", "identical") or compare.get("merge_base_commit", {}).get("sha") != revision:
        raise SystemExit("Reviewed acceptance receipts must be committed on hub main")
    destination.mkdir(parents=True, exist_ok=False)
    manifest = read_hub_file(revision, candidate["revision"], ACCEPTANCE)
    (destination / ACCEPTANCE).write_bytes(manifest)
    record = json.loads(manifest)
    expected = {f"client-acceptance-{label}.json" for label in GATES}
    expected |= {"windows-remote-native-acceptance.json", "windows-final-defender-scan.json"}
    if set(record.get("files", {})) != expected:
        raise SystemExit("Acceptance receipt set is incomplete")
    for name in sorted(expected):
        (destination / name).write_bytes(read_hub_file(revision, candidate["revision"], name))
    verify_acceptance(record, destination, candidate, candidate_sha)
    origin = {"repository": ACCEPTANCE_REPOSITORY, "revision": revision,
        "path": f"validation/client/{candidate['revision']}", "manifest_sha256": digest(destination / ACCEPTANCE)}
    (destination / "client-acceptance-origin.json").write_text(json.dumps(origin, indent=2) + "\n", encoding="utf-8")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("run-id", "artifact-id", "artifact-sha256", "revision", "version"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--acceptance-revision", help="Omit only to download a candidate for testing; publication requires receipts")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cosign", default="cosign")
    args = parser.parse_args()
    for value, pattern in ((args.run_id, r"[1-9][0-9]*"), (args.artifact_id, r"[1-9][0-9]*"),
                           (args.artifact_sha256, r"[0-9a-f]{64}"), (args.revision, r"[0-9a-f]{40}")):
        if not re.fullmatch(pattern, value):
            parser.error("Pin exact numeric IDs and full lowercase digests")
    if args.output.exists():
        parser.error("Output must be new; previous evidence is preserved")
    run = api(f"repos/{REPOSITORY}/actions/runs/{args.run_id}")
    artifact = api(f"repos/{REPOSITORY}/actions/artifacts/{args.artifact_id}")
    verify_run(run, artifact, args.revision, args.run_id, args.artifact_id, args.artifact_sha256)
    args.output.mkdir(parents=True)
    archive = args.output / "candidate.zip"
    with archive.open("xb") as stream:
        subprocess.run(["gh", "api", f"repos/{REPOSITORY}/actions/artifacts/{args.artifact_id}/zip", "--allow-escape-sequences"],
                       stdout=stream, check=True, timeout=1800)
    if digest(archive) != args.artifact_sha256:
        raise SystemExit("Downloaded candidate differs from the pinned artifact digest")
    directory = args.output / "candidate"
    extract(archive, directory)
    candidate = verify_candidate(read_json(directory / MANIFEST), directory, args.revision, args.version)
    build = candidate["build"]
    if (str(build["run_id"]) != args.run_id or build["run_attempt"] != run["run_attempt"] or
            build["source_ref"] not in {"refs/heads/" + run["head_branch"]}):
        raise SystemExit("Candidate manifest differs from the requested build invocation")
    verify_signatures(directory, candidate, args.cosign, args.output / "verification")
    acceptance = None
    if args.acceptance_revision:
        acceptance = fetch_acceptance(args.acceptance_revision, candidate, digest(directory / MANIFEST), args.output / "acceptance")
    receipt = {"schema_version": 1, "repository": REPOSITORY, "source_revision": args.revision,
        "run_id": args.run_id, "run_attempt": run["run_attempt"], "artifact_id": args.artifact_id,
        "artifact_sha256": args.artifact_sha256, "candidate_sha256": digest(directory / MANIFEST),
        "signatures_verified": True, "run_attestations_verified": True, "acceptance_revision": args.acceptance_revision}
    (args.output / "client-candidate-download.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    waived = sorted(g for g, item in (acceptance or {}).get("coverage", {}).items() if item["status"] == "waived")
    print("Verified fixed client candidate bytes" + (" and reviewed acceptance receipts" if args.acceptance_revision else "; runtime acceptance still required") +
          ("; owner-waived, NOT verified: " + ", ".join(waived) if waived else ""))


if __name__ == "__main__":
    main()
