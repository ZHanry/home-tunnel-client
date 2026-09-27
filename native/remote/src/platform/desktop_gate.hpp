#pragma once
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <span>

namespace ht::rd {
inline constexpr uint32_t kDesktopGrantMagic = 0x48544447u;
inline constexpr uint32_t kDesktopGrantVersion = 1;
inline constexpr std::size_t kDesktopGrantBytes = 52;

enum class DesktopClass : uint8_t { none = 0, ordinary = 1, secure = 2, denied = 3 };

struct DesktopGrantView {
    bool well_formed = false;
    uint32_t session_id = 0;
    uint64_t expires_unix_ms = 0;
};

inline uint32_t read_desktop_u32(std::span<const uint8_t, 4> data) {
    return uint32_t(data[0]) | (uint32_t(data[1]) << 8) | (uint32_t(data[2]) << 16) | (uint32_t(data[3]) << 24);
}
inline uint64_t read_desktop_u64(std::span<const uint8_t, 8> data) {
    uint64_t value = 0;
    for (int shift = 0; shift < 8; ++shift) value |= uint64_t(data[shift]) << (8 * shift);
    return value;
}

inline DesktopGrantView parse_desktop_grant(std::span<const uint8_t> data) {
    DesktopGrantView grant;
    if (data.size() != kDesktopGrantBytes || read_desktop_u32(data.first<4>()) != kDesktopGrantMagic ||
        read_desktop_u32(data.subspan<4, 4>()) != kDesktopGrantVersion) return grant;
    grant.session_id = read_desktop_u32(data.subspan<8, 4>());
    grant.expires_unix_ms = read_desktop_u64(data.subspan<12, 8>());
    grant.well_formed = grant.session_id != 0 && grant.session_id != 0xffffffffu && grant.expires_unix_ms != 0;
    return grant;
}

inline bool desktop_grant_accepts(DesktopGrantView grant, uint32_t active_session, uint64_t now_ms) {
    return grant.well_formed && grant.session_id == active_session && now_ms < grant.expires_unix_ms;
}

inline bool capture_allowed(DesktopClass desktop, bool service_authorized) {
    if (desktop == DesktopClass::ordinary) return true;
    return desktop == DesktopClass::secure && service_authorized;
}
inline bool service_scope_matches(bool enabled,std::string_view bound_id,std::string_view bound_jkt,
                                  std::string_view verified_id,std::string_view verified_jkt){
    return enabled && !bound_id.empty() && bound_jkt.size()==43 &&
           bound_id==verified_id && bound_jkt==verified_jkt;
}

inline bool clipboard_allowed(DesktopClass desktop, bool user_context) {
    return desktop == DesktopClass::ordinary && user_context;
}

inline bool files_allowed(DesktopClass desktop, bool user_context) {
    return user_context && (desktop == DesktopClass::ordinary || desktop == DesktopClass::secure);
}

inline bool transition_releases_input(DesktopClass previous, DesktopClass next) {
    return previous != DesktopClass::none && previous != next;
}

inline bool protected_worker_path(std::string_view path, std::string_view program_files) {
    constexpr std::string_view suffix = "\\Home Tunnel\\home_tunnel_remote_host.exe";
    if (program_files.empty() || path.size() != program_files.size() + suffix.size()) return false;
    if (path.find("..") != std::string_view::npos || path.find('/') != std::string_view::npos) return false;
    if (!path.starts_with(program_files) || path.substr(program_files.size()) != suffix) return false;
    for (const auto marker : {std::string_view("\\Users\\"), std::string_view("\\Temp\\"), std::string_view("\\AppData\\"), std::string_view("\\Public\\")}) {
        if (path.find(marker) != std::string_view::npos) return false;
    }
    return true;
}
}
