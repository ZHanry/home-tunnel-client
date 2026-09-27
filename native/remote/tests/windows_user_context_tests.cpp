#include "../src/platform/windows_user.hpp"
#include <cstdio>
#include <thread>

using namespace ht::rd;
int main() {
    const auto identity=process_identity();
    if(!identity.valid || identity.system) return 1; // Run as an ordinary test user.
    if(!identity.same_user(identity) || user_context_available()==false) return 2;
    auto other=identity;other.session++;
    if(identity.same_user(other)) return 3;
    other=identity;other.logon.LowPart++;
    if(identity.same_user(other)) return 4;
    other=identity;other.system=true;
    if(identity.same_user(other)) return 5;
    { UserContext wrong(&other);if(wrong)return 6; }
    { UserContext outer(&identity);UserContext nested(&identity);if(!outer || !nested)return 7; }
    // A real existing, foreign thread token must be rejected, not mistaken for
    // a successful approved-user impersonation. No desktop input is injected.
    if(!ImpersonateAnonymousToken(GetCurrentThread())) return 8;
    bool rejected=false;
    { UserContext foreign;rejected=!foreign; }
    if(!RevertToSelf()) return 9;
    if(!rejected || !user_context_available()) return 10;
    if(adopt_user_token(nullptr,identity.session)) return 11;
    bool callback_ok=false;
    std::thread callback([&]{UserContext context(&identity);callback_ok=bool(context);});
    callback.join();
    if(!callback_ok) return 12;
    std::puts("identity, nested context, foreign-token denial and callback checks passed");
    return 0;
}
