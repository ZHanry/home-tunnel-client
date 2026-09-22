#include "host_platform.hpp"
#if defined(WEBRTC_WIN)
#include "modules/desktop_capture/win/screen_capture_utils.h"
#include <fcntl.h>
#include <io.h>
#include <objbase.h>
#include <windows.h>
#else
#include "../src/platform/x11_session.hpp"
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#include <cstdio>

namespace ht::rd {
std::vector<HostScreen> host_displays(){
    std::vector<HostScreen> result;
#if defined(WEBRTC_WIN)
    webrtc::DesktopCapturer::SourceList sources;
    if(!HostInputSink::ordinary_desktop() || !webrtc::GetScreenList(&sources) || sources.size()>16)return result;
    for(const auto& source:sources){std::wstring key;if(!webrtc::IsScreenValid(source.id,&key))continue;
        const auto rect=webrtc::GetScreenRect(source.id,key);
        if(rect.width()<1 || rect.height()<1 || rect.width()>16384 || rect.height()>16384)continue;
        result.push_back({source.id,rect,key,"Display "+std::to_string(result.size()+1)});}
#else
    for(const auto& source:x11_screens())result.push_back({static_cast<webrtc::DesktopCapturer::SourceId>(source.id),
        webrtc::DesktopRect::MakeXYWH(source.geometry.x,source.geometry.y,source.geometry.width,source.geometry.height),{},source.name});
#endif
    return result;
}
bool host_screen_current(const HostScreen& screen){
#if defined(WEBRTC_WIN)
    return webrtc::GetScreenRect(screen.id,screen.device_key).equals(screen.rect);
#else
    return x11_screen_current(static_cast<uint64_t>(screen.id),{screen.rect.left(),screen.rect.top(),screen.rect.width(),screen.rect.height(),0});
#endif
}
bool host_prepare_process(){
#if defined(WEBRTC_WIN)
    return SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) ||
        GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext())==DPI_AWARENESS_PER_MONITOR_AWARE;
#else
    return x11_initialize_threads() && HostInputSink::pidfd_available() && signal(SIGPIPE,SIG_IGN)!=SIG_ERR;
#endif
}
bool host_pipe_transport(){
#if defined(WEBRTC_WIN)
    return GetFileType(GetStdHandle(STD_INPUT_HANDLE))==FILE_TYPE_PIPE && GetFileType(GetStdHandle(STD_OUTPUT_HANDLE))==FILE_TYPE_PIPE &&
        _setmode(_fileno(stdin),_O_BINARY)!=-1 && _setmode(_fileno(stdout),_O_BINARY)!=-1;
#else
    struct stat input{},output{};return fstat(STDIN_FILENO,&input)==0 && fstat(STDOUT_FILENO,&output)==0 && S_ISFIFO(input.st_mode) && S_ISFIFO(output.st_mode);
#endif
}
bool host_thread_enter(){
#if defined(WEBRTC_WIN)
    return SUCCEEDED(CoInitializeEx(nullptr,COINIT_MULTITHREADED));
#else
    return true;
#endif
}
void host_thread_leave(){
#if defined(WEBRTC_WIN)
    CoUninitialize();
#endif
}
webrtc::DesktopCaptureOptions host_capture_options(){
    auto options=webrtc::DesktopCaptureOptions::CreateDefault();
#if defined(WEBRTC_WIN)
    options.set_allow_directx_capturer(true);
#elif defined(WEBRTC_USE_PIPEWIRE)
    options.set_allow_pipewire(false);
#endif
    return options;
}
std::unique_ptr<ClipboardStorage> host_clipboard(){
#if defined(WEBRTC_WIN)
    return windows_clipboard();
#else
    // This platform advertises no clipboard permission. There is deliberately
    // no fake storage or success path for unimplemented clipboard operations.
    return nullptr;
#endif
}
}
