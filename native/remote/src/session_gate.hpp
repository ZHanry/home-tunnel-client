#pragma once
#include "protocol.hpp"
#include <array>
#include <cstdint>
#include <set>
#include <map>
#include <string>
#include <string_view>

namespace ht::rd {
enum class GateResult { ok, closed, expired, identity, path, state, permission, replay, malformed, backend };
enum class Candidate { host, server_reflexive, peer_reflexive, relay, unknown };
struct SelectedPair {
    std::string_view transport;
    Candidate local = Candidate::unknown, remote = Candidate::unknown;
    bool nominated = false, succeeded = false;
    uint64_t revision = 0;
};
// Internal authenticated claims. Only the native JWS/local-grant verifier may produce these
// for a real session. This type is deliberately NOT exposed through the C ABI or IPC.
struct VerifiedLease {
    uint32_t connection_epoch;
    uint64_t sequence;
    uint64_t permissions;
    int64_t issued_at_unix_ms, expires_at_unix_ms;
};
class InputSink {
public:
    virtual ~InputSink() = default;
    virtual bool key(uint16_t usage, bool down, bool repeat) = 0;
    virtual bool button(uint8_t button, bool down) = 0;
    virtual bool pointer(uint16_t display_slot, uint16_t x, uint16_t y) = 0;
    virtual bool wheel(int32_t, int32_t) { return false; }
    virtual bool text(std::string_view) { return false; }
};
class SessionGate {
public:
    explicit SessionGate(InputSink& sink) : sink_(sink) {}
    ~SessionGate();
    SessionGate(const SessionGate&) = delete;
    SessionGate& operator=(const SessionGate&) = delete;
    GateResult authorize(const VerifiedLease&, int64_t wall_ms, uint64_t steady_ms);
    GateResult renew(const VerifiedLease&, int64_t wall_ms, uint64_t steady_ms);
    GateResult peer_authenticated(uint32_t epoch, uint64_t now);
    GateResult selected_pair(uint32_t epoch, const SelectedPair&, uint64_t now);
    GateResult first_frame(uint32_t epoch, uint64_t now);
    GateResult synchronize_input(uint32_t epoch, uint32_t input_epoch, uint32_t layout_epoch, uint64_t now, uint16_t display_slot = 0);
    GateResult heartbeat(uint32_t epoch, uint32_t input_epoch, uint64_t state_version, uint64_t now);
    GateResult accept_key(std::span<const uint8_t> message, uint64_t now);
    GateResult accept_button(std::span<const uint8_t> message, uint64_t now);
    GateResult accept_pointer(std::span<const uint8_t> message, uint64_t now);
    GateResult accept_wheel(std::span<const uint8_t> message, uint64_t now);
    GateResult accept_text(std::span<const uint8_t> message, uint64_t now);
    GateResult tick(uint64_t now);
    GateResult reconnect(uint32_t epoch, uint64_t now);
    void pause();
    void release_control() { release_inputs(); }
    void close();
    bool media_allowed() const { return !closed_ && authenticated_ && path_verified_; }
    bool input_allowed() const { return media_allowed() && first_frame_ && input_enabled_; }
    uint32_t input_epoch() const { return input_epoch_; }
    uint64_t deadline_ms() const { return deadline_; }
    uint64_t lease_sequence() const { return lease_sequence_; }
    bool input_releases_pending() const { return !pressed_keys_.empty() || !pressed_buttons_.empty(); }
private:
    void release_inputs();
    GateResult lease_deadline(const VerifiedLease&, int64_t, uint64_t, uint64_t&) const;
    InputSink& sink_;
    bool closed_ = true, authenticated_ = false, path_verified_ = false, first_frame_ = false, input_enabled_ = false;
    uint32_t epoch_ = 0, input_epoch_ = 0, layout_epoch_ = 0, input_sequence_ = 0;
    uint32_t motion_sequence_ = 0, motion_id_ = 0;
    uint64_t lease_sequence_ = 0, permissions_ = 0, deadline_ = 0, last_now_ = 0, heartbeat_at_ = 0, heartbeat_version_ = 0, pair_revision_ = 0;
    std::set<uint16_t> pressed_keys_;
    std::set<uint8_t> pressed_buttons_;
    std::map<std::array<uint8_t,16>,std::pair<std::string,bool>> text_ids_;
    uint16_t display_slot_ = 0;
};
}
