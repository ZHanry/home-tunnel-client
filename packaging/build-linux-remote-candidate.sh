#!/usr/bin/env bash
set -Eeuo pipefail

# Opt-in entry point: ordinary CLI/NAS packages keep their existing independent
# build. Native candidates always require the reviewed original worker record.
: "${REMOTE_HOST_BUILD:?Set REMOTE_HOST_BUILD to the clean Linux native build's remote-host-build.json}"
: "${VERSION:?Set VERSION to the complete 8.0.0-rc.N candidate version}"
[[ "$VERSION" =~ ^8\.0\.0-rc\.[1-9][0-9]*$ ]] || { echo "This entry point prepares Home Tunnel 8.0 RC candidates" >&2; exit 2; }
export ARCH=amd64
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/build-release.sh"
