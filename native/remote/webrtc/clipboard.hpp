#pragma once
#include "authorization.hpp"
#include <deque>
#include <functional>
#include <memory>
#include <optional>
#include <string>

namespace ht::rd {
class ClipboardStorage {
 public:
  enum class Read { unchanged, text, no_text, unavailable };
  virtual ~ClipboardStorage() = default;
  virtual bool available() const { return true; }
  virtual Read read(uint64_t& sequence, std::string& utf8) = 0;
  virtual bool write(std::string_view utf8) = 0;
};

// One authenticated host session. Call only after the peer proof, selected UDP
// pair and current lease have passed; permission flags start disabled. It never
// reads or writes the OS clipboard before an explicitly approved feature request.
class ClipboardTransfer {
 public:
  using Send = std::function<bool(uint8_t,std::span<const uint8_t>)>;
  using Room = std::function<bool()>;
  using Failure = std::function<void(std::string_view)>;
  ClipboardTransfer(ClipboardStorage& storage, Send send, Room room, Failure failure);
  ~ClipboardTransfer();
  bool enable(std::string_view permission, bool enabled, uint64_t now);
  bool receive(uint8_t type, std::span<const uint8_t> payload, uint64_t now);
  void tick(uint64_t now);
  void close();
  bool enabled(std::string_view permission) const;
 private:
  struct Transfer {
    std::string id, digest, content;
    std::array<uint8_t,16> uuid{};
    size_t size=0, offset=0;
    uint64_t deadline=0;
    bool accepted=false;
    ~Transfer();
  };
  bool send_json(uint8_t type, const Json::Value& body);
  bool finish_receive();
  void fail(std::string_view permission);
  void remember(std::string id);
  ClipboardStorage& storage_; Send send_; Room room_; Failure failure_;
  std::unique_ptr<Transfer> incoming_, outgoing_;
  std::deque<std::string> seen_;
  std::string last_digest_;
  uint64_t sequence_=0, next_poll_=0;
  bool read_=false, write_=false, closed_=false;
};

#if defined(_WIN32)
// Owns a message-only clipboard owner window on the authenticated worker thread.
std::unique_ptr<ClipboardStorage> windows_clipboard();
#endif
}
