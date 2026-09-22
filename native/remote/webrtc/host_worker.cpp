// Private, bounded IPC native capture and input host.
#include "peer_identity.hpp"
#include "sdp_policy.hpp"
#include "clipboard.hpp"
#include "file_transfer.hpp"
#include "host_platform.hpp"
#include "../generated/host_version.hpp"
#include "api/audio_codecs/builtin_audio_decoder_factory.h"
#include "api/audio_codecs/builtin_audio_encoder_factory.h"
#include "api/create_peerconnection_factory.h"
#include "api/data_channel_interface.h"
#include "api/jsep.h"
#include "api/make_ref_counted.h"
#include "api/peer_connection_interface.h"
#include "api/stats/rtc_stats_collector_callback.h"
#include "api/stats/rtcstats_objects.h"
#include "api/video/i420_buffer.h"
#include "api/video/video_broadcaster.h"
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
#if defined(WEBRTC_WIN)
#include "rtc_base/win32_socket_init.h"
#endif
#include "third_party/libyuv/include/libyuv.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <charconv>
#include <cstdlib>
#include <cstdio>
#include <fcntl.h>
#include <functional>
#include <future>
#include <map>
#include <mutex>
#include <sstream>
#include <thread>

namespace {
using namespace ht::rd;
using namespace std::chrono_literals;
constexpr uint32_t maximum_ipc=262144;
constexpr uint64_t supported_permissions=HOST_PERMISSIONS;
uint32_t input_target_process=0;
int64_t wall_ms(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
uint64_t steady_ms(){return static_cast<uint64_t>(webrtc::TimeMillis());}
bool text(const Json::Value& v,std::string_view s){return v.isString() && v.asString()==s;}
bool number(const Json::Value& v,uint64_t n){return v.isUInt64() && v.asUInt64()==n;}
bool fields(const Json::Value& value,std::initializer_list<std::string_view> names){
  if(!value.isObject() || value.size()!=names.size())return false;
  for(const auto name:names)if(!value.isMember(std::string(name)))return false;return true;
}
bool valid_body(uint8_t type,const Json::Value& value){
  switch(type){
    case protocol::SESSION_HELLO:return fields(value,{"nonce","ticket_hash","protocol","capability_hash"}) && fields(value["protocol"],{"major","minor"});
    case protocol::SESSION_PROOF:return fields(value,{"transcript_version","signature","jkt"});
    case protocol::CAPABILITIES_ACK:return fields(value,{"capability_hash","permissions"});
    case protocol::SESSION_READY:return fields(value,{"epoch","permissions","lease_seq"}) && value["lease_seq"].isUInt64() && value["lease_seq"].asUInt64()>0;
    case protocol::CONTROL_REQUEST:return fields(value,{"request_id","requested_input_permissions"});
    case protocol::INPUT_STATE:return fields(value,{"request_id","generation","keys","buttons","motion_sequence"});
    case protocol::PAUSE:return fields(value,{"reason","resume_allowed"}) && value["reason"].isString() && value["reason"].asString().size()<=128 && value["resume_allowed"].isBool();
    case protocol::CONTROL_RELEASED:
      return (fields(value,{"reason"}) || (fields(value,{"reason","new_input_epoch"}) && value["new_input_epoch"].isUInt() && value["new_input_epoch"].asUInt()>0)) && value["reason"].isString() && value["reason"].asString().size()<=128;
    case protocol::RELEASE_ALL:
      return fields(value,{"reason"}) && value["reason"].isString() && value["reason"].asString().size()<=128;
    case protocol::SESSION_CLOSE:return fields(value,{}) || (fields(value,{"reason"}) && value["reason"].isString() && value["reason"].asString().size()<=128);
    case protocol::FEATURE_REQUEST:return fields(value,{"permission","enabled"}) && value["permission"].isString() && value["enabled"].isBool();
    case protocol::INPUT_HEARTBEAT:
      if(!fields(value,{"input_epoch","state_version","keys","buttons"}) || !value["keys"].isArray() || value["keys"].size()>128 ||
         !value["buttons"].isUInt() || value["buttons"].asUInt()>31)return false;
      for(const auto& key:value["keys"])if(!fields(key,{"usage_page","usage"}) || !number(key["usage_page"],7) || !key["usage"].isUInt() || key["usage"].asUInt()<4 || key["usage"].asUInt()>231)return false;
      return true;
    default:return false;
  }
}
std::mutex output_mutex;
bool write_frame(const Json::Value& value){
  const auto body=PeerIdentity::json(value);if(body.empty() || body.size()>maximum_ipc)return false;
  const auto n=static_cast<uint32_t>(body.size());
  const std::array<uint8_t,4> prefix{uint8_t(n>>24),uint8_t(n>>16),uint8_t(n>>8),uint8_t(n)};
  std::lock_guard lock(output_mutex);
  return std::fwrite(prefix.data(),1,4,stdout)==4 && std::fwrite(body.data(),1,body.size(),stdout)==body.size() && std::fflush(stdout)==0;
}
bool read_frame(Json::Value& value){
  std::array<uint8_t,4> header{};if(std::fread(header.data(),1,4,stdin)!=4)return false;
  const auto size=(uint32_t(header[0])<<24)|(uint32_t(header[1])<<16)|(uint32_t(header[2])<<8)|header[3];
  if(!size || size>maximum_ipc)return false;
  std::string body(size,'\0');if(std::fread(body.data(),1,size,stdin)!=size)return false;
  return auth::strict_json(body,value,maximum_ipc);
}
using Screen=HostScreen;
std::vector<Screen> displays(){return host_displays();}
std::vector<webrtc::RtpCodecCapability> preferred_video_codecs(webrtc::PeerConnectionFactoryInterface& factory){
  const auto available=factory.GetRtpSenderCapabilities(webrtc::MediaType::VIDEO);std::vector<webrtc::RtpCodecCapability> selected;
  for(const auto name:{"H264","VP8","rtx"})for(const auto& codec:available.codecs){
    if(codec.name!=name)continue;
    if(codec.name=="H264"){
      std::string parameters;for(const auto& [key,value]:codec.parameters){if(!parameters.empty())parameters+=';';parameters+=key+'='+value;}
      if(!valid_h264_fmtp(parameters))continue;
    }
    selected.push_back(codec);
  }
  return selected;
}
Json::Value codec_names(const std::vector<webrtc::RtpCodecCapability>& codecs){
  Json::Value names(Json::arrayValue);std::set<std::string> seen;
  for(const auto& codec:codecs)if(codec.name!="rtx" && seen.insert(codec.name).second)names.append(codec.name);
  return names;
}
Json::Value capabilities(webrtc::PeerConnectionFactoryInterface& factory){
  Json::Value value;const auto sources=displays();value["codecs"]=codec_names(preferred_video_codecs(factory));
  const bool available=!sources.empty() && !value["codecs"].empty();value["available"]=available;
  value["status"]=available?"ready":"unavailable";value["unattended_enabled"]=false;
  value["permissions"]=Json::Value(Json::arrayValue);if(available){
    for(const auto name:{"view","input.keyboard","input.pointer"})value["permissions"].append(name);
    if(supported_permissions&protocol::PERMISSION_INPUT_TEXT)value["permissions"].append("input.text");
    if(supported_permissions&protocol::PERMISSION_CLIPBOARD_READ)value["permissions"].append("clipboard.read");
    if(supported_permissions&protocol::PERMISSION_CLIPBOARD_WRITE)value["permissions"].append("clipboard.write");
    if(supported_permissions&protocol::PERMISSION_FILES_SEND)value["permissions"].append("files.send");
    if(supported_permissions&protocol::PERMISSION_FILES_RECEIVE)value["permissions"].append("files.receive");
  }
  value["displays"]=Json::Value(Json::arrayValue);
  for(const auto& source:sources){Json::Value item;item["id"]=std::to_string(source.id);item["name"]=source.name;
    item["width"]=source.rect.width();item["height"]=source.rect.height();value["displays"].append(item);}
  return value;
}
class ScreenSource : public webrtc::VideoTrackSource {
 public:ScreenSource():VideoTrackSource(false){SetState(kLive);}bool is_screencast()const override{return true;}
  void Push(const webrtc::VideoFrame& frame){broadcaster_.OnFrame(frame);}
 protected:webrtc::VideoSourceInterface<webrtc::VideoFrame>* source()override{return &broadcaster_;}
 private:webrtc::VideoBroadcaster broadcaster_;
};
class Capture : public webrtc::DesktopCapturer::Callback {
 public:
  Capture(Screen screen,webrtc::scoped_refptr<ScreenSource> source):screen_(std::move(screen)),source_(std::move(source)){}
  ~Capture(){stop();}
  void start(){last_frame=steady_ms();thread_=std::thread([this]{run();});}
  void stop(){active=false;if(thread_.joinable())thread_.join();}
  void OnCaptureResult(webrtc::DesktopCapturer::Result result,std::unique_ptr<webrtc::DesktopFrame> frame)override{
    if(!active)return;
    if(result==webrtc::DesktopCapturer::Result::ERROR_PERMANENT){failed=true;return;}
    if(result!=webrtc::DesktopCapturer::Result::SUCCESS || !frame)return;
    const int width=frame->size().width(),height=frame->size().height();
    if(width!=screen_.rect.width() || height!=screen_.rect.height()){failed=true;return;}
    auto converted=webrtc::I420Buffer::Create(width,height);
    if(libyuv::ARGBToI420(frame->data(),frame->stride(),converted->MutableDataY(),converted->StrideY(),converted->MutableDataU(),converted->StrideU(),converted->MutableDataV(),converted->StrideV(),width,height)) {failed=true;return;}
    const int target_width=std::min(width,1920)&~1,target_height=std::max(2,height*target_width/width)&~1;
    auto scaled=webrtc::I420Buffer::Create(target_width,target_height);scaled->ScaleFrom(*converted);
    if(active)source_->Push(webrtc::VideoFrame::Builder().set_video_frame_buffer(scaled).set_timestamp_us(webrtc::TimeMicros()).build());
    last_frame=steady_ms();++frames;
  }
  std::atomic<bool> active{true},failed{false};std::atomic<unsigned> frames{0};std::atomic<uint64_t> last_frame{0};
 private:
  void run(){
    if(!host_thread_enter()){failed=true;return;}
    auto options=host_capture_options();
    auto capturer=webrtc::DesktopCapturer::CreateScreenCapturer(options);
    if(!capturer || !capturer->SelectSource(screen_.id)){failed=true;host_thread_leave();return;}
    capturer->Start(this);capturer->SetMaxFrameRate(20);
    while(active){
      if(!HostInputSink::ordinary_desktop() || !host_screen_current(screen_)){failed=true;break;}
      capturer->CaptureFrame();std::this_thread::sleep_for(50ms);
    }
    capturer.reset();host_thread_leave();
  }
  Screen screen_;webrtc::scoped_refptr<ScreenSource> source_;std::thread thread_;
};
class CreateDescription : public webrtc::CreateSessionDescriptionObserver {
 public:std::promise<std::unique_ptr<webrtc::SessionDescriptionInterface>> done;
  void OnSuccess(webrtc::SessionDescriptionInterface* value)override{done.set_value(std::unique_ptr<webrtc::SessionDescriptionInterface>(value));}
  void OnFailure(webrtc::RTCError)override{done.set_value(nullptr);}
};
class SetDescription : public webrtc::SetSessionDescriptionObserver {
 public:std::promise<bool> done;void OnSuccess()override{done.set_value(true);}void OnFailure(webrtc::RTCError)override{done.set_value(false);}
};
bool set_description(webrtc::PeerConnectionInterface& peer,std::unique_ptr<webrtc::SessionDescriptionInterface> value,bool local){
  if(!value)return false;auto observer=webrtc::make_ref_counted<SetDescription>();auto done=observer->done.get_future();
  if(local)peer.SetLocalDescription(observer.get(),value.release());else peer.SetRemoteDescription(observer.get(),value.release());
  return done.wait_for(4s)==std::future_status::ready && done.get();
}
bool direct_candidate(std::string_view value){
  if(value.empty())return true;if(value.size()>1024 || value.find_first_of("\r\n")!=std::string_view::npos)return false;
  std::unique_ptr<webrtc::IceCandidate> candidate(webrtc::CreateIceCandidate("0",0,std::string(value),nullptr));if(!candidate)return false;
  const auto& c=candidate->candidate();
  if(c.protocol()!="udp" || c.type()==webrtc::IceCandidateType::kRelay || c.address().port()<1)return false;
  if(!c.address().ipaddr().IsNil())return true;
  // Browser host candidates commonly use mDNS. Allow only a bounded .local
  // name; WebRTC resolves it, and selected-pair statistics remain authoritative.
  const auto name=c.address().hostname();
  if(c.type()!=webrtc::IceCandidateType::kHost || name.size()<7 || name.size()>69 || !name.ends_with(".local"))return false;
  return std::all_of(name.begin(),name.end()-6,[](char ch){return (ch>='a'&&ch<='z') || (ch>='A'&&ch<='Z') || (ch>='0'&&ch<='9') || ch=='-';});
}
bool valid_sdp(std::string_view sdp,std::string_view expected_fingerprint={}){return valid_sdp_profile(sdp,expected_fingerprint,direct_candidate);}

class HostSession;
class ChannelObserver : public webrtc::DataChannelObserver {
 public:ChannelObserver(HostSession& owner,unsigned slot):owner_(owner),slot_(slot){}
  void OnStateChange()override;void OnMessage(const webrtc::DataBuffer&)override;
 private:HostSession& owner_;unsigned slot_;
};
class Stats : public webrtc::RTCStatsCollectorCallback {
 public:explicit Stats(std::weak_ptr<HostSession> session):session_(std::move(session)){}
  void OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report)override;
 private:std::weak_ptr<HostSession> session_;
};
class HostSession : public webrtc::PeerConnectionObserver,public std::enable_shared_from_this<HostSession> {
 public:
  HostSession(std::unique_ptr<PeerIdentity> identity,webrtc::Thread& signaling,webrtc::PeerConnectionFactoryInterface& factory)
      :identity_(std::move(identity)),signaling_(signaling),factory_(factory),sink_({}),gate_(sink_){}
  ~HostSession(){Close("");}
  const PeerIdentity& identity()const{return *identity_;}
  void Event(std::string kind,Json::Value payload={},std::string type={},std::string request={}){
    Json::Value frame;frame["abi"]=1;auto& event=frame["event"];event["session_id"]=identity_->session_id();event["connection_epoch"]=identity_->epoch();event["kind"]=kind;
    if(!type.empty())event["signal_type"]=type;if(!request.empty())event["request_id"]=request;
    if(kind=="sign_peer_proof")event["transcript"]=payload;else if(!payload.isNull())event["payload"]=payload;
    if(!write_frame(frame))Close("");
  }
  bool Start(const Json::Value& request){
    if(started_ || closed_)return false;VerifiedLease lease;
    if(identity_->authorize(request,wall_ms(),supported_permissions,lease)!=auth::Error::ok)return false;
    available_screens_=displays();
    bool found=false;for(const auto& display:available_screens_)if(text(request["display_id"],std::to_string(display.id))){screen_=display;found=true;break;}
    if(!found || gate_.authorize(lease,wall_ms(),steady_ms())!=GateResult::ok)return false;
    sink_=HostInputSink({screen_.rect.left(),screen_.rect.top(),screen_.rect.width(),screen_.rect.height(),0},input_target_process);
    webrtc::PeerConnectionInterface::RTCConfiguration config;config.sdp_semantics=webrtc::SdpSemantics::kUnifiedPlan;
    config.tcp_candidate_policy=webrtc::PeerConnectionInterface::kTcpCandidatePolicyDisabled;
    config.bundle_policy=webrtc::PeerConnectionInterface::kBundlePolicyMaxBundle;
    config.certificates.push_back(identity_->certificate());
    if(request.isMember("stun_urls")){
      if(!request["stun_urls"].isArray() || request["stun_urls"].size()>4)return false;
      for(const auto& url:request["stun_urls"]){
        if(!url.isString())return false;const auto text=url.asString();
        if(!text.starts_with("stun:") || text.size()>260 || text.find_first_of("?@/\\# \r\n\t")!=std::string::npos)return false;
        webrtc::PeerConnectionInterface::IceServer server;server.urls.push_back(text);config.servers.push_back(server);
      }
    }
    auto connection=factory_.CreatePeerConnectionOrError(config,webrtc::PeerConnectionDependencies(this));if(!connection.ok())return false;
    connection_=connection.MoveValue();source_=webrtc::make_ref_counted<ScreenSource>();auto track=factory_.CreateVideoTrack(source_,"desktop");
    if(!connection_->AddTrack(track,{"home-tunnel-desktop"}).ok())return false;
    auto codecs=preferred_video_codecs(factory_);codec_capabilities_=codec_names(codecs);
    if(codec_capabilities_.empty())return false;
    for(const auto& transceiver:connection_->GetTransceivers())
      if(!transceiver->SetCodecPreferences(codecs).ok() || !transceiver->SetDirectionWithError(webrtc::RtpTransceiverDirection::kSendOnly).ok())return false;
    clipboard_storage_=host_clipboard();
    if(clipboard_storage_)clipboard_=std::make_unique<ClipboardTransfer>(*clipboard_storage_,[this](uint8_t type,std::span<const uint8_t> payload){SendBinary(4,type,payload,0);return !closed_;},
      [this]{const auto channel=channels_.find(4);return channel!=channels_.end() && channel->second.first->state()==webrtc::DataChannelInterface::kOpen && channel->second.first->buffered_amount()<32768;},
      [this](std::string_view permission){Json::Value result;result["permission"]=std::string(permission);result["enabled"]=false;result["error_code"]="RD_CLIPBOARD_UNAVAILABLE";Send(protocol::FEATURE_STATE,result);});
    if(supported_permissions&(protocol::PERMISSION_FILES_SEND|protocol::PERMISSION_FILES_RECEIVE))files_=std::make_unique<FileTransfer>(
      [this](uint8_t type,std::span<const uint8_t> payload){SendBinary(5,type,payload,0);return !closed_;},
      [this]{const auto channel=channels_.find(5);return !closed_ && channel!=channels_.end() && channel->second.first->state()==webrtc::DataChannelInterface::kOpen && channel->second.first->buffered_amount()<65536;},
      [this](const Json::Value& value){Event("file",value);},[this]{return FileCurrent();});
    started_=true;started_at_=steady_ms();Tick();return true;
  }
  bool Signal(const Json::Value& message){
    if(closed_ || !started_)return false;
    if(text(message["type"],"session.lease")){VerifiedLease lease;
      const bool verified=identity_->renew(message,wall_ms(),lease)==auth::Error::ok && gate_.renew(lease,wall_ms(),steady_ms())==GateResult::ok;
      if(verified && !pending_ready_.isNull() && pending_ready_["lease_seq"].asUInt64()<=gate_.lease_sequence())ControllerReady(pending_ready_);
      return verified && !closed_;
    }
    if(text(message["type"],"local.signed_signal")){
      if(!text(message["envelope"]["type"],"peer.answer"))return true;
      if(identity_->signed_answer(message["envelope"],wall_ms())!=auth::Error::ok)return false;
      answer_echoed_=true;if(!pending_hello_.isNull()){auto body=pending_hello_;pending_hello_=Json::Value{};Hello(body);}return !closed_;
    }
    Json::Value payload;if(identity_->peer_signal(message,wall_ms(),payload)!=auth::Error::ok)return false;
    if(text(message["type"],"peer.offer")){
      if(!payload["sdp"].isString() || !valid_sdp(payload["sdp"].asString()))return false;
      pending_offer_=payload["sdp"].asString();return true;
    }
    if(text(message["type"],"peer.candidates")){
      if(!payload["candidates"].isArray() || remote_candidates_+payload["candidates"].size()>32)return false;
      for(const auto& item:payload["candidates"]){
        if(!item["candidate"].isString() || !direct_candidate(item["candidate"].asString()) || !item["sdpMid"].isString() ||
           !item["sdpMLineIndex"].isUInt() || item["sdpMLineIndex"].asUInt()>16)return false;
        pending_candidates_.push_back(item);++remote_candidates_;
      }
      return ApplyCandidates();
    }
    return text(message["type"],"peer.candidates_done");
  }
  // Runs on the command thread, while WebRTC callbacks remain free to execute.
  bool Negotiate(){
    webrtc::scoped_refptr<webrtc::PeerConnectionInterface> peer;std::string fingerprint;
    const auto sdp=signaling_.BlockingCall([&]{if(closed_)return std::string{};peer=connection_;fingerprint=identity_->prepared()["dtls_fingerprint_sha256"].asString();auto value=pending_offer_;pending_offer_.clear();return value;});
    if(sdp.empty())return true;
    if(!peer || !set_description(*peer,webrtc::CreateSessionDescription(webrtc::SdpType::kOffer,sdp),false))return false;
    if(!signaling_.BlockingCall([&]{if(closed_)return false;remote_description_=true;return ApplyCandidates();}))return false;
    auto create=webrtc::make_ref_counted<CreateDescription>();auto done=create->done.get_future();
    peer->CreateAnswer(create.get(),{});if(done.wait_for(4s)!=std::future_status::ready)return false;
    auto description=done.get();if(!description)return false;std::string answer;description->ToString(&answer);
    if(!valid_sdp(answer,fingerprint))return false;
    if(!set_description(*peer,std::move(description),true))return false;
    return signaling_.BlockingCall([&]{
      if(closed_)return false;Json::Value payload;payload["type"]="answer";payload["sdp"]=answer;identity_->expect_answer(payload);
      Event("outgoing_signal",payload,"peer.answer");return true;
    });
  }
  bool Proof(std::string_view request,std::span<const uint8_t> signature){
    if(closed_ || request.empty() || request!=proof_request_ || identity_->host_proof(signature)!=auth::Error::ok)return false;
    proof_request_.clear();Json::Value body;body["transcript_version"]=1;body["jkt"]=identity_->expected().host_jkt;body["signature"]=auth::base64url(signature);
    Send(protocol::SESSION_PROOF,body);MaybeReady();return !closed_;
  }
  void Close(std::string_view reason){
    if(closed_)return;closed_=true;close_reason_=reason;gate_.close();
    // File callbacks may detect failed IPC/SCTP writes. Release input now, but
    // never destroy/reenter the transfer while one of its methods is on stack.
    if(!file_depth_)FinishClose();
  }
  bool FileCommand(std::string_view operation,const Json::Value& payload){
    if(!FileCurrent() || !files_)return false;
    FileCall guard(*this);const auto now=steady_ms();bool ok=false;
    if(operation=="file_offer_sources"){
      if(!fields(payload,{"session_id","connection_epoch","paths"}) || !payload["paths"].isArray() || payload["paths"].empty() || payload["paths"].size()>64)return false;
      std::vector<std::filesystem::path> paths;
      for(const auto& value:payload["paths"]){std::filesystem::path path;if(!LocalPath(value,path))return false;paths.push_back(std::move(path));}
      ok=files_->offer_sources(paths,now);
    }else{
      std::array<uint8_t,16> id{};
      if(!payload["file_id"].isString() || !PeerIdentity::uuid(payload["file_id"].asString(),id))return false;
      if(operation=="file_accept"){
        std::filesystem::path path;
        if(!fields(payload,{"session_id","connection_epoch","file_id","path"}) || !LocalPath(payload["path"],path))return false;
        ok=files_->approve_destination(payload["file_id"].asString(),path,now);
      }else if(operation=="file_cancel" && fields(payload,{"session_id","connection_epoch","file_id"}))ok=files_->cancel(payload["file_id"].asString(),now);
    }
    if(!closed_)files_->tick(steady_ms());return ok && !closed_;
  }
  void FinishClose(){
    if(close_finished_)return;close_finished_=true;
    if(files_){files_->close();files_.reset();}
    if(clipboard_)clipboard_->close();if(capture_){capture_->stop();capture_.reset();}
    for(auto& [slot,pair]:channels_){pair.first->UnregisterObserver();pair.first->Close();}channels_.clear();
    if(connection_)connection_->Close();connection_=nullptr;source_=nullptr;
    sink_.watchdog_stop();
    if(!close_reason_.empty()){Json::Value payload;payload["error_code"]=close_reason_;Event("closed",payload);}
  }
  bool ReleasesComplete(){gate_.tick(steady_ms());return !gate_.input_releases_pending();}
  Json::Value Diagnostics()const{
    Json::Value value;const std::array names{"input_received","input_accepted","input_replayed","input_ignored_epoch","input_ignored_disabled","input_failed"};
    for(size_t n=0;n<names.size();++n)value[names[n]]=Json::UInt64(input_diagnostics_[n]);
    value["input_epoch"]=gate_.input_epoch();value["input_enabled"]=gate_.input_allowed();
    for(const auto key:{"video_codec","video_codec_parameters","video_encoder_implementation","video_frames_encoded","video_power_efficient_encoder","video_frame_width","video_frame_height"})value[key]=video_diagnostics_[key];
    return value;
  }
  void State(unsigned slot){if(closed_)return;const auto found=channels_.find(slot);if(found!=channels_.end() && found->second.first->state()==webrtc::DataChannelInterface::kClosed)Close("RD_MEDIA_FAILED");}
  void Receive(unsigned slot,const webrtc::DataBuffer& message){
    if(closed_)return;if(!message.binary || slot>5){Close("RD_PROTOCOL_MISMATCH");return;}
    if(slot==1 || slot==2)++input_diagnostics_[0];
    Frame frame;const auto bytes=std::span(message.data.cdata<uint8_t>(),message.data.size());
    if(parse_frame(bytes,static_cast<Channel>(slot),identity_->epoch(),frame)!=FrameError::ok){Close("RD_PROTOCOL_MISMATCH");return;}
    auto& previous=received_[slot];if(frame.sequence<=previous){if(slot==1 || slot==2)++input_diagnostics_[2];return;}
    if((slot<2 || slot>=4) && frame.sequence!=previous+1){Close("RD_PROTOCOL_MISMATCH");return;}previous=frame.sequence;
    const bool controlled=gate_.input_allowed();
    if(gate_.tick(steady_ms())!=GateResult::ok){Close("RD_LEASE_EXPIRED");return;}
    if(controlled && !gate_.input_allowed())ReleaseInput("RD_INPUT_WATCHDOG",true);
    Json::Value body;
    if(slot==0 || slot==3){if(!auth::strict_json(std::string_view(reinterpret_cast<const char*>(frame.payload.data()),frame.payload.size()),body) || !valid_body(frame.type,body)){Close("RD_PROTOCOL_MISMATCH");return;}}
    if(frame.type==protocol::SESSION_HELLO){
      if(!answer_echoed_){if(!pending_hello_.isNull()){Close("RD_PROTOCOL_MISMATCH");return;}pending_hello_=body;return;}Hello(body);return;
    }
    if(frame.type==protocol::SESSION_PROOF){if(identity_->controller_proof(body)!=auth::Error::ok){Close("RD_PEER_IDENTITY_MISMATCH");return;}MaybeReady();return;}
    if(!identity_->authenticated()){Close("RD_PEER_IDENTITY_MISMATCH");return;}
    if(frame.type==protocol::SESSION_CLOSE){Close("RD_SESSION_CLOSED");return;}
    if(frame.type==protocol::RELEASE_ALL || frame.type==protocol::CONTROL_RELEASED || frame.type==protocol::PAUSE){ReleaseInput("controller_released",false);return;}
    if(!ready_){Close("RD_STATE_CONFLICT");return;}
    if(slot==4){if(!clipboard_ || !clipboard_->receive(frame.type,frame.payload,steady_ms()))Close("RD_CLIPBOARD_INVALID");return;}
    if(slot==5){
      if(!FileCurrent() || !files_){Close("RD_SCOPE_DENIED");return;}
      FileCall guard(*this);
      if(!files_->receive(frame.type,frame.payload,steady_ms()))Close("RD_FILE_INVALID");
      // Flush ACKs and the next bounded chunk immediately. Waiting for the
      // 250 ms lifecycle tick would artificially limit each file to 128 KiB/s.
      if(!closed_)files_->tick(steady_ms());return;
    }
    if(frame.type==protocol::CAPABILITIES_ACK){
      if(!text(body["capability_hash"],capability_hash_) || body["permissions"]!=identity_->permissions()){Close("RD_SCOPE_DENIED");return;}capabilities_ack_=true;return;
    }
    if(frame.type==protocol::SESSION_READY){
      ControllerReady(body);return;
    }
    if(frame.type==protocol::FEATURE_REQUEST){
      const auto permission=body["permission"].asString();const bool enabled=body["enabled"].asBool();
      bool approved=false;for(const auto& value:identity_->permissions())if(value==permission)approved=true;
      if(!approved){Close("RD_SCOPE_DENIED");return;}
      bool changed=false;
      if(clipboard_ && (permission=="clipboard.read" || permission=="clipboard.write"))
        changed=(!enabled || (capture_ && capture_->frames>0)) && clipboard_->enable(permission,enabled,steady_ms());
      if(files_ && (permission=="files.send" || permission=="files.receive")){
        // Before the first captured frame both directions are already off.
        // An early disable must not call live() and permanently close the
        // not-yet-activated transfer engine during the handshake.
        if(!capture_ || !capture_->frames)changed=!enabled;
        else {FileCall guard(*this);changed=files_->enable(permission,enabled,steady_ms());}
      }
      Json::Value result;result["permission"]=permission;result["enabled"]=changed && enabled;
      if(!changed)result["error_code"]="RD_FEATURE_UNAVAILABLE";Send(protocol::FEATURE_STATE,result);return;
    }
    if(frame.type==protocol::CONTROL_REQUEST){
      std::array<uint8_t,16> id{};uint64_t requested=0;
      if(!body["request_id"].isString() || !PeerIdentity::uuid(body["request_id"].asString(),id) ||
         !body["requested_input_permissions"].isArray() || body["requested_input_permissions"].empty() || body["requested_input_permissions"].size()>3){Close("RD_PROTOCOL_MISMATCH");return;}
      for(const auto& name:body["requested_input_permissions"]){
        if(!name.isString()){Close("RD_PROTOCOL_MISMATCH");return;}
        uint64_t bit=0;for(size_t n=1;n<=3;++n)if(name.asString()==protocol::PERMISSION_NAMES[n])bit=uint64_t{1}<<n;
        if(!bit || (requested&bit) || !(identity_->expected().permission_ceiling&bit)){ReleaseInput("RD_SCOPE_DENIED",true);return;}requested|=bit;
      }
      if(!capture_ || capture_->frames==0 || request_ids_.contains(id)){ReleaseInput("RD_STATE_CONFLICT",true);return;}
      if(request_ids_.size()>=1024 || request_input_epoch_>=protocol::SEQUENCE_RECONNECT_AT){Close("RD_RECONNECT_REQUIRED");return;}
      ReleaseInput("replaced",false);request_ids_.insert(id);input_request_=body["request_id"].asString();input_permissions_=requested;
      ++request_input_epoch_;input_pending_=true;input_requested_at_=steady_ms();
      if(gate_.first_frame(identity_->epoch(),steady_ms())!=GateResult::ok){Close("RD_STATE_CONFLICT");return;}
      Json::Value grant;grant["request_id"]=input_request_;grant["new_input_epoch"]=request_input_epoch_;Send(protocol::CONTROL_GRANTED,grant);return;
    }
    if(frame.type==protocol::INPUT_STATE){
      if(!input_pending_ || !text(body["request_id"],input_request_) || !number(body["generation"],request_input_epoch_))return;
      if(!body["keys"].isArray() || !body["keys"].empty() || !number(body["buttons"],0) || !number(body["motion_sequence"],0) ||
         steady_ms()-input_requested_at_>=5000 || gate_.synchronize_input(identity_->epoch(),request_input_epoch_,1,steady_ms())!=GateResult::ok){ReleaseInput("RD_INPUT_DENIED",true);return;}
      input_pending_=false;Json::Value ack;ack["request_id"]=input_request_;ack["input_epoch"]=request_input_epoch_;ack["layout_epoch"]=1;Send(protocol::INPUT_SYNC_ACK,ack);return;
    }
    if(frame.type==protocol::INPUT_HEARTBEAT){
      if(!gate_.input_allowed() || !number(body["input_epoch"],gate_.input_epoch()))return;
      if(!body["state_version"].isUInt64() || gate_.heartbeat(identity_->epoch(),gate_.input_epoch(),body["state_version"].asUInt64(),steady_ms())!=GateResult::ok)ReleaseInput("RD_INPUT_WATCHDOG",true);
      return;
    }
    if(slot==1 || slot==2){
      if(!gate_.input_allowed()){++input_diagnostics_[4];return;}
      if(frame.input_epoch!=gate_.input_epoch()){++input_diagnostics_[3];return;}
      GateResult accepted=GateResult::permission;
      if(frame.type==protocol::KEY && (input_permissions_&protocol::PERMISSION_INPUT_KEYBOARD))accepted=gate_.accept_key(bytes,steady_ms());
      else if(frame.type==protocol::BUTTON && (input_permissions_&protocol::PERMISSION_INPUT_POINTER))accepted=gate_.accept_button(bytes,steady_ms());
      else if(frame.type==protocol::WHEEL && (input_permissions_&protocol::PERMISSION_INPUT_POINTER))accepted=gate_.accept_wheel(bytes,steady_ms());
      else if(frame.type==protocol::POINTER_ABS && (input_permissions_&protocol::PERMISSION_INPUT_POINTER))accepted=gate_.accept_pointer(bytes,steady_ms());
      else if(frame.type==protocol::TEXT_COMMIT && (input_permissions_&protocol::PERMISSION_INPUT_TEXT)){
        accepted=gate_.accept_text(bytes,steady_ms());std::array<uint8_t,18> ack{};std::copy_n(frame.payload.begin(),16,ack.begin());
        ack[17]=(accepted==GateResult::ok || accepted==GateResult::replay)?0:1;SendBinary(1,protocol::TEXT_ACK,ack,gate_.input_epoch());
      }
      if(accepted==GateResult::ok)++input_diagnostics_[1];else if(accepted==GateResult::replay)++input_diagnostics_[2];else {++input_diagnostics_[5];ReleaseInput("RD_INPUT_FAILED",true);}
      return;
    }
    if(frame.type==protocol::RECEIVER_FEEDBACK)return;
    Close("RD_PROTOCOL_MISMATCH");
  }
  void Path(const webrtc::RTCStatsReport& report){
    stats_pending_=false;if(closed_)return;bool found=false;std::string selected,local_type,remote_type;
    for(const auto* transport:report.GetStatsOfType<webrtc::RTCTransportStats>()){
      if(!transport->selected_candidate_pair_id)continue;
      const auto* pair=report.GetAs<webrtc::RTCIceCandidatePairStats>(*transport->selected_candidate_pair_id);
      if(!pair || pair->state!="succeeded" || pair->nominated!=true || transport->dtls_state!="connected" || !pair->local_candidate_id || !pair->remote_candidate_id)continue;
      const auto* local=report.GetAs<webrtc::RTCLocalIceCandidateStats>(*pair->local_candidate_id);
      const auto* remote=report.GetAs<webrtc::RTCRemoteIceCandidateStats>(*pair->remote_candidate_id);
      auto accepted=[](const auto* candidate){return candidate && candidate->protocol=="udp" &&
        (candidate->candidate_type=="host" || candidate->candidate_type=="srflx" || candidate->candidate_type=="prflx") && !candidate->relay_protocol && !candidate->tcp_type;};
      if(!accepted(local) || !accepted(remote)){Close("RD_PATH_REJECTED");return;}
      if(found && selected!=pair->id()){Close("RD_PATH_REJECTED");return;}
      found=true;selected=pair->id();local_type=*local->candidate_type;remote_type=*remote->candidate_type;
    }
    if(!found){if(path_verified_)Close("RD_PATH_CHANGED");return;}
    if(!selected_pair_.empty() && selected_pair_!=selected){Close("RD_PATH_CHANGED");return;}
    selected_pair_=selected;local_type_=local_type;remote_type_=remote_type;path_verified_=true;
    for(const auto* stream:report.GetStatsOfType<webrtc::RTCOutboundRtpStreamStats>()){
      if(stream->kind!="video" || !stream->codec_id)continue;const auto* codec=report.GetAs<webrtc::RTCCodecStats>(*stream->codec_id);
      if(!codec || !codec->mime_type)continue;
      if(*codec->mime_type!="video/VP8" && (*codec->mime_type!="video/H264" || !codec->sdp_fmtp_line || !valid_h264_fmtp(*codec->sdp_fmtp_line))){Close("RD_MEDIA_FAILED");return;}
      video_diagnostics_["video_codec"]=*codec->mime_type;
      video_diagnostics_["video_codec_parameters"]=codec->sdp_fmtp_line?Json::Value(*codec->sdp_fmtp_line):Json::Value();
      video_diagnostics_["video_encoder_implementation"]=stream->encoder_implementation?Json::Value(*stream->encoder_implementation):Json::Value();
      video_diagnostics_["video_frames_encoded"]=stream->frames_encoded?Json::Value(*stream->frames_encoded):Json::Value();
      video_diagnostics_["video_power_efficient_encoder"]=stream->power_efficient_encoder?Json::Value(*stream->power_efficient_encoder):Json::Value();
      video_diagnostics_["video_frame_width"]=stream->frame_width?Json::Value(*stream->frame_width):Json::Value();
      video_diagnostics_["video_frame_height"]=stream->frame_height?Json::Value(*stream->frame_height):Json::Value();
      break;
    }
    MaybeReady();
  }
  void OnSignalingChange(webrtc::PeerConnectionInterface::SignalingState)override{}
  void OnIceGatheringChange(webrtc::PeerConnectionInterface::IceGatheringState state)override{
    if(!closed_ && state==webrtc::PeerConnectionInterface::kIceGatheringComplete)Event("outgoing_signal",Json::Value(Json::objectValue),"peer.candidates_done");
  }
  void OnIceCandidate(const webrtc::IceCandidate* candidate)override{
    if(closed_ || local_candidates_>=32)return;std::string value;if(!candidate->ToString(&value) || !direct_candidate(value))return;
    Json::Value body,item;item["candidate"]=value;item["sdpMid"]=candidate->sdp_mid();item["sdpMLineIndex"]=candidate->sdp_mline_index();
    body["candidates"]=Json::Value(Json::arrayValue);body["candidates"].append(item);++local_candidates_;Event("outgoing_signal",body,"peer.candidates");
  }
  void OnConnectionChange(webrtc::PeerConnectionInterface::PeerConnectionState state)override{
    if(closed_)return;
    if(state==webrtc::PeerConnectionInterface::PeerConnectionState::kConnected)connected_=true;
    else if(state==webrtc::PeerConnectionInterface::PeerConnectionState::kDisconnected || state==webrtc::PeerConnectionInterface::PeerConnectionState::kFailed)Close("RD_NO_DIRECT_PATH");
  }
  void OnDataChannel(webrtc::scoped_refptr<webrtc::DataChannelInterface> channel)override{
    constexpr std::array<std::string_view,6> names{"control","input","motion","feedback","clipboard","file"};const auto label=channel->label();
    const auto found=std::find(names.begin(),names.end(),label);
    if(closed_ || found==names.end()){channel->Close();if(!closed_)Close("RD_PROTOCOL_MISMATCH");return;}
    const unsigned slot=static_cast<unsigned>(found-names.begin());
    const bool reliable=slot<2 || slot>=4;
    if(channels_.contains(slot) || channel->negotiated() || channel->ordered()!=reliable ||
       (reliable?channel->maxRetransmitsOpt().has_value():channel->maxRetransmitsOpt()!=0) || channel->maxPacketLifeTime().has_value()){
      channel->Close();Close("RD_PROTOCOL_MISMATCH");return;
    }
    auto observer=std::make_unique<ChannelObserver>(*this,slot);auto* pointer=observer.get();
    channels_.emplace(slot,std::pair{channel,std::move(observer)});channel->RegisterObserver(pointer);
  }
 private:
  struct FileCall {
    HostSession& owner;
    explicit FileCall(HostSession& value):owner(value){++owner.file_depth_;}
    ~FileCall(){if(!--owner.file_depth_ && owner.closed_)owner.FinishClose();}
  };
  static bool LocalPath(const Json::Value& value,std::filesystem::path& path){
    if(!value.isString())return false;const auto bytes=value.asString();
    if(bytes.empty() || bytes.size()>32768 || bytes.find('\0')!=std::string::npos || !valid_utf8({reinterpret_cast<const uint8_t*>(bytes.data()),bytes.size()}))return false;
    path=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(bytes.data()),bytes.size()));return path.is_absolute();
  }
  bool FileCurrent(){
    const auto now=steady_ms();
    if(closed_ || !ready_ || !capabilities_ack_ || !identity_->authenticated() || !path_verified_ || !capture_ || !capture_->frames || capture_->failed)return false;
    const auto last=capture_->last_frame.load();
    return (last>now || now-last<1750) && gate_.tick(now)==GateResult::ok && gate_.media_allowed();
  }
  bool ApplyCandidates(){
    if(!remote_description_)return true;
    for(const auto& item:pending_candidates_){std::unique_ptr<webrtc::IceCandidate> candidate(webrtc::CreateIceCandidate(item["sdpMid"].asString(),item["sdpMLineIndex"].asInt(),item["candidate"].asString(),nullptr));
      if(!candidate || !connection_->AddIceCandidate(candidate.get()))return false;}
    pending_candidates_.clear();return true;
  }
  void Hello(const Json::Value& body){
    std::vector<uint8_t> transcript;if(identity_->hello(body,transcript)!=auth::Error::ok){Close("RD_PROOF_INVALID");return;}
    Send(protocol::SESSION_HELLO,identity_->hello_body());proof_request_=auth::base64url(auth::digest(PeerIdentity::base64(transcript)));
    Event("sign_peer_proof",PeerIdentity::base64(transcript),{},proof_request_);
  }
  void Send(uint8_t type,const Json::Value& body){
    const auto text=PeerIdentity::json(body);SendBinary(0,type,std::span(reinterpret_cast<const uint8_t*>(text.data()),text.size()),0);
  }
  void SendBinary(unsigned slot,uint8_t type,std::span<const uint8_t> payload,uint32_t input_epoch){
    if(closed_)return;const auto found=channels_.find(slot);if(found==channels_.end() || found->second.first->state()!=webrtc::DataChannelInterface::kOpen){Close("RD_MEDIA_FAILED");return;}
    if(payload.size()+24>protocol::CHANNEL_LIMITS[slot] || ++sent_sequence_[slot]>=protocol::SEQUENCE_RECONNECT_AT || found->second.first->buffered_amount()+payload.size()+24>protocol::SEND_QUEUE_BYTES){Close("RD_MESSAGE_TOO_LARGE");return;}
    std::vector<uint8_t> frame(24+payload.size());auto u16=[&](size_t at,uint16_t n){frame[at]=uint8_t(n>>8);frame[at+1]=uint8_t(n);};
    auto u32=[&](size_t at,uint32_t n){frame[at]=uint8_t(n>>24);frame[at+1]=uint8_t(n>>16);frame[at+2]=uint8_t(n>>8);frame[at+3]=uint8_t(n);};
    u16(0,protocol::MAGIC);frame[2]=1;frame[3]=type;u16(6,24);u32(8,identity_->epoch());u32(12,input_epoch);u32(16,sent_sequence_[slot]);u32(20,static_cast<uint32_t>(payload.size()));
    std::copy(payload.begin(),payload.end(),frame.begin()+24);
    if(!found->second.first->Send(webrtc::DataBuffer(webrtc::CopyOnWriteBuffer(frame),true)))Close("RD_MEDIA_FAILED");
  }
  void ReleaseInput(std::string_view reason,bool notify){
    gate_.release_control();input_pending_=false;input_request_.clear();input_permissions_=0;
    if(notify){Json::Value body;body["reason"]=std::string(reason);Send(protocol::CONTROL_RELEASED,body);}
  }
  void ControllerReady(const Json::Value& body){
    if(!capabilities_ack_ || !number(body["epoch"],identity_->epoch()) || !body["lease_seq"].isUInt64() || !body["lease_seq"].asUInt64() ||
       body["permissions"]!=identity_->permissions() || gate_.tick(steady_ms())!=GateResult::ok || !gate_.media_allowed()){
      Close("RD_STATE_CONFLICT");return;
    }
    if(body["lease_seq"].asUInt64()>gate_.lease_sequence()){
      // A controller may observe a signed renewal before this host's WSS
      // channel. Wait for this host to verify it; READY never renews authority.
      if(pending_ready_.isNull()){pending_ready_=body;pending_ready_at_=steady_ms();}
      else if(pending_ready_!=body)Close("RD_STATE_CONFLICT");
      return;
    }
    pending_ready_=Json::Value();
    if(!capture_){capture_=std::make_unique<Capture>(screen_,source_);capture_->start();Event("verified_ready");}
  }
  void MaybeReady(){
    if(closed_ || ready_ || !identity_->authenticated() || !path_verified_)return;
    auto type=[](const std::string& value){return value=="host"?Candidate::host:value=="srflx"?Candidate::server_reflexive:Candidate::peer_reflexive;};
    if(gate_.peer_authenticated(identity_->epoch(),steady_ms())!=GateResult::ok || gate_.selected_pair(identity_->epoch(),{"udp",type(local_type_),type(remote_type_),true,true,1},steady_ms())!=GateResult::ok){Close("RD_PATH_REJECTED");return;}
    Json::Value path;path["epoch"]=identity_->epoch();path["protocol"]="udp";path["local_candidate_type"]=local_type_;path["remote_candidate_type"]=remote_type_;Send(protocol::PATH_VERIFIED,path);
    Json::Value caps;caps["permissions"]=identity_->permissions();caps["codecs"]=codec_capabilities_;
    capability_hash_=auth::base64url(auth::digest(PeerIdentity::json(caps)));Send(protocol::CAPABILITIES,caps);
    Json::Value layout;layout["layout_epoch"]=1;layout["active_display"]=std::to_string(screen_.id);layout["displays"]=Json::Value(Json::arrayValue);
    // The active screen is always slot zero for this immutable connection epoch.
    // Switching screens uses a new PeerConnection, so delayed decoded frames
    // and reliable input from a same-size old screen cannot enter the new view.
    auto append_display=[&](const Screen& screen,unsigned slot){Json::Value item;
      item["id"]=std::to_string(screen.id);item["slot"]=slot;item["name"]=screen.name;
      item["width_px"]=screen.rect.width();item["height_px"]=screen.rect.height();
      layout["displays"].append(item);};
    append_display(screen_,0);unsigned slot=1;
    for(const auto& display:available_screens_)if(display.id!=screen_.id)append_display(display,slot++);
    Send(protocol::DISPLAY_LAYOUT,layout);
    ready_=true;Json::Value body;body["epoch"]=identity_->epoch();Send(protocol::SESSION_READY,body);
  }
  void Tick(){
    if(closed_){if(ReleasesComplete())return;auto weak=weak_from_this();signaling_.PostDelayedTask([weak]{if(auto self=weak.lock())self->Tick();},webrtc::TimeDelta::Millis(100));return;}const auto now=steady_ms();
    if(!sink_.watchdog_tick()){Close("RD_INPUT_GUARD_FAILED");return;}
    const bool controlled=gate_.input_allowed();
    if(gate_.tick(now)!=GateResult::ok){Close("RD_LEASE_EXPIRED");return;}
    if((controlled && !gate_.input_allowed()) || (input_pending_ && now-input_requested_at_>=5000))ReleaseInput("RD_INPUT_WATCHDOG",true);
    if(!HostInputSink::ordinary_desktop()){Close("RD_DESKTOP_UNAVAILABLE");return;}
    if(!pending_ready_.isNull() && now-pending_ready_at_>=5000){Close("RD_STATE_CONFLICT");return;}
    if(!ready_ && now-started_at_>protocol::ICE_DEADLINE_MS){Close("RD_NO_DIRECT_PATH");return;}
    if(capture_){const auto last=capture_->last_frame.load();if(capture_->failed || (now>=last && now-last>=1750)){Close("RD_CAPTURE_FAILED");return;}}
    if(ready_ && clipboard_)clipboard_->tick(now);
    if(files_ && FileCurrent()){FileCall guard(*this);files_->tick(now);}
    if(closed_)return;
    if(connected_ && !stats_pending_){stats_pending_=true;connection_->GetStats(webrtc::make_ref_counted<Stats>(weak_from_this()).get());}
    auto weak=weak_from_this();signaling_.PostDelayedTask([weak]{if(auto self=weak.lock())self->Tick();},webrtc::TimeDelta::Millis(250));
  }
  std::unique_ptr<PeerIdentity> identity_;webrtc::Thread& signaling_;webrtc::PeerConnectionFactoryInterface& factory_;
  HostInputSink sink_;SessionGate gate_;Screen screen_{};std::vector<Screen> available_screens_;
  std::unique_ptr<ClipboardStorage> clipboard_storage_;std::unique_ptr<ClipboardTransfer> clipboard_;
  std::unique_ptr<FileTransfer> files_;unsigned file_depth_=0;bool close_finished_=false;std::string close_reason_;
  webrtc::scoped_refptr<webrtc::PeerConnectionInterface> connection_;webrtc::scoped_refptr<ScreenSource> source_;std::unique_ptr<Capture> capture_;
  std::map<unsigned,std::pair<webrtc::scoped_refptr<webrtc::DataChannelInterface>,std::unique_ptr<ChannelObserver>>> channels_;
  std::array<uint32_t,6> received_{};std::vector<Json::Value> pending_candidates_;Json::Value pending_hello_;
  std::array<uint64_t,6> input_diagnostics_{};Json::Value codec_capabilities_,video_diagnostics_,pending_ready_;uint64_t pending_ready_at_=0;
  std::string pending_offer_,proof_request_,selected_pair_,local_type_,remote_type_,capability_hash_;
  std::string input_request_;std::set<std::array<uint8_t,16>> request_ids_;
  std::array<uint32_t,6> sent_sequence_{};uint32_t local_candidates_=0,remote_candidates_=0,request_input_epoch_=0;uint64_t started_at_=0,input_requested_at_=0,input_permissions_=0;
  bool input_pending_=false;
  bool closed_=false,started_=false,connected_=false,stats_pending_=false,remote_description_=false,answer_echoed_=false,path_verified_=false,ready_=false,capabilities_ack_=false;
};
void ChannelObserver::OnStateChange(){owner_.State(slot_);}
void ChannelObserver::OnMessage(const webrtc::DataBuffer& message){owner_.Receive(slot_,message);}
void Stats::OnStatsDelivered(const webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report){if(auto session=session_.lock())session->Path(*report);}

