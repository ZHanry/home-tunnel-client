#include "home_tunnel/remote.h"
#include "protocol.hpp"
#include "session_gate.hpp"
#include "crypto.hpp"
#include "../generated/test_vectors.hpp"
#if defined(_WIN32)
#include "platform/windows_input.hpp"
#endif
#include <array>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <future>
#include <thread>
#include <tuple>
#include <string>
#include <vector>

using namespace ht::rd;
#define CHECK(expression) do { if (!(expression)) { std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #expression); std::exit(1); } } while (false)
namespace {
struct Sink : InputSink {
    std::vector<std::tuple<uint16_t, bool, bool>> calls;
    std::vector<std::pair<uint8_t,bool>> buttons;
    uint16_t pointer_x=0, pointer_y=0;
    bool fail = false;
    unsigned motions=0,wheels=0;
    std::vector<std::string> texts;
    bool key(uint16_t code, bool down, bool repeat) override { calls.emplace_back(code, down, repeat); return !fail; }
    bool button(uint8_t button, bool down) override { buttons.emplace_back(button,down);return !fail; }
    bool pointer(uint16_t, uint16_t x, uint16_t y) override { ++motions;pointer_x=x;pointer_y=y;return !fail; }
    bool wheel(int32_t,int32_t) override { ++wheels;return !fail; }
    bool text(std::string_view value) override { texts.emplace_back(value);return !fail; }
};
void put32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
    for (unsigned n=0; n<4; ++n) bytes.at(offset+n) = static_cast<uint8_t>(value >> (24-n*8));
}
std::vector<uint8_t> key(uint32_t epoch=1, uint32_t input=1, uint32_t sequence=1, bool down=true) {
    std::vector<uint8_t> bytes{0x52,0x44,1,0x20,0,0,0,24,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,8,0,7,0,0xe0,1,0,0,0};
    put32(bytes,8,epoch);put32(bytes,12,input);put32(bytes,16,sequence);bytes[28]=down ? 1 : 0;
    return bytes;
}
void ready(SessionGate& session, uint64_t now=1000, uint64_t scopes=protocol::PERMISSION_VIEW|protocol::PERMISSION_INPUT_KEYBOARD) {
    CHECK(session.authorize({1,1,scopes,100000,1000000},100000,now)==GateResult::ok);
    CHECK(!session.media_allowed());
    CHECK(session.peer_authenticated(1,now)==GateResult::ok);
    CHECK(!session.media_allowed());
    CHECK(session.selected_pair(1,{"udp",Candidate::host,Candidate::peer_reflexive,true,true,1},now)==GateResult::ok);
    CHECK(session.media_allowed());CHECK(!session.input_allowed());
    CHECK(session.first_frame(1,now)==GateResult::ok);
    CHECK(session.synchronize_input(1,1,1,now)==GateResult::ok);
}
void framing() {
    Frame frame;
    auto bytes=key();
    CHECK(parse_frame(bytes,Channel::input,1,frame)==FrameError::ok);
    for (size_t size=0;size<bytes.size();++size) CHECK(parse_frame(std::span(bytes).first(size),Channel::input,1,frame)!=FrameError::ok);
    CHECK(parse_frame(bytes,Channel::motion,1,frame)==FrameError::channel);
    CHECK(parse_frame(bytes,Channel::input,2,frame)==FrameError::epoch);
    bytes[4]=1;CHECK(parse_frame(bytes,Channel::input,1,frame)==FrameError::flags);bytes[4]=0;
    bytes[31]=1;CHECK(parse_frame(bytes,Channel::input,1,frame)==FrameError::payload);bytes[31]=0;
    put32(bytes,16,0xfffff000);CHECK(parse_frame(bytes,Channel::input,1,frame)==FrameError::sequence);
    CHECK(valid_utf8(std::array<uint8_t,7>{0xe4,0xb8,0xad,0xf0,0x9f,0x98,0x80}));
    for (const auto& invalid:std::vector<std::vector<uint8_t>>{{0xc0,0x80},{0xed,0xa0,0x80},{0xf4,0x90,0x80,0x80},{0xe4,0xb8},{0xff}}) CHECK(!valid_utf8(invalid));
    // Bounded exhaustive single-byte mutations exercise every header field and truncated payload.
    const auto original=key();
    for (size_t i=0;i<original.size();++i) for (unsigned value=0;value<256;++value) {
        bytes=original;bytes[i]=static_cast<uint8_t>(value);
        (void)parse_frame(bytes,Channel::input,1,frame);
    }
}
void watchdog_and_epoch() {
    Sink sink;SessionGate session(sink);ready(session);
    CHECK(session.accept_key(key(),1001)==GateResult::ok);
    CHECK(sink.calls.size()==1);
    CHECK(session.tick(2499)==GateResult::ok);CHECK(session.input_allowed());
    CHECK(session.tick(2500)==GateResult::ok);CHECK(!session.input_allowed());
    CHECK(sink.calls.size()==2 && !std::get<1>(sink.calls.back()));
    CHECK(session.accept_key(key(1,1,2),3001)==GateResult::state);
    CHECK(session.synchronize_input(1,1,1,3002)==GateResult::state);
    CHECK(session.synchronize_input(1,2,1,3002)==GateResult::ok);
    CHECK(session.accept_key(key(1,1,1),3003)==GateResult::replay);
    CHECK(session.accept_key(key(1,2,1),3003)==GateResult::replay);
    CHECK(session.accept_key(key(1,2,2),3003)==GateResult::ok);
    const auto deadline=session.deadline_ms();
    CHECK(session.reconnect(2,3004)==GateResult::ok);CHECK(session.deadline_ms()==deadline);
    CHECK(!session.media_allowed() && !session.input_allowed());
    CHECK(session.peer_authenticated(1,3005)==GateResult::identity);
    CHECK(session.tick(deadline)==GateResult::expired);
    CHECK(session.renew({2,2,3,1000000,1900000},1000000,deadline)==GateResult::closed);
}
void heartbeat_replay_cannot_hold_input() {
    Sink sink;SessionGate session(sink);ready(session);
    CHECK(session.accept_key(key(),1001)==GateResult::ok);
    // Normal quarter-second heartbeats keep a held key alive across several
    // watchdog windows. Replaying the last sequence cannot renew that hold.
    for(uint64_t sequence=1;sequence<=8;++sequence){
        const auto now=1000+sequence*250;
        CHECK(session.heartbeat(1,1,sequence,now)==GateResult::ok);
        CHECK(session.tick(now+200)==GateResult::ok && session.input_allowed());
    }
    CHECK(session.heartbeat(1,1,8,4250)==GateResult::replay);
    CHECK(session.tick(4500)==GateResult::ok && !session.input_allowed());
    CHECK(sink.calls.size()==2 && !std::get<1>(sink.calls.back()));
}
void network_gate() {
    for (const auto candidate: {Candidate::relay,Candidate::unknown}) {
        Sink sink;SessionGate session(sink);ready(session);
        CHECK(session.accept_key(key(),1001)==GateResult::ok);
        CHECK(session.selected_pair(1,{"udp",Candidate::host,candidate,true,true,2},1002)==GateResult::path);
        CHECK(!session.media_allowed() && !session.input_allowed());CHECK(sink.calls.size()==2);
        CHECK(session.selected_pair(1,{"udp",Candidate::host,Candidate::host,true,true,1},1003)==GateResult::replay);
    }
    Sink sink;SessionGate session(sink);ready(session);
    CHECK(session.selected_pair(1,{"tcp",Candidate::host,Candidate::host,true,true,2},1002)==GateResult::path);
    CHECK(!session.media_allowed());
    CHECK(session.selected_pair(1,{"udp",Candidate::host,Candidate::host,false,true,3},1003)==GateResult::path);
    CHECK(session.selected_pair(1,{"udp",Candidate::host,Candidate::host,true,true,4},1004)==GateResult::ok);
    CHECK(!session.input_allowed());
}
void button_coordinates_and_watchdog() {
    Sink sink;SessionGate session(sink);ready(session,1000,7);
    auto bytes=key();bytes.resize(56,0);bytes[3]=protocol::BUTTON;put32(bytes,20,32);
    put32(bytes,24,1);bytes[28]=0;bytes[29]=0;bytes[30]=0x80;bytes[31]=0;bytes[32]=0x40;bytes[33]=0;bytes[34]=1;bytes[35]=1;
    CHECK(session.accept_button(bytes,1001)==GateResult::ok);
    CHECK(sink.pointer_x==32768 && sink.pointer_y==16384 && sink.buttons.size()==1 && sink.buttons.back().second);
    CHECK(session.tick(3000)==GateResult::ok);
    CHECK(sink.buttons.size()==2 && !sink.buttons.back().second);
    CHECK(session.accept_button(bytes,3001)==GateResult::state);
}
void pointer_wheel_text_and_release() {
    Sink sink;SessionGate session(sink);ready(session,1000,15);
    const auto make=[](uint8_t type,uint32_t length,uint32_t sequence) {
        auto value=key(1,1,sequence);value.resize(24);value.resize(24+length,0);value[3]=type;put32(value,20,length);return value;
    };
    auto motion=make(protocol::POINTER_ABS,16,1);put32(motion,24,1);motion[30]=0x80;motion[32]=0x40;put32(motion,36,1);
    CHECK(session.accept_pointer(motion,1001)==GateResult::ok && sink.pointer_x==32768 && sink.motions==1);
    CHECK(session.accept_pointer(motion,1002)==GateResult::replay && sink.motions==1);
    auto wheel=make(protocol::WHEEL,24,1);put32(wheel,24,1);put32(wheel,36,120);put32(wheel,40,static_cast<uint32_t>(-120));put32(wheel,44,2);
    CHECK(session.accept_wheel(wheel,1003)==GateResult::ok && sink.wheels==1);
    put32(motion,16,2);CHECK(session.accept_pointer(motion,1004)==GateResult::replay);
    put32(motion,36,3);CHECK(session.accept_pointer(motion,1005)==GateResult::ok);
    const std::string content="\xe4\xb8\xad\xe6\x96\x87";
    auto text=make(protocol::TEXT_COMMIT,static_cast<uint32_t>(20+content.size()),2);
    text[24]=1;put32(text,40,static_cast<uint32_t>(content.size()));std::copy(content.begin(),content.end(),text.begin()+44);
    CHECK(session.accept_text(text,1006)==GateResult::ok && sink.texts.size()==1 && sink.texts[0]==content);
    put32(text,16,3);CHECK(session.accept_text(text,1007)==GateResult::replay && sink.texts.size()==1);
    auto changed=text;put32(changed,16,4);changed.back()=0x80;
    CHECK(session.accept_text(changed,1008)==GateResult::malformed && sink.texts.size()==1);
    session.release_control();CHECK(session.media_allowed() && !session.input_allowed());
    CHECK(session.synchronize_input(1,2,1,1009)==GateResult::ok);
    put32(motion,12,2);put32(motion,16,3);put32(motion,36,1);
    CHECK(session.accept_pointer(motion,1009)==GateResult::ok);
    put32(text,12,2);put32(text,16,4);CHECK(session.accept_text(text,1010)==GateResult::replay && sink.texts.size()==1);
    put32(text,16,5);text[24]=2;sink.fail=true;CHECK(session.accept_text(text,1011)==GateResult::backend);
    sink.fail=false;CHECK(session.synchronize_input(1,3,1,1012)==GateResult::ok);
    put32(text,12,3);put32(text,16,6);CHECK(session.accept_text(text,1013)==GateResult::backend && sink.texts.size()==2);
    Sink viewer;SessionGate view(viewer);ready(view,1000,1);
    CHECK(view.accept_pointer(motion,1001)==GateResult::permission);
    CHECK(view.accept_wheel(wheel,1001)==GateResult::permission);
    CHECK(view.accept_text(text,1001)==GateResult::permission && viewer.texts.empty());
}
void rejected_release_blocks_reenable() {
    Sink sink;SessionGate session(sink);ready(session);
    CHECK(session.accept_key(key(),1001)==GateResult::ok);
    sink.fail=true;
    CHECK(session.tick(3000)==GateResult::ok);
    CHECK(!session.input_allowed());
    CHECK(session.synchronize_input(1,2,1,3001)==GateResult::backend);
    sink.fail=false;
    CHECK(session.tick(3002)==GateResult::ok);
    CHECK(session.synchronize_input(1,2,1,3003)==GateResult::ok);
    CHECK(session.accept_key(key(1,2,2),3004)==GateResult::ok);
    sink.fail=true;session.close();CHECK(session.input_releases_pending());
    CHECK(session.tick(3005)==GateResult::closed && session.input_releases_pending());
    sink.fail=false;CHECK(session.tick(3006)==GateResult::closed && !session.input_releases_pending());
}
void lease_and_isolation() {
    Sink first,second;SessionGate a(first),b(second);ready(a);ready(b);
    CHECK(a.accept_key(key(),1001)==GateResult::ok);
    CHECK(b.accept_key(key(),1001)==GateResult::ok);
    a.close();CHECK(!a.media_allowed() && b.input_allowed());CHECK(first.calls.size()==2 && second.calls.size()==1);
    const auto deadline=b.deadline_ms();
    CHECK(b.renew({1,1,3,100100,1000100},100100,1100)==GateResult::identity);
    CHECK(b.deadline_ms()==deadline);
    CHECK(b.renew({1,2,protocol::ALL_PERMISSIONS,100100,1000100},100100,1100)==GateResult::identity);
    CHECK(b.renew({1,2,protocol::PERMISSION_VIEW,100100,1000100},100100,1100)==GateResult::ok);
    CHECK(!b.input_allowed() && second.calls.size()==2);
    CHECK(b.tick(1099)==GateResult::expired); // Monotonic clock rollback cannot extend a lease.
    Sink readonly;SessionGate c(readonly);ready(c,1000,protocol::PERMISSION_VIEW);
    CHECK(c.accept_key(key(),1001)==GateResult::permission);CHECK(readonly.calls.empty());
}
void abi_contract() {
    CHECK(ht_rd_abi_version()==1);
    ht_rd_handle handle=99;
    ht_rd_config_v1 config{sizeof(config),1,1,0};
    ht_rd_callbacks_v1 callbacks{sizeof(callbacks),1,nullptr,nullptr};
    config.abi_version=2;CHECK(ht_rd_create(&config,&callbacks,&handle)==HT_RD_ABI_MISMATCH && handle==0);config.abi_version=1;
    CHECK(ht_rd_create(&config,&callbacks,&handle)==HT_RD_OK && handle!=0);
    ht_rd_capabilities_v1 capabilities{};capabilities.size=sizeof(capabilities);capabilities.abi_version=1;
    CHECK(ht_rd_get_capabilities(handle,&capabilities)==HT_RD_OK);
    CHECK(!capabilities.available && !capabilities.can_host && capabilities.reason==HT_RD_BACKEND_UNAVAILABLE);
    const std::array<uint8_t,1> fake{0};CHECK(ht_rd_start(handle,fake.data(),fake.size())==HT_RD_BACKEND_UNAVAILABLE);
    CHECK(ht_rd_start(handle,nullptr,1)==HT_RD_INVALID_ARGUMENT);
    CHECK(ht_rd_close(handle,0)==HT_RD_OK);CHECK(ht_rd_close(handle,0)==HT_RD_OK);
    CHECK(ht_rd_submit_input(handle,fake.data(),fake.size())==HT_RD_STATE_CONFLICT);
    ht_rd_release(handle);ht_rd_release(handle);
    CHECK(ht_rd_get_capabilities(handle,&capabilities)==HT_RD_INVALID_HANDLE);
}
void callback_quiescence() {
    struct Context { std::promise<void> entered; std::shared_future<void> proceed; } context;
    std::promise<void> proceed;
    context.proceed=proceed.get_future().share();
    auto entered=context.entered.get_future();
    ht_rd_config_v1 config{sizeof(config),1,1,0};
    ht_rd_callbacks_v1 callbacks{sizeof(callbacks),1,[](void* data,const ht_rd_event_v1*) {
        auto& state=*static_cast<Context*>(data);
        state.entered.set_value();state.proceed.wait();
    },&context};
    ht_rd_handle handle=0;CHECK(ht_rd_create(&config,&callbacks,&handle)==HT_RD_OK);
    auto notify=std::async(std::launch::async,[&] { return ht_rd_pause(handle,0); });
    CHECK(entered.wait_for(std::chrono::seconds(2))==std::future_status::ready);
    auto release=std::async(std::launch::async,[&] { ht_rd_release(handle); });
    ht_rd_capabilities_v1 capabilities{};capabilities.size=sizeof(capabilities);capabilities.abi_version=1;
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
    while(ht_rd_get_capabilities(handle,&capabilities)!=HT_RD_INVALID_HANDLE && std::chrono::steady_clock::now()<deadline) std::this_thread::yield();
    CHECK(ht_rd_get_capabilities(handle,&capabilities)==HT_RD_INVALID_HANDLE);
    CHECK(release.wait_for(std::chrono::seconds(0))==std::future_status::timeout);
    proceed.set_value();
    CHECK(notify.get()==HT_RD_OK);release.get();
    CHECK(ht_rd_pause(handle,0)==HT_RD_INVALID_HANDLE);
}
void transcript() {
    std::array<uint8_t,16> id{};std::array<std::array<uint8_t,32>,5> fields{};
    const auto bytes=proof_transcript(id,7,fields);
    CHECK(bytes.size()==222 && read_u32(bytes,0)==14);
    CHECK(read_u32(bytes,18)==16 && read_u32(bytes,38)==7 && read_u32(bytes,42)==32);
    CHECK(bytes!=proof_transcript(id,8,fields));
    id={0x00,0x11,0x22,0x33,0x44,0x55,0x46,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
    for(size_t n=0;n<fields.size();++n) for(size_t i=0;i<32;++i) fields[n][i]=static_cast<uint8_t>(n*32+i);
    const auto actual=proof_transcript(id,3,fields);
    std::string hex;
    for (auto byte:actual) { hex.push_back("0123456789abcdef"[byte>>4]);hex.push_back("0123456789abcdef"[byte&15]); }
    CHECK(hex==protocol::PROOF_VECTOR_HEX);
}
std::vector<uint8_t> decode_hex(std::string_view hex) {
    const auto digit=[](char c)->uint8_t { return static_cast<uint8_t>(c<='9' ? c-'0' : c-'a'+10); };
    std::vector<uint8_t> result;
    for(size_t n=0;n<hex.size();n+=2) result.push_back(static_cast<uint8_t>((digit(hex[n])<<4)|digit(hex[n+1])));
    return result;
}
void signature_verification() {
    auto transcript=decode_hex(protocol::PROOF_VECTOR_HEX);
    const auto key_bytes=decode_hex(protocol::PROOF_PUBLIC_KEY_HEX),signature_bytes=decode_hex(protocol::PROOF_SIGNATURE_HEX);
    std::array<uint8_t,64> key{},signature{};
    std::copy(key_bytes.begin(),key_bytes.end(),key.begin());std::copy(signature_bytes.begin(),signature_bytes.end(),signature.begin());
#if defined(_WIN32)
    CHECK(verify_p256(transcript,key,signature)==CryptoResult::valid);
    transcript[17]^=1;CHECK(verify_p256(transcript,key,signature)==CryptoResult::invalid);transcript[17]^=1;
    signature[3]^=1;CHECK(verify_p256(transcript,key,signature)==CryptoResult::invalid);signature[3]^=1;
    key.fill(0);CHECK(verify_p256(transcript,key,signature)==CryptoResult::invalid);
#else
    CHECK(verify_p256(transcript,key,signature)==CryptoResult::unavailable);
#endif
}
}
int main() {
    framing();watchdog_and_epoch();heartbeat_replay_cannot_hold_input();network_gate();button_coordinates_and_watchdog();pointer_wheel_text_and_release();rejected_release_blocks_reenable();lease_and_isolation();abi_contract();callback_quiescence();transcript();signature_verification();
#if defined(_WIN32)
    CHECK(WindowsInputSink::scan_code(4)==0x1e && WindowsInputSink::scan_code(224)==0x1d && WindowsInputSink::scan_code(228)==0xe01d);
    CHECK(WindowsInputSink::scan_code(0)==0 && WindowsInputSink::scan_code(300)==0);
#endif
    std::puts("Remote core: framing, transcript, UDP path, lease, watchdog, isolation and fail-closed ABI passed");
}
