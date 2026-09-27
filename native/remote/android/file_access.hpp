#pragma once
#include "../webrtc/file_storage.hpp"
#include <map>

namespace ht::rd::android {
// The app lends SAF-selected source descriptors and freshly created private
// staging files. These opaque keys never name an actual filesystem path.
class DescriptorAccess : public FileAccess {
 public:
  std::filesystem::path source(int descriptor,std::string_view name);
  std::filesystem::path destination(int descriptor);
  void clear();
  std::unique_ptr<FileSource> open_source(const std::filesystem::path&,std::string& error) override;
  std::unique_ptr<FileDestination> create_destination(const std::filesystem::path&,uint64_t size,std::string& error) override;
 private:
  std::filesystem::path key();
  uint64_t next_=0;
  std::map<std::filesystem::path,std::unique_ptr<FileSource>> sources_;
  std::map<std::filesystem::path,std::unique_ptr<FileDestination>> destinations_;
};
}
