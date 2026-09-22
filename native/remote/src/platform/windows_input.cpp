#if defined(_WIN32)
#include "windows_input.hpp"
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <array>
#include <vector>

namespace ht::rd {
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
        map[68]=0x57;map[69]=0x58;map[71]=0x46;
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
    if(scan==0 || !ordinary_desktop()) return false;
    INPUT event{};event.type=INPUT_KEYBOARD;event.ki.wScan=scan&0xff;
    event.ki.dwFlags=KEYEVENTF_SCANCODE | (scan>0xff ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
    return SendInput(1,&event,sizeof(event))==1;
}
bool WindowsInputSink::button(uint8_t button,bool down) {
    if(!ordinary_desktop()) return false;
    INPUT event{};event.type=INPUT_MOUSE;
    switch(button) {
        case 1:event.mi.dwFlags=down ? MOUSEEVENTF_LEFTDOWN:MOUSEEVENTF_LEFTUP;break;
        case 2:event.mi.dwFlags=down ? MOUSEEVENTF_RIGHTDOWN:MOUSEEVENTF_RIGHTUP;break;
        case 3:event.mi.dwFlags=down ? MOUSEEVENTF_MIDDLEDOWN:MOUSEEVENTF_MIDDLEUP;break;
        case 4:case 5:event.mi.dwFlags=down ? MOUSEEVENTF_XDOWN:MOUSEEVENTF_XUP;event.mi.mouseData=button==4 ? XBUTTON1:XBUTTON2;break;
        default:return false;
    }
    return SendInput(1,&event,sizeof(event))==1;
}
bool WindowsInputSink::pointer(uint16_t slot,uint16_t x,uint16_t y) {
    if(slot!=display_.slot || display_.width<=0 || display_.height<=0 || !ordinary_desktop()) return false;
    const int virtual_x=GetSystemMetrics(SM_XVIRTUALSCREEN),virtual_y=GetSystemMetrics(SM_YVIRTUALSCREEN);
    const int width=GetSystemMetrics(SM_CXVIRTUALSCREEN),height=GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if(width<=1 || height<=1) return false;
    const int64_t px=int64_t(display_.x)+int64_t(x)*(display_.width-1)/65535;
    const int64_t py=int64_t(display_.y)+int64_t(y)*(display_.height-1)/65535;
    if(px<virtual_x || py<virtual_y || px>=int64_t(virtual_x)+width || py>=int64_t(virtual_y)+height) return false;
    INPUT event{};event.type=INPUT_MOUSE;
    event.mi.dx=static_cast<LONG>((px-virtual_x)*65535/(width-1));event.mi.dy=static_cast<LONG>((py-virtual_y)*65535/(height-1));
    event.mi.dwFlags=MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK;
    return SendInput(1,&event,sizeof(event))==1;
}
bool WindowsInputSink::text(std::string_view text) {
    if(text.empty() || text.size()>protocol::TEXT_BYTES || !ordinary_desktop()) return false;
    const int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
    if(size<=0) return false;
    std::vector<wchar_t> utf16(static_cast<size_t>(size));
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),utf16.data(),size)!=size) return false;
    for(const auto unit:utf16) {
        std::array<INPUT,2> pair{};
        pair[0].type=pair[1].type=INPUT_KEYBOARD;
        pair[0].ki.wScan=pair[1].ki.wScan=static_cast<WORD>(unit);
        pair[0].ki.dwFlags=KEYEVENTF_UNICODE;pair[1].ki.dwFlags=KEYEVENTF_UNICODE|KEYEVENTF_KEYUP;
        const auto sent=SendInput(2,pair.data(),sizeof(INPUT));
        if(sent!=2) { if(sent==1) (void)SendInput(1,&pair[1],sizeof(INPUT));return false; }
    }
    return true;
}
}
#endif
