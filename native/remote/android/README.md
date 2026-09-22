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

The internal SDK contains real `libwebrtc.a` and renderer archives, source headers,
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

Until PeerConnection signaling, independent native authorization, all four data
channels, direct-UDP verification and real Surface decoding acceptance are wired
through the C ABI, Android keeps reporting `RD_MEDIA_UNAVAILABLE`. Neither this
source layer nor a successful engine build changes that capability.
