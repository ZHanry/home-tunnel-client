#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <vector>
#include "../generated/remote_protocol.hpp"
#include "../generated/remote_rules.hpp"

namespace ht::rd {
enum class Channel : uint8_t { control, input, motion, feedback, clipboard, file };
struct Frame {
    uint8_t type{};
    uint16_t flags{};
    uint32_t connection_epoch{}, input_epoch{}, sequence{};
    std::span<const uint8_t> payload;
};
enum class FrameError { ok, truncated, header, type, channel, size, flags, epoch, sequence, payload };
FrameError parse_frame(std::span<const uint8_t>, Channel, uint32_t expected_epoch, Frame&);
bool valid_utf8(std::span<const uint8_t>);
uint16_t read_u16(std::span<const uint8_t>, size_t);
uint32_t read_u32(std::span<const uint8_t>, size_t);
uint64_t read_u64(std::span<const uint8_t>, size_t);
std::vector<uint8_t> proof_transcript(const std::array<uint8_t, 16>& session_id, uint32_t epoch,
    const std::array<std::array<uint8_t, 32>, 5>& nonce_and_hashes);
}
