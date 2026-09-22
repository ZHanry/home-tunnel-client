#include "clipboard.hpp"
#include "../src/platform/windows_input.hpp"
#include <windows.h>
#include <algorithm>
#include <cstring>
#include <vector>

namespace ht::rd {
namespace {
class WindowsClipboard final : public ClipboardStorage {
 public:
  WindowsClipboard(){owner_=CreateWindowExW(0,L"STATIC",L"Home Tunnel clipboard owner",0,0,0,0,0,HWND_MESSAGE,nullptr,GetModuleHandleW(nullptr),nullptr);}
  ~WindowsClipboard()override{if(owner_)DestroyWindow(owner_);}
  bool available()const override{return owner_!=nullptr;}
  Read read(uint64_t& sequence,std::string& text)override{
    if(!owner_ || !WindowsInputSink::ordinary_desktop())return Read::unavailable;
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
    if(!owner_ || text.size()>protocol::CLIPBOARD_BYTES || text.find('\0')!=std::string_view::npos || !WindowsInputSink::ordinary_desktop())return false;
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
}
std::unique_ptr<ClipboardStorage> windows_clipboard(){return std::make_unique<WindowsClipboard>();}
}
