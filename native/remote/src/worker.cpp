#include "home_tunnel/remote.h"
#include <array>
#include <cstdio>
#include <string_view>
#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#endif

namespace {
bool write_frame(std::string_view text) {
    const auto size = static_cast<uint32_t>(text.size());
    const std::array<uint8_t, 4> header{static_cast<uint8_t>(size >> 24), static_cast<uint8_t>(size >> 16), static_cast<uint8_t>(size >> 8), static_cast<uint8_t>(size)};
    return std::fwrite(header.data(), 1, header.size(), stdout) == header.size() &&
           std::fwrite(text.data(), 1, text.size(), stdout) == text.size() && std::fflush(stdout) == 0;
}
}
int main(int argc, char** argv) {
    if (argc != 2 || std::string_view(argv[1]) != "--inherited-pipe") return 2;
#if defined(_WIN32)
    if (_setmode(_fileno(stdin), _O_BINARY) == -1 || _setmode(_fileno(stdout), _O_BINARY) == -1) return 3;
#endif
    // stdin/stdout are private inherited anonymous pipes; no TCP, shell, path or signing commands.
    // One strictly framed versioned capability query then exit. Production media is not exposed.
    std::array<uint8_t, 4> header{};
    if (std::fread(header.data(), 1, header.size(), stdin) != header.size()) return 4;
    const uint32_t length = (uint32_t(header[0]) << 24) | (uint32_t(header[1]) << 16) | (uint32_t(header[2]) << 8) | header[3];
    constexpr std::string_view expected = "{\"abi\":1,\"operation\":\"capabilities\"}";
    if (length != expected.size()) return 5;
    std::array<char, 256> input{};
    if (std::fread(input.data(), 1, length, stdin) != length || std::string_view(input.data(), length) != expected) return 6;
    return write_frame("{\"abi\":1,\"available\":false,\"reason\":\"RD_BACKEND_UNAVAILABLE\",\"can_host\":false,\"can_control\":false,\"max_controller_sessions\":4}") ? 0 : 7;
}
