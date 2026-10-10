"""Verify the independently versioned device directory extension and its pinned bytes."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "nestlink-device-capabilities-v1"
FILES = {
    "contracts/nestlink-device-capabilities.v1.json",
    "contracts/nestlink-device-capabilities.v1.schema.json",
}
OPERATIONS = {
    "POST /api/v2/auth/device-capabilities/link",
    "GET /api/v2/auth/device-capabilities",
    "DELETE /api/v2/auth/device-capabilities/{remoteId}",
    "GET /api/v2/admin/device-capabilities",
}

def main():
    lock = json.loads((ROOT / "contracts/device-capabilities.lock.json").read_text(encoding="utf8"))
    assert lock["contract"] == EXPECTED
    assert lock["authentication_contract"] == "api-v2.0.0"
    assert {item["path"] for item in lock["files"]} == FILES
    assert len(lock["files"]) == len(FILES)
    for item in lock["files"]:
        assert re.fullmatch(r"[a-f0-9]{64}", item["sha256"])
        assert hashlib.sha256((ROOT / item["path"]).read_bytes()).hexdigest() == item["sha256"], item["path"]
    contract = json.loads((ROOT / "contracts/nestlink-device-capabilities.v1.json").read_text(encoding="utf8"))
    assert contract["contract_version"] == EXPECTED
    assert contract["authentication_contract"] == "api-v2.0.0"
    assert contract["version"] == 1 and contract["migration"] == 26
    assert set(contract["operations"]) == OPERATIONS
    compat = json.loads((ROOT / "compatibility.json").read_text(encoding="utf8"))
    assert compat["extensions"]["device_capabilities"] == EXPECTED
    if compat["component"] == "android":
        core = ROOT / "homedesk-core"
        for name in FILES | {"contracts/device-capabilities.lock.json"}:
            assert (ROOT / name).read_bytes() == (core / name).read_bytes(), "Shared extension differs: " + name
    print("Device directory extension identity, operations and immutable digests verified")

if __name__ == "__main__":
    main()
