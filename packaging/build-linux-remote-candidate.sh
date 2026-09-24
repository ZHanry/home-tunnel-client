#!/usr/bin/env bash
set -Eeuo pipefail

# Opt-in entry point: ordinary CLI/NAS packages keep their existing independent
# build. Native packages always require the reviewed original worker record.
: "${REMOTE_HOST_BUILD:?Set REMOTE_HOST_BUILD to the clean Linux native build record remote-host-build.json}"
: "${VERSION:?Set VERSION to a complete X.Y.Z or X.Y.Z-rc.N version}"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc\.[1-9][0-9]*)?$ ]] || { echo "This entry point requires a canonical Home Tunnel release version" >&2; exit 2; }
export ARCH=amd64
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/build-release.sh"
