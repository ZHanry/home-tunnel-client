#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "../src/platform/windows_input.hpp"
#include <array>
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>

namespace {
bool fixture(std::wstring_view mode,DWORD expected){
    std::array<wchar_t,32768> filename{};
    const auto length=GetModuleFileNameW(nullptr,filename.data(),static_cast<DWORD>(filename.size()));
    if(!length || length>=filename.size())return false;
    std::wstring command=L"\""+std::wstring(filename.data(),length)+L"\" "+std::wstring(mode);
    STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION process{};
    if(!CreateProcessW(filename.data(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process))return false;
    CloseHandle(process.hThread);
    const auto status=WaitForSingleObject(process.hProcess,7000);
    if(status!=WAIT_OBJECT_0){(void)TerminateProcess(process.hProcess,24);WaitForSingleObject(process.hProcess,1000);}
    DWORD code=0;const bool success=status==WAIT_OBJECT_0 && GetExitCodeProcess(process.hProcess,&code) && code==expected;
    CloseHandle(process.hProcess);return success;
}
bool held(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
bool pump_until(const std::function<bool()>& ready,DWORD timeout=500){
    const auto until=GetTickCount64()+timeout;
    do {
        MSG message{};
        while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}
        if(ready())return true;
        Sleep(5);
    }while(GetTickCount64()<until);
    return false;
}
struct InputWindow {
    HWND window=nullptr,previous=GetForegroundWindow();POINT previous_cursor{};
    unsigned key_down=0,key_up=0,button_down=0,button_up=0;
    bool local_key=false,local_button=false;
    static LRESULT CALLBACK events(HWND window,UINT message,WPARAM key,LPARAM argument){
        if(message==WM_NCCREATE){
            // WM_NCCREATE supplies a valid CREATESTRUCT for the current call.
            const auto* create=reinterpret_cast<const CREATESTRUCTW*>(argument);
            SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(create->lpCreateParams));
        }
        auto* self=reinterpret_cast<InputWindow*>(GetWindowLongPtrW(window,GWLP_USERDATA));
        if(self){
            if(message==WM_KEYDOWN && key==VK_F8){++self->key_down;return 0;}
            if(message==WM_KEYUP && key==VK_F8){++self->key_up;return 0;}
            if(message==WM_LBUTTONDOWN){++self->button_down;return 0;}
            if(message==WM_LBUTTONUP){++self->button_up;return 0;}
        }
        return DefWindowProcW(window,message,key,argument);
    }
    bool open(){
        GetCursorPos(&previous_cursor);
        WNDCLASSW type{};type.lpfnWndProc=events;type.hInstance=GetModuleHandleW(nullptr);
        type.lpszClassName=L"HomeTunnelInputOwnershipTest";type.hCursor=LoadCursorW(nullptr,MAKEINTRESOURCEW(32512));
        if(!RegisterClassW(&type))return false;
        window=CreateWindowExW(0,type.lpszClassName,L"Home Tunnel isolated input ownership test",WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,CW_USEDEFAULT,480,320,nullptr,nullptr,type.hInstance,this);
        if(!window)return false;
        ShowWindow(window,SW_SHOWNORMAL);UpdateWindow(window);SetForegroundWindow(window);
        return pump_until([&]{return GetForegroundWindow()==window;});
    }
    bool inject(bool mouse,bool down){
        if(down && GetForegroundWindow()!=window)return false;
        if(mouse && down){POINT point{};if(!GetCursorPos(&point) || GetAncestor(WindowFromPoint(point),GA_ROOT)!=window)return false;}
        INPUT event{};
        if(mouse){event.type=INPUT_MOUSE;event.mi.dwFlags=down?MOUSEEVENTF_LEFTDOWN:MOUSEEVENTF_LEFTUP;}
        else{event.type=INPUT_KEYBOARD;event.ki.wVk=VK_F8;event.ki.dwFlags=down?0:KEYEVENTF_KEYUP;}
        if(SendInput(1,&event,sizeof(event))!=1)return false;
        (mouse?local_button:local_key)=down;return true;
    }
    ~InputWindow(){
        if(local_key)(void)inject(false,false);
        if(local_button)(void)inject(true,false);
        (void)pump_until([]{return !held(VK_F8) && !held(VK_LBUTTON);},2000);
        if(window && GetForegroundWindow()==window){SetCursorPos(previous_cursor.x,previous_cursor.y);if(previous)SetForegroundWindow(previous);}
        if(window)DestroyWindow(window);
    }
};
int input_ownership(){
    using ht::rd::WindowsInputSink;
    // Explicitly opt in: ordinary CI runs never inject input. All downs target
    // this disposable window; the test does not simulate physical hardware.
    if(!WindowsInputSink::ordinary_desktop() || held(VK_F8) || held(VK_LBUTTON)){
        std::fputs("Input ownership: ordinary desktop and initially released F8/left button required\n",stderr);return 20;
    }
    InputWindow target;if(!target.open()){
        std::fputs("Input ownership: could not focus the isolated target window; no input was injected\n",stderr);return 21;
    }
    RECT bounds{};POINT origin{};
    if(!GetClientRect(target.window,&bounds) || !ClientToScreen(target.window,&origin)){
        std::fputs("Input ownership: could not determine target client geometry\n",stderr);return 22;
    }
    const ht::rd::DisplayGeometry display{origin.x,origin.y,bounds.right,bounds.bottom,0};
    constexpr uint16_t f8_usage=65;
    const auto require=[&](bool condition,const char* message){if(!condition)std::fprintf(stderr,"Input ownership: %s\n",message);return condition;};
    {
        WindowsInputSink sink(display,GetCurrentProcessId());
        const auto wait=[&](const std::function<bool()>& ready){return pump_until([&]{return sink.watchdog_tick() && ready();});};
        if(!require(sink.watchdog_tick() && sink.pointer(0,32768,32768),"target setup failed"))return 23;
        if(!require(target.inject(false,true) && target.inject(true,true) &&
            wait([&]{return held(VK_F8) && held(VK_LBUTTON) && target.key_down==1 && target.button_down==1;}),"local input was not observed"))return 24;
        if(!require(!sink.key(f8_usage,true,false) && !sink.button(1,true),"remote claimed already held local input"))return 25;
        if(!require(sink.key(f8_usage,false,false) && sink.button(1,false),"unowned release should be a no-op"))return 26;
        sink.watchdog_stop();
        // Let the independent process complete cleanup while the window pumps.
        const auto wait_until=GetTickCount64()+150;
        (void)pump_until([&]{return GetTickCount64()>=wait_until;},300);
        if(!require(held(VK_F8) && held(VK_LBUTTON) && target.key_down==1 && target.button_down==1 &&
            target.key_up==0 && target.button_up==0,"unowned input changed during release or guard cleanup"))return 27;
        if(!require(target.inject(false,false) && target.inject(true,false) &&
            pump_until([&]{return !held(VK_F8) && !held(VK_LBUTTON) && target.key_up==1 && target.button_up==1;}),"local cleanup failed"))return 28;
    }
    {
        WindowsInputSink sink(display,GetCurrentProcessId());
        const auto wait=[&](const std::function<bool()>& ready){return pump_until([&]{return sink.watchdog_tick() && ready();});};
        if(!require(sink.watchdog_tick() && sink.pointer(0,32768,32768) && sink.key(f8_usage,true,false) && sink.button(1,true) &&
            wait([&]{return held(VK_F8) && held(VK_LBUTTON) && target.key_down==2 && target.button_down==2;}),"owned input was not observed"))return 29;
        if(!require(sink.key(f8_usage,true,true) && sink.button(1,true) &&
            wait([&]{return target.key_down==3 && target.button_down==3;}),"owned repeat was rejected"))return 30;
        if(!require(sink.key(f8_usage,false,false) && sink.button(1,false) &&
            wait([&]{return !held(VK_F8) && !held(VK_LBUTTON) && target.key_up==2 && target.button_up==2;}),"owned release failed"))return 31;
        if(!require(sink.key(f8_usage,true,false) && sink.button(1,true) &&
            wait([&]{return held(VK_F8) && held(VK_LBUTTON) && target.key_down==4 && target.button_down==4;}),"guard release setup failed"))return 32;
        const auto stopped=GetTickCount64();sink.watchdog_stop();
        if(!require(pump_until([&]{return !held(VK_F8) && !held(VK_LBUTTON) && target.key_up==3 && target.button_up==3;},2000),"guard did not release owned input within two seconds"))return 33;
        std::printf("{\"status\":\"passed\",\"scope\":\"isolated-window-synthetic-input\",\"local_held_preserved\":true,\"unowned_up_ignored\":true,\"owned_repeat_allowed\":true,\"owned_up_released\":true,\"guard_release_ms\":%llu,\"physical_keyboard_acceptance\":false}\n",
            static_cast<unsigned long long>(GetTickCount64()-stopped));
    }
    return 0;
}
}

