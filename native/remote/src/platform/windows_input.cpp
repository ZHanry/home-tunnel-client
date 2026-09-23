#if defined(_WIN32)
#include "windows_input.hpp"
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <array>
#include <charconv>
#include <limits>
#include <string>
#include <vector>

namespace ht::rd {
namespace {
constexpr DWORD guard_timeout_ms=1200;
constexpr uint32_t ledger_magic=0x48545247;
struct alignas(8) InputLedger {
    uint32_t magic=ledger_magic;
    DWORD owner_pid=0;
    volatile LONG active=1;
    volatile LONG stop=0;
    alignas(8) volatile LONG64 heartbeat=0;
    std::array<LONG,232> keys{};
    std::array<LONG,5> buttons{};
    LONG unicode_pending=0;
    WORD unicode_unit=0;
};
LONG64 monotonic_ms(){return static_cast<LONG64>(GetTickCount64());}
bool lock_ledger(HANDLE mutex,DWORD timeout=50){
    const auto status=WaitForSingleObject(mutex,timeout);
    return status==WAIT_OBJECT_0 || status==WAIT_ABANDONED;
}
INPUT key_event(uint16_t usage,bool down){
    // Pause has an E1 multi-byte hardware sequence and cannot be represented
    // as a single E0 scan code. Let Windows map VK_PAUSE for this special key.
    if(usage==72){INPUT event{};event.type=INPUT_KEYBOARD;event.ki.wVk=VK_PAUSE;event.ki.dwFlags=down?0:KEYEVENTF_KEYUP;return event;}
    const auto scan=WindowsInputSink::scan_code(usage);
    INPUT event{};event.type=INPUT_KEYBOARD;event.ki.wScan=scan&0xff;
    event.ki.dwFlags=KEYEVENTF_SCANCODE | (scan>0xff ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
    return event;
}
bool key_held(uint16_t usage){
    const auto virtual_key=usage==72?UINT(VK_PAUSE):usage==70?UINT(VK_SNAPSHOT):
        MapVirtualKeyW(WindowsInputSink::scan_code(usage),MAPVK_VSC_TO_VK_EX);
    // An unknown mapping cannot safely establish ownership of the key state.
    return !virtual_key || (GetAsyncKeyState(static_cast<int>(virtual_key))&0x8000)!=0;
}
bool button_held(uint8_t button){
    constexpr std::array<int,5> keys{VK_LBUTTON,VK_RBUTTON,VK_MBUTTON,VK_XBUTTON1,VK_XBUTTON2};
    return (GetAsyncKeyState(keys[button-1])&0x8000)!=0;
}
INPUT button_event(uint8_t button,bool down){
    INPUT event{};event.type=INPUT_MOUSE;
    switch(button){
      case 1:event.mi.dwFlags=down?MOUSEEVENTF_LEFTDOWN:MOUSEEVENTF_LEFTUP;break;
      case 2:event.mi.dwFlags=down?MOUSEEVENTF_RIGHTDOWN:MOUSEEVENTF_RIGHTUP;break;
      case 3:event.mi.dwFlags=down?MOUSEEVENTF_MIDDLEDOWN:MOUSEEVENTF_MIDDLEUP;break;
      case 4:case 5:event.mi.dwFlags=down?MOUSEEVENTF_XDOWN:MOUSEEVENTF_XUP;event.mi.mouseData=button==4?XBUTTON1:XBUTTON2;break;
      default:break;
    }
    return event;
}
bool pointer_event(int64_t x,int64_t y,INPUT& event){
    const int origin_x=GetSystemMetrics(SM_XVIRTUALSCREEN),origin_y=GetSystemMetrics(SM_YVIRTUALSCREEN);
    const int width=GetSystemMetrics(SM_CXVIRTUALSCREEN),height=GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if(width<=1 || height<=1 || x<origin_x || y<origin_y || x>=int64_t(origin_x)+width || y>=int64_t(origin_y)+height)return false;
    event={};event.type=INPUT_MOUSE;
    event.mi.dx=static_cast<LONG>((x-origin_x)*65535/(width-1));event.mi.dy=static_cast<LONG>((y-origin_y)*65535/(height-1));
    event.mi.dwFlags=MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK;return true;
}
bool release_ledger(InputLedger& ledger){
    bool empty=true;
    const bool ordinary=WindowsInputSink::ordinary_desktop();
    for(uint16_t usage=0;usage<ledger.keys.size();++usage){
        if(!ledger.keys[usage])continue;
        auto event=key_event(usage,false);
        if(ordinary && WindowsInputSink::scan_code(usage) && SendInput(1,&event,sizeof(event))==1)ledger.keys[usage]=0;
        else empty=false;
    }
    for(uint8_t index=0;index<ledger.buttons.size();++index){
        if(!ledger.buttons[index])continue;
        auto event=button_event(index+1,false);
        if(ordinary && SendInput(1,&event,sizeof(event))==1)ledger.buttons[index]=0;
        else empty=false;
    }
    if(ledger.unicode_pending){
        INPUT event{};event.type=INPUT_KEYBOARD;event.ki.wScan=ledger.unicode_unit;event.ki.dwFlags=KEYEVENTF_UNICODE|KEYEVENTF_KEYUP;
        if(ordinary && SendInput(1,&event,sizeof(event))==1)ledger.unicode_pending=0;
        else empty=false;
    }
    return empty;
}
}
struct WindowsInputSink::ReleaseGuard {
    HANDLE mapping=nullptr,mutex=nullptr,ready=nullptr,parent=nullptr,process=nullptr;
    InputLedger* ledger=nullptr;
    ~ReleaseGuard(){
        if(ledger){InterlockedExchange(&ledger->active,0);InterlockedExchange(&ledger->stop,1);UnmapViewOfFile(ledger);}
        // Never kill the guard: it owns any release debt until the ordinary
        // input desktop returns, even after this worker has gone away.
        for(auto handle:{process,parent,ready,mutex,mapping})if(handle)CloseHandle(handle);
    }
    bool start(){
        SECURITY_ATTRIBUTES security{sizeof(security),nullptr,TRUE};
        mapping=CreateFileMappingW(INVALID_HANDLE_VALUE,&security,PAGE_READWRITE,0,sizeof(InputLedger),nullptr);
        mutex=CreateMutexW(&security,FALSE,nullptr);ready=CreateEventW(&security,TRUE,FALSE,nullptr);
        if(!mapping || !mutex || !ready || !DuplicateHandle(GetCurrentProcess(),GetCurrentProcess(),GetCurrentProcess(),&parent,
            SYNCHRONIZE|PROCESS_TERMINATE|PROCESS_QUERY_LIMITED_INFORMATION,TRUE,0))return false;
        ledger=static_cast<InputLedger*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputLedger)));
        if(!ledger)return false;
        new(ledger) InputLedger();ledger->owner_pid=GetCurrentProcessId();ledger->heartbeat=monotonic_ms();
        std::array<wchar_t,32768> filename{};const DWORD length=GetModuleFileNameW(nullptr,filename.data(),static_cast<DWORD>(filename.size()));
        if(!length || length>=filename.size())return false;
        std::wstring command=L"\""+std::wstring(filename.data(),length)+L"\" --input-release-guard=";
        const std::array<HANDLE,4> inherited{parent,mapping,mutex,ready};
        for(size_t n=0;n<inherited.size();++n){if(n)command+=L",";command+=std::to_wstring(reinterpret_cast<uintptr_t>(inherited[n]));}
        SIZE_T bytes=0;InitializeProcThreadAttributeList(nullptr,1,0,&bytes);if(!bytes)return false;
        std::vector<unsigned char> storage(bytes);auto* attributes=reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
        if(!InitializeProcThreadAttributeList(attributes,1,0,&bytes))return false;
        const bool listed=UpdateProcThreadAttribute(attributes,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
            const_cast<HANDLE*>(inherited.data()),sizeof(inherited),nullptr,nullptr)!=FALSE;
        STARTUPINFOEXW startup{};startup.StartupInfo.cb=sizeof(startup);startup.lpAttributeList=attributes;PROCESS_INFORMATION info{};
        const bool launched=listed && CreateProcessW(filename.data(),command.data(),nullptr,nullptr,TRUE,
            CREATE_NO_WINDOW|EXTENDED_STARTUPINFO_PRESENT,nullptr,nullptr,&startup.StartupInfo,&info)!=FALSE;
        DeleteProcThreadAttributeList(attributes);if(!launched)return false;
        process=info.hProcess;CloseHandle(info.hThread);
        if(WaitForSingleObject(ready,1000)!=WAIT_OBJECT_0 || WaitForSingleObject(process,0)!=WAIT_TIMEOUT)return false;
        InterlockedExchange64(&ledger->heartbeat,monotonic_ms());return true;
    }
    bool healthy(){
        return ledger && process && InterlockedCompareExchange(&ledger->active,0,0)==1 &&
            !InterlockedCompareExchange(&ledger->stop,0,0) && WaitForSingleObject(process,0)==WAIT_TIMEOUT;
    }
};
WindowsInputSink::WindowsInputSink(DisplayGeometry display,uint32_t target_process):display_(display),target_process_(target_process){}
WindowsInputSink::~WindowsInputSink()=default;
WindowsInputSink::WindowsInputSink(WindowsInputSink&&) noexcept=default;
WindowsInputSink& WindowsInputSink::operator=(WindowsInputSink&&) noexcept=default;
bool WindowsInputSink::ensure_guard(){
    if(guard_failed_)return false;
    if(!guard_){guard_=std::make_unique<ReleaseGuard>();if(!guard_->start())guard_failed_=true;}
    if(!guard_->healthy())guard_failed_=true;
    return !guard_failed_;
}
bool WindowsInputSink::watchdog_tick(){
    // Also guard view-only sessions: a blocked IPC writer must not let capture
    // outlive the authenticated signaling thread's lease/desktop checks.
    if(!ensure_guard())return false;
    InterlockedExchange64(&guard_->ledger->heartbeat,monotonic_ms());return true;
}
void WindowsInputSink::watchdog_stop(){
    guard_failed_=true;
    if(guard_ && guard_->ledger){InterlockedExchange(&guard_->ledger->active,0);InterlockedExchange(&guard_->ledger->stop,1);}
}
int WindowsInputSink::run_release_guard(int argc,char** argv){
#if defined(__clang__)
#pragma clang unsafe_buffer_usage begin
#endif
    if(argc!=2 || !argv || !argv[1])return -1;
    const std::string_view argument(argv[1]);constexpr std::string_view prefix="--input-release-guard=";
#if defined(__clang__)
#pragma clang unsafe_buffer_usage end
#endif
    if(!argument.starts_with(prefix))return -1;
    std::array<HANDLE,4> handles{};auto remaining=argument.substr(prefix.size());
    for(size_t n=0;n<handles.size();++n){
        const auto comma=remaining.find(',');const auto part=remaining.substr(0,comma);uintptr_t number=0;
        const auto parsed=std::from_chars(part.data(),std::to_address(part.end()),number);
        if(part.empty() || parsed.ec!=std::errc{} || parsed.ptr!=std::to_address(part.end()) || !number)return 2;
        handles[n]=reinterpret_cast<HANDLE>(number);DWORD flags=0;if(!GetHandleInformation(handles[n],&flags) || !(flags&HANDLE_FLAG_INHERIT))return 2;
        if(n+1==handles.size()){if(comma!=std::string_view::npos)return 2;}
        else {if(comma==std::string_view::npos)return 2;remaining.remove_prefix(comma+1);}
    }
    const auto parent_pid=GetProcessId(handles[0]);
    if(!parent_pid || parent_pid==GetCurrentProcessId())return 2;
    auto* ledger=static_cast<InputLedger*>(MapViewOfFile(handles[1],FILE_MAP_ALL_ACCESS,0,0,sizeof(InputLedger)));
    if(!ledger)return 2;
    if(ledger->magic!=ledger_magic || ledger->owner_pid!=parent_pid){UnmapViewOfFile(ledger);return 2;}
    InterlockedExchange64(&ledger->heartbeat,monotonic_ms());
    if(!SetEvent(handles[3])){UnmapViewOfFile(ledger);return 2;}
    for(;;){
        const auto heartbeat=InterlockedCompareExchange64(&ledger->heartbeat,0,0),now=monotonic_ms();
        const bool requested_stop=InterlockedCompareExchange(&ledger->stop,0,0)!=0;
        const bool alive=WaitForSingleObject(handles[0],0)==WAIT_TIMEOUT;
        const bool expired=now<heartbeat || now-heartbeat>=guard_timeout_ms;
        const bool stop=requested_stop || !alive || expired;
        if(stop){
            InterlockedExchange(&ledger->active,0);
            if(!requested_stop && alive && expired)(void)TerminateProcess(handles[0],23);
            // Stop and input injection serialize on an inherited mutex. A
            // crashed owner abandons it; a hung owner is terminated before
            // release, so it cannot inject another down after cleanup.
            if(!lock_ledger(handles[2],100)){
                (void)TerminateProcess(handles[0],23);
                if(!lock_ledger(handles[2],500)){Sleep(25);continue;}
            }
            const bool empty=release_ledger(*ledger);ReleaseMutex(handles[2]);
            if(empty)break;
            Sleep(25);
        }else Sleep(25);
    }
    UnmapViewOfFile(ledger);for(auto handle:handles)CloseHandle(handle);return 0;
}
uint16_t WindowsInputSink::scan_code(uint16_t usage) {
    static constexpr auto mapping = [] {
        std::array<uint16_t,232> map{};
        constexpr std::array<uint16_t,26> letters{0x1e,0x30,0x2e,0x20,0x12,0x21,0x22,0x23,0x17,0x24,0x25,0x26,0x32,0x31,0x18,0x19,0x10,0x13,0x1f,0x14,0x16,0x2f,0x11,0x2d,0x15,0x2c};
        for(size_t n=0;n<letters.size();++n) map[n+4]=letters[n];
        for(uint16_t n=0;n<10;++n) map[n+30]=n+2;
        map[40]=0x1c;map[41]=1;map[42]=0x0e;map[43]=0x0f;map[44]=0x39;
        map[45]=0x0c;map[46]=0x0d;map[47]=0x1a;map[48]=0x1b;map[49]=0x2b;
        map[51]=0x27;map[52]=0x28;map[53]=0x29;map[54]=0x33;map[55]=0x34;map[56]=0x35;map[57]=0x3a;
        for(uint16_t n=0;n<10;++n) map[n+58]=n+0x3b;
        map[68]=0x57;map[69]=0x58;map[70]=0xe037;map[71]=0x46;map[72]=0xe145;
        map[73]=0xe052;map[74]=0xe047;map[75]=0xe049;map[76]=0xe053;map[77]=0xe04f;map[78]=0xe051;
        map[79]=0xe04d;map[80]=0xe04b;map[81]=0xe050;map[82]=0xe048;
        map[83]=0x45;map[84]=0xe035;map[85]=0x37;map[86]=0x4a;map[87]=0x4e;map[88]=0xe01c;
        constexpr std::array<uint16_t,11> keypad{0x4f,0x50,0x51,0x4b,0x4c,0x4d,0x47,0x48,0x49,0x52,0x53};
        for(size_t n=0;n<keypad.size();++n) map[n+89]=keypad[n];
        map[100]=0x56;map[101]=0xe05d;
        map[224]=0x1d;map[225]=0x2a;map[226]=0x38;map[227]=0xe05b;
        map[228]=0xe01d;map[229]=0x36;map[230]=0xe038;map[231]=0xe05c;
        return map;
    }();
    return usage < mapping.size() ? mapping[usage] : 0;
}
bool WindowsInputSink::ordinary_desktop() {
    HDESK desktop=OpenInputDesktop(0,FALSE,DESKTOP_READOBJECTS);
    if(!desktop) return false;
    std::array<wchar_t,128> name{};
    DWORD needed=0;
    const bool read=GetUserObjectInformationW(desktop,UOI_NAME,name.data(),static_cast<DWORD>(name.size()*sizeof(wchar_t)),&needed)!=FALSE;
    CloseDesktop(desktop);
    return read && _wcsicmp(name.data(),L"Default")==0;
}
bool WindowsInputSink::key(uint16_t usage,bool down,bool) {
    const auto scan=scan_code(usage);
    if(scan==0 || (down && !ensure_guard()) || !guard_ || !guard_->ledger || !lock_ledger(guard_->mutex))return false;
    bool sent=false;
    if(!down && !guard_->ledger->keys[usage])sent=true;
    else if(ordinary_desktop() && (!down || (guard_->healthy() && target_focused() &&
        (guard_->ledger->keys[usage] || !key_held(usage))))){
        auto event=key_event(usage,down);
        // Persist before injection: a crash after SendInput must still be
        // observable to the guard. Never claim a key already held locally.
        const auto previous=guard_->ledger->keys[usage];
        if(down)guard_->ledger->keys[usage]=1;
        sent=SendInput(1,&event,sizeof(event))==1;
        if(down && !sent)guard_->ledger->keys[usage]=previous;
        if(!down && sent)guard_->ledger->keys[usage]=0;
    }
    ReleaseMutex(guard_->mutex);return sent;
}
bool WindowsInputSink::button(uint8_t button,bool down) {
    if(button<1 || button>5 || (down && !ensure_guard()) || !guard_ || !guard_->ledger || !lock_ledger(guard_->mutex))return false;
    bool sent=false;
    if(!down && !guard_->ledger->buttons[button-1])sent=true;
    else if(ordinary_desktop() && (!down || (guard_->healthy() && pointer_known_ && target_at_point(pointer_x_,pointer_y_) &&
        (guard_->ledger->buttons[button-1] || !button_held(button))))){
        std::array<INPUT,2> events{};events[down?1:0]=button_event(button,down);
        // MOVE completion is asynchronous. Use the button's own validated
        // coordinates in the SAME SendInput batch, rather than reading the
        // old cursor position immediately after a queued pointer event.
        if(down && !pointer_event(pointer_x_,pointer_y_,events[0])){ReleaseMutex(guard_->mutex);return false;}
        const auto previous=guard_->ledger->buttons[button-1];
        if(down)guard_->ledger->buttons[button-1]=1;
        const UINT count=down?2:1;sent=SendInput(count,events.data(),sizeof(INPUT))==count;
        if(down && !sent)guard_->ledger->buttons[button-1]=previous;
        if(!down && sent)guard_->ledger->buttons[button-1]=0;
    }
    ReleaseMutex(guard_->mutex);return sent;
}
bool WindowsInputSink::pointer(uint16_t slot,uint16_t x,uint16_t y) {
    if(slot!=display_.slot || display_.width<=0 || display_.height<=0 || !ordinary_desktop() || !target_focused() || !ensure_guard()) return false;
    const int64_t px=int64_t(display_.x)+int64_t(x)*(display_.width-1)/65535;
    const int64_t py=int64_t(display_.y)+int64_t(y)*(display_.height-1)/65535;
    INPUT event{};if(!pointer_event(px,py,event) || !target_at_point(px,py) || !lock_ledger(guard_->mutex))return false;
    const bool sent=guard_->healthy() && ordinary_desktop() && target_at_point(px,py) && SendInput(1,&event,sizeof(event))==1;
    if(sent){pointer_x_=px;pointer_y_=py;pointer_known_=true;}
    ReleaseMutex(guard_->mutex);return sent;
}
bool WindowsInputSink::target_focused() const {
    if(!target_process_)return true;
    const auto window=GetForegroundWindow();DWORD process=0;
    return window && GetWindowThreadProcessId(window,&process) && process==target_process_;
}
bool WindowsInputSink::target_at_point(int64_t x,int64_t y) const {
    if(!target_process_)return true;
    const auto window=GetForegroundWindow();RECT client{};POINT origin{};
    if(!target_focused() || !window || !GetClientRect(window,&client) || !ClientToScreen(window,&origin) ||
       x<origin.x || y<origin.y || x>=int64_t(origin.x)+client.right || y>=int64_t(origin.y)+client.bottom)return false;
    const auto hit=WindowFromPoint({static_cast<LONG>(x),static_cast<LONG>(y)});
    return hit && GetAncestor(hit,GA_ROOT)==GetAncestor(window,GA_ROOT);
}
bool WindowsInputSink::wheel(int32_t dx,int32_t dy) {
    if(!ordinary_desktop() || !target_focused() || dx < -12000 || dx>12000 || dy < -12000 || dy>12000 || !ensure_guard())return false;
    for(const auto axis:{0,1}) {
        const auto delta=axis? -dy:dx;if(!delta)continue;
        if(!lock_ledger(guard_->mutex))return false;
        std::array<INPUT,2> events{};events[1].type=INPUT_MOUSE;events[1].mi.dwFlags=axis?MOUSEEVENTF_WHEEL:MOUSEEVENTF_HWHEEL;
        events[1].mi.mouseData=static_cast<DWORD>(delta);
        const bool sent=guard_->healthy() && ordinary_desktop() && pointer_known_ && target_at_point(pointer_x_,pointer_y_) &&
            pointer_event(pointer_x_,pointer_y_,events[0]) && SendInput(2,events.data(),sizeof(INPUT))==2;
        ReleaseMutex(guard_->mutex);if(!sent)return false;
    }
    return true;
}
bool WindowsInputSink::text(std::string_view text) {
    if(text.empty() || text.size()>protocol::TEXT_BYTES || !ordinary_desktop() || !target_focused() || !ensure_guard()) return false;
    const int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
    if(size<=0) return false;
    std::vector<wchar_t> utf16(static_cast<size_t>(size));
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),utf16.data(),size)!=size) return false;
    for(const auto unit:utf16) {
        if(!lock_ledger(guard_->mutex))return false;
        if(!guard_->healthy() || !ordinary_desktop() || !target_focused()) {ReleaseMutex(guard_->mutex);return false;}
        std::array<INPUT,2> pair{};
        pair[0].type=pair[1].type=INPUT_KEYBOARD;
        pair[0].ki.wScan=pair[1].ki.wScan=static_cast<WORD>(unit);
        pair[0].ki.dwFlags=KEYEVENTF_UNICODE;pair[1].ki.dwFlags=KEYEVENTF_UNICODE|KEYEVENTF_KEYUP;
        guard_->ledger->unicode_unit=static_cast<WORD>(unit);guard_->ledger->unicode_pending=1;
        const auto sent=SendInput(2,pair.data(),sizeof(INPUT));
        if(sent==0 || sent==2 || (sent==1 && SendInput(1,&pair[1],sizeof(INPUT))==1))guard_->ledger->unicode_pending=0;
        ReleaseMutex(guard_->mutex);if(sent!=2)return false;
    }
    return true;
}
}
#endif
