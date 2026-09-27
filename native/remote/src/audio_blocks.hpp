#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <span>

namespace ht::rd {
// WASAPI packets need not be 10 ms long. Keep at most one partial 48 kHz,
// stereo PCM16 block; never accumulate a latency-growing media queue.
class AudioBlocks {
 public:
  static constexpr size_t frames=480, channels=2, samples=frames*channels;
  void reset() { used_=0; block_.fill(0); }
  template<class Deliver>
  bool append(std::span<const int16_t> pcm, Deliver deliver) {
    if(pcm.size()%channels || pcm.size()>48000*channels) return false;
    while(!pcm.empty()) {
      const auto count=std::min(pcm.size(),samples-used_);
      std::copy_n(pcm.begin(),count,block_.begin()+used_);
      pcm=pcm.subspan(count);used_+=count;
      if(used_==samples) { if(!deliver(std::span<const int16_t>(block_))) {reset();return false;} used_=0; }
    }
    return true;
  }
 private:
  std::array<int16_t,samples> block_{};
  size_t used_=0;
};
}
