#pragma once
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <cstdint>
#include <mutex>
#include <vector>

namespace ht::rd {
class UserTokenHandle {
public:
    HANDLE value = nullptr;
    ~UserTokenHandle() { if (value) CloseHandle(value); }
    UserTokenHandle() = default;
    UserTokenHandle(const UserTokenHandle&) = delete;
    UserTokenHandle& operator=(const UserTokenHandle&) = delete;
};
struct UserIdentity {
    std::vector<unsigned char> sid;
    LUID logon{};
    DWORD session = 0;
    bool valid = false;
    bool system = false;
    bool same_user(const UserIdentity& other) const {
        return valid && other.valid && !system && !other.system &&
            session == other.session && logon.HighPart == other.logon.HighPart &&
            logon.LowPart == other.logon.LowPart && sid == other.sid;
    }
};
inline UserIdentity token_identity(HANDLE token) {
    UserIdentity result;
    if (!token || token == INVALID_HANDLE_VALUE) return result;
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    if (size < sizeof(TOKEN_USER) || size > 4096) return result;
    std::vector<unsigned char> buffer(size);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) return result;
    const auto sid = reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid;
    if (!IsValidSid(sid)) return result;
    result.system = IsWellKnownSid(sid, WinLocalSystemSid) != FALSE;
    result.sid.resize(GetLengthSid(sid));
    if (!CopySid(static_cast<DWORD>(result.sid.size()), result.sid.data(), sid)) return {};
    TOKEN_STATISTICS stats{};
    if (!GetTokenInformation(token, TokenStatistics, &stats, sizeof(stats), &size) ||
        !GetTokenInformation(token, TokenSessionId, &result.session, sizeof(result.session), &size)) return {};
    result.logon = stats.AuthenticationId;
    result.valid = true;
    return result;
}
inline UserIdentity process_identity() {
    UserTokenHandle token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value)) return {};
    return token_identity(token.value);
}
inline bool is_local_system() { const auto user = process_identity(); return user.valid && user.system; }
struct ApprovedUserToken {
    std::mutex mutex;
    UserTokenHandle token;
    UserIdentity identity;
};
inline ApprovedUserToken& approved_user_token() { static ApprovedUserToken state; return state; }
inline bool adopt_user_token(HANDLE source, uint32_t session) {
    if (!is_local_system()) return false;
    auto& state = approved_user_token();
    std::lock_guard lock(state.mutex);
    if (!source) {
        if (state.token.value) CloseHandle(state.token.value);
        state.token.value = nullptr;
        state.identity = {};
        return true;
    }
    const auto identity = token_identity(source);
    DWORD process_session = 0;
    if (!identity.valid || identity.system || session == 0 || session == 0xffffffffu ||
        identity.session != session || session != WTSGetActiveConsoleSessionId() ||
        !ProcessIdToSessionId(GetCurrentProcessId(), &process_session) || process_session != session) return false;
    HANDLE duplicate = nullptr;
    if (!DuplicateTokenEx(source, TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_IMPERSONATE,
                         nullptr, SecurityImpersonation, TokenImpersonation, &duplicate)) return false;
    if (state.token.value) CloseHandle(state.token.value);
    state.token.value = duplicate;
    state.identity = identity;
    return true;
}
// Validate the effective identity on every callback thread and nested operation.
// An existing thread token alone is not proof of the approved interactive logon.
class UserContext {
public:
    explicit UserContext(const UserIdentity* required = nullptr) {
        const auto process = process_identity();
        if (!process.valid) return;
        UserTokenHandle approved;
        if (process.system) {
            auto& state = approved_user_token();
            std::lock_guard lock(state.mutex);
            identity_ = state.identity;
            if (!identity_.valid || identity_.system || identity_.session == 0 ||
                identity_.session != WTSGetActiveConsoleSessionId() ||
                identity_.session != process.session || !state.token.value ||
                !DuplicateHandle(GetCurrentProcess(), state.token.value, GetCurrentProcess(),
                                 &approved.value, 0, FALSE, DUPLICATE_SAME_ACCESS)) return;
        } else {
            identity_ = process;
        }
        if (required && !identity_.same_user(*required)) return;
        UserTokenHandle thread;
        if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &thread.value)) {
            active_ = identity_.same_user(token_identity(thread.value));
            return;
        }
        if (GetLastError() != ERROR_NO_TOKEN) return;
        if (!process.system) { active_ = true; return; }
        if (!ImpersonateLoggedOnUser(approved.value)) return;
        owned_ = true;
        UserTokenHandle effective;
        active_ = OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &effective.value) &&
                  identity_.same_user(token_identity(effective.value));
    }
    ~UserContext() {
        if (owned_ && !RevertToSelf()) TerminateProcess(GetCurrentProcess(), ERROR_ACCESS_DENIED);
    }
    UserContext(const UserContext&) = delete;
    UserContext& operator=(const UserContext&) = delete;
    explicit operator bool() const { return active_; }
    const UserIdentity& identity() const { return identity_; }
private:
    UserIdentity identity_;
    bool active_ = false;
    bool owned_ = false;
};
inline bool user_context_available() { UserContext user; return static_cast<bool>(user); }
}
#endif
