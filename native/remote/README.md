# Remote desktop native core (development)

This directory contains the shared C++20 ABI, binary framing/UTF-8 validation,
proof transcript encoder, and independently tested session safety gates for the
8.0 remote desktop work. It **does not currently implement a working remote
desktop host/controller**. `ht_rd_get_capabilities` and the worker truthfully
return `available=false`, `RD_BACKEND_UNAVAILABLE`. No UI/API path can bypass
that result by asserting that an unverified peer is trusted.

Implemented and tested:

- Server-owned message registry snapshots with generation/digest checks; exact
  big-endian framing, bounds, reserved flags, channel/type and epoch validation.
- The shared `ht-rd-proof-v1` transcript vector, and actual Windows CNG ES256
  raw-signature verification against the server-owned public vector and its
  corruptions. Other native crypto backends and the complete signed ticket/grant
  verifier are not yet wired into a media backend.
- Internal session gates requiring authenticated identity and an observed UDP
  selected pair, rejecting relay/TCP/unknown pairs and stale path revisions.
- Monotonic lease deadlines, no renewal by replay, no extension on reconnection,
  permission intersection, independent session input state, and two-second
  input heartbeat expiry. Safety tests use a recording input sink, not OS input.
  Release failures are retained as debt and retried even after close; a future
  worker must retain that sink and withhold close acknowledgement until settled.
- Fail-closed ABI lifetime/length/version handling and an inherited-pipe worker
  capability query. The worker has no network listener or arbitrary commands.

The Go `internal/remote` package provides a hash-checked worker query, four-window
session bookkeeping, account/server isolation, and bounded file/text receive
primitives. These primitives are not a connected remote desktop UI. File receipt
requires an explicitly selected directory and accepted offer, checks offsets and
final SHA-256, and never overwrites/opens/executes a received file. Atomic
no-replace publication currently requires a filesystem supporting hard links;
unsupported filesystems return an error rather than falling back to overwriting.

## Build and test the shared core

```powershell
cmake -S native/remote -B outputs/remote-core
cmake --build outputs/remote-core --config Release
ctest --test-dir outputs/remote-core -C Release --output-on-failure
python scripts/sync-remote-contracts.py --check
python scripts/build-remote-webrtc.py
go test ./internal/remote ./internal/gui
```

Use Visual Studio 2022 on Windows; the local verified build used MSVC 19.44 and
Windows SDK 10.0.26100. Linux/macOS use their C++20 toolchains. On Linux CI, use
`-DHT_RD_SANITIZERS=ON` for ASan/UBSan. Headless Go/CLI builds do not require or
link this library.

`remote.h` is the authoritative C ABI for Android/JNI. Callers serialize release
with API calls. Release waits for active callbacks and guarantees no callback
after return; never release synchronously inside a callback, schedule it on the
owning thread instead. Callback payloads are borrowed only during the callback.
Native surfaces are retained only after a successful attachment;
an unavailable backend takes no surface reference. The owner must not throw
exceptions from callbacks. Session/epoch/grant identity will be independently
verified by the native media backend before its capability is marked available.

## Pinned WebRTC engine build

`remote-deps.lock.json` pins the actual upstream source, full DEPS digest,
depot_tools revision, clang revision/subrevision, GN flags and license digest.
The checked-in `upstream/DEPS` records every upstream git/CIPD dependency. Source
pinning is not a claim of successful media build or hardware interoperability.

The Windows x64 release engine has now been built with the pinned compiler and
SDK. `verified_builds` records its real archive hash and the scope of a passing
local media probe. Linux/macOS/Android engine builds and device interoperability
have not been established by this Windows evidence.

```powershell
python scripts/build-remote-webrtc.py --build
```

The locked upstream engine requires Windows SDK **10.0.28000.0** (servicing
package **10.0.28000.2270**); the security core above needs only SDK 26100.
For VS 2022 machines, the following prepares SHA256-pinned official Microsoft
NuGet SDK headers/tools/libraries in an isolated cache and reuses installed
MSVC through directory junctions. It does not install or register a global SDK.

