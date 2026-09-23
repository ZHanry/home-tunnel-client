// Local-only integration evidence: two in-process peers, no external signaling,
// no STUN/TURN service, no input injection and no screen contents written out.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <future>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>
#include "no_audio_device.hpp"

#include "api/audio_codecs/builtin_audio_decoder_factory.h"
#include "api/audio_codecs/builtin_audio_encoder_factory.h"
#include "api/create_peerconnection_factory.h"
#include "api/data_channel_interface.h"
#include "api/jsep.h"
#include "api/make_ref_counted.h"
#include "api/peer_connection_interface.h"
#include "api/rtp_receiver_interface.h"
#include "api/rtp_transceiver_interface.h"
#include "api/stats/rtc_stats_collector_callback.h"
#include "api/stats/rtcstats_objects.h"
#include "api/video/i420_buffer.h"
#include "api/video/video_broadcaster.h"
#include "api/video/video_frame.h"
#include "api/video_codecs/builtin_video_decoder_factory.h"
#include "api/video_codecs/builtin_video_encoder_factory.h"
#include "modules/desktop_capture/desktop_capture_options.h"
#include "modules/desktop_capture/desktop_capturer.h"
#include "modules/desktop_capture/desktop_frame.h"
#include "pc/video_track_source.h"
#include "rtc_base/logging.h"
#include "rtc_base/ssl_adapter.h"
#include "rtc_base/thread.h"
#include "rtc_base/time_utils.h"
#include "third_party/libyuv/include/libyuv.h"
#include "third_party/jsoncpp/source/include/json/json.h"
#if defined(WEBRTC_WIN)
#include "rtc_base/win32_socket_init.h"
#include <objbase.h>
#elif defined(WEBRTC_LINUX) && !defined(WEBRTC_ANDROID)
#include <X11/Xlib.h>
#endif

