#pragma once
#if defined(__linux__) && !defined(__ANDROID__)
#include "display_geometry.hpp"
#include <cstdint>
#include <string>
#include <vector>

namespace ht::rd {
struct X11Screen { uint64_t id=0; DisplayGeometry geometry; std::string name; };
// Production requires an active, unlocked local logind X11 session and its
// actual local DISPLAY. Wayland/Xwayland and missing session evidence fail shut.
bool x11_ordinary_desktop();
std::vector<X11Screen> x11_screens();
bool x11_screen_current(uint64_t id,const DisplayGeometry& geometry);
bool x11_initialize_threads();
}
#endif