```powershell
python scripts/prepare-remote-windows-sdk.py --visual-studio "C:/Program Files/Microsoft Visual Studio/2022/Community"
python scripts/build-remote-webrtc.py --build --windows-toolchain .downloads/remote-webrtc/windows-toolchain/portable-toolchain.json --jobs 4
# After sync and hooks have already succeeded, resume without refetching:
python scripts/build-remote-webrtc.py --build-existing --windows-toolchain .downloads/remote-webrtc/windows-toolchain/portable-toolchain.json --jobs 4
```

The lock records the exact upstream build-tool revision and a reviewed patch:
external SDK environment loading, the upstream runtime-directory argument type,
and skipping debugger DLL copies when producing a static engine archive only.
The patch does not alter codecs, network behavior, SDK requirements or security
checks. Applications requiring debugger runtimes must package those separately.
Compiler output is retained in `out/home_tunnel/remote-build.log`; parallel jobs
are bounded so a dependency build does not exhaust ordinary desktop memory.

Dependencies live only under `.downloads/remote-webrtc`; no machine security
policy or global Git configuration is changed. Windows depot_tools bootstrap
downloads its pinned Git/Python/CIPD tools. The process inherits the current
system network proxy if explicit proxy environment variables are absent.
Android upstream WebRTC builds require a Linux build host; use
`--target-os android --target-cpu arm64` there. A successful upstream build writes
`remote-webrtc-build.json` with the *actual* static library hash. The wrapper,
capture/codec/input adapters, signed authorization handshake, selected-pair
statistics and complete media tests still have to be integrated and verified.

`--media-probe` additionally builds `home_tunnel_webrtc_probe` with the same GN
flags and libraries. `--run-local-probe` explicitly runs its local desktop
capture -> conversion/scaling -> encoder -> two in-process PeerConnections ->
decoder/frame-sink pipeline, plus a data-channel round trip. There is no external
signaling, STUN/TURN server or input injection. The probe requires a nominated,
succeeded UDP host/host pair and connected DTLS before capturing. Its output
contains only frame counts, dimensions and transport verdicts; no screen pixels,
SDP, addresses or private keys are saved. This development probe does not enable
the product backend or constitute browser/device/network interoperability proof.

The same GN build compiles and runs the native authorization verifier using the
engine's pinned BoringSSL and JsonCpp. It checks raw ES256 signatures, strict JSON
and public JWKs, ticket/lease/grant identity and permission ceilings, including
single-session request binding. Server trust advances only from a protected
local pin through sequential old-active-key-signed rotation proofs; foreign
instances, rollback, unsigned same-version substitutions and incomplete chains
are rejected. Tests use the shared public authorization vectors and ephemeral
test signing keys. These helpers still need integration into the session worker;
passing helper tests never enables the public media capability.

## Android consumer artifact

```powershell
python scripts/package-remote-core.py --output outputs/remote-artifacts
```

This creates a deterministic source archive, C header and `remote-artifact.json`
with source-tree/archive/header/lock hashes. Uncommitted source is explicitly
identified by `source_tree_dirty=true`; consumers pin the archive hash and must
not treat the repository HEAD as the archive identity.

To package an NDK-built library, pass `--library <path>/libhome_tunnel_remote.so
--target arm64-v8a` (or `x86_64`). Output layout is
`include/home_tunnel/remote.h`, `<abi>/libhome_tunnel_remote.so`, and
`<abi>/remote-artifact.json`. Build the extracted `native/remote` with the NDK
CMake toolchain, `-DBUILD_TESTING=OFF -DHT_RD_BUILD_WORKER=OFF`. The security-only
library continues to advertise unavailable; loading an ABI library alone never
means that video/audio, platform capture/input, or microphone injection works.

## Outstanding release gates

Still required: actual libwebrtc integration; signed lease/peer verification in
the native worker; real Windows/macOS/X11/Wayland capture, input, render and codec
adapters; controller/host account and authorization flow; native viewing windows;
system audio and virtual microphone implementation/signing; connected clipboard
and file UI; AV1/HEVC capability verification; signed worker packaging and upgrade
coordination; the plan's real-device/network/long-running test evidence. No 8.0
stable release or all-platform support claim is justified by this core alone.
