#include "authorization.hpp"
#include "json/reader.h"
#include "openssl/bn.h"
#include "openssl/ec_key.h"
#include "openssl/ecdsa.h"
#include "openssl/nid.h"
#include "openssl/sha.h"
#include <algorithm>
#include <chrono>
#include <limits>
#include <memory>
#include <span>
#include <tuple>
#include <vector>

namespace ht::rd::auth {
namespace {
constexpr uint64_t max_safe_integer = 9007199254740991ULL;
constexpr std::string_view alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
constexpr auto permission_names = protocol::PERMISSION_NAMES;
std::string encode(std::span<const uint8_t> bytes) {
  std::string result; uint32_t bits = 0; unsigned count = 0;
  for (const auto byte : bytes) {
    bits = (bits << 8) | byte; count += 8;
    while (count >= 6) { count -= 6; result += alphabet[(bits >> count) & 63]; }
  }
  if (count) result += alphabet[(bits << (6 - count)) & 63];
  return result;
}
bool decode(std::string_view text, std::vector<uint8_t>& bytes) {
  bytes.clear();
  if (text.empty() || text.size() > 65536 || text.size() % 4 == 1) return false;
  uint32_t bits = 0; unsigned count = 0;
  for (char character : text) {
    const auto index = alphabet.find(character);
    if (index == std::string_view::npos) return false;
    bits = (bits << 6) | static_cast<uint32_t>(index); count += 6;
    if (count >= 8) { count -= 8; bytes.push_back(static_cast<uint8_t>(bits >> count)); }
  }
  return encode(bytes) == text;  // Also reject non-zero unused bits/noncanonical padding.
}
bool text_utf8(std::string_view text) {
  return valid_utf8(std::span(reinterpret_cast<const uint8_t*>(text.data()), text.size()));
}
bool integer(const Json::Value& value, uint64_t& output) {
  if (value.type() != Json::uintValue && value.type() != Json::intValue) return false;
  if (value.type() == Json::intValue && value.asInt64() < 0) return false;
  output = value.asUInt64(); return output <= max_safe_integer;
}
bool validate_json_tree(const Json::Value& value) {
  if (value.isObject()) {
    if (value.size() > 128) return false;
    for (const auto& name : value.getMemberNames())
      if (!text_utf8(name) || !validate_json_tree(value[name])) return false;
  } else if (value.isArray()) {
    if (value.size() > 128) return false;
    for (const auto& child : value) if (!validate_json_tree(child)) return false;
  } else if (value.isString()) {
    if (!text_utf8(value.asString())) return false;
  } else if (value.isNumeric()) {
    uint64_t number = 0;
    if (!integer(value, number)) return false;
  }
  return true;
}
bool fields(const Json::Value& object, std::initializer_list<std::string_view> names) {
  if (!object.isObject() || object.size() != names.size()) return false;
  for (auto name : names) if (!object.isMember(std::string(name))) return false;
  return true;
}
bool same_string(const Json::Value& value, std::string_view expected) {
  return value.isString() && value.asString() == expected;
}
bool same_integer(const Json::Value& value, uint64_t expected) {
  uint64_t actual = 0; return integer(value, actual) && actual == expected;
}
bool permissions(const Json::Value& value, uint64_t& mask) {
  mask = 0;
  if (!value.isArray() || value.empty() || value.size() > permission_names.size()) return false;
  for (const auto& item : value) {
    if (!item.isString()) return false;
    const auto name = item.asString();
    auto index = std::find(permission_names.begin(), permission_names.end(), name);
    if (index == permission_names.end()) return false;
    const uint64_t bit = uint64_t{1} << (index - permission_names.begin());
    if (mask & bit) return false;
    mask |= bit;
  }
  return (mask & protocol::PERMISSION_VIEW) != 0;
}
bool iso_time(const Json::Value& value, int64_t& result) {
  if (!value.isString()) return false;
  const auto text = value.asString();
  if ((text.size() != 20 && (text.size() < 22 || text.size() > 30)) || text[4] != '-' || text[7] != '-' ||
      text[10] != 'T' || text[13] != ':' || text[16] != ':' || text.back() != 'Z' ||
      (text.size() != 20 && text[19] != '.')) return false;
  const auto number = [&](size_t start, size_t length) {
    int n = 0;
    for (size_t i = start; i < start + length; ++i) {
      if (text[i] < '0' || text[i] > '9') return -1;
      n = n * 10 + text[i] - '0';
    }
    return n;
  };
  const int year = number(0, 4), month = number(5, 2), day = number(8, 2);
  const int hour = number(11, 2), minute = number(14, 2), second = number(17, 2);
  int millis = 0;
  if (text.size() != 20) {
    const size_t digits = text.size() - 21;
    if (number(20, digits) < 0) return false;
    millis = number(20, std::min<size_t>(digits, 3));
    if (digits == 1) millis *= 100;
    else if (digits == 2) millis *= 10;
  }
  if (year < 1970 || month < 1 || day < 1 || hour < 0 || hour > 23 ||
      minute < 0 || minute > 59 || second < 0 || second > 59 || millis < 0) return false;
  const std::chrono::year_month_day date{std::chrono::year{year}, std::chrono::month{static_cast<unsigned>(month)},
                                         std::chrono::day{static_cast<unsigned>(day)}};
  if (!date.ok()) return false;
  result = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::sys_days(date).time_since_epoch()).count() +
           (int64_t{hour} * 3600 + minute * 60 + second) * 1000 + millis;
  return true;
}
bool keyset_body(const Json::Value& body) {
  uint64_t version = 0;
  if (!integer(body["keyset_version"], version) || !version || !body["active_kid"].isString() ||
      !body["keys"].isArray() || body["keys"].empty() || body["keys"].size() > 8) return false;
  std::vector<std::string> ids;
  for (const auto& item : body["keys"]) {
    PublicKey key; int64_t begin = 0, end = 0;
    if (!fields(item, {"kid", "alg", "public_jwk", "not_before", "not_after"}) ||
        !same_string(item["alg"], "ES256") || public_key(item["public_jwk"], key) != Error::ok ||
        !same_string(item["kid"], key.thumbprint) ||
        !iso_time(item["not_before"], begin) || !iso_time(item["not_after"], end) || end <= begin ||
        std::find(ids.begin(), ids.end(), key.thumbprint) != ids.end()) return false;
    ids.push_back(key.thumbprint);
  }
  return std::find(ids.begin(), ids.end(), body["active_kid"].asString()) != ids.end();
}
bool keyset(const Json::Value& value) {
  uint64_t epoch = 0;
  if (!fields(value, {"server_instance_id", "restore_epoch", "keyset_version", "active_kid", "keys", "rotation_proofs"}) ||
      !value["server_instance_id"].isString() || value["server_instance_id"].asString().empty() ||
      !integer(value["restore_epoch"], epoch) || !epoch || !keyset_body(value) ||
      !value["rotation_proofs"].isArray() || value["rotation_proofs"].size() > 32) return false;
  for (const auto& proof : value["rotation_proofs"])
    if (!proof.isString() || proof.asString().empty() || proof.asString().size() > 8192) return false;
  return true;
}
bool identity(const Json::Value& claims, const ExpectedSession& e) {
  return same_string(claims["iss"], e.issuer) && same_string(claims["server_instance_id"], e.server_instance_id) &&
         same_string(claims["session_id"], e.session_id) && same_string(claims["session_request_id"], e.session_request_id) &&
         same_string(claims["owner_user_id"], e.owner_user_id) && same_string(claims["host_endpoint_id"], e.host_endpoint_id) &&
         same_string(claims["controller_endpoint_id"], e.controller_endpoint_id) && same_string(claims["host_jkt"], e.host_jkt) &&
         same_string(claims["controller_jkt"], e.controller_jkt) && same_string(claims["grant_id"], e.grant_id) &&
         same_integer(claims["restore_epoch"], e.restore_epoch) && same_integer(claims["connection_epoch"], e.connection_epoch) &&
         same_integer(claims["grant_version"], e.grant_version) && same_integer(claims["user_token_version"], e.user_token_version);
}
Error session_claims(const Jws& value, const ExpectedSession& expected, const SigningKey& signer,
                     int64_t now, bool lease, VerifiedLease& output) {
  const auto& claims = value.claims;
  if (!identity(claims, expected) || !same_string(value.header["kid"], signer.key.thumbprint) ||
      !same_string(claims["aud"], lease ? "ht-rd-use" : "ht-rd-start") ||
      !claims["jti"].isString() || claims["jti"].asString().empty()) return Error::identity;
  uint64_t issued = 0, expires = 0, not_before = 0, sequence = 0, mask = 0;
  if (!integer(claims["iat"], issued) || !integer(claims["nbf"], not_before) ||
      !integer(claims["exp"], expires) || issued > uint64_t(std::numeric_limits<int64_t>::max() / 1000) ||
      expires > uint64_t(std::numeric_limits<int64_t>::max() / 1000) ||
      (lease && (!integer(claims["lease_seq"], sequence) || sequence == 0))) return Error::malformed;
  if (now < 0 || not_before != issued || expires <= issued || expires - issued > (lease ? 900u : 60u) ||
      issued * 1000 > uint64_t(now) + 5000 || expires * 1000 <= uint64_t(now) ||
      int64_t(issued * 1000) < signer.not_before_unix_ms || int64_t(expires * 1000) > signer.not_after_unix_ms)
    return Error::expired;
  if (!permissions(claims["permissions"], mask) || (mask & ~expected.permission_ceiling)) return Error::permission;
  output = {expected.connection_epoch, sequence, mask, int64_t(issued * 1000), int64_t(expires * 1000)};
  return Error::ok;
}
}

