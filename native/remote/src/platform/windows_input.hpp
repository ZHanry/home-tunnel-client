#pragma once
#if defined(_WIN32)
#include "../session_gate.hpp"
#include <cstdint>
#include <string_view>

namespace ht::rd {
struct DisplayGeometry { int32_t x=0, y=0, width=0, height=0; uint16_t slot=0; };
// Used only by a future authenticated host session. Construction never injects input.
class WindowsInputSink final : public InputSink {
public:
    explicit WindowsInputSink(DisplayGeometry display) : display_(display) {}
    bool key(uint16_t usage, bool down, bool repeat) override;
    bool button(uint8_t button, bool down) override;
    bool pointer(uint16_t display_slot, uint16_t x, uint16_t y) override;
    bool text(std::string_view utf8);
    static uint16_t scan_code(uint16_t usage);
    static bool ordinary_desktop();
private:
    DisplayGeometry display_;
};
}
#endif
