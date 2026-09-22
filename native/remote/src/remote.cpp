#include "home_tunnel/remote.h"
#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace {
struct Session {
    ht_rd_callbacks_v1 callbacks{};
    std::mutex mutex;
    std::condition_variable callback_done;
    size_t callbacks_running = 0;
    bool releasing = false;
    bool closed = false;
    uint64_t generation = 0;
};
std::mutex registry_mutex;
std::unordered_map<ht_rd_handle, std::shared_ptr<Session>> sessions;
std::atomic<uint64_t> next_handle{1};
constexpr size_t max_handles = 16;

std::shared_ptr<Session> find(ht_rd_handle handle) {
    const std::lock_guard lock(registry_mutex);
    const auto found = sessions.find(handle);
    return found == sessions.end() ? nullptr : found->second;
}
template<class T> bool compatible(const T* value) {
    return value && value->size == sizeof(T) && value->abi_version == HT_RD_ABI_V1;
}
ht_rd_result unavailable(ht_rd_handle handle, const uint8_t* bytes, size_t length, size_t maximum) {
    if (!bytes || length == 0 || length > maximum) return HT_RD_INVALID_ARGUMENT;
    const auto session = find(handle);
    if (!session) return HT_RD_INVALID_HANDLE;
    const std::lock_guard lock(session->mutex);
    return session->closed ? HT_RD_STATE_CONFLICT : HT_RD_BACKEND_UNAVAILABLE;
}
ht_rd_result notify(ht_rd_handle handle, uint32_t reason, bool close) {
    const auto session = find(handle);
    if (!session) return HT_RD_INVALID_HANDLE;
    ht_rd_event_v1 event{};
    ht_rd_callbacks_v1 callbacks{};
    {
        const std::lock_guard lock(session->mutex);
        if (session->releasing) return HT_RD_INVALID_HANDLE;
        if (session->closed) return close ? HT_RD_OK : HT_RD_STATE_CONFLICT;
        session->closed = close;
        event = {sizeof(event), HT_RD_ABI_V1, static_cast<uint32_t>(close ? HT_RD_EVENT_CLOSED : HT_RD_EVENT_PAUSED),
                 reason, ++session->generation, nullptr, 0};
        callbacks = session->callbacks;
        if (callbacks.on_event) ++session->callbacks_running;
    }
    // No native lock is held while invoking application code. Release waits for
    // all callbacks to return before the caller may destroy its callback context.
    auto result = HT_RD_OK;
    if (callbacks.on_event) {
        try { callbacks.on_event(callbacks.user_data, &event); }
        catch (...) { result = HT_RD_INTERNAL_ERROR; }
        const std::lock_guard lock(session->mutex);
        --session->callbacks_running;
        session->callback_done.notify_all();
    }
    return result;
}
}

extern "C" {
uint32_t ht_rd_abi_version(void) { return HT_RD_ABI_V1; }
ht_rd_result ht_rd_create(const ht_rd_config_v1* config, const ht_rd_callbacks_v1* callbacks, ht_rd_handle* out) {
    if (!out) return HT_RD_INVALID_ARGUMENT;
    *out = 0;
    if (!compatible(config) || !compatible(callbacks)) return HT_RD_ABI_MISMATCH;
    if ((config->role != 1 && config->role != 2) || config->reserved != 0) return HT_RD_INVALID_ARGUMENT;
    try {
        auto session = std::make_shared<Session>();
        session->callbacks = *callbacks;
        const std::lock_guard lock(registry_mutex);
        if (sessions.size() >= max_handles) return HT_RD_RESOURCE_LIMIT;
        const auto handle = next_handle.fetch_add(1);
        if (handle == 0) return HT_RD_RESOURCE_LIMIT;
        sessions.emplace(handle, session);
        *out = handle;
        return HT_RD_OK;
    } catch (...) { return HT_RD_INTERNAL_ERROR; }
}
ht_rd_result ht_rd_start(ht_rd_handle handle, const uint8_t* data, size_t length) {
    return unavailable(handle, data, length, 16384);
}
ht_rd_result ht_rd_on_signal(ht_rd_handle handle, const uint8_t* data, size_t length) {
    return unavailable(handle, data, length, HT_RD_MAX_SIGNAL_BYTES);
}
ht_rd_result ht_rd_submit_input(ht_rd_handle handle, const uint8_t* data, size_t length) {
    return unavailable(handle, data, length, HT_RD_MAX_INPUT_BYTES);
}
ht_rd_result ht_rd_get_capabilities(ht_rd_handle handle, ht_rd_capabilities_v1* output) {
    if (!compatible(output)) return HT_RD_ABI_MISMATCH;
    if (!find(handle)) return HT_RD_INVALID_HANDLE;
    *output = {sizeof(*output), HT_RD_ABI_V1, 0, HT_RD_BACKEND_UNAVAILABLE, 0, 0, 4, 0, 0};
    return HT_RD_OK;
}
ht_rd_result ht_rd_set_surface(ht_rd_handle handle, const ht_rd_surface_v1* surface) {
    if (!compatible(surface)) return HT_RD_ABI_MISMATCH;
    if (surface->reserved != 0 || surface->type > 4 || (surface->type == 0) != (surface->native_window == nullptr)) return HT_RD_INVALID_ARGUMENT;
    const auto session = find(handle);
    if (!session) return HT_RD_INVALID_HANDLE;
    const std::lock_guard lock(session->mutex);
    if (session->closed || surface->generation <= session->generation) return HT_RD_STATE_CONFLICT;
    // No ownership is taken while a render backend is unavailable.
    return HT_RD_BACKEND_UNAVAILABLE;
}
ht_rd_result ht_rd_pause(ht_rd_handle handle, uint32_t reason) { return notify(handle, reason, false); }
ht_rd_result ht_rd_close(ht_rd_handle handle, uint32_t reason) { return notify(handle, reason, true); }
void ht_rd_release(ht_rd_handle handle) {
    std::shared_ptr<Session> session;
    {
        const std::lock_guard lock(registry_mutex);
        const auto found = sessions.find(handle);
        if (found == sessions.end()) return;
        session = std::move(found->second);
        sessions.erase(found);
    }
    std::unique_lock lock(session->mutex);
    session->releasing = true;
    session->closed = true;
    session->callback_done.wait(lock, [&] { return session->callbacks_running == 0; });
    session->callbacks = {};
}
}
