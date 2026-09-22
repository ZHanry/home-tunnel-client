#include "protocol.hpp"
#include <algorithm>
#include <string_view>

namespace ht::rd {
uint16_t read_u16(std::span<const uint8_t> bytes, size_t offset) {
    return static_cast<uint16_t>((uint16_t(bytes[offset]) << 8) | bytes[offset + 1]);
}
uint32_t read_u32(std::span<const uint8_t> bytes, size_t offset) {
    return (uint32_t(bytes[offset]) << 24) | (uint32_t(bytes[offset+1]) << 16) |
           (uint32_t(bytes[offset+2]) << 8) | bytes[offset+3];
}
uint64_t read_u64(std::span<const uint8_t> bytes, size_t offset) {
    return (uint64_t(read_u32(bytes, offset)) << 32) | read_u32(bytes, offset + 4);
}
bool valid_utf8(std::span<const uint8_t> input) {
    size_t index = 0;
    while (index < input.size()) {
        const auto first = input[index++];
        if (first < 0x80) continue;
        unsigned count = 0;
        uint32_t codepoint = 0, minimum = 0;
        if (first >= 0xc2 && first <= 0xdf) { count = 1; codepoint = first & 0x1f; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { count = 2; codepoint = first & 0x0f; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { count = 3; codepoint = first & 7; minimum = 0x10000; }
        else return false;
        if (input.size() - index < count) return false;
        for (unsigned n = 0; n < count; ++n) {
            const auto byte = input[index++];
            if ((byte & 0xc0) != 0x80) return false;
            codepoint = (codepoint << 6) | (byte & 0x3f);
        }
        if (codepoint < minimum || codepoint > 0x10ffff || (codepoint >= 0xd800 && codepoint <= 0xdfff)) return false;
    }
    return true;
}
FrameError parse_frame(std::span<const uint8_t> bytes, Channel channel, uint32_t epoch, Frame& output) {
    using namespace protocol;
    output = {};
    if (bytes.size() < HEADER_LENGTH) return FrameError::truncated;
    if (read_u16(bytes, 0) != MAGIC || bytes[2] != VERSION || read_u16(bytes, 6) != HEADER_LENGTH) return FrameError::header;
    const auto rule = std::find_if(MESSAGE_RULES.begin(), MESSAGE_RULES.end(), [&](const auto& item) { return item.type == bytes[3]; });
    if (rule == MESSAGE_RULES.end()) return FrameError::type;
    if (rule->channel != static_cast<uint8_t>(channel)) return FrameError::channel;
    if (bytes.size() > CHANNEL_LIMITS[rule->channel] || read_u32(bytes, 20) != bytes.size() - HEADER_LENGTH) return FrameError::size;
    const auto flags = read_u16(bytes, 4);
    if ((flags & ~rule->flags) != 0) return FrameError::flags;
    if (epoch == 0 || read_u32(bytes, 8) != epoch) return FrameError::epoch;
    const auto sequence = read_u32(bytes, 16);
    if (sequence == 0 || sequence >= SEQUENCE_RECONNECT_AT) return FrameError::sequence;
    const auto input_epoch = read_u32(bytes, 12);
    if ((channel == Channel::input || channel == Channel::motion) ? input_epoch == 0 : input_epoch != 0) return FrameError::epoch;
    const auto payload = bytes.subspan(HEADER_LENGTH);
    if (rule->payload != 0 && payload.size() != rule->payload) return FrameError::size;
    // This layer validates framing and UTF-8 only. The consumer MUST apply the message JSON schema.
    if (rule->json && (payload.empty() || !valid_utf8(payload))) return FrameError::payload;
    if (rule->type == KEY && (read_u16(payload, 0) != 7 || payload[4] > 1 || payload[5] > 1 || read_u16(payload, 6) != 0 || (payload[4] == 0 && payload[5] != 0))) return FrameError::payload;
    if (rule->type == POINTER_ABS && read_u16(payload, 10) != 0) return FrameError::payload;
    if (rule->type == WHEEL && read_u16(payload, 10) != 0) return FrameError::payload;
    if (rule->type == BUTTON && (payload[10] < 1 || payload[10] > 5 || payload[11] > 1 || (flags == 0 && (read_u64(payload, 16) != 0 || read_u64(payload, 24) != 0)))) return FrameError::payload;
    if (rule->type == TEXT_COMMIT && (payload.size() < 20 || payload.size() > 20 + TEXT_BYTES || read_u32(payload, 16) != payload.size() - 20 || !valid_utf8(payload.subspan(20)))) return FrameError::payload;
    if ((rule->type == FILE_CHUNK || rule->type == CLIPBOARD_CHUNK) && (payload.size() <= 24 || payload.size() > 24 + FILE_CHUNK_BYTES)) return FrameError::payload;
    output = {rule->type, flags, epoch, input_epoch, sequence, payload};
    return FrameError::ok;
}
std::vector<uint8_t> proof_transcript(const std::array<uint8_t, 16>& id, uint32_t epoch,
                                    const std::array<std::array<uint8_t, 32>, 5>& fields) {
    std::vector<uint8_t> output;
    output.reserve(224);
    const auto u32 = [&](uint32_t value) {
        for (int shift = 24; shift >= 0; shift -= 8) output.push_back(static_cast<uint8_t>(value >> shift));
    };
    const auto append = [&](std::span<const uint8_t> value) {
        u32(static_cast<uint32_t>(value.size()));
        output.insert(output.end(), value.begin(), value.end());
    };
    constexpr std::string_view domain = "ht-rd-proof-v1";
    append({reinterpret_cast<const uint8_t*>(domain.data()), domain.size()});
    append(id);
    u32(epoch);
    for (const auto& field : fields) append(field);
    return output;
}
}
