#pragma once
#include <atomic>
#include <cstdint>
#include <functional>
#include <span>
#include <thread>
#include "../src/media_deadline.hpp"

namespace ht::rd::android {
// API26 AAudio output only. Each controller owns its stream and permission
// expiry, so one live session cannot keep another session's audio authorized.
class AudioOutput {
 public:
  using Pull=std::function<bool(std::span<int16_t>)>;
  ~AudioOutput() { stop(); }
  static bool available();
  bool start(Pull);
  void renew();
  void stop();
  bool failed() const { return failed_; }
 private:
  std::thread thread_;
  std::atomic<bool> stopping_{true},failed_{false};
  MediaDeadline deadline_;
};
}
