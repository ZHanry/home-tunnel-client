#include "clipboard.hpp"
#include "../src/platform/windows_input.hpp"
#include "../src/platform/windows_user.hpp"
#include <windows.h>
#include <algorithm>
#include <cstring>
#include <vector>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <future>
#include <mutex>
#include <thread>

namespace ht::rd {
namespace {
class ClipboardOnThread final : public ClipboardStorage {
 public:
  ClipboardOnThread(){owner_=CreateWindowExW(0,L"STATIC",L"Home Tunnel clipboard owner",0,0,0,0,0,HWND_MESSAGE,nullptr,GetModuleHandleW(nullptr),nullptr);}
  ~ClipboardOnThread()override{if(owner_)DestroyWindow(owner_);}
  bool available()const override{return owner_!=nullptr;}
  Read read(uint64_t& sequence,std::string& text)override{
    UserContext user;if(!owner_ || !user || !WindowsInputSink::user_broker_allowed())return Read::unavailable;
    const auto current=GetClipboardSequenceNumber();if(current && current==sequence)return Read::unchanged;
    if(!OpenClipboard(owner_))return Read::unavailable;
    struct Close {~Close(){CloseClipboard();}} close;
    if(!IsClipboardFormatAvailable(CF_UNICODETEXT)){sequence=current;return Read::no_text;}
    const auto handle=GetClipboardData(CF_UNICODETEXT);if(!handle)return Read::unavailable;
    const auto bytes=GlobalSize(handle);if(bytes<sizeof(wchar_t) || bytes>(protocol::CLIPBOARD_BYTES+1)*sizeof(wchar_t) || bytes%sizeof(wchar_t)){sequence=current;return Read::no_text;}
    const auto* data=static_cast<const wchar_t*>(GlobalLock(handle));if(!data)return Read::unavailable;
    struct Unlock {HANDLE value;~Unlock(){GlobalUnlock(value);}} unlock{handle};
    // GlobalSize bounds the locked OS allocation; constrain all iteration to it.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunsafe-buffer-usage"
    const std::span<const wchar_t> buffer(data,bytes/sizeof(wchar_t));
#pragma clang diagnostic pop
    const auto end=std::find(buffer.begin(),buffer.end(),L'\0');if(end==buffer.end()){sequence=current;return Read::no_text;}
    const auto length=static_cast<int>(end-buffer.begin());if(!length){sequence=current;text.clear();return Read::text;}
    const int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,data,length,nullptr,0,nullptr,nullptr);
    if(size<1 || size>int(protocol::CLIPBOARD_BYTES)){sequence=current;return Read::no_text;}
    text.resize(size);if(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,data,length,text.data(),size,nullptr,nullptr)!=size)return Read::unavailable;
    sequence=current;return Read::text;
  }
  bool write(std::string_view text)override{
    UserContext user;if(!owner_ || !user || text.size()>protocol::CLIPBOARD_BYTES || text.find('\0')!=std::string_view::npos || !WindowsInputSink::user_broker_allowed())return false;
    const auto length=static_cast<int>(text.size());const int count=length?MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),length,nullptr,0):0;
    if(length && count<1)return false;
    const auto handle=GlobalAlloc(GMEM_MOVEABLE|GMEM_ZEROINIT,(size_t(count)+1)*sizeof(wchar_t));if(!handle)return false;
    auto* data=static_cast<wchar_t*>(GlobalLock(handle));if(!data){GlobalFree(handle);return false;}
    const bool converted=!length || MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),length,data,count)==count;
    GlobalUnlock(handle);
    if(!converted || !OpenClipboard(owner_)){erase(handle);return false;}
    const bool stored=EmptyClipboard() && SetClipboardData(CF_UNICODETEXT,handle);CloseClipboard();if(!stored)erase(handle);return stored;
  }
 private:
  static void erase(HGLOBAL value){if(auto* data=GlobalLock(value)){SecureZeroMemory(data,GlobalSize(value));GlobalUnlock(value);}GlobalFree(value);}
  HWND owner_=nullptr;
};
// A window permanently binds its creating thread to a desktop. Keep the
// clipboard window off the signaling/input thread, which must switch to UAC.
class WindowsClipboard final : public ClipboardStorage {
 public:
  WindowsClipboard(){
    std::promise<bool> ready;auto started=ready.get_future();
    worker_=std::thread([this,ready=std::move(ready)]()mutable{
      ClipboardOnThread storage;ready.set_value(storage.available());
      for(;;){
        Job job;
        {
          std::unique_lock lock(mutex_);
          wake_.wait_for(lock,std::chrono::milliseconds(25),[this]{return stopping_ || !jobs_.empty();});
          if(stopping_)break;
          if(!jobs_.empty()){job=std::move(jobs_.front());jobs_.pop_front();}
        }
        if(job.work)job.work(storage,std::chrono::steady_clock::now()>=job.deadline);
        MSG message{};
        while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}
      }
    });
    available_=started.get();
  }
  ~WindowsClipboard()override{
    {std::lock_guard lock(mutex_);stopping_=true;jobs_.clear();}
    wake_.notify_one();
    if(worker_.joinable())worker_.join();
  }
  bool available()const override{return available_;}
  Read read(uint64_t& sequence,std::string& text)override{
    struct Result{Read state;uint64_t sequence;std::string text;};
    auto result=invoke<Result>([sequence](ClipboardOnThread& storage){
      Result result{Read::unavailable,sequence,{}};
      result.state=storage.read(result.sequence,result.text);return result;
    });
    if(!result)return Read::unavailable;
    sequence=result->sequence;text=std::move(result->text);return result->state;
  }
  bool write(std::string_view text)override{
    if(text.size()>protocol::CLIPBOARD_BYTES)return false;
    auto result=invoke<bool>([copy=std::string(text)](ClipboardOnThread& storage){return storage.write(copy);});
    return result && *result;
  }
 private:
  struct Job{std::function<void(ClipboardOnThread&,bool)> work;std::chrono::steady_clock::time_point deadline;};
  template<class T,class F>std::optional<T> invoke(F work){
    if(!available_)return {};
    auto promise=std::make_shared<std::promise<std::optional<T>>>();auto result=promise->get_future();
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(250);
    {
      std::lock_guard lock(mutex_);
      if(stopping_ || jobs_.size()>=4)return {};
      jobs_.push_back({[promise,work=std::move(work)](ClipboardOnThread& storage,bool expired){
        if(expired)promise->set_value(std::nullopt);else promise->set_value(work(storage));
      },deadline});
    }
    wake_.notify_one();
    if(result.wait_until(deadline)!=std::future_status::ready)return {};
    return result.get();
  }
  bool available_=false,stopping_=false;
  std::mutex mutex_;std::condition_variable wake_;std::deque<Job> jobs_;std::thread worker_;
};
}
std::unique_ptr<ClipboardStorage> windows_clipboard(){return std::make_unique<WindowsClipboard>();}
}
