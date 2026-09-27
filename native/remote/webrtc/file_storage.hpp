#pragma once
#include <cstdint>
#include <filesystem>
#include <memory>
#include <span>
#include <string>
#include <string_view>

namespace ht::rd {
// Handles created from local OS pickers. Peer filenames are metadata, never
// authority to open a path or publish a destination.
class FileSource {
 public:
  virtual ~FileSource() = default;
  virtual uint64_t size() const = 0;
  virtual std::string name() const = 0;
  virtual bool read(uint64_t offset, std::span<uint8_t> output) = 0;
  virtual bool unchanged() const = 0;
};
class FileDestination {
 public:
  virtual ~FileDestination() = default;
  virtual bool write(uint64_t offset, std::span<const uint8_t> bytes) = 0;
  // Called only after size and SHA-256 verification. Desktop storage publishes
  // without replacement. Android seals an app-private staging descriptor; the
  // app copies it to its SAF-selected destination only after the complete event.
  virtual bool commit(std::filesystem::path& actual_path) = 0;
  virtual void abort() noexcept = 0;
};
class FileAccess {
 public:
  virtual ~FileAccess() = default;
  virtual std::unique_ptr<FileSource> open_source(const std::filesystem::path&, std::string& error) = 0;
  virtual std::unique_ptr<FileDestination> create_destination(const std::filesystem::path&, uint64_t size, std::string& error) = 0;
};
std::unique_ptr<FileAccess> system_file_access();
bool file_name_allowed(std::string_view name);
}
