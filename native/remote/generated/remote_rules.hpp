// Generated from server-owned remote-desktop.v1.json; do not edit.
#pragma once
#include <array>
#include <cstdint>
#include <string_view>
namespace ht::rd::protocol {
struct MessageRule { std::uint8_t type, channel; std::uint16_t flags; std::uint32_t payload; bool json; };
inline constexpr std::array<std::uint32_t, 6> CHANNEL_LIMITS = {16384,8192,256,2048,16384,17408};
inline constexpr std::array<MessageRule, 43> MESSAGE_RULES = {{
  {1,0,0,0,true},
  {2,0,0,0,true},
  {3,0,0,0,true},
  {4,0,0,0,true},
  {5,0,0,0,true},
  {6,0,0,0,true},
  {7,0,0,0,true},
  {8,0,0,0,true},
  {9,0,0,0,true},
  {10,0,0,0,true},
  {11,0,0,0,true},
  {12,0,0,0,true},
  {16,0,0,0,true},
  {17,0,0,0,true},
  {18,0,0,0,true},
  {19,0,0,0,true},
  {20,0,0,0,true},
  {21,0,0,0,true},
  {32,1,0,8,false},
  {33,1,1,32,false},
  {34,1,0,24,false},
  {35,1,0,0,false},
  {36,1,0,18,false},
  {48,2,0,16,false},
  {49,2,0,24,false},
  {64,3,0,0,true},
  {65,3,0,0,true},
  {66,3,0,0,true},
  {67,0,0,0,true},
  {80,0,0,0,true},
  {81,0,0,0,true},
  {96,0,0,0,true},
  {97,0,0,0,true},
  {112,4,0,0,true},
  {113,4,0,0,true},
  {114,4,0,0,false},
  {115,4,0,0,true},
  {128,5,0,0,true},
  {129,5,0,0,true},
  {130,5,0,0,false},
  {131,5,0,0,true},
  {132,5,0,0,true},
  {133,5,0,0,true},
}};
inline constexpr std::uint64_t ALL_PERMISSIONS = 1023u;
inline constexpr std::uint64_t PERMISSION_VIEW = 1u;
inline constexpr std::uint64_t PERMISSION_INPUT_KEYBOARD = 2u;
inline constexpr std::uint64_t PERMISSION_INPUT_POINTER = 4u;
inline constexpr std::uint64_t PERMISSION_INPUT_TEXT = 8u;
inline constexpr std::uint64_t PERMISSION_AUDIO_SYSTEM = 16u;
inline constexpr std::uint64_t PERMISSION_AUDIO_MICROPHONE = 32u;
inline constexpr std::uint64_t PERMISSION_CLIPBOARD_READ = 64u;
inline constexpr std::uint64_t PERMISSION_CLIPBOARD_WRITE = 128u;
inline constexpr std::uint64_t PERMISSION_FILES_SEND = 256u;
inline constexpr std::uint64_t PERMISSION_FILES_RECEIVE = 512u;
inline constexpr std::array<std::string_view, 10> PERMISSION_NAMES = {"view","input.keyboard","input.pointer","input.text","audio.system","audio.microphone","clipboard.read","clipboard.write","files.send","files.receive"};
}
