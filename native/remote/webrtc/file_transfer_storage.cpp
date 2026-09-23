#include "file_transfer.hpp"
#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// Windows types must precede BCrypt declarations.
#include <bcrypt.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <openssl/rand.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>
#endif

namespace ht::rd {
namespace {
std::string utf8(const std::filesystem::path& path) {
#if defined(_WIN32)
  const auto& wide = path.native();
  if (wide.size() > 32767) return {};
  const auto count = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, wide.data(), static_cast<int>(wide.size()),
      nullptr, 0, nullptr, nullptr);
  if (count <= 0) return {};
  std::string result(static_cast<size_t>(count), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide.data(),
                          static_cast<int>(wide.size()), result.data(), count,
                          nullptr, nullptr) != count)
    return {};
  return result;
#else
  const auto text = path.u8string();
  return {text.begin(), text.end()};
#endif
}
std::filesystem::path utf8_path(std::string_view text) {
  return std::filesystem::path(std::u8string(
      reinterpret_cast<const char8_t*>(text.data()), text.size()));
}
std::string random_name() {
  std::array<uint8_t, 16> bytes{};
#if defined(_WIN32)
  if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()),
                      BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
    return {};
#else
  if (RAND_bytes(bytes.data(), bytes.size()) != 1) return {};