bool strict_json(std::string_view text, Json::Value& value, size_t byte_limit) {
  if (text.empty() || byte_limit > 262144 || text.size() > byte_limit || !text_utf8(text)) return false;
  // JsonCpp is built with exceptions disabled upstream. Prebound nesting so its
  // stackLimit cannot abort the worker on a remotely supplied deeply nested value.
  unsigned depth = 0; bool quoted = false, escaped = false;
  for (char c : text) {
    if (quoted) {
      if (escaped) escaped = false;
      else if (c == '\\') escaped = true;
      else if (c == '"') quoted = false;
    } else if (c == '"') quoted = true;
    else if (c == '{' || c == '[') { if (++depth > 20) return false; }
    else if (c == '}' || c == ']') { if (depth == 0) return false; --depth; }
  }
  if (depth || quoted) return false;
  Json::CharReaderBuilder builder;
  Json::CharReaderBuilder::strictMode(&builder.settings_);
  builder["collectComments"] = false;
  builder["rejectDupKeys"] = true;
  builder["failIfExtra"] = true;
  builder["allowTrailingCommas"] = false;
  builder["stackLimit"] = 32;
  std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
  std::string ignored;
  return reader->parse(std::to_address(text.begin()), std::to_address(text.end()), &value, &ignored) &&
         value.isObject() && validate_json_tree(value);
}

