#include "file_transfer.hpp"
#include "json/reader.h"
#include "json/writer.h"
#include <algorithm>
#include <array>
#include <deque>
#include <map>
#include <utility>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// Windows types must precede BCrypt declarations.
#include <bcrypt.h>
#else
#include <openssl/rand.h>
#include <openssl/sha.h>
#endif

namespace ht::rd {
namespace {
constexpr uint64_t timeout_ms = 30000;
constexpr size_t max_active = 2, max_queue = 256;
std::string hex(std::span<const uint8_t> bytes) {
  constexpr char table[] = "0123456789abcdef";
  std::string result;
  for (const auto c : bytes) {
    result += table[c >> 4];
    result += table[c & 15];
  }
  return result;
}
std::string uuid_text(std::span<const uint8_t> bytes) {
  const auto value = hex(bytes);
  return value.substr(0, 8) + "-" + value.substr(8, 4) + "-" +
         value.substr(12, 4) + "-" + value.substr(16, 4) + "-" +
         value.substr(20);
}
bool uuid_bytes(std::string_view text, std::array<uint8_t, 16>& bytes) {
  if (text.size() != 36) return false;
  size_t offset = 0;
  auto nibble = [](char c) {
    return c >= '0' && c <= '9'   ? c - '0'
           : c >= 'a' && c <= 'f' ? c - 'a' + 10
                                  : -1;
  };
  for (size_t n = 0; n < 36;) {
    if (n == 8 || n == 13 || n == 18 || n == 23) {
      if (text[n++] != '-') return false;
      continue;
    }
    const int hi = nibble(text[n++]), lo = nibble(text[n++]);
    if (hi < 0 || lo < 0) return false;
    bytes[offset++] = static_cast<uint8_t>(hi * 16 + lo);
  }
  return true;
}
bool new_id(std::array<uint8_t, 16>& bytes) {
#if defined(_WIN32)
  if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()),
                      BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
    return false;
#else
  if (RAND_bytes(bytes.data(), bytes.size()) != 1) return false;
#endif
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  return true;
}
bool fields(const Json::Value& body,
            std::initializer_list<std::string_view> names) {
  if (!body.isObject() || body.size() != names.size()) return false;
  for (const auto name : names)
    if (!body.isMember(std::string(name))) return false;
  return true;
}
std::string json(const Json::Value& body) {
  Json::StreamWriterBuilder writer;
  writer["indentation"] = "";
  return Json::writeString(writer, body);
}
bool parse(std::span<const uint8_t> bytes, Json::Value& body) {
  if (bytes.empty() || bytes.size() > 17384 || !valid_utf8(bytes)) return false;
  Json::CharReaderBuilder builder;
  builder["collectComments"] = false;
  builder["allowComments"] = false;
  builder["allowTrailingCommas"] = false;
  builder["strictRoot"] = true;
  builder["failIfExtra"] = true;
  builder["rejectDupKeys"] = true;
  builder["allowSpecialFloats"] = false;
  builder["stackLimit"] = 16;
  const std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
  const auto* begin = reinterpret_cast<const char*>(bytes.data());
  std::string error;
  return reader->parse(begin, begin + bytes.size(), &body, &error) &&
         body.isObject();
}
bool digest_text(const Json::Value& value) {
  if (!value.isString() || value.asString().size() != 64) return false;
  for (char c : value.asString())
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}
class Hash {
 public:
  Hash() {
#if defined(_WIN32)
    good_ =
        BCryptOpenAlgorithmProvider(&algorithm_, BCRYPT_SHA256_ALGORITHM,
                                    nullptr, 0) >= 0 &&
        BCryptCreateHash(algorithm_, &hash_, nullptr, 0, nullptr, 0, 0) >= 0;
#else
    good_ = SHA256_Init(&hash_) == 1;
#endif
  }
  ~Hash() {
#if defined(_WIN32)
    if (hash_) BCryptDestroyHash(hash_);
    if (algorithm_) BCryptCloseAlgorithmProvider(algorithm_, 0);
#endif
  }
  bool update(std::span<const uint8_t> bytes) {
    if (!good_ || finished_) return false;
#if defined(_WIN32)
    good_ = BCryptHashData(hash_, const_cast<PUCHAR>(bytes.data()),
                           static_cast<ULONG>(bytes.size()), 0) >= 0;
#else
    good_ = SHA256_Update(&hash_, bytes.data(), bytes.size()) == 1;
#endif
    return good_;
  }
  std::string finish() {
    if (!good_ || finished_) return {};
    finished_ = true;
    std::array<uint8_t, 32> bytes{};
#if defined(_WIN32)
    if (BCryptFinishHash(hash_, bytes.data(), static_cast<ULONG>(bytes.size()),
                         0) < 0)
      return {};
#else
    if (SHA256_Final(bytes.data(), &hash_) != 1) return {};
#endif
    return hex(bytes);
  }

