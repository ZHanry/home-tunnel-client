#if defined(__linux__) && !defined(__ANDROID__)
#include "x11_input.hpp"
#include "x11_session.hpp"
#include <X11/Xatom.h>
#include <X11/XKBlib.h>
#include <X11/extensions/XTest.h>
#include <array>
#include <atomic>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;
namespace ht::rd {
namespace {
constexpr uint32_t ledger_magic=0x48545847;
constexpr uint64_t guard_timeout_ms=1200;
static_assert(std::atomic<uint64_t>::is_always_lock_free && std::atomic<uint32_t>::is_always_lock_free);
struct Ledger {
    uint32_t magic=ledger_magic;pid_t owner=0;uid_t uid=0;
    pthread_mutex_t mutex{};
    std::atomic<uint32_t> active{1},stop{0};std::atomic<uint64_t> heartbeat{0};
    std::array<uint8_t,256> keys{};std::array<uint8_t,10> buttons{};
};
uint64_t now_ms(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
bool lock_ledger(Ledger& ledger,int milliseconds=50){
    timespec until{};clock_gettime(CLOCK_REALTIME,&until);until.tv_nsec+=long(milliseconds)*1000000;
    until.tv_sec+=until.tv_nsec/1000000000;until.tv_nsec%=1000000000;
    const int status=pthread_mutex_timedlock(&ledger.mutex,&until);
    if(status==EOWNERDEAD)return pthread_mutex_consistent(&ledger.mutex)==0;
    return status==0;
}
bool alive(int pidfd){pollfd item{pidfd,POLLIN,0};return pidfd>=0 && poll(&item,1,0)==0;}
bool key_held(Display* display,unsigned key){
    std::array<char,32> keys{};XQueryKeymap(display,keys.data());
    return (static_cast<unsigned char>(keys[key/8])&(1u<<(key%8)))!=0;
}
bool button_held(Display* display,unsigned button){
    if(button>5)return false;
    Window root=0,child=0;int rx=0,ry=0,wx=0,wy=0;unsigned mask=0;
    return !XQueryPointer(display,DefaultRootWindow(display),&root,&child,&rx,&ry,&wx,&wy,&mask) || (mask&(Button1Mask<<(button-1)))!=0;
}
bool release(Ledger& ledger,Display* display){
    if(!display || !x11_ordinary_desktop())return false;
    bool empty=true;
    for(size_t key=1;key<ledger.keys.size();++key)if(ledger.keys[key]){
        if(XTestFakeKeyEvent(display,static_cast<unsigned>(key),False,CurrentTime))ledger.keys[key]=0;else empty=false;}
    for(size_t button=1;button<ledger.buttons.size();++button)if(ledger.buttons[button]){
        if(XTestFakeButtonEvent(display,static_cast<unsigned>(button),False,CurrentTime))ledger.buttons[button]=0;else empty=false;}
    XSync(display,False);return empty;
}
pid_t pidfd_owner(int fd){
    const auto path="/proc/self/fdinfo/"+std::to_string(fd);FILE* input=std::fopen(path.c_str(),"r");if(!input)return -1;
    std::array<char,128> line{};pid_t result=-1;
    while(std::fgets(line.data(),static_cast<int>(line.size()),input))if(std::strncmp(line.data(),"Pid:\t",5)==0){
        const auto value=std::string_view(line.data()).substr(5);int parsed=-1;
        const auto converted=std::from_chars(value.data(),value.data()+value.size(),parsed);
        if(converted.ec==std::errc{})result=parsed;
        break;}
    std::fclose(input);return result;
}
struct Guard {
    int mapping=-1,parent=-1,child_fd=-1;pid_t child=-1;Ledger* ledger=nullptr;
    ~Guard(){
        if(ledger){ledger->active=0;ledger->stop=1;munmap(ledger,sizeof(Ledger));}
        for(int descriptor:{mapping,parent,child_fd})if(descriptor>=0)close(descriptor);
        // The guard owns pending releases; never terminate it during teardown.
        if(child>0)std::thread([pid=child]{while(waitpid(pid,nullptr,0)<0 && errno==EINTR){};}).detach();
    }
    bool start(){
        parent=static_cast<int>(syscall(SYS_pidfd_open,getpid(),0));if(parent<0)return false;
        mapping=memfd_create("home-tunnel-input-ledger",MFD_CLOEXEC|MFD_ALLOW_SEALING);
        if(mapping<0 || ftruncate(mapping,sizeof(Ledger))!=0 || fcntl(mapping,F_ADD_SEALS,F_SEAL_GROW|F_SEAL_SHRINK|F_SEAL_SEAL)<0)return false;
        auto* memory=mmap(nullptr,sizeof(Ledger),PROT_READ|PROT_WRITE,MAP_SHARED,mapping,0);if(memory==MAP_FAILED)return false;
        ledger=new(memory) Ledger();ledger->owner=getpid();ledger->uid=getuid();ledger->heartbeat=now_ms();
        pthread_mutexattr_t attributes;if(pthread_mutexattr_init(&attributes)!=0)return false;
        const bool mutex_ready=pthread_mutexattr_setpshared(&attributes,PTHREAD_PROCESS_SHARED)==0 &&
            pthread_mutexattr_setrobust(&attributes,PTHREAD_MUTEX_ROBUST)==0 && pthread_mutex_init(&ledger->mutex,&attributes)==0;
        pthread_mutexattr_destroy(&attributes);if(!mutex_ready)return false;
        int ready[2];if(pipe2(ready,O_CLOEXEC)!=0)return false;
        posix_spawn_file_actions_t actions;if(posix_spawn_file_actions_init(&actions)!=0){close(ready[0]);close(ready[1]);return false;}
        // Fixed child descriptors are independent of inherited application fds.
        // Duplicate source fds first so dup2 targets cannot clobber another one.
        std::array<int,3> inherited{};const std::array<int,3> sources{parent,mapping,ready[1]};bool copied=true;
        for(size_t n=0;n<inherited.size();++n){inherited[n]=fcntl(sources[n],F_DUPFD_CLOEXEC,64);if(inherited[n]<0)copied=false;}
        for(size_t n=0;n<inherited.size() && copied;++n)copied=posix_spawn_file_actions_adddup2(&actions,inherited[n],40+static_cast<int>(n))==0;
        for(int descriptor:{STDIN_FILENO,STDOUT_FILENO,STDERR_FILENO})if(copied)copied=posix_spawn_file_actions_addclose(&actions,descriptor)==0;
        char executable[]="/proc/self/exe",argument[]="--input-release-guard=40,41,42";char* arguments[]{executable,argument,nullptr};
        const int spawned=copied?posix_spawn(&child,executable,&actions,nullptr,arguments,environ):EINVAL;
        posix_spawn_file_actions_destroy(&actions);for(int descriptor:inherited)if(descriptor>=0)close(descriptor);close(ready[1]);
        if(spawned!=0){child=-1;close(ready[0]);return false;}
        child_fd=static_cast<int>(syscall(SYS_pidfd_open,child,0));pollfd wait{ready[0],POLLIN,0};uint8_t acknowledged=0;
        const bool started=child_fd>=0 && poll(&wait,1,1000)==1 && read(ready[0],&acknowledged,1)==1 && acknowledged==1 && alive(child_fd);
        close(ready[0]);ledger->heartbeat=now_ms();return started;
    }
    bool healthy()const{return ledger && ledger->active.load()==1 && ledger->stop.load()==0 && alive(child_fd);}
};
uint32_t window_pid(Display* display,Window window){
    const Atom property=XInternAtom(display,"_NET_WM_PID",True);if(!property)return 0;
    for(unsigned depth=0;window && depth<32;++depth){Atom type=None;int format=0;unsigned long count=0,remaining=0;unsigned char* bytes=nullptr;
        const int status=XGetWindowProperty(display,window,property,0,1,False,XA_CARDINAL,&type,&format,&count,&remaining,&bytes);
        uint32_t pid=0;if(status==Success && type==XA_CARDINAL && format==32 && count==1 && bytes)pid=static_cast<uint32_t>(*reinterpret_cast<unsigned long*>(bytes));
        if(bytes)XFree(bytes);
        if(pid)return pid;
        Window root=0,parent=0,*children=nullptr;unsigned total=0;
        if(!XQueryTree(display,window,&root,&parent,&children,&total))return 0;
        if(children)XFree(children);
        if(parent==window)return 0;
        window=parent;
    }
    return 0;
}
std::array<uint8_t,232> physical_keys(Display* display){
    std::array<uint8_t,232> result{};auto* keyboard=XkbGetKeyboard(display,XkbAllComponentsMask,XkbUseCoreKbd);
    if(!keyboard || !keyboard->names || !keyboard->names->keys){if(keyboard)XkbFreeKeyboard(keyboard,0,True);return result;}
    auto add=[&](uint16_t usage,std::string_view wanted){for(unsigned code=keyboard->min_key_code;code<=keyboard->max_key_code;++code){
        const auto& raw=keyboard->names->keys[code].name;size_t size=4;while(size && (raw[size-1]=='\0' || raw[size-1]==' '))--size;
        if(std::string_view(raw,size)==wanted){result[usage]=static_cast<uint8_t>(code);break;}}};
    const std::array<std::string_view,26> letters{"AC01","AB05","AB03","AC03","AD03","AC04","AC05","AC06","AD08","AC07","AC08","AC09","AB07","AB06","AD09","AD10","AD01","AD04","AC02","AD05","AD07","AB04","AD02","AB02","AD06","AB01"};
    for(size_t n=0;n<letters.size();++n)add(static_cast<uint16_t>(n+4),letters[n]);
    for(unsigned n=0;n<10;++n)add(static_cast<uint16_t>(30+n),"AE"+std::string(n<9?"0":"")+std::to_string(n+1));
    const std::array<std::pair<uint16_t,std::string_view>,50> fixed{{{40,"RTRN"},{41,"ESC"},{42,"BKSP"},{43,"TAB"},{44,"SPCE"},{45,"AE11"},{46,"AE12"},{47,"AD11"},{48,"AD12"},{49,"BKSL"},{51,"AC10"},{52,"AC11"},{53,"TLDE"},{54,"AB08"},{55,"AB09"},{56,"AB10"},{57,"CAPS"},{70,"PRSC"},{71,"SCLK"},{72,"PAUS"},{73,"INS"},{74,"HOME"},{75,"PGUP"},{76,"DELE"},{77,"END"},{78,"PGDN"},{79,"RGHT"},{80,"LEFT"},{81,"DOWN"},{82,"UP"},{83,"NMLK"},{84,"KPDV"},{85,"KPMU"},{86,"KPSU"},{87,"KPAD"},{88,"KPEN"},{98,"KP0"},{99,"KPDL"},{100,"LSGT"},{101,"MENU"},{224,"LCTL"},{225,"LFSH"},{226,"LALT"},{227,"LWIN"},{228,"RCTL"},{229,"RTSH"},{230,"RALT"},{231,"RWIN"},{89,"KP1"},{90,"KP2"}}};
    for(const auto& [usage,name]:fixed)add(usage,name);
    for(unsigned n=0;n<12;++n)add(static_cast<uint16_t>(58+n),"FK"+std::string(n<9?"0":"")+std::to_string(n+1));
    for(unsigned n=3;n<=9;++n)add(static_cast<uint16_t>(88+n),"KP"+std::to_string(n));
    XkbFreeKeyboard(keyboard,0,True);return result;
}
}
struct X11InputSink::Impl {
    DisplayGeometry geometry;uint32_t target=0;Display* display=nullptr;std::array<uint8_t,232> keys{};
    std::unique_ptr<Guard> guard;bool failed=false,point=false;int px=0,py=0,wheel_x=0,wheel_y=0;
    Impl(DisplayGeometry value,uint32_t pid):geometry(value),target(pid){
        display=XOpenDisplay(nullptr);int event=0,error=0,major=0,minor=0;
        if(display && XTestQueryExtension(display,&event,&error,&major,&minor))keys=physical_keys(display);else failed=true;
    }
    ~Impl(){guard.reset();if(display)XCloseDisplay(display);}
    bool ensure(){if(failed || !display)return false;if(!guard){guard=std::make_unique<Guard>();if(!guard->start())failed=true;}if(!guard->healthy())failed=true;return !failed;}
    bool focused()const{if(!target)return true;Window window=0;int revert=0;XGetInputFocus(display,&window,&revert);return window && window!=PointerRoot && window_pid(display,window)==target;}
    bool at_point(int x,int y)const{if(!target)return true;Window child=0;int dx=0,dy=0;
        return focused() && XTranslateCoordinates(display,DefaultRootWindow(display),DefaultRootWindow(display),x,y,&dx,&dy,&child) && child && window_pid(display,child)==target;}
};
X11InputSink::X11InputSink(DisplayGeometry display,uint32_t target):impl_(std::make_unique<Impl>(display,target)){}
X11InputSink::~X11InputSink()=default;X11InputSink::X11InputSink(X11InputSink&&)noexcept=default;X11InputSink& X11InputSink::operator=(X11InputSink&&)noexcept=default;
bool X11InputSink::ordinary_desktop(){return x11_ordinary_desktop();}
bool X11InputSink::pidfd_available(){const int fd=static_cast<int>(syscall(SYS_pidfd_open,getpid(),0));if(fd<0)return false;const bool result=syscall(SYS_pidfd_send_signal,fd,0,nullptr,0)==0;close(fd);return result;}
bool X11InputSink::watchdog_tick(){if(!impl_->ensure())return false;impl_->guard->ledger->heartbeat=now_ms();return true;}
void X11InputSink::watchdog_stop(){impl_->failed=true;if(impl_->guard && impl_->guard->ledger){impl_->guard->ledger->active=0;impl_->guard->ledger->stop=1;}}
bool X11InputSink::key(uint16_t usage,bool down,bool){
    auto& state=*impl_;if(usage>=state.keys.size() || !state.keys[usage] || (down && !state.ensure()) || !state.guard || !state.guard->ledger)return false;
    auto& ledger=*state.guard->ledger;if(!lock_ledger(ledger))return false;bool sent=false;const auto code=state.keys[usage];
    if(!down && !ledger.keys[code])sent=true;
    else if(ordinary_desktop() && (!down || (state.guard->healthy() && state.focused() && (ledger.keys[code] || !key_held(state.display,code))))){const auto previous=ledger.keys[code];if(down)ledger.keys[code]=1;
        sent=XTestFakeKeyEvent(state.display,code,down,CurrentTime)!=0;XSync(state.display,False);
        if(down && !sent)ledger.keys[code]=previous;
        if(!down && sent)ledger.keys[code]=0;}
    pthread_mutex_unlock(&ledger.mutex);return sent;
}
bool X11InputSink::pointer(uint16_t slot,uint16_t x,uint16_t y){
    auto& state=*impl_;const auto& g=state.geometry;if(slot!=g.slot || g.width<1 || g.height<1 || !ordinary_desktop() || !state.ensure())return false;
    const int px=static_cast<int>(int64_t(g.x)+int64_t(x)*(g.width-1)/65535),py=static_cast<int>(int64_t(g.y)+int64_t(y)*(g.height-1)/65535);
    if(px<0 || py<0 || px>=DisplayWidth(state.display,DefaultScreen(state.display)) || py>=DisplayHeight(state.display,DefaultScreen(state.display)) || !state.at_point(px,py))return false;
    auto& ledger=*state.guard->ledger;if(!lock_ledger(ledger))return false;
    const bool sent=state.guard->healthy() && ordinary_desktop() && state.at_point(px,py) && XTestFakeMotionEvent(state.display,-1,px,py,CurrentTime);
    XSync(state.display,False);if(sent){state.px=px;state.py=py;state.point=true;}pthread_mutex_unlock(&ledger.mutex);return sent;
}
bool X11InputSink::button(uint8_t button,bool down){
    constexpr std::array<unsigned,5> buttons{1,3,2,8,9};auto& state=*impl_;
    if(button<1 || button>5 || (down && !state.ensure()) || !state.guard || !state.guard->ledger)return false;
    const auto code=buttons[button-1];auto& ledger=*state.guard->ledger;if(!lock_ledger(ledger))return false;bool sent=false;
    if(!down && !ledger.buttons[code])sent=true;
    else if(ordinary_desktop() && (!down || (state.guard->healthy() && state.point && state.at_point(state.px,state.py) && (ledger.buttons[code] || !button_held(state.display,code))))){
        const auto previous=ledger.buttons[code];if(down)ledger.buttons[code]=1;
        sent=(!down || XTestFakeMotionEvent(state.display,-1,state.px,state.py,CurrentTime)) && XTestFakeButtonEvent(state.display,code,down,CurrentTime);
        XSync(state.display,False);if(down && !sent)ledger.buttons[code]=previous;if(!down && sent)ledger.buttons[code]=0;}
    pthread_mutex_unlock(&ledger.mutex);return sent;
}
bool X11InputSink::wheel(int32_t dx,int32_t dy){
    auto& state=*impl_;if(dx < -12000 || dx>12000 || dy < -12000 || dy>12000 || !ordinary_desktop() || !state.ensure() || !state.point || !state.at_point(state.px,state.py))return false;
    state.wheel_x+=dx;state.wheel_y+=dy;auto& ledger=*state.guard->ledger;if(!lock_ledger(ledger))return false;bool sent=state.guard->healthy();
    for(unsigned axis=0;axis<2 && sent;++axis){auto& value=axis?state.wheel_y:state.wheel_x;
        while((value>=120 || value<=-120) && sent){const unsigned button=axis?(value<0?4:5):(value<0?6:7);const auto previous=ledger.buttons[button];ledger.buttons[button]=1;
            sent=XTestFakeMotionEvent(state.display,-1,state.px,state.py,CurrentTime) && XTestFakeButtonEvent(state.display,button,True,CurrentTime);
            if(!sent)ledger.buttons[button]=previous;
            else if(XTestFakeButtonEvent(state.display,button,False,CurrentTime))ledger.buttons[button]=0;
            else {sent=false;ledger.active=0;ledger.stop=1;}
            XSync(state.display,False);value+=value<0?120:-120;}}
    pthread_mutex_unlock(&ledger.mutex);return sent;
}
int X11InputSink::run_release_guard(int argc,char** argv){
    if(argc!=2 || !argv || !argv[1] || std::string_view(argv[1])!="--input-release-guard=40,41,42")return -1;
    constexpr int parent=40,mapping=41,ready=42;const pid_t owner=pidfd_owner(parent);struct stat status{};
    const int seals=fcntl(mapping,F_GET_SEALS);
    if(owner<=1 || owner!=getppid() || !alive(parent) || fstat(mapping,&status)!=0 || status.st_size!=sizeof(Ledger) ||
       seals<0 || (seals&(F_SEAL_GROW|F_SEAL_SHRINK|F_SEAL_SEAL))!=(F_SEAL_GROW|F_SEAL_SHRINK|F_SEAL_SEAL))return 2;
    void* memory=mmap(nullptr,sizeof(Ledger),PROT_READ|PROT_WRITE,MAP_SHARED,mapping,0);if(memory==MAP_FAILED)return 2;
    auto& ledger=*static_cast<Ledger*>(memory);
    if(ledger.magic!=ledger_magic || ledger.owner!=owner || ledger.uid!=getuid() || !ordinary_desktop()){munmap(memory,sizeof(Ledger));return 2;}
    Display* display=XOpenDisplay(nullptr);if(!display){munmap(memory,sizeof(Ledger));return 2;}
    ledger.heartbeat=now_ms();const uint8_t acknowledged=1;if(write(ready,&acknowledged,1)!=1){XCloseDisplay(display);munmap(memory,sizeof(Ledger));return 2;}close(ready);
    for(;;){const auto heartbeat=ledger.heartbeat.load(),now=now_ms();const bool stop=ledger.stop.load()!=0,live=alive(parent),expired=now<heartbeat || now-heartbeat>=guard_timeout_ms;
        if(stop || !live || expired){ledger.active=0;
            if(!stop && live && expired)(void)syscall(SYS_pidfd_send_signal,parent,SIGKILL,nullptr,0);
            if(!lock_ledger(ledger,100)){
                // This pidfd was verified against getppid before acknowledging
                // startup. It can never address a recycled or caller-chosen pid.
                if(live)(void)syscall(SYS_pidfd_send_signal,parent,SIGKILL,nullptr,0);
                std::this_thread::sleep_for(std::chrono::milliseconds(25));continue;}
            const bool empty=release(ledger,display);pthread_mutex_unlock(&ledger.mutex);if(empty)break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    XCloseDisplay(display);munmap(memory,sizeof(Ledger));close(parent);close(mapping);return 0;
}
}
#endif
