#if defined(__linux__) && !defined(__ANDROID__)
#include "x11_session.hpp"
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-login.h>
#include <charconv>
#include <cstdlib>
#include <fcntl.h>
#include <memory>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace ht::rd {
namespace {
struct Free {void operator()(char* value)const {std::free(value);}};
using OwnedText=std::unique_ptr<char,Free>;
bool local_display(std::string_view name,unsigned& number){
    if(name.size()<2 || name.front()!=':' || name.size()>24)return false;
    name.remove_prefix(1);const auto dot=name.find('.');const auto display=name.substr(0,dot);
    const auto parsed=std::from_chars(display.data(),display.data()+display.size(),number);
    if(parsed.ec!=std::errc{} || parsed.ptr!=display.data()+display.size() || number>65535)return false;
    if(dot!=std::string_view::npos){unsigned screen=0;const auto tail=name.substr(dot+1);
        const auto value=std::from_chars(tail.data(),tail.data()+tail.size(),screen);
        if(value.ec!=std::errc{} || value.ptr!=tail.data()+tail.size() || screen!=0)return false;}
    return true;
}
bool native_x11(Display* display){
    if(!display)return false;
    int opcode=0,event=0,error=0;
    if(XQueryExtension(display,"XWAYLAND",&opcode,&event,&error))return false;
    int major=1,minor=5;
    return XRRQueryExtension(display,&event,&error) && XRRQueryVersion(display,&major,&minor) &&
        (major>1 || (major==1 && minor>=5));
}
bool valid_xauthority(){
    const char* configured=std::getenv("XAUTHORITY");std::string path;
    if(configured)path=configured;
    else {const char* home=std::getenv("HOME");if(!home)return false;path=std::string(home)+"/.Xauthority";}
    if(path.empty() || path.front()!='/' || path.size()>4096)return false;
    const int descriptor=open(path.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);if(descriptor<0)return false;
    struct stat status{};const bool valid=fstat(descriptor,&status)==0 && S_ISREG(status.st_mode) &&
        status.st_uid==getuid() && !(status.st_mode&(S_IWGRP|S_IWOTH)) && status.st_size>0 && status.st_size<=1024*1024;
    close(descriptor);return valid;
}
[[maybe_unused]] bool unlocked_session(std::string_view display_name){
    char* raw=nullptr;if(sd_pid_get_session(0,&raw)<0)return false;OwnedText session(raw);
    uid_t owner=static_cast<uid_t>(-1);
    if(sd_session_get_uid(session.get(),&owner)<0 || owner!=getuid() ||
       sd_session_is_active(session.get())<=0 || sd_session_is_remote(session.get())!=0)return false;
    raw=nullptr;if(sd_session_get_type(session.get(),&raw)<0)return false;OwnedText type(raw);
    if(std::string_view(type.get())!="x11")return false;
    raw=nullptr;if(sd_session_get_display(session.get(),&raw)<0)return false;OwnedText current(raw);
    unsigned expected=0,actual=0;if(!local_display(current.get(),expected) || !local_display(display_name,actual) || expected!=actual)return false;
    // Use the fixed root-owned system-bus socket; do not trust an environment
    // override such as DBUS_SYSTEM_BUS_ADDRESS as evidence of session state.
    struct stat status{};if(stat("/run/dbus/system_bus_socket",&status)!=0 || !S_ISSOCK(status.st_mode) || status.st_uid!=0)return false;
    sd_bus* bus=nullptr;sd_bus_message* reply=nullptr;int locked=1;bool good=false;
    if(sd_bus_new(&bus)>=0 && sd_bus_set_address(bus,"unix:path=/run/dbus/system_bus_socket")>=0 &&
       sd_bus_set_bus_client(bus,1)>=0 && sd_bus_set_method_call_timeout(bus,250000)>=0 && sd_bus_start(bus)>=0 &&
       sd_bus_call_method(bus,"org.freedesktop.login1","/org/freedesktop/login1","org.freedesktop.login1.Manager",
                          "GetSession",nullptr,&reply,"s",session.get())>=0){
        const char* path=nullptr;
        if(sd_bus_message_read(reply,"o",&path)>=0 && path &&
           sd_bus_get_property_trivial(bus,"org.freedesktop.login1",path,"org.freedesktop.login1.Session","LockedHint",nullptr,'b',&locked)>=0)
            good=locked==0;
    }
    sd_bus_message_unref(reply);sd_bus_flush_close_unref(bus);return good;
}
}
bool x11_initialize_threads(){return XInitThreads()!=0;}
bool x11_ordinary_desktop(){
    if(std::getenv("WAYLAND_DISPLAY"))return false;
    const char* kind=std::getenv("XDG_SESSION_TYPE");if(kind && std::string_view(kind)!="x11")return false;
    const char* name=std::getenv("DISPLAY");unsigned number=0;if(!name || !local_display(name,number))return false;
    if(!valid_xauthority())return false;
#if defined(HT_RD_X11_TESTING)
    // This definition exists only on the separate CI executable. Production
    // targets never compile a session-check bypass or accept a test-mode flag.
    const bool session=std::getenv("HT_RD_XVFB_ISOLATED_TEST") && std::string_view(std::getenv("HT_RD_XVFB_ISOLATED_TEST"))=="1";
#else
    const bool session=unlocked_session(name);
#endif
    if(!session)return false;
    Display* display=XOpenDisplay(name);const bool result=native_x11(display);if(display)XCloseDisplay(display);return result;
}
std::vector<X11Screen> x11_screens(){
    std::vector<X11Screen> screens;if(!x11_ordinary_desktop())return screens;
    Display* display=XOpenDisplay(nullptr);if(!display)return screens;
    XWindowAttributes root{};
    if(!XGetWindowAttributes(display,DefaultRootWindow(display),&root)){XCloseDisplay(display);return screens;}
    int count=0;auto* monitors=XRRGetMonitors(display,DefaultRootWindow(display),True,&count);
    if(monitors && count>0 && count<=16)for(int n=0;n<count;++n){const auto& monitor=monitors[n];
        if(!monitor.name || monitor.x<0 || monitor.y<0 || monitor.width<1 || monitor.height<1 || monitor.width>16384 || monitor.height>16384 ||
           int64_t(monitor.x)+monitor.width>root.width || int64_t(monitor.y)+monitor.height>root.height)continue;
        char* name=XGetAtomName(display,monitor.name);
        screens.push_back({monitor.name,{monitor.x,monitor.y,monitor.width,monitor.height,0},name?name:"Display"});if(name)XFree(name);}
    if(monitors)XRRFreeMonitors(monitors);
    XCloseDisplay(display);return screens;
}
bool x11_screen_current(uint64_t id,const DisplayGeometry& geometry){
    for(const auto& screen:x11_screens())if(screen.id==id)return screen.geometry.x==geometry.x && screen.geometry.y==geometry.y &&
        screen.geometry.width==geometry.width && screen.geometry.height==geometry.height;
    return false;
}
}
#endif
