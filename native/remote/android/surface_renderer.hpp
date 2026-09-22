#pragma once

#include <android/native_window.h>
#include <cstdint>
#include <mutex>
#include "api/video/video_frame.h"
#include "api/video/video_sink_interface.h"

namespace ht::rd::android {
// A native-owned sink. Authorization is driven only by the controller's native
// identity/path/lease state, never a Kotlin boolean. It starts disabled.
class SurfaceRenderer final : public webrtc::VideoSinkInterface<webrtc::VideoFrame> {
 public:
  SurfaceRenderer() = default;
  ~SurfaceRenderer() override;
  SurfaceRenderer(const SurfaceRenderer&) = delete;
  SurfaceRenderer& operator=(const SurfaceRenderer&) = delete;
  bool Attach(ANativeWindow* window, uint64_t generation);
  void SetAuthorized(bool authorized);
  void Close();
  void OnFrame(const webrtc::VideoFrame& frame) override;
  uint64_t presented_frames() const;
 private:
  mutable std::mutex mutex_;
  ANativeWindow* window_ = nullptr;
  uint64_t generation_ = 0, frames_ = 0;
  int width_ = 0, height_ = 0;
  bool authorized_ = false, closed_ = false;
};
}