namespace {
using namespace std::chrono_literals;

template <class Predicate>
bool wait_for(Predicate predicate, std::chrono::seconds timeout = 15s) {
  const auto end = std::chrono::steady_clock::now() + timeout;
  while (!predicate()) {
    if (std::chrono::steady_clock::now() >= end) return false;
    std::this_thread::sleep_for(10ms);
  }
  return true;
}

class ScreenSource : public webrtc::VideoTrackSource {
 public:
  ScreenSource() : VideoTrackSource(false) { SetState(kLive); }
  bool is_screencast() const override { return true; }
  void Push(const webrtc::VideoFrame& frame) { broadcaster_.OnFrame(frame); }
 protected:
  webrtc::VideoSourceInterface<webrtc::VideoFrame>* source() override {
    return &broadcaster_;
  }
 private:
  webrtc::VideoBroadcaster broadcaster_;
};

class Capture : public webrtc::DesktopCapturer::Callback {
 public:
  explicit Capture(webrtc::scoped_refptr<ScreenSource> source)
      : source_(std::move(source)) {}
  void OnCaptureResult(webrtc::DesktopCapturer::Result result,
                       std::unique_ptr<webrtc::DesktopFrame> frame) override {
    if (result != webrtc::DesktopCapturer::Result::SUCCESS || !frame) return;
    const int width = frame->size().width(), height = frame->size().height();
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return;
    auto converted = webrtc::I420Buffer::Create(width, height);
    if (libyuv::ARGBToI420(frame->data(), frame->stride(),
                          converted->MutableDataY(), converted->StrideY(),
                          converted->MutableDataU(), converted->StrideU(),
                          converted->MutableDataV(), converted->StrideV(),
                          width, height) != 0) return;
    const int target_width = std::min(width, 1280) & ~1;
    const int target_height = std::max(2, height * target_width / width) & ~1;
    auto scaled = webrtc::I420Buffer::Create(target_width, target_height);
    scaled->ScaleFrom(*converted);
    source_->Push(webrtc::VideoFrame::Builder().set_video_frame_buffer(scaled)
                     .set_timestamp_us(webrtc::TimeMicros()).build());
    ++frames;
  }
  unsigned frames = 0;
 private:
  webrtc::scoped_refptr<ScreenSource> source_;
};

struct FrameSink : webrtc::VideoSinkInterface<webrtc::VideoFrame> {
  std::atomic<unsigned> frames{0};
  std::atomic<int> width{0}, height{0};
  void OnFrame(const webrtc::VideoFrame& frame) override {
    width = frame.width(); height = frame.height(); ++frames;
  }
};

class Peer : public webrtc::PeerConnectionObserver,
             public webrtc::DataChannelObserver {
 public:
  explicit Peer(webrtc::Thread& signaling, bool echo)
      : signaling_(signaling), echo_(echo) {}
  ~Peer() override {
    signaling_.BlockingCall([&] {
      if (channel_) { channel_->UnregisterObserver(); channel_->Close(); }
      if (video_) video_->RemoveSink(&sink);
      if (connection) connection->Close();
      video_ = nullptr; channel_ = nullptr; connection = nullptr;
    });
  }
  void Attach(webrtc::scoped_refptr<webrtc::DataChannelInterface> channel) {
    channel_ = std::move(channel); channel_->RegisterObserver(this);
  }
  bool SendProbe() {
    return signaling_.BlockingCall([&] {
      return channel_ && channel_->state() == webrtc::DataChannelInterface::kOpen &&
             channel_->Send(webrtc::DataBuffer(std::string("ht-rd-local-probe-v1")));
    });
  }
  void OnSignalingChange(webrtc::PeerConnectionInterface::SignalingState) override {}
  void OnIceGatheringChange(webrtc::PeerConnectionInterface::IceGatheringState state) override {
    gathered = state == webrtc::PeerConnectionInterface::kIceGatheringComplete;
  }
  void OnIceCandidate(const webrtc::IceCandidate*) override { ++candidates; }
  void OnIceConnectionChange(webrtc::PeerConnectionInterface::IceConnectionState state) override {
    ice_state = static_cast<int>(state);
  }
  void OnConnectionChange(webrtc::PeerConnectionInterface::PeerConnectionState state) override {
    connection_state = static_cast<int>(state);
    connected = state == webrtc::PeerConnectionInterface::PeerConnectionState::kConnected;
  }
  void OnDataChannel(webrtc::scoped_refptr<webrtc::DataChannelInterface> channel) override {
    Attach(std::move(channel));
  }
  void OnTrack(webrtc::scoped_refptr<webrtc::RtpTransceiverInterface> transceiver) override {
    auto track = transceiver->receiver()->track();
    if (track && track->kind() == webrtc::MediaStreamTrackInterface::kVideoKind) {
      video_ = static_cast<webrtc::VideoTrackInterface*>(track.get());
      video_->AddOrUpdateSink(&sink, webrtc::VideoSinkWants{});
    }
  }
  void OnStateChange() override {}
  void OnMessage(const webrtc::DataBuffer& buffer) override {
    const std::string value(buffer.data.cdata<char>(), buffer.data.size());
    if (!buffer.binary && value == "ht-rd-local-probe-v1") {
      if (echo_) channel_->Send(buffer); else ++round_trips;
    }
  }
  webrtc::scoped_refptr<webrtc::PeerConnectionInterface> connection;
  std::atomic<bool> connected{false}, gathered{false};
  std::atomic<unsigned> round_trips{0};
  std::atomic<unsigned> candidates{0};
  std::atomic<int> connection_state{0}, ice_state{0};
  FrameSink sink;
 private:
  webrtc::Thread& signaling_;
  bool echo_;
  webrtc::scoped_refptr<webrtc::DataChannelInterface> channel_;
  webrtc::scoped_refptr<webrtc::VideoTrackInterface> video_;
};

class CreateDescription : public webrtc::CreateSessionDescriptionObserver {
 public:
  std::promise<std::unique_ptr<webrtc::SessionDescriptionInterface>> done;
  void OnSuccess(webrtc::SessionDescriptionInterface* description) override {
    done.set_value(std::unique_ptr<webrtc::SessionDescriptionInterface>(description));
  }
  void OnFailure(webrtc::RTCError) override { done.set_value(nullptr); }
};
class SetDescription : public webrtc::SetSessionDescriptionObserver {
 public:
  std::promise<bool> done;
  void OnSuccess() override { done.set_value(true); }
  void OnFailure(webrtc::RTCError) override { done.set_value(false); }
};

int negotiate(Peer& local, Peer& remote, webrtc::Thread& signaling, bool offer) {
  auto create = webrtc::make_ref_counted<CreateDescription>();
  auto created = create->done.get_future();
  webrtc::PeerConnectionInterface::RTCOfferAnswerOptions options;
  if (offer) local.connection->CreateOffer(create.get(), options);
  else local.connection->CreateAnswer(create.get(), options);
  if (created.wait_for(15s) != std::future_status::ready) return 1;
  auto description = created.get();
  if (!description) return 2;
  auto set = webrtc::make_ref_counted<SetDescription>();
  auto result = set->done.get_future();
  local.connection->SetLocalDescription(set.get(), description.release());
  if (result.wait_for(15s) != std::future_status::ready) return 3;
  if (!result.get()) return 4;
  if (!wait_for([&] { return local.gathered.load(); })) return 5;
  const auto sdp = signaling.BlockingCall([&] {
    std::string text; local.connection->local_description()->ToString(&text); return text;
  });
  auto incoming = webrtc::CreateSessionDescription(
      offer ? webrtc::SdpType::kOffer : webrtc::SdpType::kAnswer, sdp);
  if (!incoming) return 6;
  set = webrtc::make_ref_counted<SetDescription>();
  result = set->done.get_future();
  remote.connection->SetRemoteDescription(set.get(), incoming.release());
  if (result.wait_for(15s) != std::future_status::ready) return 7;
  return result.get() ? 0 : 8;
}

class PathStats : public webrtc::RTCStatsCollectorCallback {
 public:
  std::promise<bool> done;
  void OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report) override {
    bool found = false, valid = true;
    for (const auto* transport : report->GetStatsOfType<webrtc::RTCTransportStats>()) {
      if (!transport->selected_candidate_pair_id) continue;
      found = true;
      const auto* pair = report->GetAs<webrtc::RTCIceCandidatePairStats>(*transport->selected_candidate_pair_id);
      if (!pair || pair->nominated != true || pair->state != "succeeded" ||
          transport->dtls_state != "connected" || !pair->local_candidate_id || !pair->remote_candidate_id) {
        valid = false; continue;
      }
      const auto* local = report->GetAs<webrtc::RTCLocalIceCandidateStats>(*pair->local_candidate_id);
      const auto* remote = report->GetAs<webrtc::RTCRemoteIceCandidateStats>(*pair->remote_candidate_id);
      valid = valid && local && remote && local->protocol == "udp" && remote->protocol == "udp" &&
              local->candidate_type == "host" && remote->candidate_type == "host";
    }
    done.set_value(found && valid);
  }
};
bool direct_encrypted(Peer& peer) {
  auto callback = webrtc::make_ref_counted<PathStats>();
  auto future = callback->done.get_future();
  peer.connection->GetStats(callback.get());
  return future.wait_for(5s) == std::future_status::ready && future.get();
}

