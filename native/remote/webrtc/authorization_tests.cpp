#include "authorization.hpp"
#include "peer_identity.hpp"
#include "sdp_policy.hpp"
#include "json/writer.h"
#include "openssl/bn.h"
#include "openssl/ec_key.h"
#include "openssl/ecdsa.h"
#include "openssl/nid.h"
#include "openssl/sha.h"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <span>
#include <string>

#define REQUIRE(expression) do { if (!(expression)) { std::fprintf(stderr, "Authorization test line %d: %s\n", __LINE__, #expression); std::exit(1); } } while (false)
namespace {
using namespace ht::rd;
using namespace ht::rd::auth;
std::string json(const Json::Value& value) {
  Json::StreamWriterBuilder writer; writer["indentation"] = "";
  return Json::writeString(writer, value);
}
std::string encode(std::span<const uint8_t> bytes) {
  constexpr std::string_view alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string result; uint32_t bits = 0; unsigned count = 0;
  for (auto byte : bytes) {
    bits = (bits << 8) | byte; count += 8;
    while (count >= 6) { count -= 6; result += alphabet[(bits >> count) & 63]; }
  }
  if (count) result += alphabet[(bits << (6 - count)) & 63];
  return result;
}
std::string encode(const std::string& text) {
  return encode(std::span(reinterpret_cast<const uint8_t*>(text.data()), text.size()));
}
struct TestKey {
  bssl::UniquePtr<EC_KEY> secret{EC_KEY_new_by_curve_name(NID_X9_62_prime256v1)};
  Json::Value record;
  TestKey() {
    REQUIRE(secret && EC_KEY_generate_key(secret.get()));
    bssl::UniquePtr<BIGNUM> x(BN_new()), y(BN_new());
    REQUIRE(x && y && EC_POINT_get_affine_coordinates_GFp(EC_KEY_get0_group(secret.get()),
              EC_KEY_get0_public_key(secret.get()), x.get(), y.get(), nullptr));
    std::array<uint8_t, 32> bytes{};
    Json::Value jwk; jwk["kty"]="EC"; jwk["crv"]="P-256";
    REQUIRE(BN_bn2bin_padded(bytes.data(), bytes.size(), x.get())); jwk["x"]=encode(bytes);
    REQUIRE(BN_bn2bin_padded(bytes.data(), bytes.size(), y.get())); jwk["y"]=encode(bytes);
    PublicKey parsed; REQUIRE(public_key(jwk, parsed)==Error::ok);
    record["public_jwk"]=jwk; record["kid"]=parsed.thumbprint; record["alg"]="ES256";
    record["not_before"]="2026-09-21T00:00:00.000Z";
    record["not_after"]="2026-09-24T00:00:00.000Z";
  }
  std::array<uint8_t,64> raw_sign(std::span<const uint8_t> input) const {
    std::array<uint8_t,SHA256_DIGEST_LENGTH> digest{};
    SHA256(input.data(), input.size(), digest.data());
    bssl::UniquePtr<ECDSA_SIG> signature(ECDSA_do_sign(digest.data(),digest.size(),secret.get()));
    REQUIRE(signature); const BIGNUM *r=nullptr,*s=nullptr; ECDSA_SIG_get0(signature.get(),&r,&s);
    std::array<uint8_t,64> raw{};
    REQUIRE(BN_bn2bin_padded(raw.data(),32,r));
    REQUIRE(BN_bn2bin_padded(std::span(raw).last<32>().data(),32,s));
    return raw;
  }
  std::string sign(const Json::Value& claims,const char* type="ht-rd-keyset+jwt") const {
    Json::Value header;header["alg"]="ES256";header["typ"]=type;header["kid"]=record["kid"];
    const auto input=encode(json(header))+"."+encode(json(claims));
    return input+"."+encode(raw_sign(std::span(reinterpret_cast<const uint8_t*>(input.data()),input.size())));
  }
};
Json::Value keys(const TestKey& key, unsigned version) {
  Json::Value value;
  value["server_instance_id"]="rotation-test-instance"; value["restore_epoch"]=2;
  value["keyset_version"]=version; value["active_kid"]=key.record["kid"];
  value["keys"]=Json::Value(Json::arrayValue); value["keys"].append(key.record);
  value["rotation_proofs"]=Json::Value(Json::arrayValue);
  return value;
}
Json::Value rotation(const Json::Value& from,const Json::Value& to,const char* issued) {
  Json::Value proof; proof["server_instance_id"]=from["server_instance_id"];
  proof["from_version"]=from["keyset_version"];proof["to_version"]=to["keyset_version"];
  proof["from_kid"]=from["active_kid"];proof["issued_at"]=issued;
  for(const auto name:{"keyset_version","active_kid","keys"})proof["keyset"][name]=to[name];
  return proof;
}
void keyset_rotation(const Json::Value& vectors) {
  const auto now=vectors["reference_time_unix"].asInt64()*1000;
  const auto fixture=json(vectors["keyset"]);Json::Value verified;
  REQUIRE(verify_keyset(fixture,fixture,now,verified)==Error::ok);
  SigningKey fixture_key;
  REQUIRE(select_signing_key(verified,verified["active_kid"].asString(),fixture_key)==Error::ok);
  REQUIRE(fixture_key.key.thumbprint==vectors["identities"]["server"]["jkt"].asString());
  TestKey a,b,c;const auto first=keys(a,1);auto second=keys(b,2),third=keys(c,3);
  const auto proof2=rotation(first,second,"2026-09-22T00:01:00.000Z");
  const auto proof3=rotation(second,third,"2026-09-22T00:01:30.000Z");
  second["rotation_proofs"].append(a.sign(proof2));
  third["rotation_proofs"]=second["rotation_proofs"];third["rotation_proofs"].append(b.sign(proof3));
  const auto pin=json(first);
  REQUIRE(verify_keyset(pin,json(second),now,verified)==Error::ok);
  REQUIRE(verified["active_kid"]==b.record["kid"]);
  REQUIRE(verify_keyset(pin,json(third),now,verified)==Error::ok);
  REQUIRE(verify_keyset(json(second),json(third),now,verified)==Error::ok);
  auto reject=[&](const Json::Value& value) {
    REQUIRE(verify_keyset(pin,json(value),now,verified)!=Error::ok);REQUIRE(verified.isNull());
  };
  auto changed=second;changed["rotation_proofs"]=Json::Value(Json::arrayValue);reject(changed);
  changed=keys(b,1);reject(changed); // Unsigned same-version substitution.
  changed=third;changed["rotation_proofs"]=Json::Value(Json::arrayValue);changed["rotation_proofs"].append(b.sign(proof3));reject(changed);
  changed=third;changed["rotation_proofs"][0]=b.sign(proof3);changed["rotation_proofs"][1]=a.sign(proof2);reject(changed);
  changed=second;changed["server_instance_id"]="another-instance";reject(changed);
  changed=second;changed["restore_epoch"]=1;reject(changed);
  changed=second;changed["keys"][0]["not_after"]="2027-01-01T00:00:00Z";reject(changed);
  auto wrong_proof=proof2;wrong_proof["to_version"]=3;
  changed=second;changed["rotation_proofs"][0]=a.sign(wrong_proof);reject(changed);
  wrong_proof=proof2;wrong_proof["issued_at"]="2026-09-22T01:01:00Z";
  changed["rotation_proofs"][0]=a.sign(wrong_proof);reject(changed);
  wrong_proof=proof2;wrong_proof["from_kid"]=b.record["kid"];
  changed["rotation_proofs"][0]=a.sign(wrong_proof);reject(changed);
  changed=second;changed["rotation_proofs"][0]=b.sign(proof2);reject(changed);
  REQUIRE(verify_keyset(json(second),pin,now,verified)!=Error::ok);
  REQUIRE(verify_keyset(pin,pin,now+3*86400000LL,verified)==Error::expired);
  // Fractional RFC3339 seconds emitted by Go are accepted without relaxing dates.
  changed=first;changed["keys"][0]["not_before"]="2026-09-21T00:00:00.123456789Z";
  REQUIRE(verify_keyset(json(changed),json(changed),now,verified)==Error::ok);
  changed["keys"][0]["not_before"]="2026-02-30T00:00:00Z";reject(changed);
}
void native_identity(const Json::Value& vectors) {
  const auto now=vectors["reference_time_unix"].asInt64()*1000;
  TestKey server,host,controller;
  auto ticket=vectors["valid"]["ticket"]["claims"],lease=vectors["valid"]["lease"]["claims"],grant=vectors["valid"]["grant"]["claims"];
  for(auto* value:{&ticket,&lease,&grant}) {
    (*value)["host_jkt"]=host.record["kid"];(*value)["controller_jkt"]=controller.record["kid"];
  }
  auto keyset=vectors["keyset"];keyset["active_kid"]=server.record["kid"];keyset["keys"][0]=server.record;
  Json::Value request;
  for(const auto name:{"session_id","session_request_id","connection_epoch","grant_id","grant_version","restore_epoch","user_token_version","owner_user_id","host_endpoint_id","controller_endpoint_id"})request[name]=ticket[name];
  request["origin"]=ticket["iss"];request["host_public_jwk"]=host.record["public_jwk"];
  request["controller_public_jwk"]=controller.record["public_jwk"];request["local_permissions"]=ticket["permissions"];
  request["initial_trust_pin"]=keyset;request["server_keyset"]=keyset;request["local_grant_revoked"]=false;
  request["ticket_jws"]=server.sign(ticket,"ht-rd-ticket+jwt");request["lease_jws"]=server.sign(lease,"ht-rd-lease+jwt");
  request["grant_jws"]=host.sign(grant,"ht-rd-grant+jwt");
  auto identity=PeerIdentity::prepare(ticket["session_id"].asString(),ticket["connection_epoch"].asUInt());
  REQUIRE(identity);request["prepared"]=identity->prepared();
  auto other=PeerIdentity::prepare(ticket["session_id"].asString(),ticket["connection_epoch"].asUInt());
  REQUIRE(other && other->prepared()!=identity->prepared());
  VerifiedLease verified;auto invalid=request;invalid["prepared"]=other->prepared();
  REQUIRE(identity->authorize(invalid,now,15,verified)==Error::identity);
  invalid=request;invalid["local_grant_revoked"]=true;
  REQUIRE(identity->authorize(invalid,now,15,verified)==Error::identity);
  REQUIRE(identity->authorize(request,now,1,verified)==Error::permission);
  REQUIRE(identity->authorize(request,now,15,verified)==Error::ok);
  REQUIRE(identity->authorize(request,now,15,verified)==Error::identity);
  auto envelope=[&](const char* kind,unsigned sequence,const Json::Value& payload,bool local) {
    Json::Value claims;claims["v"]=1;claims["type"]=kind;claims["session_id"]=ticket["session_id"];
    claims["connection_epoch"]=ticket["connection_epoch"];claims["ticket_jti"]=ticket["jti"];
    claims["from_endpoint_id"]=ticket[local?"host_endpoint_id":"controller_endpoint_id"];
    claims["to_endpoint_id"]=ticket[local?"controller_endpoint_id":"host_endpoint_id"];
    claims["created_at"]="2026-09-22T00:02:00.000Z";claims["seq"]=std::to_string(sequence);claims["payload"]=payload;
    Json::Value outer;for(const auto name:{"v","type","session_id","connection_epoch"})outer[name]=claims[name];
    outer["payload_jws"]=(local?host:controller).sign(claims,"ht-rd-peer+jwt");return outer;
  };
  Json::Value offer;offer["type"]="offer";offer["sdp"]="test-offer";Json::Value extracted;
  auto remote=envelope("peer.offer",1,offer,false);
  REQUIRE(identity->peer_signal(remote,now,extracted)==Error::ok && extracted==offer);
  REQUIRE(identity->peer_signal(remote,now,extracted)==Error::identity);
  REQUIRE(identity->peer_signal(envelope("peer.offer",2,offer,false),now,extracted)==Error::identity);
  Json::Value answer;answer["type"]="answer";answer["sdp"]="test-answer";identity->expect_answer(answer);
  auto wrong=answer;wrong["sdp"]="substituted";
  REQUIRE(identity->signed_answer(envelope("peer.answer",1,wrong,true),now)==Error::identity);
  REQUIRE(identity->signed_answer(envelope("peer.answer",1,answer,true),now)==Error::ok);
  auto hello=identity->hello_body();std::array<uint8_t,32> controller_nonce{};controller_nonce.fill(19);
  hello["nonce"]=encode(controller_nonce);std::vector<uint8_t> transcript;
  wrong=hello;wrong["ticket_hash"]=encode(controller_nonce);
  REQUIRE(identity->hello(wrong,transcript)==Error::identity && transcript.empty());
  REQUIRE(identity->hello(hello,transcript)==Error::ok && transcript.size()==222);
  Json::Value proof;proof["transcript_version"]=1;proof["jkt"]=controller.record["kid"];
  proof["signature"]=encode(host.raw_sign(transcript));
  REQUIRE(identity->controller_proof(proof)==Error::signature);
  proof["signature"]=encode(controller.raw_sign(transcript));REQUIRE(identity->controller_proof(proof)==Error::ok);
  REQUIRE(!identity->authenticated());
  REQUIRE(identity->host_proof(controller.raw_sign(transcript))==Error::signature);
  REQUIRE(identity->host_proof(host.raw_sign(transcript))==Error::ok && identity->authenticated());
  REQUIRE(identity->host_proof(host.raw_sign(transcript))==Error::identity);
  REQUIRE(identity->controller_proof(proof)==Error::identity);
  REQUIRE(identity->peer_signal(envelope("peer.offer",3,offer,false),now,extracted)==Error::identity);
  lease["lease_seq"]=2;Json::Value renewal;renewal["server_keyset"]=keyset;renewal["lease_jws"]=server.sign(lease,"ht-rd-lease+jwt");
  REQUIRE(identity->renew(renewal,now,verified)==Error::ok && verified.sequence==2);
  REQUIRE(identity->renew(renewal,now,verified)==Error::expired);
}
void sdp_profile() {
  std::string fingerprint;for(int n=0;n<31;++n)fingerprint+="AA:";fingerprint+="AA";
  const std::string prefix="v=0\r\na=fingerprint:sha-256 "+fingerprint+"\r\n";
  const std::string video="m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n";
  const std::string data="m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n";
  const auto check=[&](const std::string& value){return valid_sdp_profile(value,fingerprint,[](std::string_view c){return c=="candidate:direct";});};
  REQUIRE(check(prefix+video+data));
  REQUIRE(check(prefix+video+"a=candidate:direct\r\n"+data));
  REQUIRE(!check(prefix+video+"a=candidate:relay\r\n"+data));
  REQUIRE(!check(prefix+video+data+"m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"));
  REQUIRE(!check(prefix+video+video+data));REQUIRE(!check(prefix+video+data+data));
  REQUIRE(!check(prefix+"m=video 0 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n"+data));
  REQUIRE(!check(prefix+"m=video 9 TCP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n"+data));
  REQUIRE(!check(prefix+"m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 H264/90000\r\n"+data));
  REQUIRE(!check(prefix+"m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:97 VP8/90000\r\n"+data));
  REQUIRE(!check(prefix+video));REQUIRE(!check(video+data));
}
std::string compact(const Json::Value& value) {
  const auto& parts = value["jws_parts"];
  REQUIRE(parts.isArray() && parts.size() == 3);
  return parts[0].asString() + "." + parts[1].asString() + "." + parts[2].asString();
}
void strict_parser() {
  Json::Value value;
  REQUIRE(strict_json("{\"a\":1,\"b\":[true,null,\"hello\"]}", value));
  for (const std::string text : {
      "{\"a\":1,\"a\":2}", "{\"a\":1,\"\\u0061\":2}", "{} {}", "{} garbage",
      "{\"a\":1.0}", "{\"a\":1e0}", "{\"a\":9007199254740992}", "{\"a\":-1}",
      "{\"a\":18446744073709551616}", "{\"a\":NaN}", "{\"a\":Infinity}",
      "{/*comment*/\"a\":1}", "{\"a\":1,}", "{\"a\":'text'}", "[]",
      "{\"a\":\"\\ud800\"}", "{\"a\":\"\\udc00\"}", "{\"a\":\"\xc0\x80\"}"}) {
    REQUIRE(!strict_json(text, value));
  }
  REQUIRE(!strict_json("{\"a\":" + std::string(40, '[') + "0" + std::string(40, ']') + "}", value));
  REQUIRE(!strict_json("{\"a\":\"" + std::string(65536, 'x') + "\"}", value));
  REQUIRE(strict_json("{\"emoji\":\"\\ud83d\\ude00\"}", value));
}
void authorization(const Json::Value& vectors) {
  const auto& b = vectors["expected_binding"];
  ExpectedSession e;
  e.issuer=b["iss"].asString();e.server_instance_id=b["server_instance_id"].asString();
  e.session_id=b["session_id"].asString();e.session_request_id=b["session_request_id"].asString();
  e.owner_user_id=b["owner_user_id"].asString();e.host_endpoint_id=b["host_endpoint_id"].asString();
  e.controller_endpoint_id=b["controller_endpoint_id"].asString();e.host_jkt=b["host_jkt"].asString();
  e.controller_jkt=b["controller_jkt"].asString();e.grant_id=b["grant_id"].asString();
  e.restore_epoch=b["restore_epoch"].asUInt64();e.grant_version=b["grant_version"].asUInt64();
  e.user_token_version=b["user_token_version"].asUInt64();e.connection_epoch=b["connection_epoch"].asUInt();
  e.permission_ceiling=15;
  const auto now=vectors["reference_time_unix"].asInt64()*1000;
  SigningKey signer;
  REQUIRE(public_key(vectors["identities"]["server"]["public_jwk"],signer.key)==Error::ok);
  REQUIRE(signer.key.thumbprint==vectors["identities"]["server"]["jkt"].asString());
  signer.not_before_unix_ms=now-3600000;signer.not_after_unix_ms=now+86400000;
  PublicKey host;
  REQUIRE(public_key(vectors["identities"]["host"]["public_jwk"],host)==Error::ok);
  REQUIRE(host.thumbprint==e.host_jkt);
  const auto ticket=compact(vectors["valid"]["ticket"]),lease=compact(vectors["valid"]["lease"]),grant=compact(vectors["valid"]["grant"]);
  VerifiedLease verified{};
  REQUIRE(verify_authorization(ticket,lease,grant,signer,host,e,now,verified)==Error::ok);
  REQUIRE(verified.connection_epoch==3 && verified.sequence==1 && verified.permissions==15);
  REQUIRE(verified.issued_at_unix_ms==now && verified.expires_at_unix_ms==now+900000);
  for (const auto& rejected:vectors["rejected"]) {
    const auto invalid=compact(rejected);const bool is_ticket=rejected["kind"].asString()=="ticket";
    Jws signed_but_wrong;
    REQUIRE(verify_jws(invalid,signer.key,is_ticket?"ht-rd-ticket+jwt":"ht-rd-lease+jwt",signed_but_wrong)==Error::ok);
    REQUIRE(verify_authorization(is_ticket?invalid:ticket,is_ticket?lease:invalid,grant,signer,host,e,now,verified)!=Error::ok);
    REQUIRE(verified.permissions==0 && verified.expires_at_unix_ms==0);
  }
  REQUIRE(verify_authorization(ticket,lease,grant,signer,host,e,now+60000,verified)==Error::expired);
  auto narrow=e;narrow.permission_ceiling=1;
  REQUIRE(verify_authorization(ticket,lease,grant,signer,host,narrow,now,verified)==Error::permission);
  Jws parsed;
  auto tampered=ticket;const auto index=tampered.rfind('.')+1;tampered[index]=tampered[index]=='A'?'B':'A';
  REQUIRE(verify_jws(tampered,signer.key,"ht-rd-ticket+jwt",parsed)==Error::signature);
  REQUIRE(verify_jws(ticket+"=",signer.key,"ht-rd-ticket+jwt",parsed)==Error::malformed);
  REQUIRE(verify_jws(ticket,host,"ht-rd-ticket+jwt",parsed)!=Error::ok);
  auto private_jwk=vectors["identities"]["host"]["public_jwk"];private_jwk["d"]="forbidden";
  REQUIRE(public_key(private_jwk,host)==Error::key);
}
}
int main(int argc,char** argv) {
  if(argc!=2)return 2;
  // C runtime guarantees argc argv entries; argc was checked immediately above.
#pragma clang unsafe_buffer_usage begin
  std::ifstream file(argv[1],std::ios::binary);
#pragma clang unsafe_buffer_usage end
  const std::string text((std::istreambuf_iterator<char>(file)),std::istreambuf_iterator<char>());
  Json::Value vectors;REQUIRE(strict_json(text,vectors));
  strict_parser();authorization(vectors);keyset_rotation(vectors);native_identity(vectors);sdp_profile();
  std::puts("Native authorization: strict JSON, public JWK, raw ES256, signed binding negatives, permission/lease limits and signed keyset rotation passed");
}