Error public_key(const Json::Value& jwk, PublicKey& output) {
  if (!fields(jwk, {"kty", "crv", "x", "y"}) || !same_string(jwk["kty"], "EC") ||
      !same_string(jwk["crv"], "P-256") || !jwk["x"].isString() || !jwk["y"].isString()) return Error::key;
  const auto x_text = jwk["x"].asString(), y_text = jwk["y"].asString();
  std::vector<uint8_t> x_bytes, y_bytes;
  if (!decode(x_text, x_bytes) || !decode(y_text, y_bytes) || x_bytes.size() != 32 || y_bytes.size() != 32) return Error::key;
  bssl::UniquePtr<EC_KEY> key(EC_KEY_new_by_curve_name(NID_X9_62_prime256v1));
  bssl::UniquePtr<BIGNUM> x(BN_bin2bn(x_bytes.data(), 32, nullptr)), y(BN_bin2bn(y_bytes.data(), 32, nullptr));
  if (!key || !x || !y || !EC_KEY_set_public_key_affine_coordinates(key.get(), x.get(), y.get()) || !EC_KEY_check_key(key.get())) return Error::key;
  std::copy(x_bytes.begin(), x_bytes.end(), output.xy.begin());
  std::copy(y_bytes.begin(), y_bytes.end(), output.xy.begin() + 32);
  const auto canonical = std::string("{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"") + x_text + "\",\"y\":\"" + y_text + "\"}";
  std::array<uint8_t, SHA256_DIGEST_LENGTH> digest{};
  SHA256(reinterpret_cast<const uint8_t*>(canonical.data()), canonical.size(), digest.data());
  output.thumbprint = encode(digest);
  return Error::ok;
}

Error verify_jws(std::string_view compact, const PublicKey& key, std::string_view expected_type, Jws& output) {
  if (compact.empty() || compact.size() > 65536) return Error::malformed;
  const auto first = compact.find('.'), second = compact.find('.', first == std::string_view::npos ? 0 : first + 1);
  if (first == std::string_view::npos || second == std::string_view::npos || compact.find('.', second + 1) != std::string_view::npos) return Error::malformed;
  std::vector<uint8_t> header, payload, signature;
  if (!decode(compact.substr(0, first), header) || !decode(compact.substr(first + 1, second - first - 1), payload) ||
      !decode(compact.substr(second + 1), signature) || signature.size() != 64 ||
      !strict_json(std::string_view(reinterpret_cast<const char*>(header.data()), header.size()), output.header)) return Error::malformed;
  if (!same_string(output.header["alg"], "ES256") || !same_string(output.header["typ"], expected_type)) return Error::key;
  for (const auto& name : output.header.getMemberNames())
    if (name != "alg" && name != "typ" && name != "kid" && name != "jwk") return Error::key;
  if (output.header.isMember("kid") && !same_string(output.header["kid"], key.thumbprint)) return Error::key;
  if (output.header.isMember("jwk")) {
    PublicKey embedded;
    if (public_key(output.header["jwk"], embedded) != Error::ok || embedded.xy != key.xy) return Error::key;
  }
  const auto error = verify_signature(std::span(reinterpret_cast<const uint8_t*>(compact.data()), second), key, signature);
  if (error != Error::ok) return error;
  return strict_json(std::string_view(reinterpret_cast<const char*>(payload.data()), payload.size()), output.claims) ? Error::ok : Error::malformed;
}

Error verify_signature(std::span<const uint8_t> message, const PublicKey& key, std::span<const uint8_t> signature) {
  if (message.empty() || message.size() > 65536 || signature.size() != 64) return Error::malformed;
  bssl::UniquePtr<EC_KEY> ec(EC_KEY_new_by_curve_name(NID_X9_62_prime256v1));
  bssl::UniquePtr<BIGNUM> x(BN_bin2bn(key.xy.data(), 32, nullptr)), y(BN_bin2bn(std::span(key.xy).last<32>().data(), 32, nullptr));
  bssl::UniquePtr<ECDSA_SIG> sig(ECDSA_SIG_new());
  bssl::UniquePtr<BIGNUM> r(BN_bin2bn(signature.data(), 32, nullptr)), s(BN_bin2bn(std::span(signature).last<32>().data(), 32, nullptr));
  if (!ec || !x || !y || !sig || !r || !s || !EC_KEY_set_public_key_affine_coordinates(ec.get(), x.get(), y.get()) ||
      !ECDSA_SIG_set0(sig.get(), r.get(), s.get())) return Error::key;
  (void)r.release(); (void)s.release();
  std::array<uint8_t, SHA256_DIGEST_LENGTH> digest{};
  SHA256(message.data(), message.size(), digest.data());
  if (ECDSA_do_verify(digest.data(), digest.size(), sig.get(), ec.get()) != 1) return Error::signature;
  return Error::ok;
}

std::string base64url(std::span<const uint8_t> bytes) { return encode(bytes); }
bool unbase64url(std::string_view text, std::vector<uint8_t>& bytes) { return decode(text, bytes); }
bool timestamp(const Json::Value& value, int64_t& result) { return iso_time(value, result); }
std::array<uint8_t, 32> digest(std::string_view bytes) {
  std::array<uint8_t, 32> output{};
  SHA256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), output.data());
  return output;
}