// Only content-free codec and frame counters leave this probe. Never save SDP,
// addresses, certificates, desktop pixels or the full PeerConnection report.
class MediaStats : public webrtc::RTCStatsCollectorCallback {
 public:
  explicit MediaStats(bool sender) : sender_(sender) {}
  std::promise<Json::Value> done;
  void OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report) override {
    Json::Value value(Json::objectValue);
    if (sender_) {
      for (const auto* stream : report->GetStatsOfType<webrtc::RTCOutboundRtpStreamStats>()) {
        if (stream->kind != "video" || !stream->frames_encoded || !stream->codec_id) continue;
        value["frames_encoded"] = *stream->frames_encoded;
        value["encoder_implementation"] = stream->encoder_implementation ? Json::Value(*stream->encoder_implementation) : Json::Value();
        value["power_efficient_encoder"] = stream->power_efficient_encoder ? Json::Value(*stream->power_efficient_encoder) : Json::Value();
        value["total_encode_time_seconds"] = stream->total_encode_time ? Json::Value(*stream->total_encode_time) : Json::Value();
        Codec(*report, *stream->codec_id, value);
        break;
      }
    } else {
      for (const auto* stream : report->GetStatsOfType<webrtc::RTCInboundRtpStreamStats>()) {
        if (stream->kind != "video" || !stream->codec_id) continue;
        value["frames_decoded"] = stream->frames_decoded ? Json::Value(*stream->frames_decoded) : Json::Value();
        value["packets_received"] = stream->packets_received ? Json::Value(Json::UInt64(*stream->packets_received)) : Json::Value();
        value["bytes_received"] = stream->bytes_received ? Json::Value(Json::UInt64(*stream->bytes_received)) : Json::Value();
        value["decoder_implementation"] = stream->decoder_implementation ? Json::Value(*stream->decoder_implementation) : Json::Value();
        value["power_efficient_decoder"] = stream->power_efficient_decoder ? Json::Value(*stream->power_efficient_decoder) : Json::Value();
        value["total_decode_time_seconds"] = stream->total_decode_time ? Json::Value(*stream->total_decode_time) : Json::Value();
        Codec(*report, *stream->codec_id, value);
        break;
      }
    }
    done.set_value(std::move(value));
  }
 private:
  static void Codec(const webrtc::RTCStatsReport& report, const std::string& id, Json::Value& value) {
    const auto* codec = report.GetAs<webrtc::RTCCodecStats>(id);
    if (!codec) return;
    value["mime_type"] = codec->mime_type ? Json::Value(*codec->mime_type) : Json::Value();
    value["clock_rate"] = codec->clock_rate ? Json::Value(*codec->clock_rate) : Json::Value();
    value["payload_type"] = codec->payload_type ? Json::Value(*codec->payload_type) : Json::Value();
    value["sdp_fmtp_line"] = codec->sdp_fmtp_line ? Json::Value(*codec->sdp_fmtp_line) : Json::Value();
  }
  bool sender_;
};
Json::Value media_stats(Peer& peer, bool sender) {
  auto callback = webrtc::make_ref_counted<MediaStats>(sender);
  auto future = callback->done.get_future();
  peer.connection->GetStats(callback.get());
  return future.wait_for(5s) == std::future_status::ready ? future.get() : Json::Value();
}

