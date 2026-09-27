#pragma once
#if defined(WEBRTC_WIN)
#include "../src/platform/windows_audio.hpp"
#include "api/media_stream_interface.h"
#include "api/audio_options.h"
#include "no_audio_device.hpp"
#include <atomic>
#include <mutex>
#include <set>

namespace ht::rd {
// WebRTC's audio engine lifecycle is satisfied by an external track source.
// No ADM opens a recording endpoint; PCM comes only from authorized WASAPI
// render-loopback below. Microphone capture and host playback are absent.
class SourceAudioDevice : public NoAudioDevice {
 public:
  int32_t RecordingIsAvailable(bool* value) override { *value=true;return 0; }
  int32_t StartRecording() override { recording_=true;return 0; }
  int32_t StopRecording() override { recording_=false;return 0; }
  bool Recording() const override { return recording_; }
 private:
  std::atomic<bool> recording_{false};
};

class SystemAudioSource : public webrtc::AudioSourceInterface {
 public:
  ~SystemAudioSource() override { capture_.stop(); }
  SourceState state() const override { return kLive; }
  bool remote() const override { return false; }
  void RegisterObserver(webrtc::ObserverInterface* value) override { observers_.insert(value); }
  void UnregisterObserver(webrtc::ObserverInterface* value) override { observers_.erase(value); }
  const webrtc::AudioOptions options() const override {
    webrtc::AudioOptions options;options.echo_cancellation=false;
    options.auto_gain_control=false;options.noise_suppression=false;
    options.highpass_filter=false;options.init_recording_on_send=false;return options;
  }
  void AddSink(webrtc::AudioTrackSinkInterface* sink) override { std::lock_guard lock(mutex_);sinks_.insert(sink); }
  void RemoveSink(webrtc::AudioTrackSinkInterface* sink) override { std::lock_guard lock(mutex_);sinks_.erase(sink); }
  bool enable(bool enabled) {
    capture_.stop();enabled_=false;
    if(!enabled)return true;
    enabled_=capture_.start([this](std::span<const int16_t> samples){
      std::lock_guard lock(mutex_);
      for(auto* sink:sinks_)sink->OnData(samples.data(),16,48000,2,480,std::nullopt);
    });
    return enabled_;
  }
  void renew() { if(enabled_)capture_.renew(); }
  bool failed() const { return enabled_ && capture_.failed(); }
 private:
  WindowsSystemAudio capture_;
  std::mutex mutex_;
  std::set<webrtc::AudioTrackSinkInterface*> sinks_;
  std::set<webrtc::ObserverInterface*> observers_;
  bool enabled_=false;
};
}
#endif
