#include "controller_identity.hpp"
#include "surface_renderer.hpp"
#include "../include/home_tunnel/remote.h"
#include "../webrtc/sdp_policy.hpp"
#include "api/audio_codecs/builtin_audio_decoder_factory.h"
#include "api/audio_codecs/builtin_audio_encoder_factory.h"
#include "api/create_peerconnection_factory.h"
#include "api/jsep.h"
#include "api/make_ref_counted.h"
#include "api/peer_connection_interface.h"
#include "api/stats/rtcstats_objects.h"
#include "api/stats/rtc_stats_collector_callback.h"
#include "api/video_codecs/builtin_video_decoder_factory.h"
#include "api/video_codecs/builtin_video_encoder_factory.h"
#include "rtc_base/logging.h"
#include "rtc_base/ssl_adapter.h"
#include "rtc_base/thread.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>

namespace ht::rd::android {
namespace {
// JNI only signs with AndroidKeyStore and transports these bounded callbacks.
// All authorization, protocol, path and media decisions remain in this library.
enum Event : uint32_t { signal_request = 4, proof_request = 5, direct_path = 6, control_message = 7, first_frame = 8 };
constexpr uint64_t supported = protocol::PERMISSION_VIEW | protocol::PERMISSION_INPUT_KEYBOARD |
                               protocol::PERMISSION_INPUT_POINTER | protocol::PERMISSION_INPUT_TEXT;
uint64_t steady_ms() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
int64_t wall_ms() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }
bool text(const Json::Value& value, std::string_view expected) { return value.isString() && value.asString() == expected; }
bool number(const Json::Value& value, uint64_t expected) { return value.isUInt64() && value.asUInt64() == expected; }
bool candidate_allowed(std::string_view value) {
  if (value.empty()) return true;
  if (value.size() > 1024 || value.find_first_of("\r\n") != std::string_view::npos) return false;
  std::unique_ptr<webrtc::IceCandidate> candidate(webrtc::CreateIceCandidate("0", 0, std::string(value), nullptr));
  if (!candidate) return false;
  const auto& parsed = candidate->candidate();
  return parsed.protocol() == "udp" && parsed.type() != webrtc::IceCandidateType::kRelay && parsed.address().port() > 0;
}
class Runtime {
 public:
  Runtime() {
    webrtc::LogMessage::LogToDebug(webrtc::LS_NONE); webrtc::LogMessage::SetLogToStderr(false);
    if (!webrtc::InitializeSSL()) return;
    network = webrtc::Thread::CreateWithSocketServer(); signaling = webrtc::Thread::Create();
    if (!network || !signaling || !network->Start() || !signaling->Start()) return;
    factory = webrtc::CreatePeerConnectionFactory(network.get(), network.get(), signaling.get(), nullptr,
      webrtc::CreateBuiltinAudioEncoderFactory(), webrtc::CreateBuiltinAudioDecoderFactory(),
      webrtc::CreateBuiltinVideoEncoderFactory(), webrtc::CreateBuiltinVideoDecoderFactory(), nullptr, nullptr);
  }
  std::unique_ptr<webrtc::Thread> network, signaling;
  webrtc::scoped_refptr<webrtc::PeerConnectionFactoryInterface> factory;
};
// The VM keeps the loaded JNI/media library for the process lifetime. Avoid C++
// static destruction racing JVM shutdown while WebRTC threads are still alive.
Runtime& runtime() { static Runtime* value = new Runtime(); return *value; }
class SetDescription : public webrtc::SetSessionDescriptionObserver {
 public:
  explicit SetDescription(std::function<void(bool)> done) : done_(std::move(done)) {}
  void OnSuccess() override { done_(true); }
  void OnFailure(webrtc::RTCError) override { done_(false); }
 private: std::function<void(bool)> done_;
};
class CreateDescription : public webrtc::CreateSessionDescriptionObserver {
 public:
  explicit CreateDescription(std::function<void(std::unique_ptr<webrtc::SessionDescriptionInterface>)> done) : done_(std::move(done)) {}
  void OnSuccess(webrtc::SessionDescriptionInterface* value) override { done_(std::unique_ptr<webrtc::SessionDescriptionInterface>(value)); }
  void OnFailure(webrtc::RTCError) override { done_(nullptr); }
 private: std::function<void(std::unique_ptr<webrtc::SessionDescriptionInterface>)> done_;
};
class Controller;
class ChannelObserver final : public webrtc::DataChannelObserver {
 public:
  ChannelObserver(Controller& owner, unsigned slot) : owner_(owner), slot_(slot) {}
  void OnStateChange() override;
  void OnMessage(const webrtc::DataBuffer& message) override;
 private: Controller& owner_; unsigned slot_;
};
class Statistics : public webrtc::RTCStatsCollectorCallback {
 public:
  explicit Statistics(std::weak_ptr<Controller> owner) : owner_(std::move(owner)) {}
  void OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report) override;
 private: std::weak_ptr<Controller> owner_;
};

