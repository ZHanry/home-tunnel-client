"""Import generated contracts from a reviewed server commit, preserving exact bytes.

A missing --published-ref records the schema's own contract name as proposed.
It does not create or require an immutable api tag.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "contracts/remote-desktop.v1.json": "native/remote/generated/remote-desktop.v1.json",
    "contracts/remote-test-vectors.json": "native/remote/generated/remote-test-vectors.json",
    "contracts/remote-authorization-vectors.json": "native/remote/generated/remote-authorization-vectors.json",
    "contracts/generated/remote_protocol.hpp": "native/remote/generated/remote_protocol.hpp",
}
REST_FILES = {
    "contracts/home-tunnel.v1.json": "contracts/home-tunnel.v1.json",
    "contracts/openapi.v1.json": "contracts/openapi.v1.json",
    "contracts/api.schema.json": "contracts/api.schema.json",
}
PREVIOUS_IMMUTABLE_TAG = "api-v1.4.0"


def validate_published_ref(source, value, revision, dirty):
    """The caller reviews GitHub publication; bind that exact local tag to clean source."""
    if value is None:
        return None
    number = r"(?:0|[1-9][0-9]*)"
    if not isinstance(value, str) or not re.fullmatch(rf"api-v{number}\.{number}\.{number}(?:-rc\.[1-9][0-9]*)?", value):
        raise SystemExit("Published contract must use an exact stable or RC tag")
    if dirty:
        raise SystemExit("Published contract import requires a clean source checkout")
    try:
        tagged = subprocess.check_output(["git", "rev-parse", "--verify", f"refs/tags/{value}^{{commit}}"],
                                         cwd=source, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        raise SystemExit("Published contract tag is absent from the reviewed source checkout") from None
    if tagged != revision:
        raise SystemExit("Published contract tag must identify the exact source HEAD")
    return value


def read_blob(source, revision, relative):
    if revision:
        return subprocess.check_output(["git", "show", f"{revision}:{relative}"], cwd=source)
    return (source / relative).read_bytes()


def contract_record(published, revision):
    """The OpenAPI name can be proposed. Publication is a separate immutable tag."""
    if published:
        return {"contract_status": "frozen", "frozen_tag": published, "published_contract_ref": published,
                "source_revision": revision}
    return {"contract_status": "proposed", "frozen_tag": None, "published_contract_ref": None,
            "source_revision": revision, "previous_immutable_tag": PREVIOUS_IMMUTABLE_TAG}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--published-ref", help="A fetched version tag whose GitHub publication was independently verified")
    parser.add_argument("--revision", help="Exact 40-hex commit to read. Avoids the server worktree.")
    args = parser.parse_args()
    source = args.source.resolve()
    if args.revision:
        if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
            raise SystemExit("Contract import revision must be the exact 40-hex commit")
        revision = subprocess.check_output(["git", "rev-parse", "--verify", f"{args.revision}^{{commit}}"],
                                            cwd=source, text=True).strip()
        if revision != args.revision:
            raise SystemExit("Contract import revision is not that commit")
        dirty = False
    else:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=source, text=True).strip())
    published = validate_published_ref(source, args.published_ref, revision, dirty)
    if published is None and dirty:
        raise SystemExit("A proposed contract import must name a commit or a clean checkout")
    imported = []
    for original, destination in {**REST_FILES, **FILES}.items():
        content = read_blob(source, args.revision, original)
        path = ROOT / destination
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        imported.append({"source": original, "path": destination, "sha256": hashlib.sha256(content).hexdigest()})
    rest = [item for item in imported if item["source"] in REST_FILES]
    remote = [item for item in imported if item["source"] in FILES]
    openapi = json.loads((ROOT / "contracts/openapi.v1.json").read_text(encoding="utf-8"))
    ref = openapi.get("x-contract-ref")
    if not re.fullmatch(r"api-v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-rc\.[1-9][0-9]*)?", str(ref)):
        raise SystemExit("Imported OpenAPI is missing its contract name")
    if "/api/v1/" not in json.dumps(openapi.get("paths", {})):
        raise SystemExit("Imported API must stay on /api/v1")
    status = contract_record(published, revision)
    if published and published != ref:
        raise SystemExit("Published tag must equal the imported OpenAPI contract name")
    rest_hashes = {item["path"]: item["sha256"] for item in rest}
    rest_lock = {"repository": "ZHanry/home-tunnel-server", "ref": ref, **status,
                 "source_tree_dirty": dirty, "api_prefix": "/api/v1",
                 "path": "contracts/home-tunnel.v1.json",
                 "sha256": rest_hashes["contracts/home-tunnel.v1.json"],
                 "files": [{"path": item["path"], "sha256": item["sha256"]} for item in rest]}
    (ROOT / "contracts/lock.json").write_text(json.dumps(rest_lock, indent=2) + "\n", encoding="utf-8")
    remote_hashes = {item["source"]: item["sha256"] for item in remote}
    remote_lock = {"schema_version": 1, "repository": "ZHanry/home-tunnel-server", "source_revision": revision,
                   "source_tree_dirty": dirty, "contract_status": status["contract_status"],
                   "frozen_tag": status["frozen_tag"], "published_contract_ref": published,
                   "proposed_ref": None if published else ref,
                   "previous_immutable_tag": None if published else PREVIOUS_IMMUTABLE_TAG,
                   "source_tree_sha256": hashlib.sha256(json.dumps(remote_hashes, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                   "files": remote}
    (ROOT / "contracts/remote.lock.json").write_text(json.dumps(remote_lock, indent=2) + "\n", encoding="utf-8")
    compatibility = json.loads((ROOT / "compatibility.json").read_text(encoding="utf-8"))
    compatibility["contract_ref"] = ref
    compatibility["contract_status"] = status["contract_status"]
    compatibility["frozen_tag"] = status["frozen_tag"]
    compatibility["previous_immutable_tag"] = PREVIOUS_IMMUTABLE_TAG
    (ROOT / "compatibility.json").write_text(json.dumps(compatibility, indent=2) + "\n", encoding="utf-8")
    server_lock = {"schema_version": 1, "repository": "ZHanry/home-tunnel-server", "revision": revision}
    (ROOT / "tests/remote-native/server-lock.json").write_text(json.dumps(server_lock, indent=2) + "\n", encoding="utf-8")
    import sys
    subprocess.run([sys.executable, str(ROOT / "scripts/sync-remote-contracts.py")], check=True)
    print(f"Imported exact contracts from published {published}" if published else
          f"Imported exact proposed contracts from {revision}; no API tag was created")


if __name__ == "__main__":
    main()
