# Windows 10.1.0 candidate verification

Historical candidate preparation record. Version 10.1.0 has now been published by promoting the original verified candidate; see [stable release coverage](RELEASE_10_1_STABLE.md). Existing 10.0.0 releases and immutable API tags are unchanged. The verification requirements and evidence boundaries below describe candidate preparation.

## Behavior under test

1. The approval popup has an opaque native/WebView/HTML background. Its native window is revealed only after the packaged page reports populated request/session content.
2. My Devices labels the current device and offers rename instead of Remote. Local remote-window validation and device-bound server pairing/session checks reject self connections, including assistance paths.
3. The remote window uses an expiring, single-use sign-in handoff. It cannot obtain general account/admin access. The handoff is delivered to the exact trusted HTTPS page rather than in URLs, storage or logs. Closing/replacing the window, signing out, and revoking the parent session are covered separately.
4. Settings contains update controls and the server address. Device name editing belongs to My Devices. Device tags, appearance options and the return-to-local-services button are removed from Settings.
5. Sign-in has wider fields and more spacing, scrolls at small sizes, and retains actionable retry and keyboard behavior.

Server 10.1.0 is required for the new handoff and current-device rename. An older server must produce a clear upgrade message. API 1.5.0 is additive and is imported from the verified immutable api-v1.5.0 tag with exact source and SHA-256 locks; API 1.4.0 remains unchanged. Contract freeze does not establish final-package acceptance.

## Evidence boundaries

- Go, TypeScript, browser and native-core checks validate their stated code paths. They do not establish final-package live remote behavior.
- Windows CI builds the actual ZIP/installer, reproduces the Agent baseline, scans and checks installation, then tests the embedded UI inside its real WebView2 window. Signed-in UI states in this harness use explicit local-API fixtures. Reports identify those fixtures and bind screenshots to the exact archive hash.
- The packaged popup HTML can be inspected in a native window, but that alone does not validate the separate bottom-right popup HWND or an incoming live authorization request.
- Signed final candidate artifacts must be built through the existing candidate entry point and preserved unchanged. The full final-artifact matrix in [CLIENT_ACCEPTANCE.md](CLIENT_ACCEPTANCE.md), including live remote sessions and long-running stability, remains mandatory for formal publication.
- No previous package's acceptance, scan timestamps, runtime results, or screenshots are reused as a 10.1.0 pass. Unrun or blocked checks remain explicitly unverified.

## Reproducible Agent baseline

The version-only 10.1.0 Agent build used pinned Go 1.26.6, MinGW 16.1.0 and FRP source `fa3bcca2b0c4753cd4f0e2ab189dd6a5a6a15708`. [Windows CI run 36678696146](https://github.com/ZHanry/home-tunnel-client/actions/runs/36678696146) produced SHA-256 `0be9d77918aad26539692fa80b0c2b0a8e7ab0bb8ed85de63f5e0456a2fcaef0`; it correctly failed against the old 10.0.0 baseline. Subsequent CI must independently reproduce this new recorded digest before packaging proceeds. The baseline comparison is not bypassed.
