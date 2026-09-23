#include "surface_renderer.hpp"
#include <chrono>
#include <cstring>

#include "api/video/i420_buffer.h"
#include "third_party/libyuv/include/libyuv.h"

namespace ht::rd::android {
SurfaceRenderer::~SurfaceRenderer() { Close(); }

bool SurfaceRenderer::Attach(ANativeWindow* window, uint64_t generation) {
  std::lock_guard lock(mutex_);
  if (closed_ || !generation || generation <= generation_) return false;
  // JNI's ANativeWindow_fromSurface reference is borrowed across the C ABI.
  // Acquire our own reference before replacing/releasing the previous surface.
  if (window) ANativeWindow_acquire(window);
  if (window_) ANativeWindow_release(window_);
  window_ = window;
  generation_ = generation;
  frames_ = 0;
  width_ = height_ = 0;
  return true;
}

void SurfaceRenderer::SetAuthorized(bool authorized, uint64_t deadline_ms) {
  std::lock_guard lock(mutex_);
  authorized_ = authorized && !closed_ && deadline_ms;
  deadline_ms_ = deadline_ms;
}

void SurfaceRenderer::Close() {
  std::lock_guard lock(mutex_);
  closed_ = true;
  authorized_ = false;
  if (window_) ANativeWindow_release(window_);
  window_ = nullptr;
}

SurfaceRenderer::Presentation SurfaceRenderer::presentation() const {
  std::lock_guard lock(mutex_);
  return {generation_, frames_};
}

void SurfaceRenderer::OnFrame(const webrtc::VideoFrame& frame) {
  std::lock_guard lock(mutex_);
  const auto now = [] { return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); };
  if (closed_ || !authorized_ || now() >= deadline_ms_ || !window_ || !frame.video_frame_buffer()) return;
  if (frame.width() < 1 || frame.height() < 1 || frame.width() > 8192 ||
      frame.height() > 8192 || int64_t(frame.width()) * frame.height() > 33554432) return;
  auto planar = frame.video_frame_buffer()->ToI420();
  if (!planar) return;
  if (frame.rotation() != webrtc::kVideoRotation_0) {
    if (frame.rotation() != webrtc::kVideoRotation_90 && frame.rotation() != webrtc::kVideoRotation_180 &&
        frame.rotation() != webrtc::kVideoRotation_270) return;
    planar = webrtc::I420Buffer::Rotate(*planar, frame.rotation());
    if (!planar) return;
  }
  const int width = planar->width(), height = planar->height();
  if (width_ != width || height_ != height) {
    if (ANativeWindow_setBuffersGeometry(window_, width, height, WINDOW_FORMAT_RGBA_8888)) return;
    width_ = width;
    height_ = height;
  }
  ANativeWindow_Buffer output{};
  if (ANativeWindow_lock(window_, &output, nullptr)) return;
  bool written = false;
  if (output.bits && output.format == WINDOW_FORMAT_RGBA_8888 && output.width == width &&
      output.height == height && output.stride >= width && output.stride <= 16384) {
    // libyuv ABGR names its 32-bit register order; little-endian bytes are RGBA,
    // matching Android WINDOW_FORMAT_RGBA_8888 exactly.
    written = libyuv::I420ToABGR(planar->DataY(), planar->StrideY(), planar->DataU(), planar->StrideU(),
                               planar->DataV(), planar->StrideV(), static_cast<uint8_t*>(output.bits),
                               output.stride * 4, width, height) == 0;
  }
  if (now() >= deadline_ms_ && output.bits && output.format == WINDOW_FORMAT_RGBA_8888 && output.stride > 0 && output.stride <= 16384 && output.height > 0 && output.height <= 8192) {
    std::memset(output.bits, 0, static_cast<size_t>(output.stride) * output.height * 4); written = false;
  }
  const bool posted = ANativeWindow_unlockAndPost(window_) == 0;
  if (written && posted) ++frames_;
}
}
