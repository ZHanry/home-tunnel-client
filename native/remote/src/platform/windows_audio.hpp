#pragma once
#if defined(_WIN32)
#include <atomic>
#include <cstdint>
#include <functional>
#include <span>
#include <thread>
#include "../media_deadline.hpp"

namespace ht::rd {
// Render-loopback only. This class has no microphone or remote path input.
// The verified session renews permission every lifecycle tick. The capture
// thread independently expires it and checks the current interactive user.
class WindowsSystemAudio {
 public:
  using Consume=std::function<void(std::span<const int16_t>)>;
  ~WindowsSystemAudio() { stop(); }
  static bool available(); // Initializes a stopped loopback device, no capture.
  bool start(Consume);
  void renew();
  void stop();
  bool failed() const { return failed_.load(); }
 private:
  std::thread thread_;
  std::atomic<bool> stopping_{true},failed_{false};
  MediaDeadline deadline_;
};
}
#endif