Error select_signing_key(const Json::Value& keys, std::string_view kid, SigningKey& output) {
  output = {};
  if (!keyset_body(keys)) return Error::key;
  for (const auto& item : keys["keys"]) {
    if (!same_string(item["kid"], kid)) continue;
    if (public_key(item["public_jwk"], output.key) != Error::ok ||
        !iso_time(item["not_before"], output.not_before_unix_ms) ||
        !iso_time(item["not_after"], output.not_after_unix_ms)) return Error::key;
    return Error::ok;
  }
  return Error::key;
}

Error verify_keyset(std::string_view pinned_json, std::string_view candidate_json,
                    int64_t now, Json::Value& verified) {
  verified = Json::Value{};
  Json::Value pinned, candidate;
  if (now < 0 || !strict_json(pinned_json, pinned, 262144) || !keyset(pinned) ||
      !strict_json(candidate_json, candidate, 262144) || !keyset(candidate)) return Error::malformed;
  if (candidate["server_instance_id"] != pinned["server_instance_id"] ||
      candidate["restore_epoch"].asUInt64() < pinned["restore_epoch"].asUInt64() ||
      candidate["keyset_version"].asUInt64() < pinned["keyset_version"].asUInt64()) return Error::identity;
  auto current = pinned;
  int64_t issued_before = 0;
  for (const auto& raw : candidate["rotation_proofs"]) {
    const auto compact = raw.asString();
    const auto first = compact.find('.'), second = compact.find('.', first == std::string::npos ? 0 : first + 1);
    std::vector<uint8_t> payload; Json::Value hint; uint64_t to = 0;
    if (first == std::string::npos || second == std::string::npos || compact.find('.', second + 1) != std::string::npos ||
        !decode(std::string_view(compact).substr(first + 1, second - first - 1), payload) ||
        !strict_json(std::string_view(reinterpret_cast<const char*>(payload.data()), payload.size()), hint) ||
        !integer(hint["to_version"], to)) return Error::malformed;
    // A bounded untrusted hint may only skip history already covered by the pin.
    // Every proof that advances trust is independently signature verified below.
    if (to <= pinned["keyset_version"].asUInt64()) continue;
    SigningKey signer;
    if (select_signing_key(current, current["active_kid"].asString(), signer) != Error::ok) return Error::key;
    Jws proof;
    auto error = verify_jws(compact, signer.key, "ht-rd-keyset+jwt", proof);
    if (error != Error::ok) return error;
    const auto& c = proof.claims;
    int64_t issued = 0;
    if (!fields(c, {"server_instance_id", "from_version", "to_version", "from_kid", "issued_at", "keyset"}) ||
        c["server_instance_id"] != pinned["server_instance_id"] ||
        !same_integer(c["from_version"], current["keyset_version"].asUInt64()) ||
        !same_integer(c["to_version"], current["keyset_version"].asUInt64() + 1) ||
        c["from_kid"] != current["active_kid"] || !same_string(proof.header["kid"], signer.key.thumbprint) ||
        !fields(c["keyset"], {"keyset_version", "active_kid", "keys"}) || !keyset_body(c["keyset"]) ||
        c["keyset"]["keyset_version"] != c["to_version"] || c["keyset"]["active_kid"] == current["active_kid"])
      return Error::identity;
    if (!iso_time(c["issued_at"], issued) || issued < signer.not_before_unix_ms || issued >= signer.not_after_unix_ms ||
        issued > now + 60000 || issued < issued_before) return Error::expired;
    for (const auto name : {"keyset_version", "active_kid", "keys"}) current[name] = c["keyset"][name];
    SigningKey active;
    if (select_signing_key(current, current["active_kid"].asString(), active) != Error::ok ||
        issued < active.not_before_unix_ms || issued >= active.not_after_unix_ms) return Error::expired;
    issued_before = issued;
  }
  for (const auto name : {"keyset_version", "active_kid", "keys"})
    if (current[name] != candidate[name]) return Error::identity;
  SigningKey active;
  if (select_signing_key(candidate, candidate["active_kid"].asString(), active) != Error::ok ||
      now < active.not_before_unix_ms || now >= active.not_after_unix_ms) return Error::expired;
  verified = candidate;
  return Error::ok;
}

