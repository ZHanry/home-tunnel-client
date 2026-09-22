#pragma once
#if defined(__linux__) && !defined(__ANDROID__)
#include "../session_gate.hpp"
#include "display_geometry.hpp"
#include <memory>

namespace ht::rd {
class X11InputSink final : public InputSink {
public:
    explicit X11InputSink(DisplayGeometry display,uint32_t target_process=0);
    ~X11InputSink() override;
    X11InputSink(X11InputSink&&) noexcept;
    X11InputSink& operator=(X11InputSink&&) noexcept;
    X11InputSink(const X11InputSink&)=delete;
    X11InputSink& operator=(const X11InputSink&)=delete;
    bool key(uint16_t usage,bool down,bool repeat) override;
    bool button(uint8_t button,bool down) override;
    bool pointer(uint16_t display_slot,uint16_t x,uint16_t y) override;
    bool wheel(int32_t dx,int32_t dy) override;
    bool watchdog_tick();
    void watchdog_stop();
    static bool ordinary_desktop();
    static bool pidfd_available();
    static int run_release_guard(int argc,char** argv);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}
#endif
