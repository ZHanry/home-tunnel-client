# Native Linux Xorg host

This target shares the Windows host's signed authorization, peer identity,
UDP-only selected-pair policy, lease expiry and input gate. Its initial advertised
permissions are `view`, `input.keyboard` and `input.pointer`. Unicode text,
clipboard, files, audio and Wayland are not advertised by this Linux host.

Production requires an active, local, unlocked logind session of type `x11`
matching the current user's local `DISPLAY`. It validates the Xauthority file,
rejects Xwayland, requires XRandR 1.5 and refuses to substitute a headless or
remote session. A missing or unverifiable session fails closed. The system bus
uses the fixed root-owned socket rather than an environment override.

XTest input uses XKB physical key names and the selected monitor's physical
rectangle. Before injection, a separate release guard verifies the worker's
pidfd and a sealed shared ledger. It releases only recorded keys/buttons on
worker death, shutdown or a stalled heartbeat. It never signals an unverified
numeric PID, and retains release debt while the desktop is unavailable.

## Build and verification

Use a disposable Ubuntu 24.04 x64 environment with at least 24 GiB free space;
the exact apt dependencies are in `.github/workflows/native-linux.yml`.

```sh
python3 scripts/build-native-linux.py --build --jobs 4
```

The cache is `.downloads/remote-webrtc-linux`, separate from Windows and Android.
`linux-build.lock.json` binds the X11/no-PipeWire/system-baseline GN arguments to
the exact upstream lock. The build records source, binary, recipe and notices
hashes. The production worker and its runtime library list are copied to
`outputs/native-linux-build`.

The GUI can load this adjacent production worker only when its SHA256 is pinned
at compile time. Worker version and ABI validation remains mandatory. To prepare
a complete GUI candidate from a clean checkout and a clean build of the same
commit, run:

```sh
VERSION=8.0.0-rc.1 REMOTE_HOST_BUILD="$PWD/outputs/native-linux-build/remote-host-build.json" \
  bash packaging/build-linux-remote-candidate.sh
```

This entry point verifies the worker's ELF architecture, exact source tree,
revision, immutable dependency/recipe locks, corresponding-source manifest,
license notices, authorization tests and separate production/test IPC boundary.
Both isolated codecs must actually decode over UDP. The package contains only
the production worker and public evidence; no test executable or executable path
from an evidence file is used. Dirty or changed builds are refused. Candidate
CI builds are not published as a GitHub Release or marked as physical acceptance.

The installer verifies the packaged worker digest before changing the service,
backs it up with the GUI and Agent, and restores it on a later install failure.
Updating to a tunnel-only package removes an older native worker. Ordinary
`packaging/build-release.sh` builds without `REMOTE_HOST_BUILD` remain independent
for CLI/NAS and the currently unsupported native ARM64 profile.

The separate `home_tunnel_remote_host_xvfb` executable compiles an explicit test
session allowance. Production does not compile this allowance; setting the
environment variable on the production worker cannot enable capture. The test
binary is excluded from candidate packages. Xvfb verifies real XTest key/button
events, live heartbeats, guard release after crash/stall, preservation of an
unrelated held key, native IPC boundaries, and independent H264/VP8 local UDP
capture/encode/decode probes. No screen contents are recorded.

Input-only verification without downloading WebRTC is also available:

```sh
cmake -S native/remote -B outputs/linux-platform -G Ninja -DHT_RD_BUILD_X11_HOST_SUPPORT=ON
cmake --build outputs/linux-platform -j 4
HT_RD_XVFB_ISOLATED_TEST=1 XDG_SESSION_TYPE=x11 xvfb-run -a -s '-screen 0 800x600x24' ctest --test-dir outputs/linux-platform --output-on-failure --timeout 20
```

Use Docker `--init` if running `xvfb-run` as the container's entry command, so
the X server's readiness signal is delivered to an ordinary process.

Local Ubuntu 24.04 container tests have passed the real XTest input/guard and
production rejection cases. Isolated Xvfb evidence is not physical Xorg desktop,
lock/unlock, multi-monitor, browser/device or network acceptance. The full GN
build and each packaged artifact require their own recorded successful run.
