#pragma once
#if defined(_WIN32)
#include "windows_user.hpp"
#include <fcntl.h>
#include <io.h>
#include <cstdio>
#include <string>
#include <string_view>

namespace ht::rd {
inline bool& service_transport_verified() { static bool verified=false; return verified; }
inline bool connect_service_transport(std::string_view nonce, DWORD expected_pid) {
    if(nonce.size()!=64 || !expected_pid || !is_local_system()) return false;
    for(const auto c:nonce) if(!((c>='0' && c<='9') || (c>='a' && c<='f'))) return false;
    const auto name=std::wstring(L"\\\\.\\pipe\\HomeTunnelWorker-")+std::wstring(nonce.begin(),nonce.end());
    if(!WaitNamedPipeW(name.c_str(),5000)) return false;
    UserTokenHandle pipe;
    pipe.value=CreateFileW(name.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,
                          SECURITY_SQOS_PRESENT|SECURITY_IDENTIFICATION,nullptr);
    if(pipe.value==INVALID_HANDLE_VALUE) {pipe.value=nullptr;return false;}
    ULONG server_pid=0,server_session=0;
    if(!GetNamedPipeServerProcessId(pipe.value,&server_pid) || server_pid!=expected_pid ||
       !GetNamedPipeServerSessionId(pipe.value,&server_session) || server_session!=0) return false;
    const auto scm=OpenSCManagerW(nullptr,nullptr,SC_MANAGER_CONNECT);
    if(!scm) return false;
    const auto service=OpenServiceW(scm,L"HomeTunnelHost",SERVICE_QUERY_STATUS);
    CloseServiceHandle(scm);
    if(!service) return false;
    SERVICE_STATUS_PROCESS status{};DWORD size=0;
    const bool trusted=QueryServiceStatusEx(service,SC_STATUS_PROCESS_INFO,
        reinterpret_cast<LPBYTE>(&status),sizeof(status),&size) &&
        status.dwProcessId==expected_pid &&
        (status.dwCurrentState==SERVICE_RUNNING || status.dwCurrentState==SERVICE_START_PENDING);
    CloseServiceHandle(service);
    if(!trusted) return false;
    HANDLE output=nullptr;
    if(!DuplicateHandle(GetCurrentProcess(),pipe.value,GetCurrentProcess(),&output,0,FALSE,DUPLICATE_SAME_ACCESS))return false;
    const int input_fd=_open_osfhandle(reinterpret_cast<intptr_t>(pipe.value),_O_RDONLY|_O_BINARY);
    if(input_fd<0){CloseHandle(output);return false;}
    pipe.value=nullptr; // CRT owns the handle now.
    const int output_fd=_open_osfhandle(reinterpret_cast<intptr_t>(output),_O_WRONLY|_O_BINARY);
    if(output_fd<0){_close(input_fd);CloseHandle(output);return false;}
    const bool attached=_dup2(input_fd,0)==0 && _dup2(output_fd,1)==0;
    if(input_fd!=0)_close(input_fd);
    if(output_fd!=1)_close(output_fd);
    if(!attached ||
       !SetStdHandle(STD_INPUT_HANDLE,reinterpret_cast<HANDLE>(_get_osfhandle(0))) ||
       !SetStdHandle(STD_OUTPUT_HANDLE,reinterpret_cast<HANDLE>(_get_osfhandle(1))))return false;
    service_transport_verified()=true;
    return true;
}
}
#endif
