#pragma once
#include <atomic>
#include <cstdint>

namespace ht::rd {
// A stalled lifecycle thread cannot leave a media device running. Once this
// short grant expires, periodic renewal cannot resurrect it; a new explicit
// feature activation must call begin after checking the signed session again.
class MediaDeadline {
 public:
  void begin(uint64_t now) { until_=now+500; }
  void revoke() { until_=0; }
  bool alive(uint64_t now) const { const auto end=until_.load();return end && now<end; }
  bool renew(uint64_t now) {
    auto end=until_.load();
    while(end && now<end) {
      if(until_.compare_exchange_weak(end,now+500))return true;
    }
    return false;
  }
 private:
  std::atomic<uint64_t> until_{0};
};
}
