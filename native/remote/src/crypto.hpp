#pragma once
#include <array>
#include <cstdint>
#include <span>

namespace ht::rd {
enum class CryptoResult { valid, invalid, unavailable };
CryptoResult sha256(std::span<const uint8_t> input, std::array<uint8_t,32>& digest);
// ES256 wire signatures are fixed-width r||s, NOT ASN.1 DER. Keys must already
// be pinned to the session/grant by the native identity policy before this call.
CryptoResult verify_p256(std::span<const uint8_t> message,
    const std::array<uint8_t,64>& public_key_xy, const std::array<uint8_t,64>& signature_raw);
}
