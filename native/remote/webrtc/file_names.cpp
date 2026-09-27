#include "file_storage.hpp"
#include "../src/protocol.hpp"

namespace ht::rd {
bool file_name_allowed(std::string_view name) {
  if (name.empty() || name.size() > 1020 || name == "." || name == ".." ||
      name.back() == '.' || name.back() == ' ' ||
      !valid_utf8({reinterpret_cast<const uint8_t*>(name.data()), name.size()}))
    return false;
  size_t utf16_units = 0;
  for (const auto character : name) {
    const auto byte = static_cast<uint8_t>(character);
    if ((byte & 0xc0) != 0x80) utf16_units += byte >= 0xf0 ? 2 : 1;
  }
  if (utf16_units > 255) return false;
  for (const auto c : name)
    if (static_cast<unsigned char>(c) < 32 ||
        std::string_view("/\\:<>\"|?*").find(c) != std::string_view::npos)
      return false;
  std::string base(name.substr(0, name.find('.')));
  for (auto& c : base)
    if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
  if (base == "CON" || base == "PRN" || base == "AUX" || base == "NUL" ||
      (base.size() == 4 &&
       (base.starts_with("COM") || base.starts_with("LPT")) && base[3] >= '1' &&
       base[3] <= '9'))
    return false;
  return true;
}
}
