# Android controller media build

`scripts/build-remote-android-webrtc.py --build --abi arm64-v8a` or `--abi x86_64`
uses a Linux x64 host to fetch the same immutable WebRTC revision as the Windows
host and compile that Android ABI at API 26. Omitting `--abi` selects `arm64-v8a`.
Both ABIs compile the same unmodified native sources and `remote-deps.lock.json`;
`android-build.lock.json` is the reviewed matrix and only `target_cpu` changes.
Do not patch `BUILD.gn` or rewrite GN arguments for the emulator. The security-core
NDK library from `scripts/package-remote-core.py` is not this controller.

The build compiles a real `VideoSinkInterface` implementation that retains
`ANativeWindow` ownership, applies video rotation and posts RGBA pixels.
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
Run `--verify-artifact <directory> --abi <abi>` after transferring it. Every library
object must be the reviewed ELF machine for that ABI (`AArch64` or
`Advanced Micro Devices X86-64`). The source checkout must be clean; unknown
dependency licenses or modified pinned sources fail packaging. A build is not real
decoding evidence.

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
directions. Rebuild both production ABIs from the same clean revision before
claiming clipboard support in an installable APK.

Artifact metadata keeps `available:false` and `device_media_accepted:false` until
acceptance for that ABI is recorded; `controller_backend_linked:true` and
`production_controller:true` record only that the real WebRTC implementation was
linked. Successful compilation is not evidence of remote frames actually decoded
and presented. The shared library must pass ELF, 16 KiB alignment, and C ABI
checks before an app may import it.

Consumer import contract, before a stable tag is published:

| ABI | Archive | Provenance beside the archive | Engine prefix inside the zip | Library |
| --- | --- | --- | --- | --- |
| `arm64-v8a` | `HomeTunnel-Remote-SDK-<version>-android-arm64.zip` | `android-sdk-provenance.json` | `android-webrtc-arm64/` | `lib/arm64-v8a/libhome_tunnel_remote.so` |
| `x86_64` | `HomeTunnel-Remote-SDK-<version>-android-x86_64.zip` | `android-sdk-x86_64-provenance.json` | `android-webrtc-x86_64/` | `lib/x86_64/libhome_tunnel_remote.so` |

`android-webrtc-build.json` in that prefix is the controller manifest. Its
`source_revision`, `source_tree_sha256`, `upstream_lock_sha256`, `recipe_sha256`,
`compiler_lock`, and `gn_args` must match the tagged client tree. `source/remote-artifact.json`
and `source/home-tunnel-remote-source-*.tar.gz` are the same native tree for both
archives. SBOM names are `android-sdk.spdx.json` and `android-sdk-x86_64.spdx.json`.
Hashes in this repository are not filled in until GitHub Actions builds these bytes.

Before a stable tag exists, dispatch `.github/workflows/android-sdk-candidate.yml` on the exact commit. That workflow is not available to pull requests. It builds both ABIs, writes SPDX and Sigstore bundles, and attests the archives. The seal file is `android-sdk-candidate.json`: `verification_stage=candidate`, `tag_published=false`, `stable_release=false`, `device_media_accepted=false`, plus `source_revision`, `workflow_run_id`, and each ABI's archive, provenance, SBOM, and subject digests. Download the `android-sdk-candidate` artifact from that run and verify the GitHub attestations against this workflow, the run ID, and those digests. A candidate is not a Release and does not satisfy device acceptance. The Windows client installer candidate remains the existing tag-triggered `release.yml` prepare stage.
