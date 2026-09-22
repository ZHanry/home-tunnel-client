#ifndef HOME_TUNNEL_REMOTE_H
#define HOME_TUNNEL_REMOTE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(HT_RD_SHARED)
# if defined(HT_RD_BUILD)
#  define HT_RD_API __declspec(dllexport)
# else
#  define HT_RD_API __declspec(dllimport)
# endif
#elif defined(__GNUC__)
# define HT_RD_API __attribute__((visibility("default")))
#else
# define HT_RD_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define HT_RD_ABI_V1 1u
#define HT_RD_MAX_SIGNAL_BYTES 65536u
#define HT_RD_MAX_INPUT_BYTES 8192u

typedef uint64_t ht_rd_handle;
typedef enum ht_rd_result {
    HT_RD_OK = 0,
    HT_RD_INVALID_ARGUMENT = 1,
    HT_RD_ABI_MISMATCH = 2,
    HT_RD_INVALID_HANDLE = 3,
    HT_RD_BACKEND_UNAVAILABLE = 4,
    HT_RD_STATE_CONFLICT = 5,
    HT_RD_PATH_REJECTED = 6,
    HT_RD_LEASE_EXPIRED = 7,
    HT_RD_PERMISSION_DENIED = 8,
    HT_RD_PROTOCOL_ERROR = 9,
    HT_RD_RESOURCE_LIMIT = 10,
    HT_RD_INTERNAL_ERROR = 11
} ht_rd_result;

typedef enum ht_rd_event_type {
    HT_RD_EVENT_CLOSED = 1,
    HT_RD_EVENT_PAUSED = 2,
    HT_RD_EVENT_ERROR = 3
} ht_rd_event_type;

typedef struct ht_rd_config_v1 {
    uint32_t size;
    uint32_t abi_version;
    uint32_t role; /* 1 controller, 2 host. No implicit both-role sessions. */
    uint32_t reserved; /* Must be zero. */
} ht_rd_config_v1;

typedef struct ht_rd_event_v1 {
    uint32_t size;
    uint32_t abi_version;
    uint32_t type;
    uint32_t code;
    uint64_t generation;
    const uint8_t* payload;
    size_t payload_length;
} ht_rd_event_v1;

/* Borrowed data is valid only until this callback returns. Never throw across ABI. */
typedef void (*ht_rd_event_callback)(void* user_data, const ht_rd_event_v1* event);
typedef struct ht_rd_callbacks_v1 {
    uint32_t size;
    uint32_t abi_version;
    ht_rd_event_callback on_event;
    void* user_data;
} ht_rd_callbacks_v1;

typedef struct ht_rd_surface_v1 {
    uint32_t size;
    uint32_t abi_version;
    uint32_t type; /* 0 detach; 1 HWND; 2 NSView; 3 Linux; 4 ANativeWindow. */
    uint32_t reserved;
    uint64_t generation;
    void* native_window;
} ht_rd_surface_v1;

typedef struct ht_rd_capabilities_v1 {
    uint32_t size;
    uint32_t abi_version;
    uint32_t available; /* Only true for a usable, linked media implementation. */
    uint32_t reason;
    uint32_t can_host;
    uint32_t can_control;
    uint32_t max_controller_sessions;
    uint32_t reserved;
    uint64_t permissions;
} ht_rd_capabilities_v1;

HT_RD_API uint32_t ht_rd_abi_version(void);
HT_RD_API ht_rd_result ht_rd_create(const ht_rd_config_v1*, const ht_rd_callbacks_v1*, ht_rd_handle*);
/* Ticket/proof verification is performed in the native implementation, never by a caller bool. */
HT_RD_API ht_rd_result ht_rd_start(ht_rd_handle, const uint8_t* ticket, size_t length);
HT_RD_API ht_rd_result ht_rd_on_signal(ht_rd_handle, const uint8_t* envelope, size_t length);
HT_RD_API ht_rd_result ht_rd_submit_input(ht_rd_handle, const uint8_t* message, size_t length);
/* On success the implementation retains the platform surface; the caller keeps its own ref. */
HT_RD_API ht_rd_result ht_rd_set_surface(ht_rd_handle, const ht_rd_surface_v1*);
HT_RD_API ht_rd_result ht_rd_get_capabilities(ht_rd_handle, ht_rd_capabilities_v1*);
HT_RD_API ht_rd_result ht_rd_pause(ht_rd_handle, uint32_t reason);
HT_RD_API ht_rd_result ht_rd_close(ht_rd_handle, uint32_t reason);
/* Idempotent. The owner serializes release with API calls. Release waits for
 * callbacks to finish; none may start after it returns. Do not call release
 * from a callback (schedule it on the owning thread instead). After return the
 * owner may destroy callback user_data. Successful surface attachments retain
 * the platform reference until detach/release. */
HT_RD_API void ht_rd_release(ht_rd_handle);

#ifdef __cplusplus
}
#endif
#endif
