#pragma once

#include "modules/audio_device/include/audio_device_default.h"

namespace ht::rd {
// Video-only peers still construct WebRTC's composite media engine. Supplying
// this explicit device prevents fallback to physical audio hardware (which can
// fail on headless Linux) and never grants capture or playback capabilities.
class NoAudioDevice
    : public webrtc::webrtc_impl::AudioDeviceModuleDefault<webrtc::AudioDeviceModule> {
 public:
  int32_t ActiveAudioLayer(AudioLayer* layer) const override { *layer = kDummyAudio; return 0; }
  int32_t PlayoutIsAvailable(bool* available) override { *available = false; return 0; }
  int32_t RecordingIsAvailable(bool* available) override { *available = false; return 0; }
  int32_t StartPlayout() override { return -1; }
  int32_t StartRecording() override { return -1; }
};
}  // namespace ht::rd
