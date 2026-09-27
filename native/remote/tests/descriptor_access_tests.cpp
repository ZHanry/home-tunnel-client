#include "../android/file_access.hpp"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(value) do {if(!(value)){std::fprintf(stderr,"line %d: %s\n",__LINE__,#value);std::abort();}} while(false)
using namespace ht::rd;
struct TempFile {
  std::string path;int descriptor=-1;
  TempFile(){
    std::string pattern=(std::filesystem::temp_directory_path()/"ht-descriptor-XXXXXX").string();
    descriptor=mkstemp(pattern.data());CHECK(descriptor>=0);path=pattern;
  }
  ~TempFile(){close(descriptor);unlink(path.c_str());}
  uint64_t size(){struct stat state{};CHECK(fstat(descriptor,&state)==0);return static_cast<uint64_t>(state.st_size);}
};
int main(){
  android::DescriptorAccess access;TempFile input;std::string error;
  CHECK(write(input.descriptor,"payload",7)==7);
  CHECK(access.source(-1,"test.txt").empty());
  CHECK(access.source(input.descriptor,"../escape.txt").empty());
  CHECK(access.source(input.descriptor,"CON.txt").empty());
  int pipes[2]{};CHECK(pipe(pipes)==0);CHECK(access.source(pipes[0],"pipe.txt").empty());close(pipes[0]);close(pipes[1]);
  const auto source_key=access.source(input.descriptor,"file.txt");CHECK(!source_key.empty());
  CHECK(!access.open_source("an-arbitrary-path",error));
  auto source=access.open_source(source_key,error);CHECK(source && source->size()==7);
  CHECK(!access.open_source(source_key,error));
  std::array<uint8_t,7> bytes{};CHECK(source->read(0,bytes));CHECK(std::string(bytes.begin(),bytes.end())=="payload");
  CHECK(!source->read(1,bytes));CHECK(pwrite(input.descriptor,"P",1,0)==1);CHECK(!source->unchanged());CHECK(!source->read(0,bytes));
  CHECK(access.destination(input.descriptor).empty());CHECK(input.size()==7);
  TempFile target;CHECK(fchmod(target.descriptor,0644)==0);CHECK(access.destination(target.descriptor).empty());CHECK(fchmod(target.descriptor,0600)==0);
  const auto alias=target.path+"-alias";CHECK(link(target.path.c_str(),alias.c_str())==0);CHECK(access.destination(target.descriptor).empty());CHECK(unlink(alias.c_str())==0);
  auto token=access.destination(target.descriptor);CHECK(!token.empty());
  auto destination=access.create_destination(token,7,error);CHECK(destination);CHECK(!access.create_destination(token,7,error));
  CHECK(!destination->write(1,bytes));CHECK(destination->write(0,bytes));CHECK(target.size()==7);
  destination->abort();CHECK(target.size()==0);destination.reset();
  token=access.destination(target.descriptor);destination=access.create_destination(token,7,error);CHECK(destination);
  std::filesystem::path published;CHECK(!destination->commit(published));CHECK(destination->write(0,bytes));CHECK(destination->commit(published));
  CHECK(published.empty());destination->abort();destination.reset();CHECK(target.size()==7);
  TempFile empty;token=access.destination(empty.descriptor);destination=access.create_destination(token,0,error);CHECK(destination && destination->commit(published));
  destination.reset();CHECK(empty.size()==0);
  token=access.source(empty.descriptor,"empty.txt");source=access.open_source(token,error);CHECK(source && source->size()==0 && source->read(0,{}));
  CHECK(access.destination(target.descriptor).empty());CHECK(target.size()==7);
  access.clear();
}
