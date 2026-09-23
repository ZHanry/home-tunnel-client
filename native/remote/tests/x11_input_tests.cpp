#include "../src/platform/x11_input.hpp"
#include "../src/platform/x11_session.hpp"
#include <X11/XKBlib.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <span>
#include <string>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;
namespace {
using namespace std::chrono_literals;
using Clock=std::chrono::steady_clock;
#define REQUIRE(value) do {if(!(value)){std::fprintf(stderr,"X11 test failure at line %d: %s\n",__LINE__,#value);std::exit(1);}}while(0)
struct Events {unsigned key_down=0,key_up=0,button_down=0,button_up=0;};
void collect(Display* display,KeyCode key,Events& events){
    while(XPending(display)){XEvent event{};XNextEvent(display,&event);
        if(event.type==KeyPress && event.xkey.keycode==key){REQUIRE(!event.xkey.send_event);++events.key_down;}
        if(event.type==KeyRelease && event.xkey.keycode==key){REQUIRE(!event.xkey.send_event);++events.key_up;}
        if(event.type==ButtonPress && event.xbutton.button==1){REQUIRE(!event.xbutton.send_event);++events.button_down;}
        if(event.type==ButtonRelease && event.xbutton.button==1){REQUIRE(!event.xbutton.send_event);++events.button_up;}
    }
}
bool held(Display* display,KeyCode key){std::array<char,32> keys{};XQueryKeymap(display,keys.data());return (static_cast<unsigned char>(keys[key/8])&(1u<<(key%8)))!=0;}
bool left_held(Display* display){Window root=0,child=0;int rx=0,ry=0,wx=0,wy=0;unsigned mask=0;
    REQUIRE(XQueryPointer(display,XDefaultRootWindow(display),&root,&child,&rx,&ry,&wx,&wy,&mask));return (mask&Button1Mask)!=0;}
int child(std::string_view mode,uint32_t target){
    ht::rd::X11InputSink sink({0,0,800,600,0},target);REQUIRE(sink.watchdog_tick());
    REQUIRE(sink.pointer(0,24576,32768));REQUIRE(sink.key(4,true,false));REQUIRE(sink.button(1,true));
    if(mode=="live"){
        for(int n=0;n<18;++n){REQUIRE(sink.watchdog_tick());std::this_thread::sleep_for(100ms);}
        REQUIRE(sink.key(4,false,false));REQUIRE(sink.button(1,false));sink.watchdog_stop();return 0;
    }
    // The parent either kills this exact child or waits for its guard to kill
    // it after heartbeat expiry. No test process signals unrelated processes.
    for(;;)std::this_thread::sleep_for(100ms);
}
long run_case(Display* display,Window window,std::string_view mode,KeyCode key,KeyCode unrelated){
    XSetInputFocus(display,window,RevertToParent,CurrentTime);XSync(display,False);Events discarded;collect(display,key,discarded);
    REQUIRE(XTestFakeKeyEvent(display,unrelated,True,CurrentTime));XSync(display,False);REQUIRE(held(display,unrelated));
    std::string mode_argument(mode),owner=std::to_string(getpid());char executable[]="/proc/self/exe",operation[]="--held";
    std::array<char*,5> arguments{executable,operation,mode_argument.data(),owner.data(),nullptr};pid_t pid=0;
    REQUIRE(posix_spawn(&pid,executable,nullptr,nullptr,arguments.data(),environ)==0);
    const int pidfd=static_cast<int>(syscall(SYS_pidfd_open,pid,0));REQUIRE(pidfd>=0);
    Events events;const auto down_deadline=Clock::now()+3s;
    while((!events.key_down || !events.button_down) && Clock::now()<down_deadline){collect(display,key,events);std::this_thread::sleep_for(5ms);}
    REQUIRE(events.key_down && events.button_down);REQUIRE(!events.key_up && !events.button_up);
    const auto started=Clock::now();if(mode=="crash")REQUIRE(syscall(SYS_pidfd_send_signal,pidfd,SIGKILL,nullptr,0)==0);
    const auto deadline=started+3s;
    while((!events.key_up || !events.button_up) && Clock::now()<deadline){collect(display,key,events);std::this_thread::sleep_for(5ms);}
    const auto elapsed=std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now()-started).count();
    REQUIRE(events.key_up && events.button_up);REQUIRE(!held(display,key));REQUIRE(held(display,unrelated));
    if(mode=="live")REQUIRE(elapsed>=1500 && elapsed<=2500);else REQUIRE(elapsed<=2000);
    REQUIRE(XTestFakeKeyEvent(display,unrelated,False,CurrentTime));XSync(display,False);
    int status=0;REQUIRE(waitpid(pid,&status,0)==pid);close(pidfd);
    if(mode=="live")REQUIRE(WIFEXITED(status) && WEXITSTATUS(status)==0);else REQUIRE(WIFSIGNALED(status) && WTERMSIG(status)==SIGKILL);
    return elapsed;
}
}
int main(int argc,char** argv){
    REQUIRE(ht::rd::x11_initialize_threads());const int guard=ht::rd::X11InputSink::run_release_guard(argc,argv);if(guard>=0)return guard;
    REQUIRE(std::getenv("HT_RD_XVFB_ISOLATED_TEST"));REQUIRE(ht::rd::X11InputSink::pidfd_available());REQUIRE(ht::rd::x11_ordinary_desktop());
    REQUIRE(argv && (argc==1 || argc==4));
    // The OS supplies exactly argc arguments; only the two fixture forms above
    // are accepted before constructing this bounded process-startup view.
#if defined(__clang__)
#pragma clang unsafe_buffer_usage begin
#endif
    const std::span<char*> arguments(argv,static_cast<size_t>(argc));
#if defined(__clang__)
#pragma clang unsafe_buffer_usage end
#endif
    if(argc==4 && std::string_view(arguments[1])=="--held")return child(arguments[2],static_cast<uint32_t>(std::stoul(arguments[3])));
    REQUIRE(argc==1);const auto screens=ht::rd::x11_screens();REQUIRE(!screens.empty());
    const std::string authority=std::getenv("XAUTHORITY");setenv("XAUTHORITY","/dev/null",1);REQUIRE(!ht::rd::x11_ordinary_desktop());setenv("XAUTHORITY",authority.c_str(),1);
    setenv("WAYLAND_DISPLAY","test-wayland",1);REQUIRE(!ht::rd::x11_ordinary_desktop());unsetenv("WAYLAND_DISPLAY");
    Display* display=XOpenDisplay(nullptr);REQUIRE(display);Bool detectable=False;REQUIRE(XkbSetDetectableAutoRepeat(display,True,&detectable) && detectable);
    Window window=XCreateSimpleWindow(display,XDefaultRootWindow(display),100,100,500,350,0,0,0xffffff);REQUIRE(window);
    const unsigned long owner=static_cast<unsigned long>(getpid());const Atom property=XInternAtom(display,"_NET_WM_PID",False);
    XChangeProperty(display,window,property,XA_CARDINAL,32,PropModeReplace,reinterpret_cast<const unsigned char*>(&owner),1);
    XSelectInput(display,window,KeyPressMask|KeyReleaseMask|ButtonPressMask|ButtonReleaseMask);XMapRaised(display,window);XSync(display,False);
    const auto key=XKeysymToKeycode(display,XK_a),unrelated=XKeysymToKeycode(display,XK_b);REQUIRE(key && unrelated);
    XSetInputFocus(display,window,RevertToParent,CurrentTime);XSync(display,False);
    REQUIRE(XTestFakeKeyEvent(display,key,True,CurrentTime));XSync(display,False);
    {
        ht::rd::X11InputSink sink({0,0,800,600,0},static_cast<uint32_t>(getpid()));REQUIRE(sink.watchdog_tick());
        REQUIRE(!sink.key(4,true,false));sink.watchdog_stop();
    }
    std::this_thread::sleep_for(100ms);REQUIRE(held(display,key));
    REQUIRE(XTestFakeKeyEvent(display,key,False,CurrentTime));XSync(display,False);
    REQUIRE(XTestFakeMotionEvent(display,-1,300,300,CurrentTime));
    REQUIRE(XTestFakeButtonEvent(display,1,True,CurrentTime));XSync(display,False);
    {
        ht::rd::X11InputSink sink({0,0,800,600,0},static_cast<uint32_t>(getpid()));REQUIRE(sink.watchdog_tick());
        REQUIRE(sink.pointer(0,24576,32768));REQUIRE(!sink.button(1,true));sink.watchdog_stop();
    }
    std::this_thread::sleep_for(100ms);REQUIRE(left_held(display));
    REQUIRE(XTestFakeButtonEvent(display,1,False,CurrentTime));XSync(display,False);
    const auto live=run_case(display,window,"live",key,unrelated),stalled=run_case(display,window,"stall",key,unrelated),crashed=run_case(display,window,"crash",key,unrelated);
    XDestroyWindow(display,window);XCloseDisplay(display);
    std::printf("{\"status\":\"passed\",\"scope\":\"isolated-xvfb-real-xtest-input\",\"live_release_ms\":%ld,\"heartbeat_release_ms\":%ld,\"worker_crash_release_ms\":%ld,\"unrelated_key_preserved\":true,\"already_held_key_preserved\":true,\"physical_xorg_acceptance\":false}\n",live,stalled,crashed);
    return 0;
}
