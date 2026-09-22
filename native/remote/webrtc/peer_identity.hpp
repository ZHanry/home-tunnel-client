#pragma once
#include "authorization.hpp"
#include "rtc_base/rtc_certificate.h"
#include <memory>
#include <set>

namespace ht::rd {
// Each instance owns one native-generated DTLS key and one connection epoch.
// Nothing supplied later over IPC may replace its certificate, nonce or binding.
class PeerIdentity {
 public:
  static std::unique_ptr<PeerIdentity> prepare(std::string session_id, uint32_t epoch);
  const Json::Value& prepared() const { return prepared_; }
  webrtc::scoped_refptr<webrtc::RTCCertificate> certificate() const { return certificate_; }
  auth::Error authorize(const Json::Value& request, int64_t now, uint64_t supported_permissions, VerifiedLease& lease);
  auth::Error renew(const Json::Value& message, int64_t now, VerifiedLease& lease);
  auth::Error peer_signal(const Json::Value& envelope, int64_t now, Json::Value& payload);
  void expect_answer(const Json::Value& payload) { answer_payload_ = payload; }
  auth::Error signed_answer(const Json::Value& envelope, int64_t now);
  auth::Error hello(const Json::Value& body, std::vector<uint8_t>& transcript);
  auth::Error controller_proof(const Json::Value& body);
  auth::Error host_proof(std::span<const uint8_t> signature);
  Json::Value hello_body() const;
  const auth::ExpectedSession& expected() const { return expected_; }
  const std::string& session_id() const { return session_id_; }
  uint32_t epoch() const { return epoch_; }
  bool authenticated() const { return controller_proved_ && host_proved_; }
  const Json::Value& permissions() const { return permissions_; }
  static std::string json(const Json::Value& value);
  static std::string base64(std::span<const uint8_t> value);
  static bool decode_base64(std::string_view value, std::vector<uint8_t>& output);
  static bool uuid(std::string_view value, std::array<uint8_t,16>& output);
 private:
  PeerIdentity(std::string session_id, uint32_t epoch) : session_id_(std::move(session_id)), epoch_(epoch) {}
  auth::Error signal(const Json::Value&, const auth::PublicKey&, bool local, int64_t now, auth::Jws&);
  std::string session_id_, ticket_jws_, ticket_jti_, offer_jws_, answer_jws_;
  uint32_t epoch_;
  webrtc::scoped_refptr<webrtc::RTCCertificate> certificate_;
  std::array<uint8_t,32> host_nonce_{}, controller_nonce_{};
  Json::Value prepared_, keys_, answer_payload_, permissions_;
  auth::ExpectedSession expected_;
  auth::PublicKey host_key_, controller_key_;
  std::vector<uint8_t> transcript_;
  std::set<uint64_t> peer_sequences_;
  uint64_t highest_sequence_=0, lease_sequence_=0;
  int64_t grant_expiry_=0;
  bool authorized_=false, controller_proved_=false, host_proved_=false;
};
}