class Controller final : public webrtc::PeerConnectionObserver, public std::enable_shared_from_this<Controller> {
 public:
  explicit Controller(ht_rd_callbacks_v1 callbacks) : callbacks_(callbacks) {}
  bool Start(const Json::Value& context) {
    if (closed_ || identity_ || !context["session_id"].isString() || !context["connection_epoch"].isUInt()) return false;
    identity_ = ControllerIdentity::prepare(context["session_id"].asString(), context["connection_epoch"].asUInt());
    VerifiedLease lease{};
    if (!identity_ || identity_->authorize(context, wall_ms(), supported, lease) != auth::Error::ok || !Lease(lease)) return false;
    webrtc::PeerConnectionInterface::RTCConfiguration config;
    config.sdp_semantics = webrtc::SdpSemantics::kUnifiedPlan;
    config.tcp_candidate_policy = webrtc::PeerConnectionInterface::kTcpCandidatePolicyDisabled;
    config.bundle_policy = webrtc::PeerConnectionInterface::kBundlePolicyMaxBundle;
    config.certificates.push_back(identity_->certificate());
    if (context.isMember("stun_urls")) {
      if (!context["stun_urls"].isArray() || context["stun_urls"].size() > 4) return false;
      for (const auto& url : context["stun_urls"]) {
        if (!url.isString()) return false;
        const auto value = url.asString();
        if (!value.starts_with("stun:") || value.size() > 260 || value.find_first_of("?@/\\# \r\n\t") != std::string::npos) return false;
        webrtc::PeerConnectionInterface::IceServer server; server.urls.push_back(value); config.servers.push_back(server);
      }
    }
    auto created = runtime().factory->CreatePeerConnectionOrError(config, webrtc::PeerConnectionDependencies(this));
    if (!created.ok()) return false;
    peer_ = created.MoveValue();
    webrtc::RtpTransceiverInit receive; receive.direction = webrtc::RtpTransceiverDirection::kRecvOnly;
    auto video = peer_->AddTransceiver(webrtc::MediaType::VIDEO, receive);
    if (!video.ok()) return false;
    std::vector<webrtc::RtpCodecCapability> codecs;
    for (const auto& codec : runtime().factory->GetRtpReceiverCapabilities(webrtc::MediaType::VIDEO).codecs)
      if (codec.name == "VP8" || codec.name == "rtx") codecs.push_back(codec);
    if (codecs.empty() || !video.value()->SetCodecPreferences(codecs).ok()) return false;
    const std::array<std::string, 4> labels{"control", "input", "motion", "feedback"};
    for (unsigned slot = 0; slot < labels.size(); ++slot) {
      webrtc::DataChannelInit options; options.ordered = slot < 2;
      if (slot >= 2) options.maxRetransmits = 0;
      auto channel = peer_->CreateDataChannelOrError(labels[slot], &options);
      if (!channel.ok()) return false;
      auto observer = std::make_unique<ChannelObserver>(*this, slot);
      channel.value()->RegisterObserver(observer.get());
      channels_.emplace(slot, std::make_pair(channel.MoveValue(), std::move(observer)));
    }
    started_ = steady_ms();
    const auto weak = weak_from_this();
    peer_->CreateOffer(webrtc::make_ref_counted<CreateDescription>([weak](auto description) {
      const auto self = weak.lock(); if (!self || self->closed_) return;
      std::string sdp;
      if (!description || !description->ToString(&sdp) || !valid_sdp_profile(sdp, self->identity_->prepared()["dtls_fingerprint_sha256"].asString(), candidate_allowed)) { self->Close("RD_PROTOCOL_MISMATCH"); return; }
      Json::Value payload; payload["type"] = "offer"; payload["sdp"] = sdp;
      self->identity_->expect_offer(payload);
      self->peer_->SetLocalDescription(webrtc::make_ref_counted<SetDescription>([weak, payload](bool ok) {
        if (const auto current = weak.lock(); current && !current->closed_) {
          if (ok) current->Outgoing("peer.offer", payload); else current->Close("RD_MEDIA_FAILED");
        }
      }).get(), description.release());
    }).get(), {});
    Tick(); return true;
  }
  bool Signal(const Json::Value& message) {
    if (!Live()) return false;
    if (text(message["type"], "local.signed_offer")) {
      if (offer_signed_ || identity_->signed_offer(message["envelope"], wall_ms()) != auth::Error::ok) return false;
      offer_signed_ = true;
      for (const auto& candidate : local_candidates_) { Json::Value body; body["candidates"].append(candidate); Outgoing("peer.candidates", body); }
      local_candidates_.clear(); return true;
    }
    if (text(message["type"], "local.proof")) {
      std::vector<uint8_t> signature;
      if (!text(message["request_id"], proof_request_) || proof_request_.empty() || !message["signature"].isString() ||
          !auth::unbase64url(message["signature"].asString(), signature) || identity_->controller_proof(signature) != auth::Error::ok) return false;
      proof_request_.clear(); Json::Value body; body["transcript_version"] = 1;
      body["jkt"] = identity_->expected().controller_jkt; body["signature"] = auth::base64url(signature);
      Send(protocol::SESSION_PROOF, body); MaybeReady(); return !closed_;
    }
    if (text(message["type"], "local.resume")) { paused_ = false; path_reported_ = false; MaybeReady(); return true; }
    if (text(message["type"], "session.lease_updated")) {
      if (!text(message["session_id"], identity_->session_id()) || !number(message["connection_epoch"], identity_->epoch())) return false;
      VerifiedLease lease{};
      if (identity_->renew(message["payload"], wall_ms(), lease) != auth::Error::ok || !Lease(lease)) return false;
      UpdateRendering(); return true;
    }
    Json::Value payload;
    if (identity_->peer_signal(message, wall_ms(), payload) != auth::Error::ok) return false;
    if (text(message["type"], "peer.answer")) {
      if (remote_pending_ || remote_description_ || !payload["sdp"].isString() || !valid_sdp_profile(payload["sdp"].asString(), {}, candidate_allowed)) return false;
      auto description = webrtc::CreateSessionDescription(webrtc::SdpType::kAnswer, payload["sdp"].asString());
      if (!description) return false;
      remote_pending_ = true; const auto weak = weak_from_this();
      peer_->SetRemoteDescription(webrtc::make_ref_counted<SetDescription>([weak](bool ok) {
        if (const auto self = weak.lock(); self && !self->closed_) {
          self->remote_pending_ = false; self->remote_description_ = ok;
          if (!ok || !self->ApplyCandidates()) self->Close("RD_MEDIA_FAILED");
        }
      }).get(), description.release());
      return true;
    }
    if (text(message["type"], "peer.candidates")) {
      if (!payload["candidates"].isArray() || payload["candidates"].size() + remote_candidate_count_ > 32) return false;
      for (const auto& item : payload["candidates"]) {
        if (!item["candidate"].isString() || !candidate_allowed(item["candidate"].asString()) || !item["sdpMid"].isString() ||
            item["sdpMid"].asString().size() > 32 || !item["sdpMLineIndex"].isUInt() || item["sdpMLineIndex"].asUInt() > 8) return false;
        remote_candidates_.push_back(item); ++remote_candidate_count_;
      }
      return ApplyCandidates();
    }
    return text(message["type"], "peer.candidates_done");
  }
  bool Surface(ANativeWindow* window, uint64_t generation) {
    if (closed_ || !renderer_.Attach(window, generation)) return false;
    surface_ = window != nullptr; if (!surface_) ReleaseInput("surface_detached");
    UpdateRendering(); return true;
  }
  void Pause() { if (!closed_) { paused_ = true; ReleaseInput("background"); renderer_.SetAuthorized(false); Emit(HT_RD_EVENT_PAUSED, {}); } }
  void Close(std::string_view reason) {
    if (closed_ || closing_) return; closing_ = true;
    ReleaseInput("closed"); closed_ = true; renderer_.Close();
    if (track_) track_->RemoveSink(&renderer_); track_ = nullptr;
    for (auto& [slot, channel] : channels_) { channel.first->UnregisterObserver(); channel.first->Close(); }
    channels_.clear(); if (peer_) peer_->Close(); peer_ = nullptr;
    Json::Value body; body["error_code"] = std::string(reason); Emit(HT_RD_EVENT_CLOSED, body);
  }
  void Destroy() { Close("RD_LOCAL_CLOSE"); callbacks_ = {}; }
  bool Submit(std::span<const uint8_t> bytes) {
    if (!Live() || !ready_ || !local_path_ || !remote_path_ || !identity_->authenticated() || paused_ || bytes.size() < 24) return false;
    const auto rule = std::find_if(protocol::MESSAGE_RULES.begin(), protocol::MESSAGE_RULES.end(), [&](const auto& item) { return item.type == bytes[3]; });
    if (rule == protocol::MESSAGE_RULES.end() || rule->channel > 3) return false;
    Frame frame;
    if (parse_frame(bytes, static_cast<Channel>(rule->channel), identity_->epoch(), frame) != FrameError::ok || frame.sequence <= submitted_[rule->channel]) return false;
    submitted_[rule->channel] = frame.sequence;
    if (rule->channel == 0) {
      Json::Value body; if (!auth::strict_json(std::string_view(reinterpret_cast<const char*>(frame.payload.data()), frame.payload.size()), body)) return false;
      if (frame.type == protocol::CONTROL_REQUEST) {
        std::array<uint8_t,16> id{};
        if (!surface_ || !first_frame_ || !body["request_id"].isString() || !PeerIdentity::uuid(body["request_id"].asString(), id) ||
            !body["requested_input_permissions"].isArray() || body["requested_input_permissions"].empty()) return false;
        std::set<std::string> names;
        for (const auto& name : body["requested_input_permissions"]) {
          if (!name.isString() || !names.insert(name.asString()).second) return false;
          const auto found = std::find(protocol::PERMISSION_NAMES.begin() + 1, protocol::PERMISSION_NAMES.begin() + 4, name.asString());
          if (found == protocol::PERMISSION_NAMES.begin() + 4 || !(identity_->expected().permission_ceiling & (uint64_t{1} << (found - protocol::PERMISSION_NAMES.begin())))) return false;
        }
        ReleaseInput("new_request"); input_request_ = body["request_id"].asString(); input_deadline_ = steady_ms() + 5000;
      } else if (frame.type == protocol::INPUT_STATE) {
        if (input_request_.empty() || !text(body["request_id"], input_request_) || !number(body["generation"], input_epoch_) ||
            !body["keys"].isArray() || !body["keys"].empty() || !number(body["buttons"], 0) || !number(body["motion_sequence"], 0) || steady_ms() >= input_deadline_) return false;
        state_sent_ = true;
      } else if (frame.type == protocol::RELEASE_ALL || frame.type == protocol::CONTROL_RELEASED) { ReleaseInput("controller_released"); return true; }
      else return false;
      Send(frame.type, body); return !closed_;
    }
    if (!input_enabled_ || !surface_ || frame.input_epoch != input_epoch_) return false;
    uint64_t permission = 0;
    if (frame.type == protocol::KEY) permission = protocol::PERMISSION_INPUT_KEYBOARD;
    if (frame.type == protocol::TEXT_COMMIT) permission = protocol::PERMISSION_INPUT_TEXT;
    if (frame.type == protocol::BUTTON || frame.type == protocol::WHEEL || frame.type == protocol::POINTER_ABS) permission = protocol::PERMISSION_INPUT_POINTER;
    if (!permission || !(identity_->expected().permission_ceiling & permission)) return false;
    if (permission == protocol::PERMISSION_INPUT_POINTER && (read_u32(frame.payload, 0) != layout_epoch_ || !display_slots_.contains(read_u16(frame.payload, 4)))) return false;
    SendBinary(rule->channel, frame.type, frame.payload, input_epoch_);
    if (!closed_ && frame.type == protocol::KEY) {
      const auto usage = read_u16(frame.payload, 2);
      if (frame.payload[4]) held_keys_.insert(usage); else held_keys_.erase(usage);
    }
    if (!closed_ && frame.type == protocol::BUTTON) {
      const auto bit = uint32_t{1} << (frame.payload[10] - 1);
      if (frame.payload[11]) held_buttons_ |= bit; else held_buttons_ &= ~bit;
    }
    return !closed_;
  }
  void State(unsigned slot) {
    if (closed_) return; const auto found = channels_.find(slot); if (found == channels_.end()) return;
    if (found->second.first->state() == webrtc::DataChannelInterface::kClosed) { Close("RD_MEDIA_FAILED"); return; }
    if (!slot && found->second.first->state() == webrtc::DataChannelInterface::kOpen && !hello_sent_) {
      if (!offer_signed_ || !remote_description_) return;
      hello_sent_ = true; Send(protocol::SESSION_HELLO, identity_->hello_body());
    }
  }
  void Receive(unsigned slot, const webrtc::DataBuffer& message) {
    if (!Live() || !message.binary || slot > 3) { Close("RD_PROTOCOL_MISMATCH"); return; }
    Frame frame; const auto bytes = std::span(message.data.cdata<uint8_t>(), message.data.size());
    if (parse_frame(bytes, static_cast<Channel>(slot), identity_->epoch(), frame) != FrameError::ok) { Close("RD_PROTOCOL_MISMATCH"); return; }
    if (frame.sequence <= received_[slot]) return;
    if (slot < 2 && frame.sequence != received_[slot] + 1) { Close("RD_PROTOCOL_MISMATCH"); return; }
    received_[slot] = frame.sequence;
    if (frame.type == protocol::TEXT_ACK) return;
    if (slot != 0) { Close("RD_PROTOCOL_MISMATCH"); return; }
    Json::Value body;
    if (!auth::strict_json(std::string_view(reinterpret_cast<const char*>(frame.payload.data()), frame.payload.size()), body)) { Close("RD_PROTOCOL_MISMATCH"); return; }
    if (frame.type == protocol::SESSION_HELLO) {
      std::vector<uint8_t> transcript;
      if (identity_->hello(body, transcript) != auth::Error::ok) { Close("RD_PROOF_INVALID"); return; }
      proof_request_ = auth::base64url(auth::digest(PeerIdentity::base64(transcript)));
      Json::Value request; request["request_id"] = proof_request_; request["transcript"] = auth::base64url(transcript); Emit(proof_request, request); return;
    }
    if (frame.type == protocol::SESSION_PROOF) {
      if (identity_->host_proof(body) != auth::Error::ok) { Close("RD_PROOF_INVALID"); return; }
      MaybeReady(); return;
    }
    if (!identity_->authenticated()) { Close("RD_PEER_IDENTITY_MISMATCH"); return; }
    if (frame.type == protocol::PATH_VERIFIED) {
      if (!number(body["epoch"], identity_->epoch()) || !text(body["protocol"], "udp") ||
          !DirectType(body["local_candidate_type"]) || !DirectType(body["remote_candidate_type"])) { Close("RD_PATH_REJECTED"); return; }
      remote_path_ = true; MaybeReady(); return;
    }
    if (frame.type == protocol::SESSION_CLOSE || frame.type == protocol::PROTOCOL_ERROR) { Close("RD_SESSION_CLOSED"); return; }
    if (frame.type == protocol::CONTROL_RELEASED || frame.type == protocol::RELEASE_ALL) {
      ResetInput(); Control(frame.type, body); return;
    }
    if (!remote_path_) { Close("RD_PATH_REJECTED"); return; }
    if (frame.type == protocol::CAPABILITIES) {
      if (capabilities_ || body["permissions"] != identity_->permissions() || !body["codecs"].isArray() || std::find(body["codecs"].begin(), body["codecs"].end(), Json::Value("VP8")) == body["codecs"].end()) { Close("RD_SCOPE_DENIED"); return; }
      capabilities_ = true; Json::Value ack; ack["capability_hash"] = auth::base64url(auth::digest(PeerIdentity::json(body))); ack["permissions"] = identity_->permissions(); Send(protocol::CAPABILITIES_ACK, ack); return;
    }
    if (frame.type == protocol::DISPLAY_LAYOUT) {
      if (!body["layout_epoch"].isUInt() || body["layout_epoch"].asUInt() <= layout_epoch_ || !body["displays"].isArray() || body["displays"].empty() || body["displays"].size() > 16 || !body["active_display"].isString()) { Close("RD_PROTOCOL_MISMATCH"); return; }
      std::set<std::string> ids; std::set<uint16_t> slots; bool active = false;
      for (const auto& display : body["displays"]) {
        if (!display["id"].isString() || display["id"].asString().size() > 128 || !ids.insert(display["id"].asString()).second ||
            !display["slot"].isUInt() || display["slot"].asUInt() > 65535 || !slots.insert(static_cast<uint16_t>(display["slot"].asUInt())).second ||
            !display["width_px"].isUInt() || !display["height_px"].isUInt() || !display["width_px"].asUInt() || !display["height_px"].asUInt() ||
            display["width_px"].asUInt() > 32768 || display["height_px"].asUInt() > 32768) { Close("RD_PROTOCOL_MISMATCH"); return; }
        active |= display["id"] == body["active_display"];
      }
      if (!active) { Close("RD_PROTOCOL_MISMATCH"); return; }
      ReleaseInput("layout_changed"); display_slots_ = slots; layout_epoch_ = body["layout_epoch"].asUInt(); Control(frame.type, body); return;
    }
    if (frame.type == protocol::SESSION_READY) {
      if (ready_ || !number(body["epoch"], identity_->epoch()) || !capabilities_ || !layout_epoch_) { Close("RD_STATE_CONFLICT"); return; }
      ready_ = true; ready_at_ = steady_ms(); Json::Value ack; ack["epoch"] = identity_->epoch(); ack["permissions"] = identity_->permissions(); ack["lease_seq"] = Json::UInt64(lease_sequence_);
      Send(protocol::SESSION_READY, ack); UpdateRendering(); return;
    }
    if (frame.type == protocol::CONTROL_GRANTED) {
      if (input_request_.empty() || !text(body["request_id"], input_request_) || !body["new_input_epoch"].isUInt() || body["new_input_epoch"].asUInt() <= input_epoch_ || steady_ms() >= input_deadline_) { ReleaseInput("stale_control_request"); return; }
      input_epoch_ = body["new_input_epoch"].asUInt(); input_enabled_ = false; heartbeat_version_ = 0; Control(frame.type, body); return;
    }
    if (frame.type == protocol::INPUT_SYNC_ACK) {
      if (!state_sent_ || input_request_.empty() || !text(body["request_id"], input_request_) || !number(body["input_epoch"], input_epoch_) || !number(body["layout_epoch"], layout_epoch_) || steady_ms() >= input_deadline_ || !surface_ || paused_) { ReleaseInput("stale_input_sync"); return; }
      input_enabled_ = true; Control(frame.type, body); return;
    }
    Close("RD_PROTOCOL_MISMATCH");
  }
  void Path(const webrtc::RTCStatsReport& report) {
    stats_pending_ = false; if (!Live()) return;
    bool found = false; std::string selected, local_type, remote_type;
    for (const auto* transport : report.GetStatsOfType<webrtc::RTCTransportStats>()) {
      if (!transport->selected_candidate_pair_id) continue;
      const auto* pair = report.GetAs<webrtc::RTCIceCandidatePairStats>(*transport->selected_candidate_pair_id);
      if (!pair || pair->state != "succeeded" || pair->nominated != true || transport->dtls_state != "connected" || !pair->local_candidate_id || !pair->remote_candidate_id) continue;
      const auto* local = report.GetAs<webrtc::RTCLocalIceCandidateStats>(*pair->local_candidate_id);
      const auto* remote = report.GetAs<webrtc::RTCRemoteIceCandidateStats>(*pair->remote_candidate_id);
      auto accepted = [](const auto* item) { return item && item->protocol == "udp" && (item->candidate_type == "host" || item->candidate_type == "srflx" || item->candidate_type == "prflx") && !item->relay_protocol && !item->tcp_type; };
      if (!accepted(local) || !accepted(remote) || (found && selected != pair->id())) { Close("RD_PATH_REJECTED"); return; }
      found = true; selected = pair->id(); local_type = *local->candidate_type; remote_type = *remote->candidate_type;
    }
    if (!found) { if (local_path_) Close("RD_PATH_CHANGED"); return; }
    if (!selected_pair_.empty() && selected_pair_ != selected) { Close("RD_PATH_CHANGED"); return; }
    selected_pair_ = selected; local_type_ = local_type; remote_type_ = remote_type; local_path_ = true; MaybeReady();
  }
  void OnSignalingChange(webrtc::PeerConnectionInterface::SignalingState) override {}
  void OnDataChannel(webrtc::scoped_refptr<webrtc::DataChannelInterface> channel) override { channel->Close(); Close("RD_PROTOCOL_MISMATCH"); }
  void OnRenegotiationNeeded() override {}
  void OnIceConnectionChange(webrtc::PeerConnectionInterface::IceConnectionState state) override {
    if (state == webrtc::PeerConnectionInterface::kIceConnectionFailed || state == webrtc::PeerConnectionInterface::kIceConnectionDisconnected || state == webrtc::PeerConnectionInterface::kIceConnectionClosed) Close("RD_NO_DIRECT_PATH");
  }
  void OnIceGatheringChange(webrtc::PeerConnectionInterface::IceGatheringState) override {}
  void OnIceCandidate(const webrtc::IceCandidate* candidate) override {
    if (closed_ || local_candidate_count_ >= 32) return; std::string value;
    if (!candidate->ToString(&value) || !candidate_allowed(value)) return;
    Json::Value item; item["candidate"] = value; item["sdpMid"] = candidate->sdp_mid(); item["sdpMLineIndex"] = candidate->sdp_mline_index(); ++local_candidate_count_;
    if (!offer_signed_) local_candidates_.push_back(item);
    else { Json::Value body; body["candidates"].append(item); Outgoing("peer.candidates", body); }
  }
  void OnTrack(webrtc::scoped_refptr<webrtc::RtpTransceiverInterface> transceiver) override {
    if (!transceiver || !transceiver->receiver()) { Close("RD_MEDIA_FAILED"); return; }
    const auto track = transceiver->receiver()->track();
    if (closed_ || track_ || !track || track->kind() != webrtc::MediaStreamTrackInterface::kVideoKind) { Close("RD_SCOPE_DENIED"); return; }
    track_ = static_cast<webrtc::VideoTrackInterface*>(track.get());
    track_->AddOrUpdateSink(&renderer_, webrtc::VideoSinkWants{}); UpdateRendering();
  }
 private:
  bool Live() { if (closed_ || !identity_) return false; if (steady_ms() >= deadline_) { Close("RD_LEASE_EXPIRED"); return false; } return true; }
  bool Lease(const VerifiedLease& lease) {
    const auto wall = wall_ms(); const auto duration = std::min(lease.expires_at_unix_ms - wall, lease.expires_at_unix_ms - lease.issued_at_unix_ms);
    if (duration <= 0 || duration > 900000 || lease.sequence <= lease_sequence_ || (lease_sequence_ && steady_ms() >= deadline_)) return false;
    deadline_ = steady_ms() + static_cast<uint64_t>(duration); lease_sequence_ = lease.sequence; return true;
  }
  void Emit(uint32_t type, const Json::Value& body) {
    if (!callbacks_.on_event) return;
    const auto payload = PeerIdentity::json(body); if (payload.size() > HT_RD_MAX_SIGNAL_BYTES) return;
    const ht_rd_event_v1 event{sizeof(event), HT_RD_ABI_V1, type, 0, ++event_generation_, reinterpret_cast<const uint8_t*>(payload.data()), payload.size()};
    callbacks_.on_event(callbacks_.user_data, &event);
  }
  void Outgoing(std::string_view type, const Json::Value& payload) { Json::Value body; body["signal_type"] = std::string(type); body["payload"] = payload; Emit(signal_request, body); }
  void Control(uint8_t type, const Json::Value& payload) { Json::Value body; body["type"] = type; body["epoch"] = identity_->epoch(); body["payload"] = payload; Emit(control_message, body); }
  bool ApplyCandidates() {
    if (!remote_description_) return true;
    for (const auto& item : remote_candidates_) {
      std::unique_ptr<webrtc::IceCandidate> candidate(webrtc::CreateIceCandidate(item["sdpMid"].asString(), item["sdpMLineIndex"].asInt(), item["candidate"].asString(), nullptr));
      if (!candidate || !peer_->AddIceCandidate(candidate.get())) return false;
    }
    remote_candidates_.clear(); State(0); return true;
  }
  static bool DirectType(const Json::Value& value) { return text(value,"host") || text(value,"srflx") || text(value,"prflx"); }
  void MaybeReady() {
    if (closed_ || !identity_->authenticated() || !local_path_ || !remote_path_) return;
    if (!path_reported_) { path_reported_ = true; Json::Value body; body["epoch"] = identity_->epoch(); body["protocol"] = "udp"; body["local_candidate_type"] = local_type_; body["remote_candidate_type"] = remote_type_; Emit(direct_path, body); }
    UpdateRendering();
  }
  void UpdateRendering() { renderer_.SetAuthorized(!closed_ && !paused_ && ready_ && local_path_ && remote_path_ && identity_ && identity_->authenticated() && steady_ms() < deadline_, deadline_); }
  void ResetInput() { input_enabled_ = state_sent_ = false; input_request_.clear(); input_deadline_ = 0; held_keys_.clear(); held_buttons_ = 0; }
  void ReleaseInput(std::string_view reason) {
    const bool needed = input_enabled_ || !input_request_.empty(); ResetInput();
    if (needed && !closed_ && channels_.contains(0) && channels_.at(0).first->state() == webrtc::DataChannelInterface::kOpen) { Json::Value body; body["reason"] = std::string(reason); Send(protocol::RELEASE_ALL, body); }
  }
  void Send(uint8_t type, const Json::Value& body) { const auto text = PeerIdentity::json(body); SendBinary(0, type, std::span(reinterpret_cast<const uint8_t*>(text.data()), text.size()), 0); }
  void SendBinary(unsigned slot, uint8_t type, std::span<const uint8_t> payload, uint32_t input_epoch) {
    if (closed_) return;
    const auto found = channels_.find(slot);
    if (found == channels_.end() || found->second.first->state() != webrtc::DataChannelInterface::kOpen || payload.size()+24 > protocol::CHANNEL_LIMITS[slot] || found->second.first->buffered_amount()+payload.size()+24 > protocol::SEND_QUEUE_BYTES || ++sent_[slot] >= protocol::SEQUENCE_RECONNECT_AT) { Close("RD_MEDIA_FAILED"); return; }
    std::vector<uint8_t> bytes(24+payload.size());
    auto u16 = [&](size_t at,uint16_t n) { bytes[at]=uint8_t(n>>8); bytes[at+1]=uint8_t(n); };
    auto u32 = [&](size_t at,uint32_t n) { bytes[at]=uint8_t(n>>24); bytes[at+1]=uint8_t(n>>16); bytes[at+2]=uint8_t(n>>8); bytes[at+3]=uint8_t(n); };
    u16(0,protocol::MAGIC); bytes[2]=1; bytes[3]=type; u16(6,24); u32(8,identity_->epoch()); u32(12,input_epoch); u32(16,sent_[slot]); u32(20,static_cast<uint32_t>(payload.size()));
    std::copy(payload.begin(),payload.end(),bytes.begin()+24);
    if (!found->second.first->Send(webrtc::DataBuffer(webrtc::CopyOnWriteBuffer(bytes),true))) Close("RD_MEDIA_FAILED");
  }
  void Tick() {
    if (!Live()) return;
    if (!ready_ && steady_ms()-started_ >= protocol::ICE_DEADLINE_MS) { Close("RD_NO_DIRECT_PATH"); return; }
    if (ready_ && !first_frame_ && !paused_ && surface_ && steady_ms()-ready_at_ >= 15000) { Close("RD_MEDIA_FAILED"); return; }
    State(0);
    if (!stats_pending_) { stats_pending_=true; peer_->GetStats(webrtc::make_ref_counted<Statistics>(weak_from_this()).get()); }
    if (input_enabled_) {
      Json::Value heartbeat; heartbeat["input_epoch"]=input_epoch_; heartbeat["state_version"]=Json::UInt64(++heartbeat_version_); heartbeat["keys"]=Json::Value(Json::arrayValue); heartbeat["buttons"]=held_buttons_;
      for (const auto usage : held_keys_) { Json::Value key; key["usage_page"]=7; key["usage"]=usage; heartbeat["keys"].append(key); }
      Send(protocol::INPUT_HEARTBEAT,heartbeat);
    }
    if (!input_enabled_ && !input_request_.empty() && steady_ms() >= input_deadline_) { ReleaseInput("request_timeout"); Json::Value body; body["reason"]="request_timeout"; Control(protocol::CONTROL_RELEASED,body); }
    if (!first_frame_ && renderer_.presented_frames()) { first_frame_=true; Json::Value body; body["epoch"]=identity_->epoch(); body["frames_presented"]=Json::UInt64(renderer_.presented_frames()); Emit(first_frame,body); }
    const auto weak=weak_from_this(); runtime().signaling->PostDelayedTask([weak] { if (auto self=weak.lock()) self->Tick(); },webrtc::TimeDelta::Millis(250));
  }
  ht_rd_callbacks_v1 callbacks_{};
  std::unique_ptr<ControllerIdentity> identity_;
  webrtc::scoped_refptr<webrtc::PeerConnectionInterface> peer_;
  webrtc::scoped_refptr<webrtc::VideoTrackInterface> track_;
  SurfaceRenderer renderer_;
  std::map<unsigned,std::pair<webrtc::scoped_refptr<webrtc::DataChannelInterface>,std::unique_ptr<ChannelObserver>>> channels_;
  std::array<uint32_t,4> sent_{},received_{},submitted_{};
  std::vector<Json::Value> local_candidates_,remote_candidates_;
  std::set<uint16_t> display_slots_;
  std::set<uint16_t> held_keys_;
  uint64_t deadline_=0,lease_sequence_=0,started_=0,ready_at_=0,event_generation_=0,input_deadline_=0,heartbeat_version_=0;
  uint32_t input_epoch_=0,layout_epoch_=0,held_buttons_=0;
  unsigned local_candidate_count_=0,remote_candidate_count_=0;
  std::string proof_request_,input_request_,selected_pair_,local_type_,remote_type_;
  bool closed_=false,closing_=false,paused_=false,surface_=false,offer_signed_=false,remote_pending_=false,remote_description_=false;
  bool hello_sent_=false,ready_=false,local_path_=false,remote_path_=false,path_reported_=false,capabilities_=false;
  bool input_enabled_=false,state_sent_=false,stats_pending_=false,first_frame_=false;
};
void ChannelObserver::OnStateChange() { owner_.State(slot_); }
void ChannelObserver::OnMessage(const webrtc::DataBuffer& message) { owner_.Receive(slot_,message); }
void Statistics::OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report) { if (const auto owner=owner_.lock()) owner->Path(*report); }

