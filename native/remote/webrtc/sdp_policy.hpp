#pragma once
#include <charconv>
#include <memory>
#include <map>
#include <sstream>
#include <set>
#include <string>
#include <string_view>

namespace ht::rd {
inline std::string_view trim_sdp_parameter(std::string_view value) {
  const auto first=value.find_first_not_of(" \t");if(first==std::string_view::npos)return {};
  return value.substr(first,value.find_last_not_of(" \t")-first+1);
}
inline bool valid_h264_fmtp(std::string_view value) {
  std::map<std::string,std::string> parameters;
  while(!value.empty()){
    const auto separator=value.find(';');const auto item=trim_sdp_parameter(value.substr(0,separator));
    const auto equals=item.find('=');if(equals==std::string_view::npos)return false;
    std::string key(trim_sdp_parameter(item.substr(0,equals))),parameter(trim_sdp_parameter(item.substr(equals+1)));
    for(auto& ch:key)if(ch>='A' && ch<='Z')ch=char(ch-'A'+'a');
    if(key.empty() || parameter.empty() || !parameters.emplace(key,parameter).second)return false;
    if(separator==std::string_view::npos)break;value.remove_prefix(separator+1);
  }
  auto profile=parameters.find("profile-level-id"),packetization=parameters.find("packetization-mode");
  if(profile==parameters.end() || packetization==parameters.end() || packetization->second!="1")return false;
  for(auto& ch:profile->second)if(ch>='A' && ch<='F')ch=char(ch-'A'+'a');
  const auto asymmetry=parameters.find("level-asymmetry-allowed");
  return profile->second=="42e01f" && (asymmetry==parameters.end() || asymmetry->second=="0" || asymmetry->second=="1");
}
// The Windows RC profile is one VP8/H264 video sender plus data channels. Codec
// preferences are set on its transceiver; a rejected (port 0) media answer is
// never treated as a working or authorized capture path.
inline bool valid_sdp_profile(std::string_view sdp,std::string_view expected_fingerprint,
                              bool (*direct_candidate)(std::string_view)) {
  if(sdp.empty() || sdp.size()>24576 || sdp.find('\0')!=std::string_view::npos)return false;
  std::istringstream input{std::string(sdp)};std::string line;bool fingerprint=false,in_video=false;unsigned video=0,data=0;std::set<unsigned> video_formats;
  std::map<unsigned,std::string> codecs,parameters;
  while(std::getline(input,line)){
    if(!line.empty() && line.back()=='\r')line.pop_back();
    if(line.starts_with("a=candidate:") && !direct_candidate(std::string_view(line).substr(2)))return false;
    if(line.starts_with("m=")){
      std::istringstream m(line);std::string media,port,protocol;m>>media>>port>>protocol;
      unsigned port_number=0;const auto end=std::to_address(port.end());const auto parsed=std::from_chars(port.data(),end,port_number);
      if(parsed.ec!=std::errc{} || parsed.ptr!=end || port_number<1 || port_number>65535)return false;
      if(media=="m=video"){
        if(++video>1 || protocol!="UDP/TLS/RTP/SAVPF")return false;in_video=true;
        std::string format;while(m>>format){unsigned id=0;const auto last=std::to_address(format.end());const auto p=std::from_chars(format.data(),last,id);if(p.ec!=std::errc{} || p.ptr!=last || id>127 || !video_formats.insert(id).second)return false;}
      }
      else if(media=="m=application"){if(++data>1 || protocol!="UDP/DTLS/SCTP")return false;in_video=false;}
      else return false;
    }
    if(in_video && line.starts_with("a=rtpmap:")){
      std::istringstream r(line.substr(9));std::string number,codec,extra;r>>number>>codec;
      unsigned id=128;const auto end=std::to_address(number.end());const auto parsed=std::from_chars(number.data(),end,id);
      if(parsed.ec!=std::errc{} || parsed.ptr!=end || !video_formats.contains(id) || codec.empty() || r>>extra || !codecs.emplace(id,codec).second)return false;
    }
    if(in_video && line.starts_with("a=fmtp:")){
      const auto body=std::string_view(line).substr(7);const auto separator=body.find_first_of(" \t");
      if(separator==std::string_view::npos)return false;const auto number=body.substr(0,separator);
      unsigned id=128;const auto end=std::to_address(number.end());const auto parsed=std::from_chars(number.data(),end,id);
      const auto value=trim_sdp_parameter(body.substr(separator+1));
      if(parsed.ec!=std::errc{} || parsed.ptr!=end || !video_formats.contains(id) || value.empty() || !parameters.emplace(id,value).second)return false;
    }
    if(line.starts_with("a=fingerprint:")){
      std::istringstream f(line.substr(14));std::string algorithm,value;f>>algorithm>>value;
      if(algorithm!="sha-256" || value.size()!=95 || (!expected_fingerprint.empty() && value!=expected_fingerprint))return false;
      fingerprint=true;
    }
  }
  bool supported=false;
  for(const auto& [id,codec]:codecs){
    if(codec=="VP8/90000" || codec=="vp8/90000")supported=true;
    if((codec=="H264/90000" || codec=="h264/90000") && parameters.contains(id) && valid_h264_fmtp(parameters.at(id)))supported=true;
  }
  return fingerprint && video==1 && data==1 && supported;
}
}
