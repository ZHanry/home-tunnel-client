#pragma once
#include <cstdint>

namespace ht::rd::android {
// Used on the signaling thread. A decoded frame belongs to one specific target;
// neither an old target nor a queued callback can unlock its replacement.
class SurfaceLifecycle {
 public:
  bool Replace(uint64_t generation, bool attached, uint64_t now) {
    if (!generation || generation <= generation_) return false;
    generation_ = generation; attached_ = attached; presented_ = false; wait_started_ = now;
    return true;
  }
  void RestartWait(uint64_t now) { if (!presented_) wait_started_ = now; }
  bool Presented(uint64_t generation, uint64_t frames) {
    if (!attached_ || presented_ || generation != generation_ || !frames) return false;
    presented_ = true; return true;
  }
  bool Expired(uint64_t now) const {
    return attached_ && !presented_ && now >= wait_started_ && now - wait_started_ >= 15000;
  }
  bool presented() const { return presented_; }
  uint64_t generation() const { return generation_; }
 private:
  uint64_t generation_ = 0, wait_started_ = 0;
  bool attached_ = false, presented_ = false;
};
}
