#pragma once
#if defined(_WIN32)
#include "../session_gate.hpp"
#include "display_geometry.hpp"
#include <cstdint>
#include <memory>
#include <string_view>

namespace ht::rd {
// Construction never injects input. The release guard starts on the session tick.
class WindowsInputSink final : public InputSink {
public:
    explicit WindowsInputSink(DisplayGeometry display, uint32_t target_process = 0);
    ~WindowsInputSink() override;
    WindowsInputSink(WindowsInputSink&&) noexcept;
    WindowsInputSink& operator=(WindowsInputSink&&) noexcept;
    WindowsInputSink(const WindowsInputSink&) = delete;
    WindowsInputSink& operator=(const WindowsInputSink&) = delete;
    bool key(uint16_t usage, bool down, bool repeat) override;
    bool button(uint8_t button, bool down) override;
    bool pointer(uint16_t display_slot, uint16_t x, uint16_t y) override;
    bool text(std::string_view utf8) override;
    bool wheel(int32_t dx, int32_t dy) override;
    static uint16_t scan_code(uint16_t usage);
    static bool ordinary_desktop();
    // Must be called by the authenticated session's independent 250 ms tick.
    // A stopped or expired guard can never be rearmed by a later input event.
    bool watchdog_tick();
    void watchdog_stop();
    // Returns -1 for the ordinary worker invocation, or a guard process exit code.
    static int run_release_guard(int argc, char** argv);
private:
    struct ReleaseGuard;
    bool ensure_guard();
    bool target_focused() const;
    bool target_at_point(int64_t x, int64_t y) const;
    DisplayGeometry display_;
    uint32_t target_process_ = 0;
    std::unique_ptr<ReleaseGuard> guard_;
    bool guard_failed_ = false;
    int64_t pointer_x_ = 0, pointer_y_ = 0;
    bool pointer_known_ = false;
};
}
#endif
