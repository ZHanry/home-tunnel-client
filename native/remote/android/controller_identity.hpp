#pragma once
#include "../webrtc/peer_identity.hpp"

namespace ht::rd {
// One controller, one native-generated certificate/nonce and one connection epoch.
// The shared verifier validates ticket, lease, host grant and pinned keyset; this
// class independently enforces the controller direction of the peer handshake.
class ControllerIdentity {
 public:
  static std::unique_ptr<ControllerIdentity> prepare(std::string session_id, uint32_t epoch);
  const Json::Value& prepared() const { return prepared_; }
  webrtc::scoped_refptr<webrtc::RTCCertificate> certificate() const { return authorization_->certificate(); }
  auth::Error authorize(const Json::Value& context, int64_t now, uint64_t supported, VerifiedLease& lease);
  auth::Error renew(const Json::Value& message, int64_t now, VerifiedLease& lease);
  const auth::ExpectedSession& expected() const { return authorization_->expected(); }
  const Json::Value& permissions() const { return authorization_->permissions(); }
  const std::string& session_id() const { return authorization_->session_id(); }
  uint32_t epoch() const { return authorization_->epoch(); }
  // The runtime must validate its generated SDP against certificate() before
  // fixing this payload; a later signing callback cannot substitute another SDP.
  void expect_offer(const Json::Value& payload);
  auth::Error signed_offer(const Json::Value& envelope, int64_t now);
  auth::Error peer_signal(const Json::Value& envelope, int64_t now, Json::Value& payload);
  Json::Value hello_body() const;
  auth::Error hello(const Json::Value& host_body, std::vector<uint8_t>& transcript);
  auth::Error host_proof(const Json::Value& body);
  auth::Error controller_proof(std::span<const uint8_t> signature);
  bool authenticated() const { return host_proved_ && controller_proved_; }
 private:
  explicit ControllerIdentity(std::unique_ptr<PeerIdentity> authorization)
      : authorization_(std::move(authorization)) {}
  auth::Error signal(const Json::Value&, const auth::PublicKey&, bool local, int64_t now,
                     auth::Jws&, uint64_t& sequence) const;
  std::unique_ptr<PeerIdentity> authorization_;
  Json::Value prepared_, offer_payload_;
  auth::PublicKey host_key_, controller_key_;
  std::string ticket_jws_, ticket_jti_, offer_jws_, answer_jws_;
  std::array<uint8_t,32> controller_nonce_{}, host_nonce_{};
  std::vector<uint8_t> transcript_;
  std::set<uint64_t> peer_sequences_;
  uint64_t highest_sequence_=0;
  bool authorized_=false, host_proved_=false, controller_proved_=false;
};
}
