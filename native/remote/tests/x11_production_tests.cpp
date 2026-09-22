#include "../src/platform/x11_session.hpp"
#include <cstdio>
#include <cstdlib>

int main(){
    // Run only under the isolated CI Xvfb session. A production platform object
    // must reject its missing logind session despite the testing environment.
    if(!std::getenv("HT_RD_XVFB_ISOLATED_TEST") || !ht::rd::x11_initialize_threads())return 2;
    if(ht::rd::x11_ordinary_desktop())return 3;
    std::puts("X11 production gate rejects test-only Xvfb environment without an active native logind session");
    return 0;
}
