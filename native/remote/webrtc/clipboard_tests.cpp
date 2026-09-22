#include "clipboard.hpp"
#include "peer_identity.hpp"
#include <cstdio>
#include <cstdlib>
#include <algorithm>

#define REQUIRE(x) do{if(!(x)){std::fprintf(stderr,"Clipboard assertion failed at line %d\n",__LINE__);std::abort();}}while(false)
using namespace ht::rd;
namespace {
const std::string transfer_id="00112233-4455-4677-8899-aabbccddeeff";
std::string hash(std::string_view content){constexpr std::string_view hex="0123456789abcdef";std::string value;for(auto byte:auth::digest(content)){value+=hex[byte>>4];value+=hex[byte&15];}return value;}
struct Storage : ClipboardStorage {
  std::string text="local text";unsigned reads=0,writes=0;uint64_t version=1;bool fail_write=false;
  Read read(uint64_t& sequence,std::string& output)override{++reads;if(sequence==version)return Read::unchanged;sequence=version;output=text;return Read::text;}
  bool write(std::string_view value)override{++writes;if(fail_write)return false;text=value;++version;return true;}
};
struct Message {uint8_t type;std::vector<uint8_t> bytes;Json::Value json()const{Json::Value value;REQUIRE(auth::strict_json(std::string_view(reinterpret_cast<const char*>(bytes.data()),bytes.size()),value));return value;}};
struct Harness {
  Storage storage;std::vector<Message> sent;std::vector<std::string> failures;bool room=true;
  ClipboardTransfer transfer{storage,[this](uint8_t type,std::span<const uint8_t> bytes){sent.push_back({type,{bytes.begin(),bytes.end()}});return true;},[this]{return room;},[this](std::string_view permission){failures.emplace_back(permission);}};
  bool json(uint8_t type,const Json::Value& value,uint64_t now=100){const auto body=PeerIdentity::json(value);return transfer.receive(type,{reinterpret_cast<const uint8_t*>(body.data()),body.size()},now);}
  bool offer(std::string_view text,std::string digest={}){Json::Value value;value["id"]=transfer_id;value["size"]=Json::UInt(text.size());value["sha256"]=digest.empty()?hash(text):digest;value["mime"]="text/plain;charset=utf-8";return json(protocol::CLIPBOARD_OFFER,value);}
  bool chunk(std::string_view text,size_t offset=0,uint64_t now=200){std::array<uint8_t,16> id{};REQUIRE(PeerIdentity::uuid(transfer_id,id));std::vector<uint8_t> payload(24+text.size());std::copy(id.begin(),id.end(),payload.begin());for(unsigned i=0;i<8;++i)payload[16+i]=static_cast<uint8_t>(uint64_t(offset)>>(56-8*i));std::copy(text.begin(),text.end(),payload.begin()+24);return transfer.receive(protocol::CLIPBOARD_CHUNK,payload,now);}
  bool ack(uint8_t type,const std::string& id){Json::Value value;value["id"]=id;return json(type,value);}
};
void disabled_and_revoked(){
  Harness h;h.transfer.tick(100);REQUIRE(h.storage.reads==0 && h.sent.empty());
  REQUIRE(h.offer("remote") && h.chunk("remote"));REQUIRE(h.storage.writes==0 && h.sent.empty());
  REQUIRE(h.transfer.enable("clipboard.write",true,100));REQUIRE(h.offer("remote"));
  REQUIRE(h.transfer.enable("clipboard.write",false,100));REQUIRE(h.chunk("remote"));REQUIRE(h.storage.writes==0);
  REQUIRE(h.transfer.enable("clipboard.read",true,100));h.transfer.tick(100);REQUIRE(h.storage.reads==1 && h.sent.back().type==protocol::CLIPBOARD_OFFER);
  const auto id=h.sent.back().json()["id"].asString();h.transfer.enable("clipboard.read",false,100);
  const auto count=h.sent.size();REQUIRE(h.ack(protocol::CLIPBOARD_ACCEPT,id));h.transfer.tick(1000);REQUIRE(h.sent.size()==count);
  h.transfer.close();REQUIRE(!h.transfer.enable("clipboard.read",true,1000));h.transfer.tick(2000);REQUIRE(h.sent.size()==count);
}
void incoming_integrity_and_loop(){
  Harness h;const std::string text="\xe4\xb8\xad\xe6\x96\x87\xf0\x9f\x99\x82";
  h.transfer.enable("clipboard.write",true,100);REQUIRE(h.offer(text));REQUIRE(h.sent.back().type==protocol::CLIPBOARD_ACCEPT);
  REQUIRE(h.chunk(std::string_view(text).substr(0,2)));REQUIRE(h.storage.writes==0);
  REQUIRE(h.chunk(std::string_view(text).substr(2),2));REQUIRE(h.storage.writes==1 && h.storage.text==text && h.sent.back().type==protocol::CLIPBOARD_ACK);
  REQUIRE(!h.offer(text));const auto count=h.sent.size();
  h.transfer.enable("clipboard.read",true,100);h.transfer.tick(1000);REQUIRE(h.sent.size()==count);
  for(const auto& invalid:std::vector<std::string>{std::string("\xed\xa0\x80"),std::string("a\0b",3)}){Harness bad;bad.transfer.enable("clipboard.write",true,0);REQUIRE(bad.offer(invalid));REQUIRE(!bad.chunk(invalid));REQUIRE(bad.storage.writes==0);}
  Harness corrupt;corrupt.transfer.enable("clipboard.write",true,0);REQUIRE(corrupt.offer("abc",hash("different")));REQUIRE(!corrupt.chunk("abc"));REQUIRE(corrupt.storage.writes==0);
  Harness offset;offset.transfer.enable("clipboard.write",true,0);REQUIRE(offset.offer("abc"));REQUIRE(!offset.chunk("bc",1));REQUIRE(offset.storage.writes==0);
  Harness too_large;too_large.transfer.enable("clipboard.write",true,0);REQUIRE(!too_large.offer(std::string(protocol::CLIPBOARD_BYTES+1,'a')));
  Harness empty;empty.transfer.enable("clipboard.write",true,0);REQUIRE(empty.offer(""));REQUIRE(empty.storage.writes==1 && empty.storage.text.empty() && empty.sent.back().type==protocol::CLIPBOARD_ACK);
}
void outgoing_bounded_and_backpressure(){
  Harness h;h.storage.text=std::string(protocol::CLIPBOARD_BYTES,'a');h.transfer.enable("clipboard.read",true,100);h.room=false;h.transfer.tick(100);REQUIRE(h.storage.reads==0);
  h.room=true;h.transfer.tick(100);const auto offer=h.sent.back().json();const auto id=offer["id"].asString();REQUIRE(offer["size"].asUInt()==protocol::CLIPBOARD_BYTES && offer["sha256"].asString()==hash(h.storage.text));
  REQUIRE(!h.ack(protocol::CLIPBOARD_ACK,id));REQUIRE(h.ack(protocol::CLIPBOARD_ACCEPT,id));REQUIRE(!h.ack(protocol::CLIPBOARD_ACCEPT,id));
  h.room=false;h.transfer.tick(200);REQUIRE(h.sent.size()==1);h.room=true;
  for(uint64_t now=500;now<=2000;now+=500)h.transfer.tick(now);
  REQUIRE(h.sent.size()==9);size_t offset=0;
  for(size_t n=1;n<h.sent.size();++n){REQUIRE(h.sent[n].type==protocol::CLIPBOARD_CHUNK);const auto& bytes=h.sent[n].bytes;REQUIRE(bytes.size()==8216 && read_u64(bytes,16)==offset);offset+=bytes.size()-24;}
  REQUIRE(offset==protocol::CLIPBOARD_BYTES);REQUIRE(h.ack(protocol::CLIPBOARD_ACK,id));const auto count=h.sent.size();h.transfer.tick(3000);REQUIRE(h.sent.size()==count);
}
void failed_write_and_timeout(){
  Harness bad;bad.storage.fail_write=true;bad.transfer.enable("clipboard.write",true,0);REQUIRE(bad.offer("abc"));REQUIRE(bad.chunk("abc"));REQUIRE(!bad.transfer.enabled("clipboard.write"));REQUIRE(bad.sent.back().type!=protocol::CLIPBOARD_ACK && bad.failures.size()==1);
  Harness incoming;incoming.transfer.enable("clipboard.write",true,0);REQUIRE(incoming.offer("abc"));incoming.transfer.tick(30100);REQUIRE(!incoming.transfer.enabled("clipboard.write") && incoming.storage.writes==0);
  Harness late;late.transfer.enable("clipboard.write",true,0);REQUIRE(late.offer("abc"));REQUIRE(late.chunk("abc",0,30100));REQUIRE(!late.transfer.enabled("clipboard.write") && late.storage.writes==0);
  Harness outgoing;outgoing.transfer.enable("clipboard.read",true,0);outgoing.transfer.tick(100);outgoing.transfer.tick(30100);REQUIRE(!outgoing.transfer.enabled("clipboard.read") && outgoing.sent.size()==1);
  Harness invalid;invalid.transfer.enable("clipboard.write",true,0);Json::Value array{Json::arrayValue};REQUIRE(!invalid.json(protocol::CLIPBOARD_OFFER,array));
}
}
int main(){disabled_and_revoked();incoming_integrity_and_loop();outgoing_bounded_and_backpressure();failed_write_and_timeout();std::puts("Native clipboard protocol: explicit enable/revoke, UTF8 integrity, bounded chunks, backpressure, loop suppression and failure handling passed (no OS clipboard accessed)");}
