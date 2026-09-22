#include "clipboard.hpp"
#include "peer_identity.hpp"
#include "openssl/mem.h"
#include "openssl/rand.h"
#include <algorithm>
#include <limits>

namespace ht::rd {
namespace {
void wipe(std::string& value){if(!value.empty())OPENSSL_cleanse(value.data(),value.size());value.clear();}
std::string digest(std::string_view value){
  const auto bytes=auth::digest(value);constexpr std::string_view hex="0123456789abcdef";std::string result;
  for(const auto byte:bytes){result+=hex[byte>>4];result+=hex[byte&15];}return result;
}
bool fields(const Json::Value& body,std::initializer_list<std::string_view> keys){
  if(!body.isObject() || body.size()!=keys.size())return false;
  for(const auto key:keys)if(!body.isMember(std::string(key)))return false;return true;
}
bool id(const Json::Value& body,std::array<uint8_t,16>& uuid){return body["id"].isString() && PeerIdentity::uuid(body["id"].asString(),uuid);}
bool hex_digest(const Json::Value& value){
  if(!value.isString() || value.asString().size()!=64)return false;
  const auto text=value.asString();return std::all_of(text.begin(),text.end(),[](char c){return (c>='0'&&c<='9') || (c>='a'&&c<='f');});
}
bool plain_text(std::string_view value){return value.find('\0')==std::string_view::npos && valid_utf8({reinterpret_cast<const uint8_t*>(value.data()),value.size()});}
std::string new_id(std::array<uint8_t,16>& bytes){
  if(!RAND_bytes(bytes.data(),bytes.size()))return {};bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
  constexpr std::string_view hex="0123456789abcdef";std::string value;
  for(size_t n=0;n<bytes.size();++n){if(n==4 || n==6 || n==8 || n==10)value+='-';value+=hex[bytes[n]>>4];value+=hex[bytes[n]&15];}return value;
}
}
ClipboardTransfer::ClipboardTransfer(ClipboardStorage& storage,Send send,Room room,Failure failure)
  :storage_(storage),send_(std::move(send)),room_(std::move(room)),failure_(std::move(failure)){}
ClipboardTransfer::Transfer::~Transfer(){wipe(content);}
ClipboardTransfer::~ClipboardTransfer(){close();}
bool ClipboardTransfer::enabled(std::string_view permission)const{return !closed_ && (permission=="clipboard.read"?read_:permission=="clipboard.write"?write_:false);}
bool ClipboardTransfer::enable(std::string_view permission,bool value,uint64_t now){
  if(closed_ || (value && !storage_.available()))return false;
  if(permission=="clipboard.read"){read_=value;outgoing_.reset();if(value){sequence_=0;next_poll_=now;}}
  else if(permission=="clipboard.write"){write_=value;incoming_.reset();}
  else return false;
  if(!read_ && !write_){last_digest_.clear();seen_.clear();}return true;
}
void ClipboardTransfer::close(){closed_=true;read_=write_=false;incoming_.reset();outgoing_.reset();last_digest_.clear();seen_.clear();}
void ClipboardTransfer::fail(std::string_view permission){enable(permission,false,0);failure_(permission);}
void ClipboardTransfer::remember(std::string value){seen_.push_back(std::move(value));if(seen_.size()>128)seen_.pop_front();}
bool ClipboardTransfer::send_json(uint8_t type,const Json::Value& body){const auto value=PeerIdentity::json(body);return send_(type,{reinterpret_cast<const uint8_t*>(value.data()),value.size()});}
bool ClipboardTransfer::finish_receive(){
  if(!incoming_ || !write_)return false;
  if(digest(incoming_->content)!=incoming_->digest || !plain_text(incoming_->content))return false;
  const auto transfer_id=incoming_->id, hash=incoming_->digest;
  if(!storage_.write(incoming_->content)){fail("clipboard.write");return true;}
  last_digest_=hash;remember(transfer_id);incoming_.reset();Json::Value ack;ack["id"]=transfer_id;return send_json(protocol::CLIPBOARD_ACK,ack);
}
bool ClipboardTransfer::receive(uint8_t type,std::span<const uint8_t> payload,uint64_t now){
  if(closed_)return false;
  const bool incoming=type==protocol::CLIPBOARD_OFFER || type==protocol::CLIPBOARD_CHUNK;
  if(incoming_ && now>=incoming_->deadline)fail("clipboard.write");
  if(outgoing_ && now>=outgoing_->deadline)fail("clipboard.read");
  if(closed_)return false;
  // A control-channel revoke may race with an already queued clipboard frame.
  if(incoming?!write_:!read_)return true;
  if(type==protocol::CLIPBOARD_CHUNK){
    if(!incoming_ || payload.size()<=24 || payload.size()>16360 ||
       !std::equal(incoming_->uuid.begin(),incoming_->uuid.end(),payload.begin()) ||
       read_u64(payload,16)!=incoming_->offset || payload.size()-24>incoming_->size-incoming_->offset)return false;
    const auto content=payload.subspan(24);incoming_->content.append(reinterpret_cast<const char*>(content.data()),content.size());incoming_->offset+=content.size();
    return incoming_->offset==incoming_->size?finish_receive():true;
  }
  Json::Value body;if(!auth::strict_json(std::string_view(reinterpret_cast<const char*>(payload.data()),payload.size()),body,16360) || !body.isObject())return false;
  std::array<uint8_t,16> uuid{};if(!id(body,uuid))return false;const auto transfer_id=body["id"].asString();
  if(type==protocol::CLIPBOARD_OFFER){
    if(!fields(body,{"id","size","sha256","mime"}) || !body["size"].isUInt() || body["size"].asUInt()>protocol::CLIPBOARD_BYTES ||
       !hex_digest(body["sha256"]) || body["mime"]!="text/plain;charset=utf-8" || incoming_ || std::find(seen_.begin(),seen_.end(),transfer_id)!=seen_.end())return false;
    incoming_=std::make_unique<Transfer>();auto& item=*incoming_;item.id=transfer_id;item.uuid=uuid;item.digest=body["sha256"].asString();item.size=body["size"].asUInt();item.deadline=now+30000;
    item.content.reserve(item.size);const bool empty=item.size==0;Json::Value accept;accept["id"]=transfer_id;if(!send_json(protocol::CLIPBOARD_ACCEPT,accept) || closed_)return false;
    return empty?finish_receive():true;
  }
  if(!fields(body,{"id"}) || !outgoing_ || outgoing_->id!=transfer_id)return false;
  if(type==protocol::CLIPBOARD_ACCEPT){if(outgoing_->accepted)return false;outgoing_->accepted=true;return true;}
  if(type==protocol::CLIPBOARD_ACK){
    if(!outgoing_->accepted || outgoing_->offset!=outgoing_->size)return false;
    last_digest_=outgoing_->digest;remember(transfer_id);outgoing_.reset();return true;
  }
  return false;
}
void ClipboardTransfer::tick(uint64_t now){
  if(closed_)return;
  if(incoming_ && now>=incoming_->deadline)fail("clipboard.write");
  if(outgoing_ && now>=outgoing_->deadline)fail("clipboard.read");
  if(closed_)return;
  if(outgoing_ && outgoing_->accepted){
    for(unsigned n=0;n<2 && outgoing_ && outgoing_->offset<outgoing_->size && room_();++n){
      auto& item=*outgoing_;const auto count=std::min(size_t{8192},item.size-item.offset);std::vector<uint8_t> chunk(24+count);
      std::copy(item.uuid.begin(),item.uuid.end(),chunk.begin());for(unsigned i=0;i<8;++i)chunk[16+i]=static_cast<uint8_t>(uint64_t(item.offset)>>(56-8*i));
      std::copy_n(item.content.begin()+item.offset,count,chunk.begin()+24);item.offset+=count;
      const bool sent=send_(protocol::CLIPBOARD_CHUNK,chunk);OPENSSL_cleanse(chunk.data(),chunk.size());if(!sent){fail("clipboard.read");return;}
    }
  }
  if(!read_ || outgoing_ || now<next_poll_ || !room_())return;next_poll_=now+500;
  std::string content;const auto status=storage_.read(sequence_,content);
  if(status!=ClipboardStorage::Read::text){wipe(content);return;}
  if(content.size()>protocol::CLIPBOARD_BYTES || !plain_text(content)){wipe(content);return;}
  auto hash=digest(content);if(hash==last_digest_){wipe(content);return;}
  outgoing_=std::make_unique<Transfer>();auto& item=*outgoing_;item.id=new_id(item.uuid);
  if(item.id.empty()){wipe(content);fail("clipboard.read");return;}
  item.content=content;wipe(content);item.digest=std::move(hash);item.size=item.content.size();item.deadline=now+30000;
  Json::Value offer;offer["id"]=item.id;offer["size"]=Json::UInt(item.size);offer["sha256"]=item.digest;offer["mime"]="text/plain;charset=utf-8";
  if(!send_json(protocol::CLIPBOARD_OFFER,offer))fail("clipboard.read");
}
}
