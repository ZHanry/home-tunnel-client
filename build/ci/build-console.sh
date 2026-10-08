#!/usr/bin/env bash
# 原生 Linux x64/ARM64 构建静态管理台及无基础镜像的运行容器。
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
case "$(uname -m)" in
  x86_64) target=x86_64-unknown-linux-musl; platform=linux/amd64 ;;
  aarch64|arm64) target=aarch64-unknown-linux-musl; platform=linux/arm64 ;;
  *) echo '仅支持 Linux x64 和 ARM64 原生构建' >&2; exit 1 ;;
esac
command -v musl-gcc >/dev/null || { echo '请先安装 musl-tools' >&2; exit 1; }
rustup target add "$target"
CC=musl-gcc cargo build --locked --release --target "$target" --manifest-path "$root/server/console/Cargo.toml"
context="$root/server/console/target/container-$target"
mkdir -p "$context"
cp -- "$root/server/console/target/$target/release/homedesk-console" "$context/homedesk-console"
docker build --platform "$platform" -f "$root/server/console/Dockerfile.prebuilt" -t homedesk/console:0.1.0 "$context"
