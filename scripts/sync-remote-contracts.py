"""Copy the server-owned RD registry and generate bounded C++ framing metadata."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "native/remote/generated"


def generate(registry):
    channels = list(registry["channels"])
    lines = ["// Generated from server-owned remote-desktop.v1.json; do not edit.",
             "#pragma once", "#include <array>", "#include <cstdint>", "#include <string_view>",
             "namespace ht::rd::protocol {",
             "struct MessageRule { std::uint8_t type, channel; std::uint16_t flags; std::uint32_t payload; bool json; };",
             "inline constexpr std::array<std::uint32_t, 6> CHANNEL_LIMITS = {" +
             ",".join(str(v["max_message_bytes"]) for v in registry["channels"].values()) + "};",
             f"inline constexpr std::array<MessageRule, {len(registry['messages'])}> MESSAGE_RULES = {{{{"]
    for item in registry["messages"].values():
        lines.append("  {" + ",".join([str(item["id"]), str(channels.index(item["channel"])),
                                     str(item.get("allowed_flags", 0)), str(item.get("payload_bytes", 0)),
                                     "true" if item["encoding"] == "json" else "false"]) + "},")
    lines += ["}};", "inline constexpr std::uint64_t ALL_PERMISSIONS = " + str((1 << len(registry["permissions"])) - 1) + "u;"]
    for bit, name in enumerate(registry["permissions"]):
        lines.append("inline constexpr std::uint64_t PERMISSION_" + name.upper().replace(".", "_") + f" = {1 << bit}u;")
    lines.append("inline constexpr std::array<std::string_view, " + str(len(registry["permissions"])) + "> PERMISSION_NAMES = {" +
                 ",".join(json.dumps(name) for name in registry["permissions"]) + "};")
    lines += ["}", ""]
    return "\n".join(lines).encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.source:
        for name, source in [("remote-desktop.v1.json", args.source / "remote-desktop.v1.json"),
                             ("remote_protocol.hpp", args.source / "generated/remote_protocol.hpp"),
                             ("remote-test-vectors.json", args.source / "remote-test-vectors.json")]:
            DESTINATION.mkdir(parents=True, exist_ok=True)
            (DESTINATION / name).write_bytes(source.read_bytes())
        authorization = args.source / "remote-authorization-vectors.json"
        if authorization.is_file():
            (DESTINATION / authorization.name).write_bytes(authorization.read_bytes())
    registry_bytes = (DESTINATION / "remote-desktop.v1.json").read_bytes()
    expected = generate(json.loads(registry_bytes))
    vectors = json.loads((DESTINATION / "remote-test-vectors.json").read_bytes())
    vector_header = "// Generated from shared public protocol vectors; do not edit.\n#pragma once\n#include <string_view>\nnamespace ht::rd::protocol {\n"
    vector_header += 'inline constexpr std::string_view PROOF_VECTOR_HEX = "' + vectors['proof']['transcript_hex'] + '";\n'
    vector_header += 'inline constexpr std::string_view KEY_VECTOR_HEX = "' + vectors['key_down_a']['wire_hex'] + '";\n}\n'
    vector_header = vector_header[:-2] + 'inline constexpr std::string_view PROOF_PUBLIC_KEY_HEX = "' + vectors['proof']['public_key_xy_hex'] + '";\n'
    vector_header += 'inline constexpr std::string_view PROOF_SIGNATURE_HEX = "' + vectors['proof']['signature_raw64_hex'] + '";\n}\n'
    target = DESTINATION / "remote_rules.hpp"
    digest = hashlib.sha256(registry_bytes).hexdigest()
    manifest = {"source_repository": "https://github.com/ZHanry/home-tunnel-server",
                "source_path": "contracts/remote-desktop.v1.json", "registry_sha256": digest,
                "vectors_sha256": hashlib.sha256((DESTINATION / "remote-test-vectors.json").read_bytes()).hexdigest(),
                "authorization_vectors_sha256": hashlib.sha256((DESTINATION / "remote-authorization-vectors.json").read_bytes()).hexdigest(),
                "header_sha256": hashlib.sha256((DESTINATION / "remote_protocol.hpp").read_bytes()).hexdigest()}
    manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
    if args.check:
        if target.read_bytes() != expected or (DESTINATION / "source.json").read_bytes() != manifest_bytes or (DESTINATION / "test_vectors.hpp").read_text(encoding="utf-8") != vector_header:
            raise SystemExit("Remote contract snapshot is stale; synchronize from the server registry")
    else:
        target.write_bytes(expected)
        (DESTINATION / "source.json").write_bytes(manifest_bytes)
        (DESTINATION / "test_vectors.hpp").write_text(vector_header, encoding="utf-8", newline="\n")
    print("RD framing metadata and source digest verified")


if __name__ == "__main__":
    main()
