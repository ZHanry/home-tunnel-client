#include "windows_audio.hpp"
#if defined(_WIN32)
#include "windows_input.hpp"
#include "windows_user.hpp"
#include "../audio_blocks.hpp"
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <chrono>
#include <future>
#include <string>

namespace ht::rd {
namespace {
uint64_t audio_clock() {
  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count());
}
template<class T> struct ComPtr {
  T* value=nullptr;
  ~ComPtr() { if(value)value->Release(); }
  T* operator->() const { return value; }
};
struct ComScope {
  HRESULT result=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
  ~ComScope() { if(SUCCEEDED(result))CoUninitialize(); }
};
struct Loopback {
  ComPtr<IMMDeviceEnumerator> devices;
  ComPtr<IMMDevice> device;
  ComPtr<IAudioClient> client;
  ComPtr<IAudioCaptureClient> capture;
  std::wstring id;
  bool running=false;
  ~Loopback(){ if(running)client->Stop(); }
  bool initialize() {
    if(FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_INPROC_SERVER,
                               __uuidof(IMMDeviceEnumerator),reinterpret_cast<void**>(&devices.value))) ||
       FAILED(devices->GetDefaultAudioEndpoint(eRender,eMultimedia,&device.value)))return false;
    LPWSTR name=nullptr;
    if(FAILED(device->GetId(&name)) || !name)return false;
    id=name;CoTaskMemFree(name);
    if(FAILED(device->Activate(__uuidof(IAudioClient),CLSCTX_INPROC_SERVER,nullptr,
                               reinterpret_cast<void**>(&client.value))))return false;
    WAVEFORMATEX format{WAVE_FORMAT_PCM,2,48000,192000,4,16,0};
    if(FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK|AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM|AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        200000,0,&format,nullptr)))return false;
    return SUCCEEDED(client->GetService(__uuidof(IAudioCaptureClient),reinterpret_cast<void**>(&capture.value)));
  }
  bool current() {
    ComPtr<IMMDevice> current;
    if(FAILED(devices->GetDefaultAudioEndpoint(eRender,eMultimedia,&current.value)))return false;
    LPWSTR name=nullptr;
    if(FAILED(current->GetId(&name)) || !name)return false;
    const bool same=id==name;CoTaskMemFree(name);return same;
  }
};
}
bool WindowsSystemAudio::available() {
  // COM identity and the default endpoint belong to the approved user, even
  // when the owning process is SYSTEM. Never initialize under ambient SYSTEM.
  std::promise<bool> result;auto ready=result.get_future();
  std::thread probe([&]{
    UserContext user;ComScope com;Loopback device;
    result.set_value(user && SUCCEEDED(com.result) && WindowsInputSink::user_broker_allowed() && device.initialize());
  });
  probe.join();return ready.get();
}
void WindowsSystemAudio::renew() { if(!deadline_.renew(audio_clock()))failed_=true; }
bool WindowsSystemAudio::start(Consume consume) {
  stop();if(!consume)return false;
  stopping_=false;failed_=false;deadline_.begin(audio_clock());
  std::promise<bool> initialized;auto ready=initialized.get_future();
  thread_=std::thread([this,consume=std::move(consume),ready=std::move(initialized)]() mutable {
    UserContext user;ComScope com;Loopback device;
    if(!user || FAILED(com.result) || !WindowsInputSink::user_broker_allowed() || !device.initialize() ||
       stopping_ || !deadline_.alive(audio_clock()) || FAILED(device.client->Start())) {
      failed_=true;ready.set_value(false);return;
    }
    device.running=true;ready.set_value(true);
    AudioBlocks blocks;std::array<int16_t,AudioBlocks::samples> silence{};
    auto next_device_check=audio_clock()+500;
    while(!stopping_) {
      UserContext current(&user.identity());
      if(!current || !deadline_.alive(audio_clock()) || !WindowsInputSink::user_broker_allowed()) {failed_=true;break;}
      if(audio_clock()>=next_device_check) {
        if(!device.current()) {failed_=true;break;}
        next_device_check=audio_clock()+500;
      }
      UINT32 frames=0;
      if(FAILED(device.capture->GetNextPacketSize(&frames))) {failed_=true;break;}
      if(!frames) { std::this_thread::sleep_for(std::chrono::milliseconds(5));continue; }
      BYTE* bytes=nullptr;DWORD flags=0;
      if(FAILED(device.capture->GetBuffer(&bytes,&frames,&flags,nullptr,nullptr))) {failed_=true;break;}
      bool ok=frames<=48000 && (!(flags&AUDCLNT_BUFFERFLAGS_SILENT)?bytes!=nullptr:true);
      if(flags&AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)blocks.reset();
      const auto deliver=[&](std::span<const int16_t> samples) {
        if(stopping_ || !deadline_.alive(audio_clock()) || !WindowsInputSink::user_broker_allowed())return false;
        consume(samples);return true;
      };
      if(ok && (flags&AUDCLNT_BUFFERFLAGS_SILENT)) {
        size_t remaining=static_cast<size_t>(frames)*2;
        while(ok && remaining) {const auto size=std::min(remaining,silence.size());ok=blocks.append(std::span(silence).first(size),deliver);remaining-=size;}
      } else if(ok) ok=blocks.append(std::span(reinterpret_cast<const int16_t*>(bytes),static_cast<size_t>(frames)*2),deliver);
      const auto release=device.capture->ReleaseBuffer(frames);
      if(!ok || FAILED(release)) {failed_=true;break;}
    }
    blocks.reset();
  });
  const bool started=ready.get();if(!started)stop();return started;
}
void WindowsSystemAudio::stop() {
  deadline_.revoke();stopping_=true;
  if(thread_.joinable())thread_.join();
}
}
#endif
