"""Select a reviewed immutable candidate; never fall back to historical bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PIN_FILES = {
    "original-10.1": "final-candidate-10.1.json",
    "repaired-10.1": "repaired-candidate-10.1.json",
}
ORIGINAL = {
    "schema_version": 1,
    "repository": "ZHanry/home-tunnel-client",
    "version": "10.1.0",
    "revision": "9b3dbb751942fee040049f9901ea61e95e60c10c",
    "server_revision": "194ae805f3569dc16d94b7fda71367e5d68fdff5",
    "run_id": "36696397157",
    "run_attempt": 1,
    "artifact_id": "11089548057",
    "artifact_sha256": "985228faa3eadf896558a7d46fe696c79d8d62b1677f5ff865334301d112e95c",
}


def require(value, message):
    if not value:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate candidate identity field")
        result[key] = value
    return result


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def validate_pin(pin, identity):
    require(identity in PIN_FILES, "Unknown candidate identity")
    require(isinstance(pin, dict) and set(pin) == set(ORIGINAL), "Candidate pin schema differs")
    require(type(pin["schema_version"]) is int and pin["schema_version"] == 1 and
            pin["repository"] == ORIGINAL["repository"] and pin["version"] == "10.1.0",
            "Candidate repository, schema or version differs")
    for field, pattern in (("revision", r"[0-9a-f]{40}"), ("server_revision", r"[0-9a-f]{40}"),
                           ("run_id", r"[1-9][0-9]*"), ("artifact_id", r"[1-9][0-9]*"),
                           ("artifact_sha256", r"[0-9a-f]{64}")):
        require(isinstance(pin[field], str) and re.fullmatch(pattern, pin[field]) is not None,
                "Candidate identity must use exact IDs and full lowercase hashes: " + field)
    require(type(pin["run_attempt"]) is int and pin["run_attempt"] >= 1,
            "Candidate run attempt must be a positive integer")
    if identity == "original-10.1":
        require(pin == ORIGINAL, "Historical candidate identity must remain unchanged")
    else:
        require(all(pin[field] != ORIGINAL[field] for field in
                    ("revision", "run_id", "artifact_id", "artifact_sha256")),
                "Repaired candidate must be a new source, run and immutable artifact")
    return pin


def load_pin(root, identity):
    require(identity in PIN_FILES, "Unknown candidate identity")
    # Validate the preserved identity even when the new candidate is selected.
    original = root / "tests/remote-native" / PIN_FILES["original-10.1"]
    require(not original.is_symlink(), "Historical pin cannot be a link")
    validate_pin(read_json(original), "original-10.1")
    path = root / "tests/remote-native" / PIN_FILES[identity]
    require(path.is_file() and not path.is_symlink(),
            "Selected candidate pin is absent; seal and record its new immutable build first")
    return validate_pin(read_json(path), identity), path


def verify_download(pin, receipt):
    expected = {"repository": pin["repository"], "source_revision": pin["revision"],
                **{key: pin[key] for key in ("run_id", "run_attempt", "artifact_id", "artifact_sha256")}}
    require(all(type(receipt.get(key)) is type(value) and receipt[key] == value
                for key, value in expected.items()), "Verified download does not match the selected candidate pin")
    require(receipt.get("signatures_verified") is True and receipt.get("run_attestations_verified") is True and
            re.fullmatch(r"[0-9a-f]{64}", str(receipt.get("candidate_sha256", ""))) is not None,
            "Candidate download lacks verified signatures, attestations or manifest digest")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, choices=tuple(PIN_FILES))
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    pin, path = load_pin(ROOT, args.identity)
    if args.receipt:
        verify_download(pin, read_json(args.receipt))
    if args.output:
        # Never replace an earlier selection receipt or candidate file.
        with args.output.open("x", encoding="utf-8") as stream:
            json.dump({"identity": args.identity, "pin_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "pin": pin}, stream, indent=2)
            stream.write("\n")
    if args.github_output:
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
            for key, value in {"identity": args.identity, **pin}.items():
                stream.write(f"{key}={value}\n")
    print("Verified immutable candidate identity: " + args.identity)


if __name__ == "__main__":
    main()
