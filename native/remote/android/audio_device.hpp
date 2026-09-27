#pragma once
#include "audio_output.hpp"
#include "modules/audio_device/include/audio_device_default.h"
#include <mutex>

namespace ht::rd::android {
class ControllerAudioDevice : public webrtc::webrtc_impl::AudioDeviceModuleDefault<webrtc::AudioDeviceModule> {
 public:
  ~ControllerAudioDevice() override { StopPlayout(); }
  int32_t ActiveAudioLayer(AudioLayer* value) const override {*value=kAndroidAAudioAudio;return 0;}
  int32_t RecordingIsAvailable(bool* value) override {*value=false;return 0;}
  int32_t StartRecording() override {return -1;}
  bool RecordingIsInitialized() const override {return false;}
  int32_t PlayoutIsAvailable(bool* value) override {*value=AudioOutput::available();return 0;}
  int16_t PlayoutDevices() override {return 1;}
  int32_t RegisterAudioCallback(webrtc::AudioTransport* callback) override {std::lock_guard lock(callback_mutex_);callback_=callback;return 0;}
  int32_t StartPlayout() override {std::lock_guard lock(state_mutex_);requested_=true;return 0;}
  int32_t StopPlayout() override {std::lock_guard lock(state_mutex_);requested_=active_=false;output_.stop();return 0;}
  int32_t Terminate() override {return StopPlayout();}
  bool Playing() const override {std::lock_guard lock(state_mutex_);return requested_;}
  int32_t StereoPlayoutIsAvailable(bool* value) const override {*value=true;return 0;}
  int32_t StereoPlayout(bool* value) const override {*value=true;return 0;}
  int32_t SetStereoPlayout(bool value) override {return value?0:-1;}
  bool enable(bool enabled){
    std::lock_guard lock(state_mutex_);
    if(!enabled){active_=false;output_.stop();return true;}
    if(!requested_)return false;
    output_.stop();
    active_=output_.start([this](std::span<int16_t> samples){
      std::lock_guard callback_lock(callback_mutex_);
      if(!callback_)return false;
      size_t frames=0;int64_t elapsed=0,ntp=0;
      return callback_->NeedMorePlayData(480,sizeof(int16_t),2,48000,samples.data(),frames,&elapsed,&ntp)==0 && frames==480;
    });
    return active_;
  }
  void renew(){std::lock_guard lock(state_mutex_);if(active_)output_.renew();}
  bool failed()const{std::lock_guard lock(state_mutex_);return active_ && output_.failed();}
 private:
  mutable std::mutex state_mutex_,callback_mutex_;
  webrtc::AudioTransport* callback_=nullptr;
  AudioOutput output_;
  bool requested_=false,active_=false;
};
}