int main(int argc,char** argv){
    using ht::rd::WindowsInputSink;
    const auto guard=WindowsInputSink::run_release_guard(argc,argv);if(guard>=0)return guard;
    if(WindowsInputSink::scan_code(70)!=0xe037 || WindowsInputSink::scan_code(72)!=0xe145)return 14;
#if defined(__clang__)
#pragma clang unsafe_buffer_usage begin
#endif
    const auto mode=argc==2?std::string_view(argv[1]):std::string_view{};
#if defined(__clang__)
#pragma clang unsafe_buffer_usage end
#endif
    if(mode=="--input-ownership")return input_ownership();
    if(!mode.empty()){
        WindowsInputSink sink({});
        if(!sink.watchdog_tick())return 10;
        if(mode=="--fixture-stall"){
            // No input is injected by any fixture. The guard must terminate a
            // stalled worker even in a view-only session, before lease checks
            // could be held indefinitely behind blocked IPC.
            Sleep(5000);return 11;
        }
        if(mode=="--fixture-live"){
            for(unsigned n=0;n<10;++n){Sleep(200);if(!sink.watchdog_tick())return 12;}
        }else if(mode!="--fixture-stop")return 13;
        sink.watchdog_stop();Sleep(1600);return 0;
    }
    if(!fixture(L"--fixture-stall",23)){std::fputs("Stalled worker was not terminated by its independent guard\n",stderr);return 1;}
    if(!fixture(L"--fixture-live",0)){std::fputs("Guard killed a worker with fresh session ticks\n",stderr);return 1;}
    if(!fixture(L"--fixture-stop",0)){std::fputs("Stopped guard killed the idle worker\n",stderr);return 1;}
    std::puts("Windows input release guard: stalled, live and gracefully stopped worker lifecycle passed (no input injected)");
    return 0;
}
#endif
