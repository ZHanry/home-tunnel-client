#include "controller_identity.hpp"
#include <algorithm>
#include <charconv>

namespace ht::rd {
namespace {
bool text(const Json::Value& value, std::string_view expected) {
  return value.isString() && value.asString()==expected;
}
bool number(const Json::Value& value,uint64_t expected) {
  return value.isUInt64() && value.asUInt64()==expected;
}
bool fields(const Json::Value& value,std::initializer_list<std::string_view> names) {
  if(!value.isObject() || value.size()!=names.size())return false;
  for(const auto name:names)if(!value.isMember(std::string(name)))return false;
  return true;
}
bool description(const Json::Value& value,std::string_view type) {
  return fields(value,{"type","sdp"}) && text(value["type"],type) && value["sdp"].isString() &&
    value["sdp"].asString().starts_with("v=0") && value["sdp"].asString().size()<=24576;
}
}
std::unique_ptr<ControllerIdentity> ControllerIdentity::prepare(std::string session_id,uint32_t epoch) {
  auto common=PeerIdentity::prepare(std::move(session_id),epoch);if(!common)return nullptr;
  auto result=std::unique_ptr<ControllerIdentity>(new ControllerIdentity(std::move(common)));
  result->prepared_=result->authorization_->prepared();
  result->prepared_["controller_nonce"]=result->prepared_["host_nonce"];
  result->prepared_.removeMember("host_nonce");
  std::vector<uint8_t> nonce;
  if(!PeerIdentity::decode_base64(result->prepared_["controller_nonce"].asString(),nonce) || nonce.size()!=32)return nullptr;
  std::copy(nonce.begin(),nonce.end(),result->controller_nonce_.begin());return result;
}
auth::Error ControllerIdentity::authorize(const Json::Value& context,int64_t now,uint64_t supported,VerifiedLease& lease) {
  lease={};
  if(!context.isObject())return auth::Error::malformed;
  if(authorized_ || (context.isMember("prepared") && context["prepared"]!=prepared_))return auth::Error::identity;
  // Only our own generated material enters the common authorization verifier.
  // The controller context cannot replace a certificate or nonce through IPC.
  auto native_context=context;native_context["prepared"]=authorization_->prepared();
  const auto error=authorization_->authorize(native_context,now,supported,lease);
  if(error!=auth::Error::ok)return error;
  if(auth::public_key(context["host_public_jwk"],host_key_)!=auth::Error::ok ||
     auth::public_key(context["controller_public_jwk"],controller_key_)!=auth::Error::ok){lease={};return auth::Error::key;}
  ticket_jws_=context["ticket_jws"].asString();
  // Extract from the exact compact ticket already signature/binding verified by
  // authorize above, never from a caller-provided decoded claims object.
  const auto first=ticket_jws_.find('.'),last=ticket_jws_.rfind('.');
  std::vector<uint8_t> bytes;Json::Value ticket;
  if(first==std::string::npos || last<=first ||
     !auth::unbase64url(std::string_view(ticket_jws_).substr(first+1,last-first-1),bytes) ||
     !auth::strict_json(std::string_view(reinterpret_cast<const char*>(bytes.data()),bytes.size()),ticket) ||
     !ticket["jti"].isString()){lease={};return auth::Error::malformed;}
  ticket_jti_=ticket["jti"].asString();authorized_=true;return auth::Error::ok;
}
auth::Error ControllerIdentity::renew(const Json::Value& message,int64_t now,VerifiedLease& lease) {
  lease={};if(!authorized_)return auth::Error::identity;
  if(!message.isObject())return auth::Error::malformed;
  return authorization_->renew(message,now,lease);
}
void ControllerIdentity::expect_offer(const Json::Value& payload) {
  if(authorized_ && offer_payload_.isNull() && description(payload,"offer"))offer_payload_=payload;
}
auth::Error ControllerIdentity::signal(const Json::Value& envelope,const auth::PublicKey& key,
    bool local,int64_t now,auth::Jws& proof,uint64_t& sequence) const {
  sequence=0;
  if(!authorized_ || !envelope.isObject() || !number(envelope["v"],1) || !text(envelope["session_id"],session_id()) ||
     !number(envelope["connection_epoch"],epoch()) || !envelope["type"].isString() ||
     !envelope["payload_jws"].isString())return auth::Error::identity;
  const auto error=auth::verify_jws(envelope["payload_jws"].asString(),key,"ht-rd-peer+jwt",proof);
  if(error!=auth::Error::ok)return error;
  const auto& claims=proof.claims;int64_t created=0;
  if(!number(claims["v"],1) || claims["type"]!=envelope["type"] || !text(claims["session_id"],session_id()) ||
     !number(claims["connection_epoch"],epoch()) ||
     !text(claims["from_endpoint_id"],local?expected().controller_endpoint_id:expected().host_endpoint_id) ||
     !text(claims["to_endpoint_id"],local?expected().host_endpoint_id:expected().controller_endpoint_id) ||
     !text(claims["ticket_jti"],ticket_jti_) || !auth::timestamp(claims["created_at"],created) ||
     created>now+60000 || created<now-60000 || !claims["payload"].isObject() ||
     !claims["seq"].isString())return auth::Error::identity;
  const auto encoded=claims["seq"].asString();
  const auto parsed=std::from_chars(encoded.data(),std::to_address(encoded.end()),sequence);
  if(parsed.ec!=std::errc{} || parsed.ptr!=std::to_address(encoded.end()) || !sequence ||
     std::to_string(sequence)!=encoded)return auth::Error::malformed;
  return auth::Error::ok;
}
auth::Error ControllerIdentity::signed_offer(const Json::Value& envelope,int64_t now) {
  if(!offer_jws_.empty() || offer_payload_.isNull())return auth::Error::identity;
  auth::Jws proof;uint64_t sequence=0;
  const auto error=signal(envelope,controller_key_,true,now,proof,sequence);
  if(error!=auth::Error::ok)return error;
  if(!text(envelope["type"],"peer.offer") || proof.claims["payload"]!=offer_payload_)return auth::Error::identity;
  offer_jws_=envelope["payload_jws"].asString();return auth::Error::ok;
}
auth::Error ControllerIdentity::peer_signal(const Json::Value& envelope,int64_t now,Json::Value& payload) {
  payload=Json::Value{};
  if(offer_jws_.empty())return auth::Error::identity;
  auth::Jws proof;uint64_t sequence=0;
  const auto error=signal(envelope,host_key_,false,now,proof,sequence);
  if(error!=auth::Error::ok)return error;
  const auto type=envelope["type"].asString();
  const bool candidate=type=="peer.candidates" || type=="peer.candidates_done";
  if(type=="peer.answer") {
    if(!answer_jws_.empty() || !description(proof.claims["payload"],"answer"))return auth::Error::identity;
  } else if(!candidate)return auth::Error::identity;
  if(peer_sequences_.contains(sequence) ||
     (sequence<highest_sequence_ && highest_sequence_-sequence>=32) ||
     (!candidate && sequence<=highest_sequence_))return auth::Error::identity;
  peer_sequences_.insert(sequence);highest_sequence_=std::max(highest_sequence_,sequence);
  while(!peer_sequences_.empty() && *peer_sequences_.begin()<highest_sequence_ &&
        highest_sequence_-*peer_sequences_.begin()>=32)peer_sequences_.erase(peer_sequences_.begin());
  if(type=="peer.answer")answer_jws_=envelope["payload_jws"].asString();
  payload=proof.claims["payload"];return auth::Error::ok;
}
Json::Value ControllerIdentity::hello_body() const {
  return authorized_?authorization_->hello_body():Json::Value{};
}
auth::Error ControllerIdentity::hello(const Json::Value& body,std::vector<uint8_t>& transcript) {
  transcript.clear();std::vector<uint8_t> nonce;Json::Value caps;caps["permissions"]=permissions();
  if(!authorized_ || !transcript_.empty() || offer_jws_.empty() || answer_jws_.empty() ||
     !fields(body,{"nonce","ticket_hash","protocol","capability_hash"}) ||
     !fields(body["protocol"],{"major","minor"}) || !number(body["protocol"]["major"],1) ||
     !number(body["protocol"]["minor"],0) || !body["nonce"].isString() ||
     !text(body["ticket_hash"],auth::base64url(auth::digest(ticket_jws_))) ||
     !text(body["capability_hash"],auth::base64url(auth::digest(PeerIdentity::json(caps)))) ||
     !auth::unbase64url(body["nonce"].asString(),nonce) || nonce.size()!=32)return auth::Error::identity;
  std::copy(nonce.begin(),nonce.end(),host_nonce_.begin());std::array<uint8_t,16> id{};
  if(!PeerIdentity::uuid(session_id(),id))return auth::Error::identity;
  transcript_=proof_transcript(id,epoch(),{controller_nonce_,host_nonce_,auth::digest(offer_jws_),
    auth::digest(answer_jws_),auth::digest(ticket_jws_)});
  transcript=transcript_;return auth::Error::ok;
}
auth::Error ControllerIdentity::host_proof(const Json::Value& body) {
  std::vector<uint8_t> signature;
  if(host_proved_ || transcript_.empty() || !fields(body,{"transcript_version","signature","jkt"}) ||
     !number(body["transcript_version"],1) || !text(body["jkt"],host_key_.thumbprint) ||
     !body["signature"].isString() || !auth::unbase64url(body["signature"].asString(),signature))return auth::Error::identity;
  const auto error=auth::verify_signature(transcript_,host_key_,signature);
  if(error==auth::Error::ok)host_proved_=true;return error;
}
auth::Error ControllerIdentity::controller_proof(std::span<const uint8_t> signature) {
  if(controller_proved_ || transcript_.empty())return auth::Error::identity;
  const auto error=auth::verify_signature(transcript_,controller_key_,signature);
  if(error==auth::Error::ok)controller_proved_=true;return error;
}
}
