#include "peer_identity.hpp"
#include "json/writer.h"
#include "openssl/bio.h"
#include "openssl/bn.h"
#include "openssl/ec_key.h"
#include "openssl/evp.h"
#include "openssl/pem.h"
#include "openssl/rand.h"
#include "rtc_base/ssl_identity.h"
#include <algorithm>
#include <charconv>
#include <limits>

namespace ht::rd {
namespace {
bool text(const Json::Value& value, std::string_view expected) {
  return value.isString() && value.asString()==expected;
}
bool number(const Json::Value& value,uint64_t expected) {
  return value.isUInt64() && value.asUInt64()==expected;
}
bool nonzero(const Json::Value& value) {
  return value.isUInt64() && value.asUInt64()>0 && value.asUInt64()<=9007199254740991ULL;
}
auth::Error header_key(std::string_view compact,const Json::Value& keys,auth::SigningKey& signer) {
  const auto dot=compact.find('.');std::vector<uint8_t> data;Json::Value header;
  if(dot==std::string_view::npos || dot>2048 || !auth::unbase64url(compact.substr(0,dot),data) ||
     !auth::strict_json(std::string_view(reinterpret_cast<const char*>(data.data()),data.size()),header) ||
     !header["kid"].isString())return auth::Error::malformed;
  return auth::select_signing_key(keys,header["kid"].asString(),signer);
}
bool mask(const Json::Value& names,uint64_t& output) {
  output=0;if(!names.isArray() || names.empty() || names.size()>protocol::PERMISSION_NAMES.size())return false;
  for(const auto& item:names) {
    if(!item.isString())return false;
    const auto name=item.asString();
    const auto found=std::find(protocol::PERMISSION_NAMES.begin(),protocol::PERMISSION_NAMES.end(),name);
    if(found==protocol::PERMISSION_NAMES.end())return false;
    const auto bit=uint64_t{1}<<(found-protocol::PERMISSION_NAMES.begin());if(output&bit)return false;output|=bit;
  }
  return (output&protocol::PERMISSION_VIEW)!=0;
}
}
std::string PeerIdentity::json(const Json::Value& value) {
  Json::StreamWriterBuilder writer;writer["indentation"]="";writer["emitUTF8"]=true;
  return Json::writeString(writer,value);
}
std::string PeerIdentity::base64(std::span<const uint8_t> value) {
  std::string output=auth::base64url(value);
  std::replace(output.begin(),output.end(),'-','+');std::replace(output.begin(),output.end(),'_','/');
  while(output.size()%4)output+='=';return output;
}
bool PeerIdentity::decode_base64(std::string_view value,std::vector<uint8_t>& output) {
  if(value.empty() || value.size()>65536 || value.size()%4)return false;
  std::string converted(value);while(!converted.empty() && converted.back()=='=')converted.pop_back();
  std::replace(converted.begin(),converted.end(),'+','-');std::replace(converted.begin(),converted.end(),'/','_');
  return auth::unbase64url(converted,output) && base64(output)==value;
}
bool PeerIdentity::uuid(std::string_view value,std::array<uint8_t,16>& output) {
  if(value.size()!=36)return false;size_t offset=0;
  auto digit=[](char c)->int {if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;return -1;};
  for(size_t i=0;i<value.size();) {
    if(i==8 || i==13 || i==18 || i==23){if(value[i++]!='-')return false;continue;}
    const auto a=digit(value[i++]),b=digit(value[i++]);if(a<0 || b<0 || offset>=output.size())return false;
    output[offset++]=static_cast<uint8_t>((a<<4)|b);
  }
  return offset==output.size();
}
std::unique_ptr<PeerIdentity> PeerIdentity::prepare(std::string session_id,uint32_t epoch) {
  std::array<uint8_t,16> id{};if(!uuid(session_id,id) || !epoch)return nullptr;
  auto result=std::unique_ptr<PeerIdentity>(new PeerIdentity(std::move(session_id),epoch));
  auto identity=webrtc::SSLIdentity::Create("",webrtc::KeyParams::ECDSA(),3600);
  if(!identity || !RAND_bytes(result->host_nonce_.data(),result->host_nonce_.size()))return nullptr;
  const auto pem=identity->PublicKeyToPEMString();
  bssl::UniquePtr<BIO> bio(BIO_new_mem_buf(pem.data(),static_cast<int>(pem.size())));
  if(!bio)return nullptr;
  bssl::UniquePtr<EVP_PKEY> key(PEM_read_bio_PUBKEY(bio.get(),nullptr,nullptr,nullptr));
  if(!key || EVP_PKEY_id(key.get())!=EVP_PKEY_EC)return nullptr;
  const auto* ec=EVP_PKEY_get0_EC_KEY(key.get());
  bssl::UniquePtr<BIGNUM> x(BN_new()),y(BN_new());
  if(!ec || !x || !y || !EC_POINT_get_affine_coordinates_GFp(EC_KEY_get0_group(ec),EC_KEY_get0_public_key(ec),x.get(),y.get(),nullptr))return nullptr;
  Json::Value jwk;jwk["kty"]="EC";jwk["crv"]="P-256";std::array<uint8_t,32> bytes{};
  if(!BN_bn2bin_padded(bytes.data(),bytes.size(),x.get()))return nullptr;jwk["x"]=auth::base64url(bytes);
  if(!BN_bn2bin_padded(bytes.data(),bytes.size(),y.get()))return nullptr;jwk["y"]=auth::base64url(bytes);
  auth::PublicKey checked;if(auth::public_key(jwk,checked)!=auth::Error::ok)return nullptr;
  result->certificate_=webrtc::RTCCertificate::Create(std::move(identity));
  auto certificate_digest=webrtc::Buffer::CreateUninitializedWithSize(32);
  if(!result->certificate_ || !result->certificate_->GetSSLCertificate().ComputeDigest("sha-256",certificate_digest) || certificate_digest.size()!=32)return nullptr;
  std::string fingerprint;constexpr std::string_view hex="0123456789ABCDEF";
  for(auto byte:std::span(certificate_digest.data(),certificate_digest.size())){if(!fingerprint.empty())fingerprint+=':';fingerprint+=hex[byte>>4];fingerprint+=hex[byte&15];}
  result->prepared_["ephemeral_public_jwk"]=jwk;
  result->prepared_["dtls_fingerprint_sha256"]=fingerprint;
  result->prepared_["host_nonce"]=base64(result->host_nonce_);
  return result;
}
auth::Error PeerIdentity::authorize(const Json::Value& r,int64_t now,uint64_t supported,VerifiedLease& lease) {
  lease={};
  if(authorized_ || !text(r["session_id"],session_id_) || !number(r["connection_epoch"],epoch_) ||
     r["prepared"]!=prepared_ || !r["local_grant_revoked"].isBool() || r["local_grant_revoked"].asBool())return auth::Error::identity;
  for(const auto name:{"session_request_id","grant_id","origin","owner_user_id","host_endpoint_id","controller_endpoint_id","ticket_jws","lease_jws","grant_jws"})
    if(!r[name].isString() || r[name].asString().empty() || r[name].asString().size()>65536)return auth::Error::malformed;
  for(const auto name:{"grant_version","restore_epoch"})if(!nonzero(r[name]))return auth::Error::malformed;
  if(!r["user_token_version"].isUInt64() || r["user_token_version"].asUInt64()>9007199254740991ULL)return auth::Error::malformed;
  if(auth::public_key(r["host_public_jwk"],host_key_)!=auth::Error::ok || auth::public_key(r["controller_public_jwk"],controller_key_)!=auth::Error::ok)return auth::Error::key;
  auto error=auth::verify_keyset(json(r["initial_trust_pin"]),json(r["server_keyset"]),now,keys_);if(error!=auth::Error::ok)return error;
  if(keys_["restore_epoch"]!=r["restore_epoch"])return auth::Error::identity;
  expected_.issuer=r["origin"].asString();expected_.server_instance_id=keys_["server_instance_id"].asString();
  expected_.session_id=session_id_;expected_.connection_epoch=epoch_;expected_.session_request_id=r["session_request_id"].asString();
  expected_.grant_id=r["grant_id"].asString();expected_.grant_version=r["grant_version"].asUInt64();expected_.restore_epoch=r["restore_epoch"].asUInt64();
  expected_.owner_user_id=r["owner_user_id"].asString();expected_.host_endpoint_id=r["host_endpoint_id"].asString();
  expected_.controller_endpoint_id=r["controller_endpoint_id"].asString();expected_.user_token_version=r["user_token_version"].asUInt64();
  expected_.host_jkt=host_key_.thumbprint;expected_.controller_jkt=controller_key_.thumbprint;
  if(!mask(r["local_permissions"],expected_.permission_ceiling))return auth::Error::permission;
  expected_.permission_ceiling&=supported;
  ticket_jws_=r["ticket_jws"].asString();auth::SigningKey signer;
  error=header_key(ticket_jws_,keys_,signer);if(error!=auth::Error::ok)return error;
  error=auth::verify_authorization(ticket_jws_,r["lease_jws"].asString(),r["grant_jws"].asString(),signer,host_key_,expected_,now,lease);
  if(error!=auth::Error::ok)return error;
  auth::Jws ticket,grant;
  if(auth::verify_jws(ticket_jws_,signer.key,"ht-rd-ticket+jwt",ticket)!=auth::Error::ok ||
     auth::verify_jws(r["grant_jws"].asString(),host_key_,"ht-rd-grant+jwt",grant)!=auth::Error::ok)return auth::Error::signature;
  if(!grant.claims["expires_at"].isNull() && !auth::timestamp(grant.claims["expires_at"],grant_expiry_))return auth::Error::malformed;
  ticket_jti_=ticket.claims["jti"].asString();permissions_=ticket.claims["permissions"];
  expected_.permission_ceiling=lease.permissions;lease_sequence_=lease.sequence;authorized_=true;
  return auth::Error::ok;
}
auth::Error PeerIdentity::renew(const Json::Value& message,int64_t now,VerifiedLease& lease) {
  lease={};if(!authorized_ || !message["lease_jws"].isString())return auth::Error::identity;
  Json::Value next;auto error=auth::verify_keyset(json(keys_),json(message["server_keyset"]),now,next);
  if(error!=auth::Error::ok)return error;
  if(!number(next["restore_epoch"],expected_.restore_epoch))return auth::Error::identity;
  error=auth::verify_lease(message["lease_jws"].asString(),next,expected_,now,lease);
  if(error!=auth::Error::ok)return error;
  if(lease.sequence<=lease_sequence_ || (grant_expiry_ && lease.expires_at_unix_ms>grant_expiry_)){lease={};return auth::Error::expired;}
  lease_sequence_=lease.sequence;keys_=next;return auth::Error::ok;
}
auth::Error PeerIdentity::signal(const Json::Value& envelope,const auth::PublicKey& key,bool local,int64_t now,auth::Jws& proof) {
  if(!authorized_ || !number(envelope["v"],1) || !text(envelope["session_id"],session_id_) ||
     !number(envelope["connection_epoch"],epoch_) || !envelope["type"].isString() || !envelope["payload_jws"].isString())return auth::Error::identity;
  const auto error=auth::verify_jws(envelope["payload_jws"].asString(),key,"ht-rd-peer+jwt",proof);
  if(error!=auth::Error::ok)return error;const auto& p=proof.claims;int64_t created=0;
  if(!number(p["v"],1) || p["type"]!=envelope["type"] || !text(p["session_id"],session_id_) || !number(p["connection_epoch"],epoch_) ||
     !text(p["from_endpoint_id"],local?expected_.host_endpoint_id:expected_.controller_endpoint_id) ||
     !text(p["to_endpoint_id"],local?expected_.controller_endpoint_id:expected_.host_endpoint_id) ||
     !text(p["ticket_jti"],ticket_jti_) || !auth::timestamp(p["created_at"],created) || created>now+60000 || created<now-60000 ||
     !p["payload"].isObject() || !p["seq"].isString())return auth::Error::identity;
  const auto sequence=p["seq"].asString();uint64_t number=0;
  const auto parsed=std::from_chars(sequence.data(),std::to_address(sequence.end()),number);
  if(parsed.ec!=std::errc{} || parsed.ptr!=std::to_address(sequence.end()) || !number || std::to_string(number)!=sequence)return auth::Error::malformed;
  if(!local) {
    if(peer_sequences_.contains(number) || (number<highest_sequence_ && highest_sequence_-number>=32) ||
       (p["type"]!="peer.candidates" && number<=highest_sequence_))return auth::Error::identity;
    peer_sequences_.insert(number);highest_sequence_=std::max(highest_sequence_,number);
    while(!peer_sequences_.empty() && *peer_sequences_.begin()<highest_sequence_ && highest_sequence_-*peer_sequences_.begin()>=32)peer_sequences_.erase(peer_sequences_.begin());
  }
  return auth::Error::ok;
}
auth::Error PeerIdentity::peer_signal(const Json::Value& envelope,int64_t now,Json::Value& payload) {
  auth::Jws proof;const auto error=signal(envelope,controller_key_,false,now,proof);if(error!=auth::Error::ok)return error;
  const auto type=envelope["type"].asString();
  if(type=="peer.offer") {
    if(!offer_jws_.empty() || !text(proof.claims["payload"]["type"],"offer"))return auth::Error::identity;
    offer_jws_=envelope["payload_jws"].asString();
  } else if(type!="peer.candidates" && type!="peer.candidates_done")return auth::Error::identity;
  payload=proof.claims["payload"];return auth::Error::ok;
}
auth::Error PeerIdentity::signed_answer(const Json::Value& envelope,int64_t now) {
  if(!answer_jws_.empty() || answer_payload_.isNull() || offer_jws_.empty())return auth::Error::identity;
  auth::Jws proof;const auto error=signal(envelope,host_key_,true,now,proof);if(error!=auth::Error::ok)return error;
  if(!text(envelope["type"],"peer.answer") || proof.claims["payload"]!=answer_payload_)return auth::Error::identity;
  answer_jws_=envelope["payload_jws"].asString();return auth::Error::ok;
}
Json::Value PeerIdentity::hello_body() const {
  Json::Value body;body["nonce"]=auth::base64url(host_nonce_);body["ticket_hash"]=auth::base64url(auth::digest(ticket_jws_));
  body["protocol"]["major"]=1;body["protocol"]["minor"]=0;
  Json::Value caps;caps["permissions"]=permissions_;body["capability_hash"]=auth::base64url(auth::digest(json(caps)));return body;
}
auth::Error PeerIdentity::hello(const Json::Value& body,std::vector<uint8_t>& transcript) {
  transcript.clear();std::vector<uint8_t> nonce;
  Json::Value caps;caps["permissions"]=permissions_;
  if(!authorized_ || !transcript_.empty() || offer_jws_.empty() || answer_jws_.empty() ||
     !number(body["protocol"]["major"],1) || !number(body["protocol"]["minor"],0) || !body["nonce"].isString() ||
     !text(body["ticket_hash"],auth::base64url(auth::digest(ticket_jws_))) ||
     !text(body["capability_hash"],auth::base64url(auth::digest(json(caps)))) ||
     !auth::unbase64url(body["nonce"].asString(),nonce) || nonce.size()!=32)return auth::Error::identity;
  std::copy(nonce.begin(),nonce.end(),controller_nonce_.begin());std::array<uint8_t,16> id{};
  if(!uuid(session_id_,id))return auth::Error::identity;
  transcript_=proof_transcript(id,epoch_,{controller_nonce_,host_nonce_,auth::digest(offer_jws_),auth::digest(answer_jws_),auth::digest(ticket_jws_)});
  transcript=transcript_;return auth::Error::ok;
}
auth::Error PeerIdentity::controller_proof(const Json::Value& body) {
  std::vector<uint8_t> signature;
  if(controller_proved_ || transcript_.empty() || !number(body["transcript_version"],1) || !text(body["jkt"],controller_key_.thumbprint) ||
     !body["signature"].isString() || !auth::unbase64url(body["signature"].asString(),signature))return auth::Error::identity;
  const auto error=auth::verify_signature(transcript_,controller_key_,signature);if(error==auth::Error::ok)controller_proved_=true;return error;
}
auth::Error PeerIdentity::host_proof(std::span<const uint8_t> signature) {
  if(host_proved_ || transcript_.empty())return auth::Error::identity;
  const auto error=auth::verify_signature(transcript_,host_key_,signature);if(error==auth::Error::ok)host_proved_=true;return error;
}
}