#endif
  constexpr std::string_view hex = "0123456789abcdef";
  std::string result = ".home-tunnel-";
  for (const auto byte : bytes) {
    result += hex[byte >> 4];
    result += hex[byte & 15];
  }
  return result;
}
std::string collision_name(std::string name, unsigned attempt) {
  if (!attempt) return name;
  const auto dot = name.find_last_of('.');
  const auto extension =
      dot != std::string::npos && dot && name.size() - dot <= 32
          ? name.substr(dot)
          : std::string{};
  std::string base = extension.empty() ? name : name.substr(0, dot);
  while (base.size() > 200) base.pop_back();
  while (
      !base.empty() &&
      !valid_utf8({reinterpret_cast<const uint8_t*>(base.data()), base.size()}))
    base.pop_back();
  return base + " (" + std::to_string(attempt) + ")" + extension;
}
bool local_path(const std::filesystem::path& path) {
  if (!path.is_absolute() || !file_name_allowed(utf8(path.filename())))
    return false;
  for (const auto& part : path)
    if (part == ".." || part == ".") return false;
  return true;
}
#if defined(_WIN32)
class Handle {
 public:
  HANDLE value = INVALID_HANDLE_VALUE;
  Handle() = default;
  explicit Handle(HANDLE handle) : value(handle) {}
  ~Handle() {
    if (value != INVALID_HANDLE_VALUE) CloseHandle(value);
  }
  Handle(Handle&& other) noexcept : value(other.value) {
    other.value = INVALID_HANDLE_VALUE;
  }
  Handle& operator=(Handle&& other) noexcept {
    if (this != &other) {
      if (value != INVALID_HANDLE_VALUE) CloseHandle(value);
      value = other.value;
      other.value = INVALID_HANDLE_VALUE;
    }
    return *this;
  }
  explicit operator bool() const { return value != INVALID_HANDLE_VALUE; }
};
struct Directory {
  std::filesystem::path path;
  std::vector<Handle> ancestors;
  bool open(const std::filesystem::path& value) {
    // Local drive paths only; network shares/device namespaces require a
    // separate picker/storage adapter rather than implicit remote access.
    const auto root = value.root_name().wstring();
    if (root.size() != 2 || root[1] != L':' || !value.is_absolute())
      return false;
    path = value;
    std::filesystem::path cursor = value.root_path();
    auto pin = [&] {
      Handle handle(CreateFileW(
          cursor.c_str(), FILE_READ_ATTRIBUTES | FILE_LIST_DIRECTORY,
          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
          FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
      BY_HANDLE_FILE_INFORMATION info{};
      if (!handle || !GetFileInformationByHandle(handle.value, &info) ||
          !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
          (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT))
        return false;
      ancestors.push_back(std::move(handle));
      return true;
    };
    if (!pin()) return false;
    for (const auto& part : value.relative_path()) {
      if (part == "." || part == "..") return false;
      cursor /= part;
      if (!pin()) return false;
    }
    return true;
  }
};
class Source final : public FileSource {
 public:
  Directory directory;
  Handle file;
  uint64_t length = 0;
  std::string filename;
  uint64_t size() const override { return length; }
  std::string name() const override { return filename; }
  bool unchanged() const override {
    LARGE_INTEGER n{};
    return GetFileSizeEx(file.value, &n) && n.QuadPart >= 0 &&
           static_cast<uint64_t>(n.QuadPart) == length;
  }
  bool read(uint64_t offset, std::span<uint8_t> output) override {
    if (offset > length || output.size() > length - offset || !unchanged())
      return false;
    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset);
    DWORD count = 0;
    return SetFilePointerEx(file.value, position, nullptr, FILE_BEGIN) &&
           ReadFile(file.value, output.data(),
                    static_cast<DWORD>(output.size()), &count, nullptr) &&
           count == output.size() && unchanged();
  }
};
class Destination final : public FileDestination {
 public:
  Directory directory;
  Handle file;
  std::string filename;
  uint64_t offset = 0, total = 0;
  bool committed = false;
  ~Destination() override { abort(); }
  bool write(uint64_t at, std::span<const uint8_t> bytes) override {
    if (committed || !file || at != offset || bytes.size() > total - offset)
      return false;
    DWORD count = 0;
    if (!WriteFile(file.value, bytes.data(), static_cast<DWORD>(bytes.size()),
                   &count, nullptr) ||
        count != bytes.size() || !FlushFileBuffers(file.value))
      return false;
    offset += bytes.size();
    return true;
  }
  bool commit(std::filesystem::path& actual) override {
    if (committed || !file || offset != total || !FlushFileBuffers(file.value))
      return false;
    FILE_BASIC_INFO basic{};
    basic.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    if (!SetFileInformationByHandle(file.value, FileBasicInfo, &basic,
                                    sizeof(basic)))
      return false;
    for (unsigned attempt = 0; attempt < 10000; ++attempt) {
      const auto target =
          directory.path / utf8_path(collision_name(filename, attempt));
      const auto name = target.wstring();
      // Keep a real terminator as well as the counted filename: the Win32
      // translation layer may inspect it before issuing the NT rename.
      const auto bytes = offsetof(FILE_RENAME_INFO, FileName) +
                         (name.size() + 1) * sizeof(wchar_t);
      std::vector<uint8_t> buffer(bytes, 0);
      // Win32 requires this variable-length structure. The allocation above
      // includes the complete counted UTF-16 filename plus its terminator.
#if defined(__clang__)
#pragma clang unsafe_buffer_usage begin
#endif
      auto* rename = reinterpret_cast<FILE_RENAME_INFO*>(buffer.data());
#if defined(__clang__)
#pragma clang unsafe_buffer_usage end
#endif
      rename->ReplaceIfExists = FALSE;
      rename->RootDirectory = nullptr;
      rename->FileNameLength =
          static_cast<DWORD>(name.size() * sizeof(wchar_t));
      std::memcpy(rename->FileName, name.data(), rename->FileNameLength);
      if (SetFileInformationByHandle(file.value, FileRenameInfo, rename,
                                     static_cast<DWORD>(buffer.size()))) {
        committed = true;
        actual = target;
        file = Handle{};
        return true;
      }
      const auto error = GetLastError();
      if (error != ERROR_ALREADY_EXISTS && error != ERROR_FILE_EXISTS &&
          !(error == ERROR_ACCESS_DENIED &&
            GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES))
        return false;
    }
    return false;
  }
  void abort() noexcept override {
    if (file && !committed) {
      FILE_DISPOSITION_INFO remove{TRUE};
      SetFileInformationByHandle(file.value, FileDispositionInfo, &remove,
                                 sizeof(remove));
    }
    file = Handle{};
  }
};
#else
class Handle {
 public:
  int value = -1;
  Handle() = default;
  explicit Handle(int fd) : value(fd) {}
  ~Handle() {
    if (value >= 0) ::close(value);
  }
  Handle(Handle&& other) noexcept : value(other.value) { other.value = -1; }
  Handle& operator=(Handle&& other) noexcept {
    if (this != &other) {
      if (value >= 0) ::close(value);
      value = other.value;
      other.value = -1;
    }
    return *this;
  }
  explicit operator bool() const { return value >= 0; }
};
struct Directory {
  std::filesystem::path path;
  Handle handle;
  bool open(const std::filesystem::path& value) {
    if (!value.is_absolute()) return false;
    path = value;
    handle = Handle(::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    if (!handle) return false;
    for (const auto& part : value.relative_path()) {
      if (part == ".." || part == ".") return false;
      Handle next(openat(handle.value, part.c_str(),
                         O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
      if (!next) return false;
      handle = std::move(next);
    }
    return true;
  }
};
bool same_snapshot(const struct stat& a, const struct stat& b) {
  if (a.st_dev != b.st_dev || a.st_ino != b.st_ino || a.st_size != b.st_size)
    return false;
#if defined(__APPLE__)
  return a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
         a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
         a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
         a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec;
#else
  return a.st_mtim.tv_sec == b.st_mtim.tv_sec &&
         a.st_mtim.tv_nsec == b.st_mtim.tv_nsec &&
         a.st_ctim.tv_sec == b.st_ctim.tv_sec &&
         a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
#endif
}
class Source final : public FileSource {
 public:
  Directory directory;
  Handle file;
  struct stat snapshot{};
  std::string filename;
  uint64_t size() const override {
    return static_cast<uint64_t>(snapshot.st_size);
  }
  std::string name() const override { return filename; }
  bool unchanged() const override {
    struct stat current{};
    return fstat(file.value, &current) == 0 && same_snapshot(snapshot, current);
  }
  bool read(uint64_t offset, std::span<uint8_t> output) override {
    if (offset > size() || output.size() > size() - offset || !unchanged())
      return false;
    size_t done = 0;
    while (done < output.size()) {
      const auto count =
          pread(file.value, output.subspan(done).data(), output.size() - done,
                static_cast<off_t>(offset + done));
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) return false;
      done += static_cast<size_t>(count);
    }
    return unchanged();
  }
};
class Destination final : public FileDestination {
 public:
  Directory directory;
  Handle staging, file;
  std::string stage_name, filename;
  struct stat stage_snapshot{};
  uint64_t offset = 0, total = 0;
  bool committed = false;
  ~Destination() override { abort(); }
  bool write(uint64_t at, std::span<const uint8_t> bytes) override {
    if (committed || !file || at != offset || bytes.size() > total - offset)
      return false;
    size_t done = 0;
    while (done < bytes.size()) {
      const auto count =
          pwrite(file.value, bytes.subspan(done).data(), bytes.size() - done,
                 static_cast<off_t>(at + done));
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) return false;
      done += static_cast<size_t>(count);
    }
    if (fsync(file.value) != 0) return false;
    offset += bytes.size();
    return true;
  }
  void cleanup() noexcept {
    if (staging) unlinkat(staging.value, "data", 0);
    if (directory.handle && !stage_name.empty()) {
      struct stat current{};
      if (fstatat(directory.handle.value, stage_name.c_str(), &current,
                  AT_SYMLINK_NOFOLLOW) == 0 &&
          current.st_dev == stage_snapshot.st_dev &&
          current.st_ino == stage_snapshot.st_ino)
        unlinkat(directory.handle.value, stage_name.c_str(), AT_REMOVEDIR);
    }
  }
  bool commit(std::filesystem::path& actual) override {
    if (committed || !file || offset != total || fsync(file.value) != 0)
      return false;
    for (unsigned attempt = 0; attempt < 10000; ++attempt) {
      const auto name = collision_name(filename, attempt);
      if (linkat(staging.value, "data", directory.handle.value, name.c_str(),
                 0) == 0) {
        committed = true;
        actual = directory.path / utf8_path(name);
        cleanup();
        file = Handle{};
        return fsync(directory.handle.value) == 0;
      }
      if (errno != EEXIST) return false;
    }
    return false;
  }
  void abort() noexcept override {
    cleanup();
    file = Handle{};
    staging = Handle{};
    stage_name.clear();
  }
};
#endif
class SystemAccess final : public FileAccess {
 public:
  std::unique_ptr<FileSource> open_source(const std::filesystem::path& path,
                                          std::string& error) override {
    error = "RD_FILE_PATH_INVALID";
    if (!local_path(path)) return {};
    auto result = std::make_unique<Source>();
    if (!result->directory.open(path.parent_path())) return {};
    error = "RD_FILE_READ_FAILED";
#if defined(_WIN32)
    result->file = Handle(CreateFileW(
        path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
    BY_HANDLE_FILE_INFORMATION info{};
    LARGE_INTEGER size{};
    if (!result->file || GetFileType(result->file.value) != FILE_TYPE_DISK ||
        !GetFileInformationByHandle(result->file.value, &info) ||
        (info.dwFileAttributes &
         (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) ||
        !GetFileSizeEx(result->file.value, &size) || size.QuadPart < 0)
      return {};
    result->length = static_cast<uint64_t>(size.QuadPart);
#else
    result->file =
        Handle(openat(result->directory.handle.value, path.filename().c_str(),
                      O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
    if (!result->file || fstat(result->file.value, &result->snapshot) != 0 ||
        !S_ISREG(result->snapshot.st_mode) || result->snapshot.st_size < 0)
      return {};
#endif
    result->filename = utf8(path.filename());
    error.clear();
    return result;
  }
  std::unique_ptr<FileDestination> create_destination(
      const std::filesystem::path& path, uint64_t size,
      std::string& error) override {
    error = "RD_FILE_PATH_INVALID";
    if (!local_path(path) || size > protocol::FILE_BYTES) return {};
    auto result = std::make_unique<Destination>();
    if (!result->directory.open(path.parent_path())) return {};
    result->filename = utf8(path.filename());
    result->total = size;
    error = "RD_FILE_NO_SPACE";
#if defined(_WIN32)
    ULARGE_INTEGER available{};
    if (!GetDiskFreeSpaceExW(path.parent_path().c_str(), &available, nullptr,
                             nullptr) ||
        available.QuadPart < size)
      return {};
    error = "RD_FILE_WRITE_FAILED";
    const auto name = random_name();
    if (name.empty()) return {};
    const auto temporary = path.parent_path() / utf8_path(name + ".part");
    result->file = Handle(CreateFileW(
        temporary.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
        FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_TEMPORARY |
            FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr));
    if (!result->file) return {};
#else
    struct statvfs space{};
    if (fstatvfs(result->directory.handle.value, &space) != 0 ||
        !space.f_frsize ||
        size / space.f_frsize + (size % space.f_frsize != 0) > space.f_bavail)
      return {};
    error = "RD_FILE_WRITE_FAILED";
    result->stage_name = random_name();
    if (result->stage_name.empty() ||
        mkdirat(result->directory.handle.value, result->stage_name.c_str(),
                0700) != 0)
      return {};
    result->staging = Handle(
        openat(result->directory.handle.value, result->stage_name.c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!result->staging ||
        fstat(result->staging.value, &result->stage_snapshot) != 0)
      return {};
    result->file = Handle(
        openat(result->staging.value, "data",
               O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
    if (!result->file) return {};
#endif
    error.clear();
    return result;
  }
};
}  // namespace
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
std::unique_ptr<FileAccess> system_file_access() {
  return std::make_unique<SystemAccess>();
}
}  // namespace ht::rd