std::mutex registry_mutex;
std::map<ht_rd_handle,std::shared_ptr<Controller>> registry;
std::atomic<uint64_t> next_handle{1};
std::shared_ptr<Controller> find(ht_rd_handle handle) { std::lock_guard lock(registry_mutex); const auto found=registry.find(handle); return found==registry.end()?nullptr:found->second; }
template<class T> bool compatible(const T* value) { return value && value->size==sizeof(T) && value->abi_version==HT_RD_ABI_V1; }
ht_rd_result json_call(ht_rd_handle handle,const uint8_t* bytes,size_t size,bool start) {
  if (!bytes || !size || size>HT_RD_MAX_SIGNAL_BYTES) return HT_RD_INVALID_ARGUMENT;
  const auto owner=find(handle); if (!owner) return HT_RD_INVALID_HANDLE;
  Json::Value value; if (!auth::strict_json(std::string_view(reinterpret_cast<const char*>(bytes),size),value)) return HT_RD_PROTOCOL_ERROR;
  return runtime().signaling->BlockingCall([&] { const bool ok=start?owner->Start(value):owner->Signal(value); if (!ok) owner->Close("RD_AUTHORIZATION_INVALID"); return ok?HT_RD_OK:HT_RD_PERMISSION_DENIED; });
}
}  // namespace
}  // namespace ht::rd::android

