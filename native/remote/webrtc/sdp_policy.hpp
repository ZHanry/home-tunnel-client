#pragma once
#include <charconv>
#include <memory>
#include <sstream>
#include <set>
#include <string>
#include <string_view>

namespace ht::rd {
// The Windows RC profile is one VP8 video sender plus data channels. Codec
// preferences are set on its transceiver; a rejected (port 0) media answer is
// never treated as a working or authorized capture path.
inline bool valid_sdp_profile(std::string_view sdp,std::string_view expected_fingerprint,
                              bool (*direct_candidate)(std::string_view)) {
  if(sdp.empty() || sdp.size()>24576 || sdp.find('\0')!=std::string_view::npos)return false;
  std::istringstream input{std::string(sdp)};std::string line;bool fingerprint=false,in_video=false,vp8=false;unsigned video=0,data=0;std::set<unsigned> video_formats;
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
      std::istringstream r(line.substr(9));unsigned id=128;std::string codec;r>>id>>codec;
      if((codec=="VP8/90000" || codec=="vp8/90000") && video_formats.contains(id))vp8=true;
    }
    if(line.starts_with("a=fingerprint:")){
      std::istringstream f(line.substr(14));std::string algorithm,value;f>>algorithm>>value;
      if(algorithm!="sha-256" || value.size()!=95 || (!expected_fingerprint.empty() && value!=expected_fingerprint))return false;
      fingerprint=true;
    }
  }
  return fingerprint && video==1 && data==1 && vp8;
}
}
