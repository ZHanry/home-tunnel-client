#pragma once
#include "clipboard.hpp"
#include "../generated/remote_protocol.hpp"
#include "modules/desktop_capture/desktop_capture_options.h"
#include "modules/desktop_capture/desktop_capturer.h"
#include "modules/desktop_capture/desktop_geometry.h"
#include <memory>
#include <string>
#include <vector>
#if defined(WEBRTC_WIN)
#include "../src/platform/windows_input.hpp"
#else
#include "../src/platform/x11_input.hpp"
#endif

namespace ht::rd {
#if defined(WEBRTC_WIN)
using HostInputSink=WindowsInputSink;
inline constexpr uint64_t HOST_PERMISSIONS=protocol::PERMISSION_VIEW|protocol::PERMISSION_INPUT_KEYBOARD|protocol::PERMISSION_INPUT_POINTER|protocol::PERMISSION_INPUT_TEXT|protocol::PERMISSION_CLIPBOARD_READ|protocol::PERMISSION_CLIPBOARD_WRITE;
#else
using HostInputSink=X11InputSink;
inline constexpr uint64_t HOST_PERMISSIONS=protocol::PERMISSION_VIEW|protocol::PERMISSION_INPUT_KEYBOARD|protocol::PERMISSION_INPUT_POINTER;
#endif
struct HostScreen {webrtc::DesktopCapturer::SourceId id;webrtc::DesktopRect rect;std::wstring device_key;std::string name;};
std::vector<HostScreen> host_displays();
bool host_screen_current(const HostScreen& screen);
bool host_prepare_process();
bool host_pipe_transport();
bool host_thread_enter();
void host_thread_leave();
webrtc::DesktopCaptureOptions host_capture_options();
std::unique_ptr<ClipboardStorage> host_clipboard();
}
