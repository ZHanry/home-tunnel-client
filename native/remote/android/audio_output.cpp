#include "audio_output.hpp"
#include <aaudio/AAudio.h>
#include <array>
#include <chrono>
#include <future>

static_assert(__ANDROID_API__ >= 26, "System audio requires an Android API 26 native toolchain target");

namespace ht::rd::android {
namespace {
uint64_t now_ms(){return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
struct Output {
  AAudioStream* stream=nullptr;
  ~Output(){if(stream){AAudioStream_requestStop(stream);AAudioStream_close(stream);}}
  bool open(){
    AAudioStreamBuilder* builder=nullptr;
    if(AAudio_createStreamBuilder(&builder)!=AAUDIO_OK || !builder)return false;
    AAudioStreamBuilder_setDirection(builder,AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setFormat(builder,AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setChannelCount(builder,2);
    AAudioStreamBuilder_setSampleRate(builder,48000);
    AAudioStreamBuilder_setSharingMode(builder,AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setPerformanceMode(builder,AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setBufferCapacityInFrames(builder,1920);
    const auto result=AAudioStreamBuilder_openStream(builder,&stream);
    AAudioStreamBuilder_delete(builder);
    if(result!=AAUDIO_OK || !stream || AAudioStream_getSampleRate(stream)!=48000 ||
       AAudioStream_getChannelCount(stream)!=2 || AAudioStream_getFormat(stream)!=AAUDIO_FORMAT_PCM_I16)return false;
    const auto frames=AAudioStream_setBufferSizeInFrames(stream,960);
    return frames>0 && frames<=1920;
  }
};
}
bool AudioOutput::available(){Output output;return output.open();}
void AudioOutput::renew(){if(!deadline_.renew(now_ms()))failed_=true;}
bool AudioOutput::start(Pull pull){
  stop();if(!pull)return false;
  stopping_=false;failed_=false;deadline_.begin(now_ms());
  std::promise<bool> started;auto result=started.get_future();
  thread_=std::thread([this,pull=std::move(pull),ready=std::move(started)]()mutable{
    Output output;
    if(!output.open() || stopping_ || !deadline_.alive(now_ms()) || AAudioStream_requestStart(output.stream)!=AAUDIO_OK){failed_=true;ready.set_value(false);return;}
    ready.set_value(true);
    std::array<int16_t,960> samples{};
    while(!stopping_){
      if(!deadline_.alive(now_ms())){failed_=true;break;}
      samples.fill(0);
      if(!pull(samples)){failed_=true;break;}
      size_t written=0;
      while(written<480 && !stopping_ && deadline_.alive(now_ms())){
        // A bounded blocking write paces 10 ms frames and cannot accumulate
        // an unbounded app queue. Expiry/mute closes and flushes this stream.
        const auto remaining=std::span(samples).subspan(written*2);
        const auto count=AAudioStream_write(output.stream,remaining.data(),static_cast<int32_t>(remaining.size()/2),20000000);
        if(count<=0){failed_=true;return;}
        written+=static_cast<size_t>(count);
      }
    }
    samples.fill(0);
  });
  const bool ok=result.get();if(!ok)stop();return ok;
}
void AudioOutput::stop(){deadline_.revoke();stopping_=true;if(thread_.joinable())thread_.join();}
}
