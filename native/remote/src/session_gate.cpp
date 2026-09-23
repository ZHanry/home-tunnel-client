#include "session_gate.hpp"
#include <limits>
#include <algorithm>
#include <bit>

namespace ht::rd {
SessionGate::~SessionGate() { release_inputs(); }
GateResult SessionGate::lease_deadline(const VerifiedLease& lease, int64_t wall, uint64_t now, uint64_t& deadline) const {
    if (lease.connection_epoch == 0 || lease.sequence == 0 || lease.permissions == 0 ||
        (lease.permissions & ~protocol::ALL_PERMISSIONS) != 0 ||
        (lease.permissions & protocol::PERMISSION_VIEW) == 0 || lease.issued_at_unix_ms < 0 ||
        lease.issued_at_unix_ms > wall || lease.expires_at_unix_ms <= wall ||
        lease.expires_at_unix_ms <= lease.issued_at_unix_ms ||
        lease.expires_at_unix_ms - lease.issued_at_unix_ms > 900000) return GateResult::identity;
    const auto remaining = static_cast<uint64_t>(lease.expires_at_unix_ms - wall);
    if (remaining > std::numeric_limits<uint64_t>::max() - now) return GateResult::identity;
    deadline = now + remaining;
    return GateResult::ok;
}
GateResult SessionGate::authorize(const VerifiedLease& lease, int64_t wall, uint64_t now) {
    if (!closed_ || epoch_ != 0) return GateResult::state;
    uint64_t deadline;
    const auto result = lease_deadline(lease, wall, now, deadline);
    if (result != GateResult::ok) return result;
    epoch_ = lease.connection_epoch;
    lease_sequence_ = lease.sequence;
    permissions_ = lease.permissions;
    deadline_ = deadline;
    last_now_ = now;
    closed_ = false;
    return GateResult::ok;
}
GateResult SessionGate::renew(const VerifiedLease& lease, int64_t wall, uint64_t now) {
    const auto current = tick(now);
    if (current != GateResult::ok) return current;
    if (lease.connection_epoch != epoch_ || lease.sequence <= lease_sequence_ || (lease.permissions & ~permissions_) != 0) return GateResult::identity;
    uint64_t deadline;
    const auto result = lease_deadline(lease, wall, now, deadline);
    if (result != GateResult::ok) return result;
    if (lease.permissions != permissions_) release_inputs();
    permissions_ = lease.permissions;
    lease_sequence_ = lease.sequence;
    deadline_ = deadline;
    return GateResult::ok;
}
GateResult SessionGate::tick(uint64_t now) {
    if (closed_) { if(input_releases_pending()) release_inputs(); return GateResult::closed; }
    if (now < last_now_ || now >= deadline_) { close(); return GateResult::expired; }
    last_now_ = now;
    // The wire value is an upper bound, not the time to begin OS releases.
    // Reserve two heartbeat/tick intervals for scheduling and actual key-up
    // delivery; a busy encoder or file write must not consume the last margin.
    if (input_enabled_ && now - heartbeat_at_ >= protocol::INPUT_WATCHDOG_MS - 2 * protocol::INPUT_HEARTBEAT_MS) release_inputs();
    else if (!input_enabled_ && (!pressed_keys_.empty() || !pressed_buttons_.empty())) release_inputs();
    return GateResult::ok;
}
GateResult SessionGate::peer_authenticated(uint32_t epoch, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch != epoch_) return GateResult::identity;
    authenticated_ = true;
    return GateResult::ok;
}
GateResult SessionGate::selected_pair(uint32_t epoch, const SelectedPair& pair, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch != epoch_ || pair.revision <= pair_revision_) return GateResult::replay;
    pair_revision_ = pair.revision;
    // A new selected pair ALWAYS closes sensitive gates before it is checked.
    release_inputs();
    first_frame_ = false;
    path_verified_ = false;
    const auto direct = [](Candidate type) { return type == Candidate::host || type == Candidate::server_reflexive || type == Candidate::peer_reflexive; };
    if (pair.transport != "udp" || !pair.nominated || !pair.succeeded || !direct(pair.local) || !direct(pair.remote)) return GateResult::path;
    path_verified_ = true;
    return GateResult::ok;
}
GateResult SessionGate::first_frame(uint32_t epoch, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch != epoch_ || !media_allowed()) return GateResult::state;
    first_frame_ = true;
    return GateResult::ok;
}
GateResult SessionGate::synchronize_input(uint32_t epoch, uint32_t input_epoch, uint32_t layout, uint64_t now, uint16_t display_slot) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch != epoch_ || !media_allowed() || !first_frame_ || input_epoch == 0 || input_epoch <= input_epoch_ || layout == 0 || layout < layout_epoch_ || display_slot >= 16) return GateResult::state;
    release_inputs();
    if (!pressed_keys_.empty() || !pressed_buttons_.empty()) return GateResult::backend;
    input_epoch_ = input_epoch;
    layout_epoch_ = layout;
    display_slot_ = display_slot;
    heartbeat_version_ = 0;
    motion_id_ = 0;
    heartbeat_at_ = now;
    input_enabled_ = true;
    return GateResult::ok;
}
GateResult SessionGate::heartbeat(uint32_t epoch, uint32_t input_epoch, uint64_t version, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch != epoch_ || input_epoch != input_epoch_ || !input_allowed() || version <= heartbeat_version_) return GateResult::replay;
    heartbeat_version_ = version;
    heartbeat_at_ = now;
    return GateResult::ok;
}
GateResult SessionGate::accept_key(std::span<const uint8_t> bytes, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (!input_allowed()) return GateResult::state;
    if ((permissions_ & protocol::PERMISSION_INPUT_KEYBOARD) == 0) return GateResult::permission;
    Frame frame;
    if (parse_frame(bytes, Channel::input, epoch_, frame) != FrameError::ok || frame.type != protocol::KEY) return GateResult::malformed;
    if (frame.input_epoch != input_epoch_ || frame.sequence <= input_sequence_) return GateResult::replay;
    const auto usage = read_u16(frame.payload, 2);
    if (usage < 4 || usage > 231) return GateResult::malformed;
    const bool down = frame.payload[4] == 1, repeat = frame.payload[5] == 1;
    const bool pressed = pressed_keys_.contains(usage);
    if ((repeat && !pressed) || (down && pressed && !repeat)) return GateResult::state;
    if (!down && !pressed) { input_sequence_ = frame.sequence; return GateResult::ok; }
    if (!sink_.key(usage, down, repeat)) { release_inputs(); return GateResult::backend; }
    input_sequence_ = frame.sequence;
    if (down) pressed_keys_.insert(usage); else pressed_keys_.erase(usage);
    return GateResult::ok;
}
void SessionGate::release_inputs() {
    // A permission/desktop transition can temporarily reject key-up. Retain that
    // debt and retry while paused; never enable new input before releases succeed.
    for (auto item=pressed_keys_.begin();item!=pressed_keys_.end();) {
        if(sink_.key(*item,false,false)) item=pressed_keys_.erase(item); else ++item;
    }
    for (auto item=pressed_buttons_.begin();item!=pressed_buttons_.end();) {
        if(sink_.button(*item,false)) item=pressed_buttons_.erase(item); else ++item;
    }
    input_enabled_ = false;
    // The next enable requires a strictly newer input epoch even after a watchdog timeout.
}
GateResult SessionGate::accept_button(std::span<const uint8_t> bytes, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (!input_allowed()) return GateResult::state;
    if ((permissions_ & protocol::PERMISSION_INPUT_POINTER) == 0) return GateResult::permission;
    Frame frame;
    if (parse_frame(bytes, Channel::input, epoch_, frame) != FrameError::ok || frame.type != protocol::BUTTON) return GateResult::malformed;
    if (frame.input_epoch != input_epoch_ || frame.sequence <= input_sequence_) return GateResult::replay;
    if (read_u32(frame.payload,0) != layout_epoch_ || read_u16(frame.payload,4) != display_slot_) return GateResult::state;
    if (frame.flags != 0) return GateResult::backend; // Relative backend is not implemented yet.
    const auto button = frame.payload[10];
    const bool down = frame.payload[11] == 1;
    const bool pressed = pressed_buttons_.contains(button);
    if (down && pressed) return GateResult::state;
    if (!down && !pressed) { input_sequence_ = frame.sequence; return GateResult::ok; }
    // The reliable button contains its own absolute coordinates, so losing the
    // latest unreliable motion message cannot turn this into a click elsewhere.
    if (!sink_.pointer(display_slot_,read_u16(frame.payload,6),read_u16(frame.payload,8)) || !sink_.button(button,down)) {
        release_inputs(); return GateResult::backend;
    }
    input_sequence_ = frame.sequence;
    if (down) pressed_buttons_.insert(button); else pressed_buttons_.erase(button);
    motion_id_=std::max(motion_id_,read_u32(frame.payload,12));
    return GateResult::ok;
}
GateResult SessionGate::accept_pointer(std::span<const uint8_t> bytes,uint64_t now) {
    const auto result=tick(now);if(result!=GateResult::ok)return result;
    if(!input_allowed())return GateResult::state;
    if(!(permissions_&protocol::PERMISSION_INPUT_POINTER))return GateResult::permission;
    Frame frame;if(parse_frame(bytes,Channel::motion,epoch_,frame)!=FrameError::ok || frame.type!=protocol::POINTER_ABS)return GateResult::malformed;
    const auto motion=read_u32(frame.payload,12);
    if(frame.input_epoch!=input_epoch_ || frame.sequence<=motion_sequence_ || !motion || motion<=motion_id_)return GateResult::replay;
    if(read_u32(frame.payload,0)!=layout_epoch_ || read_u16(frame.payload,4)!=display_slot_)return GateResult::state;
    if(!sink_.pointer(display_slot_,read_u16(frame.payload,6),read_u16(frame.payload,8))){release_inputs();return GateResult::backend;}
    motion_sequence_=frame.sequence;motion_id_=motion;return GateResult::ok;
}
GateResult SessionGate::accept_wheel(std::span<const uint8_t> bytes,uint64_t now) {
    const auto result=tick(now);if(result!=GateResult::ok)return result;
    if(!input_allowed())return GateResult::state;
    if(!(permissions_&protocol::PERMISSION_INPUT_POINTER))return GateResult::permission;
    Frame frame;if(parse_frame(bytes,Channel::input,epoch_,frame)!=FrameError::ok || frame.type!=protocol::WHEEL)return GateResult::malformed;
    if(frame.input_epoch!=input_epoch_ || frame.sequence<=input_sequence_)return GateResult::replay;
    if(read_u32(frame.payload,0)!=layout_epoch_ || read_u16(frame.payload,4)!=display_slot_)return GateResult::state;
    const auto dx=std::bit_cast<int32_t>(read_u32(frame.payload,12)),dy=std::bit_cast<int32_t>(read_u32(frame.payload,16));
    if(dx < -12000 || dx>12000 || dy < -12000 || dy>12000)return GateResult::malformed;
    if(!sink_.pointer(display_slot_,read_u16(frame.payload,6),read_u16(frame.payload,8)) || !sink_.wheel(dx,dy)){release_inputs();return GateResult::backend;}
    input_sequence_=frame.sequence;motion_id_=std::max(motion_id_,read_u32(frame.payload,20));return GateResult::ok;
}
GateResult SessionGate::accept_text(std::span<const uint8_t> bytes,uint64_t now) {
    const auto result=tick(now);if(result!=GateResult::ok)return result;
    if(!input_allowed())return GateResult::state;
    if(!(permissions_&protocol::PERMISSION_INPUT_TEXT))return GateResult::permission;
    Frame frame;if(parse_frame(bytes,Channel::input,epoch_,frame)!=FrameError::ok || frame.type!=protocol::TEXT_COMMIT || frame.payload.size()==20)return GateResult::malformed;
    if(frame.input_epoch!=input_epoch_ || frame.sequence<=input_sequence_)return GateResult::replay;
    std::array<uint8_t,16> id{};std::copy_n(frame.payload.begin(),16,id.begin());
    if(std::all_of(id.begin(),id.end(),[](uint8_t n){return n==0;}))return GateResult::malformed;
    const auto content=frame.payload.subspan(20);const std::string text(reinterpret_cast<const char*>(content.data()),content.size());
    const auto prior=text_ids_.find(id);
    if(prior!=text_ids_.end()){
        if(prior->second.first!=text)return GateResult::malformed;
        input_sequence_=frame.sequence;return prior->second.second?GateResult::replay:GateResult::backend;
    }
    if(text_ids_.size()>=1024)return GateResult::state;
    // Reserve before injection: a partial backend failure must never replay text.
    auto inserted=text_ids_.emplace(id,std::pair{text,false}).first;input_sequence_=frame.sequence;
    if(!sink_.text(text)){release_inputs();return GateResult::backend;}
    inserted->second.second=true;
    return GateResult::ok;
}
void SessionGate::pause() {
    release_inputs();
    first_frame_ = false;
    path_verified_ = false;
}
GateResult SessionGate::reconnect(uint32_t epoch, uint64_t now) {
    const auto result = tick(now);
    if (result != GateResult::ok) return result;
    if (epoch <= epoch_) return GateResult::replay;
    pause();
    epoch_ = epoch;
    authenticated_ = false;
    pair_revision_ = 0;
    input_sequence_ = 0;
    motion_sequence_ = 0;
    motion_id_ = 0;
    // Deadline and lease sequence intentionally survive a reconnect.
    return GateResult::ok;
}
void SessionGate::close() {
    pause();
    closed_ = true;
    authenticated_ = false;
}
}
