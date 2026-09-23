#!/usr/bin/env bash
set -Eeuo pipefail

# Opt-in entry point: ordinary CLI/NAS packages keep their existing independent
# build. Native packages always require the reviewed original worker record.
: "${REMOTE_HOST_BUILD:?Set REMOTE_HOST_BUILD to the clean Linux native build record remote-host-build.json}"
: "${VERSION:?Set VERSION to 8.0.0 or a complete 8.0.0-rc.N version}"
[[ "$VERSION" =~ ^8\.0\.0(-rc\.[1-9][0-9]*)?$ ]] || { echo "This entry point requires Home Tunnel 8.0.0 or 8.0.0-rc.N" >&2; exit 2; }
export ARCH=amd64
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/build-release.sh"
