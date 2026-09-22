#!/usr/bin/env bash
set -Eeuo pipefail

version=${VERSION:-8.0.0-rc.1}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "VERSION must be X.Y.Z or X.Y.Z-rc.N" >&2; exit 2; }
architecture=${ARCH:-$(go env GOARCH)}
case "$architecture" in
  amd64|arm64) ;;
  *) echo "ARCH must be amd64 or arm64" >&2; exit 2 ;;
esac
for command in go curl sed sha256sum tar; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
if ! command -v unzip >/dev/null && ! command -v python3 >/dev/null; then
  echo "unzip or python3 is required to extract the pinned FRP source" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
client_dir=$(cd -- "$script_dir/.." && pwd)
workspace_dir="$client_dir"
source_version=$(sed -n 's/^const Version = "\([^"]*\)"$/\1/p' "$client_dir/internal/model/model.go")
[[ "$version" == "$source_version" ]] || { echo "Linux client source version $source_version does not match release version $version" >&2; exit 1; }
downloads_dir="$workspace_dir/.downloads"
output_dir="$workspace_dir/outputs/linux"
frp_version=0.70.1
agent_version=$(tr -d '\r' < "$workspace_dir/agent/build-agent.ps1" | sed -n 's/^\$agentVersion = "\([^"]*\)"$/\1/p')
[[ "$agent_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[1-9][0-9]*)?$ ]] || { echo "unable to read the unified Agent version" >&2; exit 1; }
[[ "$agent_version" == "$source_version" ]] || { echo "Client and first-party Agent versions must match" >&2; exit 1; }
frp_commit=fa3bcca2b0c4753cd4f0e2ab189dd6a5a6a15708
frp_archive="$downloads_dir/frp-$frp_commit.zip"
frp_archive_sha256=9c6b0188a8f74e982069dc89218cc3d79bada8663cedf3b514b98847530cbf7d
frp_extract_root="$downloads_dir/frp-api-$frp_commit"
archive="$output_dir/home-tunnel-linux-$version-$architecture.tar.gz"
checksum_file="$output_dir/home-tunnel-linux-$version-$architecture.sha256"
[[ ! -e "$archive" && ! -e "$checksum_file" ]] || { echo "release output already exists: $archive" >&2; exit 1; }

mkdir -p "$downloads_dir" "$output_dir"
if [[ ! -f "$frp_archive" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    --header 'Accept: application/vnd.github+json' \
    --header 'User-Agent: HomeTunnelBuild' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    "https://api.github.com/repos/fatedier/frp/zipball/$frp_commit" --output "$frp_archive"
fi
actual_archive_hash=$(sha256sum "$frp_archive" | awk '{print $1}')
[[ "$actual_archive_hash" == "$frp_archive_sha256" ]] || { echo "pinned FRP source checksum mismatch: $actual_archive_hash" >&2; exit 1; }
if [[ ! -d "$frp_extract_root" ]]; then
  mkdir -p "$frp_extract_root"
  if command -v unzip >/dev/null; then
    unzip -q "$frp_archive" -d "$frp_extract_root"
  else
    python3 -m zipfile -e "$frp_archive" "$frp_extract_root"
  fi
fi
frp_source=$(find "$frp_extract_root" -mindepth 1 -maxdepth 1 -type d -name "fatedier-frp-${frp_commit:0:7}*" -print -quit)
[[ -n "$frp_source" && -f "$frp_source/go.mod" ]] || { echo "pinned FRP source tree not found" >&2; exit 1; }

temporary_command="$frp_source/cmd/home-tunnel-agent-linux-build"
[[ ! -e "$temporary_command" ]] || { echo "fixed Agent build directory is already in use: $temporary_command" >&2; exit 1; }
mkdir "$temporary_command"
stage=$(mktemp -d "$output_dir/.stage.XXXXXX")
cleanup() {
  rm -rf -- "$temporary_command" "$stage"
}
trap cleanup EXIT INT TERM
cp "$workspace_dir/agent/main.go" "$temporary_command/main.go"

mkdir -p "$stage/bin" "$stage/lib/systemd/system" "$stage/libexec"
package_dir="$stage/home-tunnel-linux-$version-$architecture"
mkdir -p "$package_dir/bin" "$package_dir/lib" "$package_dir/lib/systemd/system" "$package_dir/libexec"
agent_output="$package_dir/lib/home-tunnel-agent"
(
  cd "$frp_source"
  export CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" GOFLAGS=-buildvcs=false
  dependency_packages=$(go list -deps -modfile="$workspace_dir/agent/frp-go.mod" -mod=readonly "./cmd/$(basename "$temporary_command")")
    if grep -q '^golang.org/x/crypto/openpgp' <<< "$dependency_packages"; then
      echo "Unsupported OpenPGP package must not be linked into the Agent" >&2
      exit 1
    fi
    CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" GOFLAGS=-buildvcs=false \
    go build -modfile="$workspace_dir/agent/frp-go.mod" -mod=readonly -trimpath \
    -ldflags "-s -w -buildid= -X main.agentVersion=$agent_version -X main.frpVersion=$frp_version -X main.frpCommit=$frp_commit" \
    -o "$agent_output" "./cmd/$(basename "$temporary_command")"
)
module_version=$(go version -m "$agent_output" | awk '$1 == "dep" && $2 == "github.com/Azure/go-ntlmssp" { print $3 }')
[[ "$module_version" == "v0.1.1" ]] || { echo "Agent did not include the reviewed NTLM security fix" >&2; exit 1; }
crypto_version=$(go version -m "$agent_output" | awk '$1 == "dep" && $2 == "golang.org/x/crypto" { print $3 }')
[[ "$crypto_version" == "v0.56.0" ]] || { echo "Agent did not include the reviewed SSH security fixes" >&2; exit 1; }
agent_hash=$(sha256sum "$agent_output" | awk '{print $1}')
(
  cd "$client_dir"
  CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" GOFLAGS=-buildvcs=false \
    go build -trimpath \
    -ldflags "-s -w -buildid= -X main.version=$version -X main.agentVersion=$agent_version -X main.expectedAgentSHA256=$agent_hash" \
    -o "$package_dir/bin/home-tunnel-client" ./cmd/home-tunnel-client
  gui_cgo=0
  if [[ "$(go env GOOS)" == "linux" && "$architecture" == "$(go env GOARCH)" ]]; then
    gui_cgo=1
  fi
  CGO_ENABLED="$gui_cgo" GOOS=linux GOARCH="$architecture" GOFLAGS=-buildvcs=false \
    go build -trimpath \
    -ldflags "-s -w -buildid= -X main.version=$version -X main.agentVersion=$agent_version -X main.expectedAgentSHA256=$agent_hash" \
    -o "$package_dir/bin/home-tunnel-gui" ./cmd/home-tunnel-gui
)
cp "$script_dir/home-tunnel-client.service" "$package_dir/lib/systemd/system/"
cp "$script_dir/home-tunnel.desktop" "$package_dir/lib/home-tunnel.desktop"
cp "$script_dir/home-tunnel-enroll" "$package_dir/libexec/"
cp "$script_dir/install.sh" "$package_dir/install.sh"
cp "$client_dir/README.md" "$client_dir/README.en.md" "$client_dir/LICENSE" "$package_dir/"
cp "$client_dir/agent/FRP-LICENSE.txt" "$client_dir/agent/THIRD-PARTY-NOTICES.txt" "$package_dir/"
cp -R "$client_dir/docs" "$client_dir/contracts" "$package_dir/"
mkdir -p "$package_dir/packaging"
cp -R "$client_dir/packaging/nas" "$package_dir/packaging/"
chmod 0755 "$package_dir/bin/home-tunnel-client" "$package_dir/bin/home-tunnel-gui" "$package_dir/lib/home-tunnel-agent" "$package_dir/libexec/home-tunnel-enroll" "$package_dir/install.sh"

if [[ "$(go env GOOS)" == "linux" && "$architecture" == "$(go env GOARCH)" ]]; then
  client_version_output=$("$package_dir/bin/home-tunnel-client" version)
  agent_version_output=$("$package_dir/lib/home-tunnel-agent" version)
  [[ "$client_version_output" == "Home Tunnel Linux Client $version (Agent $agent_version)" ]] || { echo "client version self-check failed: $client_version_output" >&2; exit 1; }
  [[ "$agent_version_output" == "Home Tunnel Agent $agent_version (FRP $frp_version, $frp_commit)" ]] || { echo "Agent version self-check failed: $agent_version_output" >&2; exit 1; }
fi
tar -C "$stage" -czf "$archive" "$(basename "$package_dir")"
archive_hash=$(sha256sum "$archive" | awk '{print $1}')
printf '%s  %s\n' "$archive_hash" "$(basename "$archive")" >"$checksum_file"
echo "CLIENT=$archive"
echo "CLIENT_SHA256=$archive_hash"
echo "AGENT_SHA256=$agent_hash"