Error verify_lease(std::string_view compact, const Json::Value& keys,
                    const ExpectedSession& expected, int64_t now, VerifiedLease& output) {
  output = {};
  const auto first = compact.find('.');
  if (first == std::string_view::npos || first > 2048) return Error::malformed;
  std::vector<uint8_t> decoded; Json::Value header;
  if (!decode(compact.substr(0, first), decoded) ||
      !strict_json(std::string_view(reinterpret_cast<const char*>(decoded.data()), decoded.size()), header) ||
      !header["kid"].isString()) return Error::malformed;
  SigningKey signer;
  if (select_signing_key(keys, header["kid"].asString(), signer) != Error::ok) return Error::key;
  Jws lease;
  const auto error = verify_jws(compact, signer.key, "ht-rd-lease+jwt", lease);
  if (error != Error::ok) return error;
  return session_claims(lease, expected, signer, now, true, output);
}

Error verify_authorization(std::string_view ticket, std::string_view lease, std::string_view grant,
                           const SigningKey& signer, const PublicKey& host_key, const ExpectedSession& e,
                           int64_t now, VerifiedLease& output) {
  output = {};
  if (e.connection_epoch == 0 || e.session_id.empty() || e.session_request_id.empty() || e.grant_version == 0 ||
      e.host_jkt != host_key.thumbprint || now < signer.not_before_unix_ms || now >= signer.not_after_unix_ms) return Error::identity;
  Jws ticket_value, lease_value, grant_value;
  for (auto [compact, key, type, destination] : {
      std::tuple{ticket, &signer.key, "ht-rd-ticket+jwt", &ticket_value},
      std::tuple{lease, &signer.key, "ht-rd-lease+jwt", &lease_value},
      std::tuple{grant, &host_key, "ht-rd-grant+jwt", &grant_value}}) {
    const auto error = verify_jws(compact, *key, type, *destination);
    if (error != Error::ok) return error;
  }
  VerifiedLease ticket_claims{}, lease_claims{};
  auto error = session_claims(ticket_value, e, signer, now, false, ticket_claims);
  if (error != Error::ok) return error;
  error = session_claims(lease_value, e, signer, now, true, lease_claims);
  if (error != Error::ok) return error;
  const auto& c = grant_value.claims;
  uint64_t granted = 0;
  if (!fields(c, {"id", "server_instance_id", "owner_user_id", "host_endpoint_id", "controller_endpoint_id", "host_jkt", "controller_jkt",
                  "scope", "mode", "one_session_request_id", "grant_version", "expires_at"}) ||
      !same_string(c["id"], e.grant_id) || !same_string(c["server_instance_id"], e.server_instance_id) ||
      !same_string(c["owner_user_id"], e.owner_user_id) || !same_string(c["host_endpoint_id"], e.host_endpoint_id) ||
      !same_string(c["controller_endpoint_id"], e.controller_endpoint_id) || !same_string(c["host_jkt"], e.host_jkt) ||
      !same_string(c["controller_jkt"], e.controller_jkt) || !same_integer(c["grant_version"], e.grant_version)) return Error::identity;
  if (same_string(c["mode"], "one_session")) {
    if (!same_string(c["one_session_request_id"], e.session_request_id)) return Error::identity;
  } else if (!same_string(c["mode"], "persistent") || !c["one_session_request_id"].isNull()) return Error::identity;
  if (!permissions(c["scope"], granted) || (ticket_claims.permissions & ~granted) ||
      (lease_claims.permissions & ~ticket_claims.permissions)) return Error::permission;
  if (!c["expires_at"].isNull()) {
    int64_t expiry = 0;
    if (!iso_time(c["expires_at"], expiry) || expiry <= now || lease_claims.expires_at_unix_ms > expiry) return Error::expired;
  }
  output = lease_claims;
  return Error::ok;
}
}
