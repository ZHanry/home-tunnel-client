#pragma once
#include <algorithm>
#include <cstdint>

namespace ht::rd::android {
struct AudioBufferPolicy {
  int32_t requested_frames=0;
  int32_t maximum_frames=0;
  int64_t write_timeout_ns=0;
  bool accepts(int32_t actual)const{return actual>=requested_frames && actual<=maximum_frames;}
};
// AAudio can round a 1920-frame capacity request up to the device's minimum
// burst size. Slow shared devices (including emulators) are valid outputs.
// Bound queued audio to 200 ms at 48 kHz and each write wait to two bursts.
inline AudioBufferPolicy audio_buffer_policy(int32_t burst,int32_t capacity){
  if(burst<=0 || burst>4800 || capacity<burst)return {};
  const int32_t maximum=std::min<int32_t>(capacity,9600);
  const int32_t requested=std::min<int32_t>(maximum,std::max<int32_t>(960,burst*2));
  return {requested,maximum,std::max<int64_t>(20000000,static_cast<int64_t>(burst)*2000000000/48000)};
}
}