using namespace ht::rd::android;
extern "C" {
uint32_t ht_rd_abi_version() { return HT_RD_ABI_V1; }
ht_rd_result ht_rd_create(const ht_rd_config_v1* config,const ht_rd_callbacks_v1* callbacks,ht_rd_handle* output) {
  if (!output) return HT_RD_INVALID_ARGUMENT; *output=0;
  if (!compatible(config) || !compatible(callbacks)) return HT_RD_ABI_MISMATCH;
  if (config->role!=1 || config->reserved) return HT_RD_INVALID_ARGUMENT;
  if (!runtime().factory) return HT_RD_BACKEND_UNAVAILABLE;
  std::lock_guard lock(registry_mutex); if (registry.size()>=4) return HT_RD_RESOURCE_LIMIT;
  const auto handle=next_handle.fetch_add(1); if (!handle) return HT_RD_RESOURCE_LIMIT;
  registry.emplace(handle,std::make_shared<Controller>(*callbacks)); *output=handle; return HT_RD_OK;
}
ht_rd_result ht_rd_get_capabilities(ht_rd_handle handle,ht_rd_capabilities_v1* output) {
  if (!compatible(output)) return HT_RD_ABI_MISMATCH; if (!find(handle)) return HT_RD_INVALID_HANDLE;
  *output={sizeof(*output),HT_RD_ABI_V1,1,HT_RD_OK,0,1,4,0,supported}; return HT_RD_OK;
}
ht_rd_result ht_rd_start(ht_rd_handle handle,const uint8_t* bytes,size_t size) { return json_call(handle,bytes,size,true); }
ht_rd_result ht_rd_on_signal(ht_rd_handle handle,const uint8_t* bytes,size_t size) { return json_call(handle,bytes,size,false); }
ht_rd_result ht_rd_submit_input(ht_rd_handle handle,const uint8_t* bytes,size_t size) {
  if (!bytes || size<24 || size>HT_RD_MAX_INPUT_BYTES) return HT_RD_INVALID_ARGUMENT;
  const auto owner=find(handle); if (!owner) return HT_RD_INVALID_HANDLE;
  return runtime().signaling->BlockingCall([&] { return owner->Submit(std::span(bytes,size))?HT_RD_OK:HT_RD_PERMISSION_DENIED; });
}
ht_rd_result ht_rd_set_surface(ht_rd_handle handle,const ht_rd_surface_v1* surface) {
  if (!compatible(surface)) return HT_RD_ABI_MISMATCH;
  if (surface->reserved || (surface->type!=0 && surface->type!=4) || (surface->type==0)!=(surface->native_window==nullptr)) return HT_RD_INVALID_ARGUMENT;
  const auto owner=find(handle); if (!owner) return HT_RD_INVALID_HANDLE;
  return runtime().signaling->BlockingCall([&] { return owner->Surface(static_cast<ANativeWindow*>(surface->native_window),surface->generation)?HT_RD_OK:HT_RD_STATE_CONFLICT; });
}
ht_rd_result ht_rd_pause(ht_rd_handle handle,uint32_t) { const auto owner=find(handle); if (!owner) return HT_RD_INVALID_HANDLE; runtime().signaling->BlockingCall([&] { owner->Pause(); }); return HT_RD_OK; }
ht_rd_result ht_rd_close(ht_rd_handle handle,uint32_t) { const auto owner=find(handle); if (!owner) return HT_RD_INVALID_HANDLE; runtime().signaling->BlockingCall([&] { owner->Close("RD_LOCAL_CLOSE"); }); return HT_RD_OK; }
void ht_rd_release(ht_rd_handle handle) {
  std::shared_ptr<Controller> owner;
  { std::lock_guard lock(registry_mutex); const auto found=registry.find(handle); if (found==registry.end()) return; owner=std::move(found->second); registry.erase(found); }
  runtime().signaling->BlockingCall([&] { owner->Destroy(); });
}
}
