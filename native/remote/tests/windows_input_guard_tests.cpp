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
}

int main(int argc,char** argv){
    using ht::rd::WindowsInputSink;
    const auto guard=WindowsInputSink::run_release_guard(argc,argv);if(guard>=0)return guard;
#if defined(__clang__)
#pragma clang unsafe_buffer_usage begin
#endif
    const auto mode=argc==2?std::string_view(argv[1]):std::string_view{};
#if defined(__clang__)
#pragma clang unsafe_buffer_usage end
#endif
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
