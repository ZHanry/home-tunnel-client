#pragma once
#include "../src/protocol.hpp"
#include "json/value.h"
#include <filesystem>
#include <functional>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace ht::rd {
// These handles are capabilities created only from a local OS picker result.
// A peer-provided filename is display metadata, never a path to open.
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
  // Success includes flushing the write; callers must not ACK a failed write.
  virtual bool write(uint64_t offset, std::span<const uint8_t> bytes) = 0;
  // Atomically publishes without replacing an existing name; collisions get a
  // new local basename. Returns the actual local path, never sent to the peer.
  virtual bool commit(std::filesystem::path& actual_path) = 0;
  // Removes only this object's uncommitted temporary file. Never removes a
  // committed destination, including cancellation after a successful commit.
  virtual void abort() noexcept = 0;
};
class FileAccess {
 public:
  virtual ~FileAccess() = default;
  virtual std::unique_ptr<FileSource> open_source(const std::filesystem::path&,
                                                  std::string& error) = 0;
  virtual std::unique_ptr<FileDestination> create_destination(
      const std::filesystem::path&, uint64_t size, std::string& error) = 0;
};
std::unique_ptr<FileAccess> system_file_access();
bool file_name_allowed(std::string_view name);

// One authenticated host session/connection epoch, called on one serialized
// worker. The owner must enforce current lease, peer proof and selected UDP
// path before receive/tick/local operations. Callbacks must not reenter.
// Permissions use controller perspective: files.send is incoming to the host;
// files.receive is outgoing from the host. Both are disabled initially.
class FileTransfer {
 public:
  using Send = std::function<bool(uint8_t, std::span<const uint8_t>)>;
  using Room = std::function<bool()>;
  using Event = std::function<void(const Json::Value&)>;
  using Current = std::function<bool()>;
  FileTransfer(Send send, Room room, Event event, Current current);
  FileTransfer(FileAccess& access, Send send, Room room, Event event,
               Current current);
  ~FileTransfer();
  FileTransfer(const FileTransfer&) = delete;
  FileTransfer& operator=(const FileTransfer&) = delete;
  bool enable(std::string_view permission, bool value, uint64_t now);
  bool enabled(std::string_view permission) const;
  // Local-only APIs. The GUI/IPC owner must bind picker approval to this exact
  // session and epoch and validate it again after the picker returns.
  bool offer_sources(const std::vector<std::filesystem::path>& paths,
                     uint64_t now);
  bool approve_destination(std::string_view id,
                           const std::filesystem::path& absolute_path,
                           uint64_t now);
  bool cancel(std::string_view id, uint64_t now, bool notify = true);
  bool receive(uint8_t type, std::span<const uint8_t> payload, uint64_t now);
  void tick(uint64_t now);
  void close();
  size_t pending() const;
  size_t active() const;

 private:
  class Impl;
  std::unique_ptr<FileAccess> owned_access_;
  std::unique_ptr<Impl> impl_;
};
}  // namespace ht::rd