int serve(webrtc::PeerConnectionFactoryInterface& factory,webrtc::Thread& signaling){
  std::shared_ptr<HostSession> session;Json::Value request;uint64_t last_id=0;
  while(read_frame(request)){
    if(!number(request["abi"],1) || !request["id"].isUInt64() || request["id"].asUInt64()<=last_id ||
       !request["operation"].isString() || !request["payload"].isObject())break;
    last_id=request["id"].asUInt64();const auto operation=request["operation"].asString();const auto& payload=request["payload"];
    const bool file_operation=operation=="file_offer_sources" || operation=="file_accept" || operation=="file_cancel";
    Json::Value response;response["abi"]=1;response["id"]=request["id"];response["ok"]=false;response["result"]=Json::Value(Json::objectValue);
    bool ok=false;
    if(operation=="hello"){response["result"]["version"]=std::string(HOST_VERSION);response["result"]["abi"]=1;response["result"]["max_frame_bytes"]=maximum_ipc;ok=true;}
    else if(operation=="capabilities"){response["result"]=capabilities(factory);ok=true;}
    else if(operation=="diagnostics"){response["result"]=signaling.BlockingCall([&]{return session?session->Diagnostics():Json::Value(Json::objectValue);});ok=true;}
    else if(operation=="prepare"){
      if(payload["session_id"].isString() && payload["connection_epoch"].isUInt() && payload["connection_epoch"].asUInt()){
        auto identity=PeerIdentity::prepare(payload["session_id"].asString(),payload["connection_epoch"].asUInt());
        if(identity){ok=signaling.BlockingCall([&]{if(session){session->Close("RD_REPLACED");if(!session->ReleasesComplete())return false;}session.reset();
          session=std::make_shared<HostSession>(std::move(identity),signaling,factory);return true;});if(ok)response["result"]=session->identity().prepared();}
      }
    }else if(session && text(payload["session_id"],session->identity().session_id()) && number(payload["connection_epoch"],session->identity().epoch())){
      if(operation=="start")ok=signaling.BlockingCall([&]{return session->Start(payload);});
      else if(operation=="signal"){
        ok=signaling.BlockingCall([&]{return session->Signal(payload["signal"]);});if(ok)ok=session->Negotiate();
      }else if(operation=="proof"){
        std::vector<uint8_t> signature;if(payload["request_id"].isString() && payload["signature"].isString() && PeerIdentity::decode_base64(payload["signature"].asString(),signature) && signature.size()==64)
          ok=signaling.BlockingCall([&]{return session->Proof(payload["request_id"].asString(),signature);});
      }else if(operation=="close"){signaling.BlockingCall([&]{session->Close("RD_LOCAL_CLOSE");});ok=true;}
      else if(file_operation)ok=signaling.BlockingCall([&]{return session->FileCommand(operation,payload);});
      if(!ok && !file_operation)signaling.BlockingCall([&]{session->Close("RD_AUTHORIZATION_INVALID");});
    }else if(operation=="close")ok=true;
    response["ok"]=ok;if(!ok)response["error_code"]=file_operation?"RD_FILE_OPERATION_FAILED":"RD_AUTHORIZATION_INVALID";
    if(!write_frame(response))break;
  }
  signaling.BlockingCall([&]{if(session)session->Close("RD_WORKER_CLOSED");session.reset();});return 0;
}
}
int main(int argc,char** argv){
  // Desktop capture and wire coordinates are physical pixels. Adopt the same
  // space before creating any threads/windows or consulting client rectangles.
  if(!host_prepare_process())return 7;
  const auto guard_result=HostInputSink::run_release_guard(argc,argv);if(guard_result>=0)return guard_result;
#pragma clang unsafe_buffer_usage begin
  if((argc!=2 && argc!=3) || std::string_view(argv[1])!="--host-inherited-pipe")return 2;
  if(argc==3){
    const std::string_view argument(argv[2]);constexpr std::string_view prefix="--input-target-pid=";
    if(!argument.starts_with(prefix))return 2;const auto value=argument.substr(prefix.size());
    const auto parsed=std::from_chars(value.data(),std::to_address(value.end()),input_target_process);
    if(parsed.ec!=std::errc{} || parsed.ptr!=std::to_address(value.end()) || !input_target_process)return 2;
  }
#pragma clang unsafe_buffer_usage end
  if(!host_pipe_transport())return 3;
#if defined(WEBRTC_WIN)
  webrtc::WinsockInitializer winsock;
#endif
  if(!host_thread_enter())return 4;
  webrtc::LogMessage::LogToDebug(webrtc::LS_NONE);webrtc::LogMessage::SetLogToStderr(false);
  if(!webrtc::InitializeSSL()){host_thread_leave();return 5;}int result=6;
  {
    auto network=webrtc::Thread::CreateWithSocketServer(),signaling=webrtc::Thread::Create();
    if(network->Start() && signaling->Start()){
      auto factory=webrtc::CreatePeerConnectionFactory(network.get(),network.get(),signaling.get(),nullptr,
        webrtc::CreateBuiltinAudioEncoderFactory(),webrtc::CreateBuiltinAudioDecoderFactory(),
        webrtc::CreateBuiltinVideoEncoderFactory(),webrtc::CreateBuiltinVideoDecoderFactory(),nullptr,nullptr);
      if(factory)result=serve(*factory,*signaling);factory=nullptr;
    }
  }
  webrtc::CleanupSSL();host_thread_leave();return result;
}
