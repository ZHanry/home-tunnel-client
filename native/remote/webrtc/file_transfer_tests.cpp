#include "file_transfer.hpp"
#include "json/reader.h"
#include "json/writer.h"
#include <algorithm>
#include <cstdlib>
#include <deque>
#include <cstring>
#include <fstream>
#include <iostream>
#include <set>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winioctl.h>
#endif

using namespace ht::rd;
namespace {
#define REQUIRE(condition)                                                     \
  do {                                                                         \
    if (!(condition)) {                                                        \
      std::cerr << __FILE__ << ":" << __LINE__ << " failed: " #condition "\n"; \
      std::abort();                                                            \
    }                                                                          \
  } while (false)
const std::string id = "f0000000-0000-4000-8000-000000000001";
const std::string empty_hash =
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
const std::string abc_hash =
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
#if defined(_WIN32)
// Junction creation does not require the symbolic-link privilege. Exercise a
// real directory reparse point even under a standard Windows user account.
void junction(const std::filesystem::path& link,
              const std::filesystem::path& target) {
  REQUIRE(CreateDirectoryW(link.c_str(), nullptr));
  const auto substitute = L"\\??\\" + target.wstring(),
             printable = target.wstring();
  struct Header {
    ULONG tag;
    USHORT length, reserved, sub_offset, sub_length, print_offset, print_length;
  };
  const auto data_bytes =
      (substitute.size() + 1 + printable.size() + 1) * sizeof(wchar_t);
  std::vector<uint8_t> buffer(sizeof(Header) + data_bytes, 0);
  auto* header = reinterpret_cast<Header*>(buffer.data());
  header->tag = IO_REPARSE_TAG_MOUNT_POINT;
  header->length = static_cast<USHORT>(8 + data_bytes);
  header->sub_length = static_cast<USHORT>(substitute.size() * sizeof(wchar_t));
  header->print_offset =
      static_cast<USHORT>((substitute.size() + 1) * sizeof(wchar_t));
  header->print_length =
      static_cast<USHORT>(printable.size() * sizeof(wchar_t));
  std::memcpy(buffer.data() + sizeof(Header), substitute.data(),
              header->sub_length);
  std::memcpy(buffer.data() + sizeof(Header) + header->print_offset,
              printable.data(), header->print_length);
  HANDLE handle = CreateFileW(
      link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  REQUIRE(handle != INVALID_HANDLE_VALUE);
  DWORD count = 0;
  const auto ok = DeviceIoControl(
      handle, FSCTL_SET_REPARSE_POINT, buffer.data(),
      static_cast<DWORD>(buffer.size()), nullptr, 0, &count, nullptr);
  CloseHandle(handle);
  REQUIRE(ok);
}
#endif
Json::Value body(std::string_view text) {
  Json::CharReaderBuilder b;
  std::unique_ptr<Json::CharReader> reader(b.newCharReader());
  Json::Value result;
  std::string error;
  REQUIRE(
      reader->parse(text.data(), text.data() + text.size(), &result, &error));
  return result;
}
std::string json(const Json::Value& value) {
  Json::StreamWriterBuilder b;
  b["indentation"] = "";
  return Json::writeString(b, value);
}
std::string read(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input.good()) std::cerr << "Cannot read " << path << "\n";
  REQUIRE(input.good());
  return {std::istreambuf_iterator<char>(input), {}};
}
void write(const std::filesystem::path& path, std::string_view bytes) {
  std::ofstream output(path, std::ios::binary);
  REQUIRE(output.good());
  output.write(bytes.data(), bytes.size());
  REQUIRE(output.good());
}
struct Temp {
  std::filesystem::path path;
  Temp() {
    for (unsigned n = 0; n < 1000; ++n) {
      path = std::filesystem::temp_directory_path() /
             ("ht-file-transfer-test-" + std::to_string(std::rand()) + "-" +
              std::to_string(n));
      std::error_code error;
      if (std::filesystem::create_directory(path, error)) return;
    }
    REQUIRE(false);
  }
  ~Temp() {
    std::error_code ignored;
    std::filesystem::remove_all(path, ignored);
  }
  size_t entries() const {
    return std::distance(std::filesystem::directory_iterator(path),
                         std::filesystem::directory_iterator{});
  }
};
struct Message {
  uint8_t type;
  std::vector<uint8_t> payload;
  Json::Value value() const {
    return body(std::string_view(reinterpret_cast<const char*>(payload.data()),
                                 payload.size()));
  }
};
struct Harness {
  std::deque<Message> frames;
  std::vector<Json::Value> events;
  bool room = true, current = true, send_ok = true;
  uint64_t now = 100;
  std::unique_ptr<FileTransfer> transfer;
  explicit Harness(FileAccess* access = nullptr) {
    const auto send = [&](uint8_t type, std::span<const uint8_t> bytes) {
      if (!send_ok) return false;
      frames.push_back({type, {bytes.begin(), bytes.end()}});
      return true;
    };
    const auto available = [&] { return room; };
    const auto event = [&](const Json::Value& value) {
      events.push_back(value);
    };
    const auto live = [&] { return current; };
    transfer =
        access ? std::make_unique<FileTransfer>(*access, send, available, event,
                                                live)
               : std::make_unique<FileTransfer>(send, available, event, live);
  }
  void enable() {
    REQUIRE(transfer->enable("files.send", true, now));
    REQUIRE(transfer->enable("files.receive", true, now));
  }
  bool receive(uint8_t type, const Json::Value& value) {
    const auto bytes = json(value);
    return transfer->receive(
        type, {reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()},
        now);
  }
  bool offer(uint64_t size = 3, std::string transfer_id = id,
             std::string name = "peer.bin") {
    Json::Value value;
    value["id"] = transfer_id;
    value["name"] = name;
    value["size"] = Json::UInt64(size);
    return receive(protocol::FILE_OFFER, value);
  }
  bool complete(uint64_t size = 3, std::string hash = abc_hash,
                std::string transfer_id = id) {
    Json::Value value;
    value["id"] = transfer_id;
    value["size"] = Json::UInt64(size);
    value["sha256"] = hash;
    return receive(protocol::FILE_COMPLETE, value);
  }
  bool chunk(std::string_view bytes, uint64_t offset = 0,
             std::string transfer_id = id) {
    std::vector<uint8_t> value(24 + bytes.size());
    size_t n = 0;
    for (size_t at = 0; at < transfer_id.size();) {
      if (transfer_id[at] == '-') {
        ++at;
        continue;
      }
      value[n++] = static_cast<uint8_t>(
          std::stoul(transfer_id.substr(at, 2), nullptr, 16));
      at += 2;
    }
    for (unsigned i = 0; i < 8; ++i)
      value[16 + i] = static_cast<uint8_t>(offset >> (56 - 8 * i));
    std::copy(bytes.begin(), bytes.end(), value.begin() + 24);
    return transfer->receive(protocol::FILE_CHUNK, value, now);
  }
  void tick() { transfer->tick(now++); }
  size_t count(uint8_t type) const {
    return std::count_if(frames.begin(), frames.end(),
                         [&](const auto& frame) { return frame.type == type; });
  }
  bool event(std::string_view code) const {
    return std::any_of(events.begin(), events.end(), [&](const auto& event) {
      return event["error_code"] == code;
    });
  }
};
void deliver(Harness& from, Harness& to) {
  while (!from.frames.empty()) {
    auto message = std::move(from.frames.front());
    from.frames.pop_front();
    REQUIRE(to.transfer->receive(message.type, message.payload, to.now));
  }
}
void consent_integrity_collision() {
  Temp directory;
  Harness h;
  REQUIRE(h.offer());
  REQUIRE(h.transfer->pending() == 0);
  REQUIRE(!h.transfer->approve_destination(id, directory.path / "saved.bin",
                                           h.now));
  h.enable();
  REQUIRE(h.offer());
  REQUIRE(directory.entries() == 0);
  REQUIRE(!h.chunk("abc"));
  REQUIRE(!h.transfer->approve_destination(id, "relative.bin", h.now));
  REQUIRE(h.event("RD_FILE_PATH_INVALID"));
  REQUIRE(directory.entries() == 0);
  Harness good;
  good.enable();
  REQUIRE(good.offer());
  write(directory.path / "saved.bin", "existing-user-data");
  REQUIRE(good.transfer->approve_destination(id, directory.path / "saved.bin",
                                             good.now));
  REQUIRE(directory.entries() == 2);
  good.tick();
  REQUIRE(!good.chunk("abc", 1));
  REQUIRE(!good.chunk("abc", uint64_t{1} << 32));
  REQUIRE(good.chunk("abc"));
  REQUIRE(!good.complete());  // One chunk ACK must leave the receiver before
                              // completion.
  good.tick();
  REQUIRE(good.frames.back().value()["offset"] == 3);
  REQUIRE(good.complete());
  good.tick();
  REQUIRE(read(directory.path / "saved.bin") == "existing-user-data");
  REQUIRE(read(directory.path / "saved (1).bin") == "abc");
  REQUIRE(directory.entries() == 2);
  REQUIRE(good.frames.back().type == protocol::FILE_ACK);
  REQUIRE(good.frames.back().value()["sha256"] == abc_hash);
  REQUIRE(good.events.back()["name"] == "saved (1).bin");
  REQUIRE(!good.events.back().isMember("path"));
  REQUIRE(good.transfer->cancel(id, good.now));
  REQUIRE(read(directory.path / "saved (1).bin") == "abc");
}
void real_bidirectional_batch() {
  Temp source, destination;
  std::string content(65539, '\0');
  for (size_t n = 0; n < content.size(); ++n)
    content[n] = static_cast<char>(n % 251);
  write(source.path / "one.bin", content);
  write(source.path / "two.bin", "");
  write(source.path / "three.bin", "abc");
  Harness sender, receiver;
  sender.enable();
  receiver.enable();
  sender.room = false;
  REQUIRE(sender.transfer->offer_sources(
      {source.path / "one.bin", source.path / "two.bin",
       source.path / "three.bin"},
      sender.now));
  REQUIRE(sender.frames.empty());
  sender.room = true;
  sender.tick();
  deliver(sender, receiver);
  REQUIRE(receiver.events.size() == 3);
  REQUIRE(destination.entries() == 0);
  std::vector<std::string> ids;
  for (const auto& event : receiver.events)
    ids.push_back(event["id"].asString());
  REQUIRE(receiver.transfer->approve_destination(
      ids[0], destination.path / "selected.bin", receiver.now));
  REQUIRE(receiver.transfer->approve_destination(
      ids[1], destination.path / "selected.bin", receiver.now));
  REQUIRE(!receiver.transfer->approve_destination(
      ids[2], destination.path / "selected.bin", receiver.now));
  bool third = false;
  for (unsigned pass = 0; pass < 100 && (sender.transfer->pending() ||
                                         receiver.transfer->pending());
       ++pass) {
    receiver.tick();
    deliver(receiver, sender);
    sender.tick();
    REQUIRE(sender.transfer->active() <= 2);
    deliver(sender, receiver);
    if (!third && receiver.transfer->active() < 2) {
      third = receiver.transfer->approve_destination(
          ids[2], destination.path / "selected.bin", receiver.now);
    }
  }
  REQUIRE(third);
  REQUIRE(sender.transfer->pending() == 0);
  REQUIRE(receiver.transfer->pending() == 0);
  REQUIRE(destination.entries() == 3);
  std::multiset<std::string> contents;
  for (const auto& entry :
       std::filesystem::directory_iterator(destination.path))
    contents.insert(read(entry.path()));
  REQUIRE(contents == std::multiset<std::string>({content, "", "abc"}));
  REQUIRE(std::count_if(sender.events.begin(), sender.events.end(),
                        [](const auto& event) {
                          return event["event"] == "complete";
                        }) == 3);
  // Opposite direction uses the other permission on the same live instances.
  REQUIRE(receiver.transfer->offer_sources({destination.path / "selected.bin"},
                                           receiver.now));
  deliver(receiver, sender);
  const auto incoming = sender.events.back()["id"].asString();
  REQUIRE(sender.transfer->approve_destination(
      incoming, source.path / "return.bin", sender.now));
  for (unsigned pass = 0; pass < 100 && (sender.transfer->pending() ||
                                         receiver.transfer->pending());
       ++pass) {
    sender.tick();
    deliver(sender, receiver);
    receiver.tick();
    deliver(receiver, sender);
  }
  REQUIRE(read(source.path / "return.bin") ==
          read(destination.path / "selected.bin"));
}
void cancellation_hash_disconnect_timeout() {
  for (unsigned scenario = 0; scenario < 6; ++scenario) {
    Temp directory;
    Harness h;
    h.enable();
    REQUIRE(h.offer());
    REQUIRE(h.transfer->approve_destination(id, directory.path / "target.bin",
                                            h.now));
    h.tick();
    REQUIRE(h.chunk("abc"));
    h.tick();
    h.frames.clear();
    if (scenario == 0) REQUIRE(h.complete(3, std::string(64, '0')));
    if (scenario == 1) REQUIRE(h.transfer->cancel(id, h.now));
    if (scenario == 2) h.transfer->close();
    if (scenario == 3) {
      h.now += 30000;
      h.tick();
    }
    if (scenario == 4) REQUIRE(h.transfer->enable("files.send", false, h.now));
    if (scenario == 5) {
      h.current = false;
      h.tick();
    }
    h.tick();
    REQUIRE(directory.entries() == 0);
    REQUIRE(h.transfer->pending() == 0);
    REQUIRE(h.count(protocol::FILE_ACK) == 0);
  }
  Temp directory;
  Harness h;
  h.enable();
  REQUIRE(h.offer(0));
  REQUIRE(
      h.transfer->approve_destination(id, directory.path / "empty.bin", h.now));
  h.tick();
  h.frames.clear();
  REQUIRE(h.complete(0, empty_hash));
  REQUIRE(h.transfer->enable("files.send", false, h.now));
  h.tick();
  REQUIRE(h.count(protocol::FILE_ACK) == 0);
  REQUIRE(read(directory.path / "empty.bin").empty());
}
class FaultDestination final : public FileDestination {
 public:
  std::unique_ptr<FileDestination> real;
  bool write_fails = false, commit_fails = false;
  bool* revoke = nullptr;
  bool* revoke_commit = nullptr;
  bool write(uint64_t offset, std::span<const uint8_t> bytes) override {
    if (write_fails) return false;
    const auto result = real->write(offset, bytes);
    if (revoke) *revoke = false;
    return result;
  }
  bool commit(std::filesystem::path& path) override {
    const auto result = !commit_fails && real->commit(path);
    if (revoke_commit) *revoke_commit = false;
    return result;
  }
  void abort() noexcept override { real->abort(); }
};
class FaultAccess final : public FileAccess {
 public:
  std::unique_ptr<FileAccess> real = system_file_access();
  bool write_fails = false, commit_fails = false, no_space = false;
  bool* revoke = nullptr;
  bool* revoke_commit = nullptr;
  std::unique_ptr<FileSource> open_source(const std::filesystem::path& path,
                                          std::string& error) override {
    return real->open_source(path, error);
  }
  std::unique_ptr<FileDestination> create_destination(
      const std::filesystem::path& path, uint64_t size,
      std::string& error) override {
    if (no_space) {
      error = "RD_FILE_NO_SPACE";
      return {};
    }
    auto destination = real->create_destination(path, size, error);
    if (!destination) return {};
    auto result = std::make_unique<FaultDestination>();
    result->real = std::move(destination);
    result->write_fails = write_fails;
    result->commit_fails = commit_fails;
    result->revoke = revoke;
    result->revoke_commit = revoke_commit;
    return result;
  }
};
void disk_failures_never_ack_success() {
  for (unsigned scenario = 0; scenario < 5; ++scenario) {
    Temp directory;
    FaultAccess access;
    Harness h(&access);
    h.enable();
    access.write_fails = scenario == 0;
    access.commit_fails = scenario == 1;
    access.no_space = scenario == 2;
    if (scenario == 3) access.revoke = &h.current;
    if (scenario == 4) access.revoke_commit = &h.current;
    REQUIRE(h.offer());
    const auto approved =
        h.transfer->approve_destination(id, directory.path / "out.bin", h.now);
    if (scenario == 2) {
      REQUIRE(!approved);
      REQUIRE(h.event("RD_FILE_NO_SPACE"));
    } else {
      REQUIRE(approved);
      h.tick();
      h.frames.clear();
      const auto received = h.chunk("abc");
      REQUIRE(received == (scenario != 3));
      h.tick();
      if (scenario == 1) {
        h.frames.clear();
        REQUIRE(h.complete());
        h.tick();
        REQUIRE(h.event("RD_FILE_WRITE_FAILED"));
        REQUIRE(h.events.back()["may_be_saved"].asBool());
      }
      if (scenario == 4) {
        h.frames.clear();
        REQUIRE(!h.complete());
        h.tick();
        REQUIRE(read(directory.path / "out.bin") == "abc");
      }
    }
    REQUIRE(h.count(protocol::FILE_ACK) == 0);
    REQUIRE(directory.entries() == (scenario == 4 ? 1u : 0u));
    REQUIRE(h.transfer->pending() == 0);
  }
}
void limits_names_and_stream_backpressure() {
  for (const auto name : {"../bad", "C:bad", "CON", "nul.txt", "name.", "name ",
                          "a/b", "a\\b", "a\nb"})
    REQUIRE(!file_name_allowed(name));
  REQUIRE(!file_name_allowed(std::string("a\0b", 3)));
  REQUIRE(file_name_allowed("中文.bin"));
  std::string chinese, emoji;
  for (unsigned n = 0; n < 200; ++n) chinese += "文";
  for (unsigned n = 0; n < 128; ++n) emoji += "😀";
  REQUIRE(file_name_allowed(chinese));
  REQUIRE(!file_name_allowed(emoji));
  Harness h;
  h.enable();
  REQUIRE(!h.offer(protocol::FILE_BYTES + 1));
  REQUIRE(h.offer(protocol::FILE_BYTES));
  REQUIRE(!h.offer(1));  // Reused transfer identity.
  for (unsigned n = 1; n < 4; ++n) {
    auto transfer_id = id;
    transfer_id.back() = static_cast<char>('1' + n);
    REQUIRE(h.offer(protocol::FILE_BYTES, transfer_id));
  }
  auto fifth = id;
  fifth.back() = '5';
  REQUIRE(!h.offer(1, fifth));
  Harness many;
  many.enable();
  for (unsigned n = 1; n <= 65; ++n) {
    const auto suffix = std::to_string(n);
    const auto transfer_id =
        id.substr(0, 24) + std::string(12 - suffix.size(), '0') + suffix;
    REQUIRE(many.offer(0, transfer_id) == (n <= 64));
  }
  REQUIRE(many.transfer->pending() == 64);
  Harness malformed;
  malformed.enable();
  const auto duplicate = std::string("{\"id\":\"") + id +
                         "\",\"name\":\"a\",\"size\":0,\"size\":1}";
  REQUIRE(!malformed.transfer->receive(
      protocol::FILE_OFFER,
      {reinterpret_cast<const uint8_t*>(duplicate.data()), duplicate.size()},
      100));
  Temp directory;
  write(directory.path / "data.bin", std::string(50000, 'x'));
  Harness sender;
  sender.enable();
  REQUIRE(sender.transfer->offer_sources({directory.path / "data.bin"},
                                         sender.now));
  const auto transfer_id = sender.frames.front().value()["id"].asString();
  sender.frames.clear();
  Json::Value accept;
  accept["id"] = transfer_id;
  REQUIRE(sender.receive(protocol::FILE_ACCEPT, accept));
  sender.tick();
  REQUIRE(sender.count(protocol::FILE_CHUNK) == 1);
  sender.tick();
  REQUIRE(sender.count(protocol::FILE_CHUNK) == 1);
  Json::Value ack;
  ack["id"] = transfer_id;
  ack["offset"] = Json::UInt64(16385);
  REQUIRE(!sender.receive(protocol::FILE_ACK, ack));
  ack["offset"] = Json::UInt64(16384);
  REQUIRE(sender.receive(protocol::FILE_ACK, ack));
  sender.room = false;
  sender.tick();
  REQUIRE(sender.count(protocol::FILE_CHUNK) == 1);
  sender.room = true;
  sender.tick();
  REQUIRE(sender.count(protocol::FILE_CHUNK) == 2);
  REQUIRE(sender.transfer->cancel(transfer_id, sender.now));
  sender.tick();
  REQUIRE(sender.count(protocol::FILE_COMPLETE) == 0);
}
void local_handle_boundaries_and_large_offsets() {
  Temp directory;
  auto access = system_file_access();
  std::string error;
  write(directory.path / "source.bin", "original");
  auto source = access->open_source(directory.path / "source.bin", error);
  REQUIRE(source);
  std::array<uint8_t, 3> bytes{};
  REQUIRE(source->read(2, bytes));
  REQUIRE(std::string(bytes.begin(), bytes.end()) == "igi");
  REQUIRE(!access->open_source(directory.path / "." / "source.bin", error));
  REQUIRE(!access->create_destination(directory.path / ".." / "escape.bin", 3,
                                      error));
#if defined(_WIN32)
  HANDLE changed =
      CreateFileW((directory.path / "source.bin").c_str(), GENERIC_WRITE,
                  FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  REQUIRE(changed == INVALID_HANDLE_VALUE);
  const auto large = directory.path / "large.bin";
  HANDLE file = CreateFileW(large.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_NEW, 0, nullptr);
  REQUIRE(file != INVALID_HANDLE_VALUE);
  DWORD ignored = 0;
  REQUIRE(DeviceIoControl(file, FSCTL_SET_SPARSE, nullptr, 0, nullptr, 0,
                          &ignored, nullptr));
  LARGE_INTEGER position{};
  position.QuadPart = (uint64_t{1} << 32) + 123;
  REQUIRE(SetFilePointerEx(file, position, nullptr, FILE_BEGIN));
  REQUIRE(WriteFile(file, "xyz", 3, &ignored, nullptr) && ignored == 3);
  CloseHandle(file);
#else
  write(directory.path / "source.bin", "changed");
  REQUIRE(!source->unchanged());
  const auto large = directory.path / "large.bin";
  std::ofstream file(large, std::ios::binary);
  file.seekp((uint64_t{1} << 32) + 123);
  file.write("xyz", 3);
  file.close();
#endif
  auto large_source = access->open_source(large, error);
  REQUIRE(large_source);
  REQUIRE(large_source->size() == (uint64_t{1} << 32) + 126);
  REQUIRE(large_source->read((uint64_t{1} << 32) + 123, bytes));
  REQUIRE(std::string(bytes.begin(), bytes.end()) == "xyz");
#if defined(_WIN32)
  junction(directory.path / "linked", directory.path);
  REQUIRE(
      !access->open_source(directory.path / "linked" / "source.bin", error));
  REQUIRE(!access->create_destination(directory.path / "linked" / "out.bin", 3,
                                      error));
  REQUIRE(RemoveDirectoryW((directory.path / "linked").c_str()));
#else
  std::error_code link_error;
  std::filesystem::create_directory_symlink(
      directory.path, directory.path / "linked", link_error);
  if (!link_error) {
    REQUIRE(
        !access->open_source(directory.path / "linked" / "source.bin", error));
    REQUIRE(!access->create_destination(directory.path / "linked" / "out.bin",
                                        3, error));
  } else
    std::cout << "NOTE: directory symlink test unavailable on this account\n";
#endif
}
}  // namespace
int main() {
  consent_integrity_collision();
  real_bidirectional_batch();
  cancellation_hash_disconnect_timeout();
  disk_failures_never_ack_success();
  limits_names_and_stream_backpressure();
  local_handle_boundaries_and_large_offsets();
  std::cout
      << "File transfer: consent, real files, both directions, batch, SHA256, "
         "cancellation, IO errors, backpressure and 64-bit offsets passed\n";
}