bool force_codec(webrtc::PeerConnectionFactoryInterface& factory, Peer& host, const std::string& codec_name) {
  std::vector<webrtc::RtpCodecCapability> selected;
  bool available = false;
  for (const auto& codec : factory.GetRtpSenderCapabilities(webrtc::MediaType::VIDEO).codecs) {
    if (codec.name == "rtx") { selected.push_back(codec); continue; }
    if (codec.name != codec_name) continue;
    if (codec_name == "H264") {
      const auto profile = codec.parameters.find("profile-level-id");
      const auto packetization = codec.parameters.find("packetization-mode");
      if (profile == codec.parameters.end() || profile->second != "42e01f" ||
          packetization == codec.parameters.end() || packetization->second != "1") continue;
    }
    selected.push_back(codec);
    available = true;
  }
  if (!available) return false;
  for (const auto& transceiver : host.connection->GetTransceivers()) {
    if (!transceiver->SetCodecPreferences(selected).ok() ||
        !transceiver->SetDirectionWithError(webrtc::RtpTransceiverDirection::kSendOnly).ok()) return false;
  }
  return true;
}

int probe(webrtc::PeerConnectionFactoryInterface& factory, webrtc::Thread& signaling, const std::string& codec_name) {
  Peer host(signaling, false), controller(signaling, true);
  webrtc::PeerConnectionInterface::RTCConfiguration configuration;
  configuration.sdp_semantics = webrtc::SdpSemantics::kUnifiedPlan;
  configuration.tcp_candidate_policy = webrtc::PeerConnectionInterface::kTcpCandidatePolicyDisabled;
  configuration.servers.clear();  // Only two local peers; never STUN/TURN.
  for (auto* peer : {&host, &controller}) {
    auto connection = factory.CreatePeerConnectionOrError(configuration, webrtc::PeerConnectionDependencies(peer));
    if (!connection.ok()) return 10;
    peer->connection = connection.MoveValue();
  }
  auto source = signaling.BlockingCall([] { return webrtc::make_ref_counted<ScreenSource>(); });
  auto track = factory.CreateVideoTrack(source, "desktop-probe");
  if (!host.connection->AddTrack(track, {"local-desktop-probe"}).ok()) return 11;
  if (!force_codec(factory, host, codec_name)) return 19;
  auto channel = host.connection->CreateDataChannelOrError("local-probe", nullptr);
  if (!channel.ok()) return 12;
  signaling.BlockingCall([&] { host.Attach(channel.MoveValue()); });
  const int offer_result = negotiate(host, controller, signaling, true);
  if (offer_result) return 130 + offer_result;
  const int answer_result = negotiate(controller, host, signaling, false);
  if (answer_result) return 140 + answer_result;
  if (!wait_for([&] { return host.connected.load() && controller.connected.load(); })) {
    std::fprintf(stderr, "Local ICE diagnostic: host candidates=%u connection=%d ice=%d; controller candidates=%u connection=%d ice=%d.\n",
                 host.candidates.load(), host.connection_state.load(), host.ice_state.load(),
                 controller.candidates.load(), controller.connection_state.load(), controller.ice_state.load());
    return 150;
  }
  if (!direct_encrypted(host) || !direct_encrypted(controller)) return 14;
  if (!wait_for([&] { return host.SendProbe(); }) ||
      !wait_for([&] { return host.round_trips.load() > 0; })) return 15;

  auto options = webrtc::DesktopCaptureOptions::CreateDefault();
#if defined(WEBRTC_WIN)
  options.set_allow_directx_capturer(true);
#endif
  auto capturer = webrtc::DesktopCapturer::CreateScreenCapturer(options);
  if (!capturer) return 16;
  webrtc::DesktopCapturer::SourceList screens;
  if (!capturer->GetSourceList(&screens) || screens.empty() || !capturer->SelectSource(screens.front().id)) return 17;
  Capture capture(source);
  capturer->Start(&capture);
  const auto deadline = std::chrono::steady_clock::now() + 10s;
  while (std::chrono::steady_clock::now() < deadline && controller.sink.frames < 30) {
    if (!host.connected || !controller.connected) break;
    capturer->CaptureFrame();
    std::this_thread::sleep_for(70ms);
  }
  capturer.reset();
  const bool final_direct = direct_encrypted(host) && direct_encrypted(controller);
  const auto sender = media_stats(host, true), receiver = media_stats(controller, false);
  const std::string mime = "video/" + codec_name;
  const bool codec_verified = sender["mime_type"] == mime && receiver["mime_type"] == mime &&
      sender["frames_encoded"].asUInt() >= 10 && receiver["frames_decoded"].asUInt() >= 10 &&
      sender["encoder_implementation"].isString() && receiver["decoder_implementation"].isString();
  const bool verified = controller.sink.frames >= 10 && final_direct && codec_verified;
  Json::Value evidence(Json::objectValue);
  evidence["status"] = verified ? "passed" : "failed";
  evidence["scope"] = "local-native-media-probe";
  evidence["requested_codec"] = codec_name;
  evidence["desktop_frames_captured"] = capture.frames;
  evidence["video_frames_decoded"] = controller.sink.frames.load();
  evidence["decoded_width"] = controller.sink.width.load();
  evidence["decoded_height"] = controller.sink.height.load();
  evidence["data_channel_round_trips"] = host.round_trips.load();
  evidence["selected_pair"] = final_direct ? "udp-host-host" : "unverified";
  evidence["dtls_connected"] = final_direct;
  evidence["screen_content_saved"] = false;
  evidence["product_acceptance"] = false;
  evidence["sender"] = sender;
  evidence["receiver"] = receiver;
  Json::StreamWriterBuilder writer;
  writer["indentation"] = "";
  std::printf("%s\n", Json::writeString(writer, evidence).c_str());
  return verified ? 0 : 18;
}
}