 private:
#if defined(_WIN32)
  BCRYPT_ALG_HANDLE algorithm_ = nullptr;
  BCRYPT_HASH_HANDLE hash_ = nullptr;
#else
  SHA256_CTX hash_{};
#endif
  bool good_ = false, finished_ = false;
};
}  // namespace
class FileTransfer::Impl {
 public:
  struct Item {
    std::string id, name, digest;
    std::array<uint8_t, 16> uuid{};
    uint64_t size = 0, offset = 0, deadline = 0, awaiting_offset = 0,
             last_progress = 0;
    bool outgoing = false, offered = false, accepted = false, running = false,
         awaiting = false, completing = false, pending_ack = false;
    std::unique_ptr<FileSource> source;
    std::unique_ptr<FileDestination> destination;
    std::unique_ptr<Hash> hash;
    ~Item() {
      if (destination) destination->abort();
    }
  };
  struct Message {
    uint8_t type;
    std::string id, text;
  };
  FileAccess& access;
  Send send;
  Room room;
  Event event;
  Current current;
  std::map<std::string, std::unique_ptr<Item>> items;
  std::deque<Message> queue;
  std::deque<std::string> seen;
  bool incoming_enabled = false, outgoing_enabled = false, closed = false;
  Impl(FileAccess& a, Send s, Room r, Event e, Current c)
      : access(a),
        send(std::move(s)),
        room(std::move(r)),
        event(std::move(e)),
        current(std::move(c)) {}
  bool live() {
    if (closed) return false;
    if (!current || !current()) {
      close();
      return false;
    }
    return true;
  }
  void emit(const Item& item, std::string_view state,
            std::string_view error = {}, bool maybe_saved = false) {
    if (!event) return;
    Json::Value body;
    body["event"] = std::string(state);
    body["id"] = item.id;
    body["name"] = item.name;
    body["size"] = Json::UInt64(item.size);
    body["offset"] = Json::UInt64(item.offset);
    body["outgoing"] = item.outgoing;
    if (!error.empty()) body["error_code"] = std::string(error);
    if (maybe_saved) body["may_be_saved"] = true;
    event(body);
  }
  void local_error(std::string_view error) {
    if (event) {
      Json::Value body;
      body["event"] = "error";
      body["error_code"] = std::string(error);
      body["outgoing"] = true;
      event(body);
    }
  }
  void progress(Item& item, uint64_t now) {
    if (!item.last_progress || now - item.last_progress >= 100 ||
        item.offset == item.size) {
      item.last_progress = now;
      emit(item, "progress");
    }
  }
  size_t active() const {
    size_t count = 0;
    for (const auto& [id, item] : items) count += item->running;
    return count;
  }
  uint64_t total() const {
    uint64_t size = 0;
    for (const auto& [id, item] : items) size += item->size;
    return size;
  }
  bool remembered(std::string_view id) const {
    return std::find(seen.begin(), seen.end(), id) != seen.end();
  }
  void remember(const std::string& id) {
    if (!remembered(id)) seen.push_back(id);
    if (seen.size() > 128) seen.pop_front();
  }
  bool enqueue(uint8_t type, const Json::Value& body) {
    if (queue.size() >= max_queue) {
      close();
      return false;
    }
    queue.push_back({type, body["id"].asString(), json(body)});
    return true;
  }
  void close() {
    closed = true;
    incoming_enabled = outgoing_enabled = false;
    queue.clear();
    items.clear();
    seen.clear();
  }
  bool cancel(std::string_view id, uint64_t now, bool notify,
              std::string_view error = "RD_FILE_CANCELLED",
              bool may_be_saved = false) {
    (void)now;
    const auto found = items.find(std::string(id));
    if (found == items.end()) return remembered(id);
    auto item = std::move(found->second);
    items.erase(found);
    std::erase_if(queue,
                  [&](const Message& message) { return message.id == id; });
    remember(item->id);
    if (item->destination) item->destination->abort();
    if (notify && !closed) {
      Json::Value body;
      body["id"] = item->id;
      body["reason"] = "cancelled";
      enqueue(protocol::FILE_CANCEL, body);
    }
    emit(*item, error == "RD_FILE_CANCELLED" ? "cancelled" : "error", error,
         may_be_saved || item->completing);
    return true;
  }
  bool enable(std::string_view permission, bool value, uint64_t now) {
    if (!live()) return false;
    bool outgoing;
    if (permission == "files.send") {
      incoming_enabled = value;
      outgoing = false;
    } else if (permission == "files.receive") {
      outgoing_enabled = value;
      outgoing = true;
    } else
      return false;
    if (!value) {
      std::erase_if(queue, [&](const Message& message) {
        return outgoing ? (message.type == protocol::FILE_OFFER ||
                           message.type == protocol::FILE_COMPLETE)
                        : (message.type == protocol::FILE_ACCEPT ||
                           message.type == protocol::FILE_ACK);
      });
      std::vector<std::string> ids;
      for (const auto& [id, item] : items)
        if (item->outgoing == outgoing) ids.push_back(id);
      for (const auto& id : ids) cancel(id, now, true);
    }
    return true;
  }
  bool offer_sources(const std::vector<std::filesystem::path>& paths,
                     uint64_t now) {
    if (!live() || !outgoing_enabled) return false;
    if (paths.empty() || paths.size() + items.size() > protocol::BATCH_FILES) {
      local_error("RD_FILE_LIMIT");
      return false;
    }
    uint64_t batch = total();
    std::vector<std::unique_ptr<Item>> prepared;
    for (const auto& path : paths) {
      std::string error;
      auto source = access.open_source(path, error);
      if (!live()) return false;
      if (!source) {
        local_error(error);
        return false;
      }
      const auto size = source->size();
      if (!file_name_allowed(source->name()) || size > protocol::FILE_BYTES ||
          size > protocol::BATCH_FILE_BYTES - batch) {
        local_error("RD_FILE_LIMIT");
        return false;
      }
      batch += size;
      auto item = std::make_unique<Item>();
      if (!new_id(item->uuid)) {
        local_error("RD_FILE_INVALID");
        return false;
      }
      item->id = uuid_text(item->uuid);
      if (items.contains(item->id) || remembered(item->id)) {
        local_error("RD_FILE_INVALID");
        return false;
      }
      item->name = source->name();
      item->size = size;
      item->source = std::move(source);
      item->outgoing = true;
      item->deadline = now + timeout_ms;
      prepared.push_back(std::move(item));
    }
    for (auto& item : prepared) {
      const auto id = item->id;
      emit(*item, "offer");
      items.emplace(id, std::move(item));
    }
    tick(now);
    return !closed;
  }
  bool approve(std::string_view id, const std::filesystem::path& path,
               uint64_t now) {
    if (!live() || !incoming_enabled) return false;
    const auto found = items.find(std::string(id));
    if (found == items.end() || found->second->outgoing ||
        found->second->accepted || now >= found->second->deadline ||
        active() >= max_active)
      return false;
    auto& item = *found->second;
    std::string error;
    auto destination = access.create_destination(path, item.size, error);
    if (!live()) return false;
    if (!destination) {
      cancel(id, now, true, error);
      return false;
    }
    item.destination = std::move(destination);
    item.hash = std::make_unique<Hash>();
    item.accepted = item.running = true;
    item.deadline = now + timeout_ms;
    Json::Value body;
    body["id"] = item.id;
    return enqueue(protocol::FILE_ACCEPT, body);
  }
  bool receive(uint8_t type, std::span<const uint8_t> payload, uint64_t now) {
    if (!live()) return false;
    if (type < protocol::FILE_OFFER || type > protocol::FILE_CANCEL)
      return false;
    if (type == protocol::FILE_CHUNK) {
      if (payload.size() <= 24 ||
          payload.size() > 24 + protocol::FILE_CHUNK_BYTES)
        return false;
      if (!incoming_enabled) return true;
      const auto id = uuid_text(payload.first(16));
      const auto found = items.find(id);
      if (found == items.end()) return remembered(id);
      auto& item = *found->second;
      const auto offset = read_u64(payload, 16);
      const auto bytes = payload.subspan(24);
      if (item.outgoing || !item.destination || !item.accepted ||
          item.pending_ack || offset != item.offset ||
          bytes.size() > item.size - item.offset)
        return false;
      if (now >= item.deadline) {
        cancel(id, now, true, "RD_FILE_TIMEOUT");
        return true;
      }
      if (!item.destination->write(offset, bytes)) {
        cancel(id, now, true, "RD_FILE_WRITE_FAILED");
        return true;
      }
      if (!live()) return false;
      if (!item.hash->update(bytes)) {
        cancel(id, now, true, "RD_FILE_HASH_FAILED");
        return true;
      }
      item.offset += bytes.size();
      item.deadline = now + timeout_ms;
      item.pending_ack = true;
      Json::Value ack;
      ack["id"] = id;
      ack["offset"] = Json::UInt64(item.offset);
      progress(item, now);
      return enqueue(protocol::FILE_ACK, ack);
    }
    Json::Value body;
    if (!parse(payload, body) || !body["id"].isString()) return false;
    std::array<uint8_t, 16> uuid{};
    const auto id = body["id"].asString();
    if (!uuid_bytes(id, uuid)) return false;
    if (type == protocol::FILE_OFFER) {
      if (!fields(body, {"id", "name", "size"}) || !body["name"].isString() ||
          !file_name_allowed(body["name"].asString()) ||
          !body["size"].isUInt64() ||
          body["size"].asUInt64() > protocol::FILE_BYTES)
        return false;
      if (!incoming_enabled) return true;
      if (items.contains(id) || remembered(id)) return false;
      if (items.size() >= protocol::BATCH_FILES ||
          body["size"].asUInt64() > protocol::BATCH_FILE_BYTES - total())
        return false;
      auto item = std::make_unique<Item>();
      item->id = id;
      item->uuid = uuid;
      item->name = body["name"].asString();
      item->size = body["size"].asUInt64();
      item->deadline = now + timeout_ms;
      const auto* inserted = item.get();
      items.emplace(id, std::move(item));
      emit(*inserted, "offer");
      return true;
    }
    if (type == protocol::FILE_CANCEL) {
      if (!(fields(body, {"id"}) ||
            (fields(body, {"id", "reason"}) && body["reason"].isString() &&
             body["reason"].asString().size() <= 64)))
        return false;
      // Unknown cancellation is harmless and cannot create a transfer or path.
      cancel(id, now, false);
      return true;
    }
    const bool from_sender = type == protocol::FILE_COMPLETE;
    if (from_sender ? !incoming_enabled : !outgoing_enabled) return true;
    const auto found = items.find(id);
    if (found == items.end()) return remembered(id);
    auto& item = *found->second;
    if (now >= item.deadline) {
      cancel(id, now, true, "RD_FILE_TIMEOUT");
      return true;
    }
    if (type == protocol::FILE_ACCEPT) {
      if (!fields(body, {"id"}) || !item.outgoing || !item.offered ||
          item.accepted)
        return false;
      item.accepted = true;
      item.deadline = now + timeout_ms;
      return true;
    }
    if (type == protocol::FILE_COMPLETE) {
      if (!fields(body, {"id", "size", "sha256"}) || item.outgoing ||
          !item.destination || item.pending_ack || !body["size"].isUInt64() ||
          body["size"].asUInt64() != item.size || item.offset != item.size ||
          !digest_text(body["sha256"]))
        return false;
      const auto digest = item.hash->finish();
      if (digest.empty() || digest != body["sha256"].asString()) {
        cancel(id, now, true, "RD_FILE_HASH_MISMATCH");
        return true;
      }
      if (!live()) return false;
      std::filesystem::path actual;
      item.completing = true;
      if (!item.destination->commit(actual)) {
        cancel(id, now, true, "RD_FILE_WRITE_FAILED", true);
        return true;
      }
      if (!live()) return false;
      Json::Value ack;
      ack["id"] = id;
      ack["sha256"] = digest;
      // UI only needs the safe basename; never include the local absolute path.
      const auto name = actual.filename().u8string();
      item.name.assign(name.begin(), name.end());
      emit(item, "complete");
      remember(id);
      items.erase(found);
      return enqueue(protocol::FILE_ACK, ack);
    }
    if (type == protocol::FILE_ACK) {
      if (!item.outgoing || !item.accepted) return false;
      if (fields(body, {"id", "offset"}) && body["offset"].isUInt64()) {
        if (!item.awaiting || body["offset"].asUInt64() != item.awaiting_offset)
          return false;
        item.awaiting = false;
        item.offset = item.awaiting_offset;
        item.deadline = now + timeout_ms;
        progress(item, now);
        return true;
      }
      if (!fields(body, {"id", "sha256"}) || !digest_text(body["sha256"]) ||
          !item.completing || item.digest != body["sha256"].asString())
        return false;
      emit(item, "complete");
      remember(id);
      items.erase(found);
      return true;
    }
    return false;
  }
  void tick(uint64_t now) {
    if (!live()) return;
    std::vector<std::string> expired;
    for (const auto& [id, item] : items)
      if (now >= item->deadline) expired.push_back(id);
    for (const auto& id : expired) cancel(id, now, true, "RD_FILE_TIMEOUT");
    for (auto& [id, item] : items)
      if (item->outgoing && !item->offered) {
        Json::Value offer;
        offer["id"] = id;
        offer["name"] = item->name;
        offer["size"] = Json::UInt64(item->size);
        if (!enqueue(protocol::FILE_OFFER, offer)) return;
        item->offered = true;
      }
    unsigned sent = 0;
    while (!queue.empty() && sent < 16 && room() && live()) {
      auto message = std::move(queue.front());
      queue.pop_front();
      if (!send(message.type,
                {reinterpret_cast<const uint8_t*>(message.text.data()),
                 message.text.size()})) {
        close();
        return;
      }
      if (message.type == protocol::FILE_ACK) {
        const auto found = items.find(message.id);
        if (found != items.end() && !found->second->outgoing)
          found->second->pending_ack = false;
      }
      ++sent;
    }
    if (!queue.empty() || !live()) return;
    for (auto iterator = items.begin(); iterator != items.end();) {
      auto& item = *iterator->second;
      const auto id = item.id;
      ++iterator;
      if (!item.outgoing || !item.accepted || item.awaiting ||
          item.completing || !room())
        continue;
      if (!item.running) {
        if (active() >= max_active) continue;
        item.running = true;
        item.hash = std::make_unique<Hash>();
      }
      if (!live()) return;
      if (item.offset < item.size) {
        const auto count = static_cast<size_t>(std::min(
            uint64_t{protocol::FILE_CHUNK_BYTES}, item.size - item.offset));
        std::vector<uint8_t> bytes(24 + count);
        std::copy(item.uuid.begin(), item.uuid.end(), bytes.begin());
        for (unsigned n = 0; n < 8; ++n)
          bytes[16 + n] = static_cast<uint8_t>(item.offset >> (56 - 8 * n));
        if (!item.source->read(item.offset, std::span(bytes).subspan(24))) {
          cancel(id, now, true, "RD_FILE_READ_FAILED");
          continue;
        }
        if (!live()) return;
        if (!item.hash->update(std::span(bytes).subspan(24))) {
          cancel(id, now, true, "RD_FILE_HASH_FAILED");
          continue;
        }
        item.awaiting = true;
        item.awaiting_offset = item.offset + count;
        item.deadline = now + timeout_ms;
        if (!send(protocol::FILE_CHUNK, bytes)) {
          close();
          return;
        }
      } else {
        if (!item.source->unchanged()) {
          cancel(id, now, true, "RD_FILE_READ_FAILED");
          continue;
        }
        item.digest = item.hash->finish();
        if (item.digest.empty()) {
          cancel(id, now, true, "RD_FILE_HASH_FAILED");
          continue;
        }
        item.completing = true;
        item.deadline = now + timeout_ms;
        Json::Value complete;
        complete["id"] = id;
        complete["size"] = Json::UInt64(item.size);
        complete["sha256"] = item.digest;
        if (!enqueue(protocol::FILE_COMPLETE, complete)) return;
      }
    }
  }
};
FileTransfer::FileTransfer(Send send, Room room, Event event, Current current)
    : owned_access_(system_file_access()),
      impl_(std::make_unique<Impl>(*owned_access_, std::move(send),
                                   std::move(room), std::move(event),
                                   std::move(current))) {}
