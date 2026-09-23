# 7.0.0 desktop and CLI

Use server **7.0.0** and the Agent bundled in the same client release. The desktop
is a device client: it manages only this computer. Web/Android manage account-wide
resources. Use Android's encrypted saved profiles to switch between deployments;
on a desktop, logging out stops its active tunnels and clears that device's state.

Sign in using an account plus a fresh TOTP/recovery code, or enter a ten-minute,
single-use enrollment code created in Web/Android. HTTP is self-service. TCP/UDP
and SSH/RDP/RTSP presets appear according to server deployment and account
capabilities. Public ports are allocated by the server, never guessed by the UI.

Settings edit this device's tags/favorite with a metadata version check. Select
up to 50 local services to pause/resume; confirm the named selection, then inspect
each result. A conflict or missing permission on one item does not erase the
successful results of other items. Re-read before retrying a conflict.

Updates accept only stable semantic versions newer than the current one. HTTPS,
successful HTTP responses, an exact filename/SHA-256 manifest entry, bounded size
and complete content are mandatory. A verified temporary file is synced and
renamed atomically; failed downloads never become a successful installer.

[Credential protection, diagnostics and signing](PLATFORM_SECURITY.md) ·
[NAS Compose template](../packaging/nas/README.md) ·
[CLI/service operations](OPERATIONS.md)

## 8.0 candidate development

The candidate adds opt-in remote hosting through a separately verified native
worker. Windows supports the H.264/VP8 viewing path, ordinary-desktop input,
explicit text clipboard permissions and consent-bound file transfer. Only
capabilities reported by the actual packaged worker can be selected; a missing,
wrong-version or wrong-hash worker leaves remote hosting unavailable. Local file
selection is bound to the current session and connection epoch, and is cancelled
when that authorization ends. File contents never enter the local HTTP API or
the signaling server.

The Linux Xorg worker and Android controller have separate build/acceptance
records. Wayland/macOS hosting, native desktop viewing and audio remain under
development. See [candidate notes](RELEASE_NOTES.md) for actual tested scope and
remaining restrictions. These additions do not change the 7.0 stable downloads.