int main(int argc, char** argv) {
  // argc protects the single access to the C runtime argument array.
#pragma clang unsafe_buffer_usage begin
  std::string codec_name = "VP8";
  if ((argc != 2 && argc != 3) || std::string(argv[1]) != "--local-desktop-loopback") {
    std::fprintf(stderr, "Use --local-desktop-loopback [--codec=VP8|--codec=H264] for an in-memory local desktop media test.\n");
    return 2;
  }
  if (argc == 3) {
    const std::string argument(argv[2]);
    if (argument != "--codec=VP8" && argument != "--codec=H264") return 2;
    codec_name = argument.substr(8);
  }
#pragma clang unsafe_buffer_usage end
#if defined(WEBRTC_WIN)
  webrtc::WinsockInitializer winsock;
  const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 3;
#elif defined(WEBRTC_LINUX) && !defined(WEBRTC_ANDROID)
  if (!XInitThreads()) return 3;
#endif
  webrtc::LogMessage::LogToDebug(webrtc::LS_ERROR);
  webrtc::LogMessage::SetLogToStderr(false);
  if (!webrtc::InitializeSSL()) return 4;
  int result = 5;
  {
    auto network = webrtc::Thread::CreateWithSocketServer();
    auto worker = webrtc::Thread::Create();
    auto signaling = webrtc::Thread::Create();
    if (network->Start() && worker->Start() && signaling->Start()) {
      auto factory = webrtc::CreatePeerConnectionFactory(network.get(), worker.get(), signaling.get(), webrtc::make_ref_counted<ht::rd::NoAudioDevice>(),
          webrtc::CreateBuiltinAudioEncoderFactory(), webrtc::CreateBuiltinAudioDecoderFactory(),
          webrtc::CreateBuiltinVideoEncoderFactory(), webrtc::CreateBuiltinVideoDecoderFactory(), nullptr, nullptr);
      if (factory) result = probe(*factory, *signaling, codec_name);
      factory = nullptr;
    }
  }
  webrtc::CleanupSSL();
#if defined(WEBRTC_WIN)
  CoUninitialize();
#endif
  if (result != 0) std::fprintf(stderr, "Local media probe failed at stage %d.\n", result);
  return result;
}
