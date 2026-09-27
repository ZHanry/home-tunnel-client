#include "file_access.hpp"
#include "../generated/remote_protocol.hpp"
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace ht::rd::android {
namespace {
struct Descriptor {
  int value=-1;
  explicit Descriptor(int fd):value(fd<0?-1:fcntl(fd,F_DUPFD_CLOEXEC,0)){}
  ~Descriptor(){if(value>=0)close(value);}
  Descriptor(const Descriptor&)=delete;
};
bool regular(int fd,struct stat& state){return fd>=0 && fstat(fd,&state)==0 && S_ISREG(state.st_mode) && state.st_size>=0;}
bool same(const struct stat& a,const struct stat& b){
  return a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_size==b.st_size &&
    a.st_mtim.tv_sec==b.st_mtim.tv_sec && a.st_mtim.tv_nsec==b.st_mtim.tv_nsec &&
    a.st_ctim.tv_sec==b.st_ctim.tv_sec && a.st_ctim.tv_nsec==b.st_ctim.tv_nsec;
}
class Source : public FileSource {
 public:
  Source(int fd,std::string_view name):descriptor_(fd),name_(name){
    const auto flags=descriptor_.value<0?-1:fcntl(descriptor_.value,F_GETFL);
    valid_=flags>=0 && (flags&O_ACCMODE)!=O_WRONLY && regular(descriptor_.value,state_) &&
      static_cast<uint64_t>(state_.st_size)<=protocol::FILE_BYTES;
  }
  bool valid() const {return valid_;}
  uint64_t size()const override{return static_cast<uint64_t>(state_.st_size);}
  std::string name()const override{return name_;}
  bool unchanged()const override{struct stat current{};return valid_ && regular(descriptor_.value,current) && same(state_,current);}
  bool read(uint64_t offset,std::span<uint8_t> bytes)override{
    if(!unchanged() || offset>size() || bytes.size()>size()-offset)return false;
    while(!bytes.empty()){
      const auto count=pread(descriptor_.value,bytes.data(),bytes.size(),static_cast<off_t>(offset));
      if(count<0 && errno==EINTR)continue;
      if(count<=0)return false;
      bytes=bytes.subspan(static_cast<size_t>(count));offset+=static_cast<uint64_t>(count);
    }
    return unchanged();
  }
 private:
  Descriptor descriptor_;std::string name_;struct stat state_{};bool valid_=false;
};
class Destination : public FileDestination {
 public:
  explicit Destination(int fd):descriptor_(fd){
    const auto flags=descriptor_.value<0?-1:fcntl(descriptor_.value,F_GETFL);struct stat state{};
    // Never truncate or write directly into a selected existing document.
    // The consumer must provide its own empty, private staging file.
    valid_=flags>=0 && (flags&O_ACCMODE)!=O_RDONLY && !(flags&O_APPEND) &&
      regular(descriptor_.value,state) && state.st_size==0 && state.st_uid==geteuid() &&
      !(state.st_mode&0077) && state.st_nlink<=1;
  }
  ~Destination()override{abort();}
  bool valid()const{return valid_;}
  void expect(uint64_t size){size_=size;}
  bool write(uint64_t offset,std::span<const uint8_t> bytes)override{
    if(!valid_ || committed_ || offset!=written_ || offset>size_ || bytes.size()>size_-offset)return false;
    while(!bytes.empty()){
      const auto count=pwrite(descriptor_.value,bytes.data(),bytes.size(),static_cast<off_t>(written_));
      if(count<0 && errno==EINTR)continue;
      if(count<=0)return false;
      bytes=bytes.subspan(static_cast<size_t>(count));written_+=static_cast<uint64_t>(count);
    }
    return fsync(descriptor_.value)==0;
  }
  bool commit(std::filesystem::path& actual)override{
    struct stat state{};
    if(!valid_ || committed_ || written_!=size_ || !regular(descriptor_.value,state) ||
       static_cast<uint64_t>(state.st_size)!=size_ || fsync(descriptor_.value)!=0)return false;
    committed_=true;actual.clear();return true;
  }
  void abort()noexcept override{
    if(valid_ && !committed_){const auto truncated=ftruncate(descriptor_.value,0);(void)truncated;valid_=false;}
  }
 private:
  Descriptor descriptor_;uint64_t size_=0,written_=0;bool valid_=false,committed_=false;
};
}
std::filesystem::path DescriptorAccess::key(){return std::filesystem::path("descriptor-"+std::to_string(++next_));}
std::filesystem::path DescriptorAccess::source(int fd,std::string_view name){
  if(sources_.size()>=protocol::BATCH_FILES || !file_name_allowed(name))return {};
  auto value=std::make_unique<Source>(fd,name);if(!value->valid())return {};
  const auto token=key();sources_.emplace(token,std::move(value));return token;
}
std::filesystem::path DescriptorAccess::destination(int fd){
  if(destinations_.size()>=protocol::BATCH_FILES)return {};
  auto value=std::make_unique<Destination>(fd);if(!value->valid())return {};
  const auto token=key();destinations_.emplace(token,std::move(value));return token;
}
std::unique_ptr<FileSource> DescriptorAccess::open_source(const std::filesystem::path& token,std::string& error){
  auto entry=sources_.extract(token);if(entry.empty()){error="RD_FILE_READ_FAILED";return nullptr;}
  return std::move(entry.mapped());
}
std::unique_ptr<FileDestination> DescriptorAccess::create_destination(const std::filesystem::path& token,uint64_t size,std::string& error){
  auto entry=destinations_.extract(token);if(entry.empty() || size>protocol::FILE_BYTES){error="RD_FILE_WRITE_FAILED";return nullptr;}
  static_cast<Destination*>(entry.mapped().get())->expect(size);return std::move(entry.mapped());
}
void DescriptorAccess::clear(){sources_.clear();destinations_.clear();}
}
