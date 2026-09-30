# Credentials, diagnostics and publisher signatures

Home Tunnel stores the device credential using **Windows DPAPI** for the
current OS account or **macOS Keychain**. Existing plaintext state migrates when
saved successfully. Losing the OS key or switching OS users can require device
re-enrollment. A credential-store failure does not silently downgrade encryption.
Linux/headless deployments use explicit owner-only (0600) files in a private
directory; there is no claimed Linux keychain encryption.

Desktop settings provide **Run checks** and **Export bundle**. CLI equivalents:

```sh
home-tunnel-client doctor --state /your/private/state.json
home-tunnel-client support-bundle --state /your/private/state.json --output /private/support.zip
```

Checks distinguish DNS, control HTTPS, FRPS, authorization, the local Agent and
local targets. Support bundles use an allowlist of statuses, versions and hints;
they omit credentials, tokens, raw logs, server addresses and private service
topology. Inspect a bundle before voluntarily sharing it. Diagnostics do not
upload anything. Android provides a redacted management-side diagnostic report;
it cannot probe the home host as if it were the Agent.

## Windows service host

The optional Windows service is installed only when an administrator chooses
that unchecked task. Installation does not enable unattended access. Enabling
access uses a local UAC helper and binds one controller endpoint and public-key
thumbprint. Portable and per-user installs retain the ordinary desktop host.

The service owns one durable endpoint and a hash-pinned native worker in the
active console session. Management pipes verify the installed peer image, PID,
user SID, session and elevation. The worker verifies its pipe server against
SCM. A two-second service delegation enables the backend; secure desktop access
also requires local opt-in and the controller identity independently verified by
the native ticket/lease/grant handshake. Discovery alone grants no remote access.

The protected machine store uses DPAPI **under LocalSystem**, without
`CRYPTPROTECT_LOCAL_MACHINE`. It contains the endpoint key, server trust and
revocation state, not account passwords or login tokens. Endpoint handoff disables
the tray owner first; retries do not replace newer service grants or tombstones.
Emergency disable cancels the worker and persists local revocation without
waiting for the network.

File access impersonates the signed-in endpoint owner's exact logon token;
handles cannot cross identities or logon sessions. Clipboard requires that user
context and the ordinary desktop. The input-release guard survives a worker
crash solely to release recorded held input. The system-audio implementation
captures the render endpoint through WASAPI loopback under that same user
context, only on the ordinary desktop and after a verified feature request.
An independent 500 ms media deadline stops capture if the session thread stalls;
expiry requires a new explicit activation. No microphone capture is implemented.

These code-level controls do not establish final runtime acceptance. Published
10.0.0 does not support lock-screen, pre-login, UAC secure-desktop or session-switch
control, and the remaining service runtime cases were not run on the final bytes.
The reported Web-to-Windows checks used development builds of the same feature
code and were not repeated on the final release artifacts. CI builds and final
Windows Defender, installation and payload-hash checks have separate passing
evidence. See [release notes](RELEASE_NOTES.md) for the exact verified and unverified
scope; do not treat implementation or build success as runtime acceptance.

## Current signing state

**No Windows Authenticode or Apple Developer ID identity is currently configured.**
Windows/macOS packages without configured publisher identities are marked unsigned in
`platform-signing.json`. Platform installation prompts may remain. SHA-256,
Sigstore provenance, antivirus scanning and installer tests do not replace an OS
publisher certificate. Do not disable OS signature verification to hide prompts.
Android retains its independent release signing identity.

The workflow is ready for these GitHub Secrets:

| Platform | Secret names |
| --- | --- |
| Windows | `WINDOWS_SIGNING_PFX_BASE64`, `WINDOWS_SIGNING_PFX_PASSWORD` |
| macOS Developer ID | `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_PASSWORD`, `MACOS_SIGNING_IDENTITY` |
| Apple notarization | `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` |

Configure certificates privately in GitHub; never put them in issues or source.
Once both platforms have valid identities, set repository variable
`REQUIRE_PLATFORM_SIGNING=true` to reject missing signing configuration. Partial
configuration always fails. Windows uses SHA-256 signatures with an RFC 3161
timestamp and verifies the result. macOS uses a temporary Keychain, hardened
runtime signing and Apple notarytool; only an Accepted result succeeds. The CLI
tar archive does not support stapling, disclosed as `offline_stapling=false`.
Ephemeral keys and certificate files are removed by the workflow.

The Agent is signed before its shipped hash is embedded in the CLI/GUI. The
reproducible unsigned baseline remains separately recorded. Release assets retain
checksums, SBOMs, Sigstore bundles and platform evidence so verification does not
depend on expiring Actions artifacts.

中文：Windows/macOS 目前没有平台发行证书，包内如实标注未签名；Android 继续使用
既有签名。先完成凭据存储、诊断与签名流程接入，取得证书后通过 GitHub Secrets
启用，不在聊天或工单传递私钥。签名改变 Agent 字节，发行流程会重新注入签名后哈希。
