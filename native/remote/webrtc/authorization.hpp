#pragma once
#include "../src/session_gate.hpp"
#include <array>
#include <string>
#include <string_view>
#include <span>
#include <vector>
#include "json/value.h"

namespace ht::rd::auth {
enum class Error { ok, malformed, key, signature, identity, expired, permission };
struct PublicKey {
  std::array<uint8_t, 64> xy{};
  std::string thumbprint;
};
struct Jws { Json::Value header, claims; };
struct ExpectedSession {
  std::string issuer, server_instance_id, session_id, session_request_id;
  std::string owner_user_id, host_endpoint_id, controller_endpoint_id;
  std::string host_jkt, controller_jkt, grant_id;
  uint64_t restore_epoch = 0, grant_version = 0, user_token_version = 0;
  uint32_t connection_epoch = 0;
  uint64_t permission_ceiling = 0;
};

// A signer is selected only after independently verifying the keyset against a
// locally pinned identity. This internal API is never exposed as a trusted IPC bool.
struct SigningKey {
  PublicKey key;
  int64_t not_before_unix_ms = 0, not_after_unix_ms = 0;
};
bool strict_json(std::string_view text, Json::Value& value, size_t byte_limit = 65536);
Error public_key(const Json::Value& jwk, PublicKey& output);
std::string base64url(std::span<const uint8_t> bytes);
bool unbase64url(std::string_view text, std::vector<uint8_t>& bytes);
std::array<uint8_t, 32> digest(std::string_view bytes);
bool timestamp(const Json::Value& text, int64_t& unix_ms);
Error verify_signature(std::span<const uint8_t> message, const PublicKey& key,
                        std::span<const uint8_t> raw_signature);
Error verify_lease(std::string_view compact, const Json::Value& verified_keyset,
                    const ExpectedSession& expected, int64_t now_unix_ms, VerifiedLease& output);
// pinned_json must come from the protected, explicitly approved local trust store.
// IPC-provided network keysets are never eligible to supply their own trust pin.
Error verify_keyset(std::string_view pinned_json, std::string_view candidate_json,
                    int64_t now_unix_ms, Json::Value& verified);
Error select_signing_key(const Json::Value& verified_keyset, std::string_view kid,
                         SigningKey& output);
Error verify_jws(std::string_view compact, const PublicKey& key,
                 std::string_view expected_type, Jws& output);
Error verify_authorization(std::string_view ticket, std::string_view lease,
                           std::string_view grant, const SigningKey& signer,
                           const PublicKey& host_key, const ExpectedSession& expected,
                           int64_t now_unix_ms, VerifiedLease& output);
}