FileTransfer::FileTransfer(FileAccess& access, Send send, Room room,
                           Event event, Current current)
    : impl_(std::make_unique<Impl>(access, std::move(send), std::move(room),
                                   std::move(event), std::move(current))) {}
FileTransfer::~FileTransfer() { close(); }
bool FileTransfer::enabled(std::string_view permission) const {
  return !impl_->closed &&
         (permission == "files.send"      ? impl_->incoming_enabled
          : permission == "files.receive" ? impl_->outgoing_enabled
                                          : false);
}
bool FileTransfer::enable(std::string_view permission, bool value,
                          uint64_t now) {
  return impl_->enable(permission, value, now);
}
bool FileTransfer::offer_sources(
    const std::vector<std::filesystem::path>& paths, uint64_t now) {
  return impl_->offer_sources(paths, now);
}
bool FileTransfer::approve_destination(std::string_view id,
                                       const std::filesystem::path& path,
                                       uint64_t now) {
  return impl_->approve(id, path, now);
}
bool FileTransfer::cancel(std::string_view id, uint64_t now, bool notify) {
  return impl_->cancel(id, now, notify);
}
bool FileTransfer::receive(uint8_t type, std::span<const uint8_t> payload,
                           uint64_t now) {
  return impl_->receive(type, payload, now);
}
void FileTransfer::tick(uint64_t now) { impl_->tick(now); }
void FileTransfer::close() {
  if (impl_) impl_->close();
}
size_t FileTransfer::pending() const { return impl_->items.size(); }
size_t FileTransfer::active() const { return impl_->active(); }
}  // namespace ht::rd
