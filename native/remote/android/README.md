# Android controller media build

`scripts/build-remote-android-webrtc.py --build` uses a Linux x64 host to fetch the
same immutable WebRTC revision as the Windows host and compile Android arm64 at
API 26. It additionally compiles a real `VideoSinkInterface` implementation that
retains `ANativeWindow` ownership, applies video rotation and posts RGBA pixels.
Surface attachment generations are monotonic; detach/close serialize against
frame presentation. Rendering starts disabled and is intended to be enabled only
after the native controller has independently verified identity, lease and UDP.

The recipe pins the upstream dependency-lock hash and exact GN arguments. Android
currently enables software codecs and disables optional H.264/HEVC, internal audio
device capture and upstream examples/tools. This does not claim hardware decoding,
audio or any codec/device interoperability.

The internal SDK contains real `libwebrtc.a`, renderer archives, a shared C ABI
controller, source headers,
dependency notices, source revisions, GN configuration and a SHA-256 inventory.
Run `--verify-artifact <directory>` after transferring it. Every library object must
be AArch64. The source checkout must be clean; unknown dependency licenses or
modified pinned sources fail packaging. A build is not real decoding evidence.

Do not link this C++ archive directly into the NDK 27 JNI wrapper. The controller
and WebRTC must be compiled together inside this GN build, with the same Chromium
Clang/libc++ ABI. The app communicates with that shared library only through
`home_tunnel/remote.h`; no C++ types, exceptions or ownership cross that boundary.
The app's existing JNI NDK remains 27.2.12479018. The final shared-library packaging
must also verify 16 KiB ELF segment alignment and the exact exported C symbols.

The shared controller implements PeerConnection signaling, independent native
ticket/lease/grant verification, five data channels including text clipboard, mutual identity proofs,
direct-UDP statistics checks, Surface presentation and synchronized input. Lease
deadlines are enforced on every rendered frame and input operation. It reports
backend availability only when that implementation is linked. The default app
security-core build continues to report `RD_MEDIA_UNAVAILABLE`.

The clipboard channel is scoped to the signed session and feature acknowledgement.
Only foreground Android plain text is synchronized; backgrounding disables both
directions. Rebuild the exact same-source arm64 and emulator SDKs before claiming
clipboard support in an installable APK.

Artifact metadata keeps `available:false` and `device_media_accepted:false` until
physical-device acceptance is recorded; `controller_backend_linked:true` records
only the existence of the real implementation. Successful compilation is not
evidence of remote frames actually decoded and presented on a device. The arm64
shared library must pass ELF/C ABI checks before an app may import it.
