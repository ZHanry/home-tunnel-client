#!/usr/bin/env bash
set -euo pipefail
target="$1"
if [[ "$target" == mac-* ]]; then
  brew install llvm ninja cmake pkg-config nasm yasm
  export LIBCLANG_PATH="$(brew --prefix llvm)/lib"
  echo "LIBCLANG_PATH=$LIBCLANG_PATH" >> "$GITHUB_ENV"
  # Media dependencies require the NASM 2.x command line.
  if nasm -v | grep -q 'version 3\.'; then
    curl --fail --location https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/macosx/nasm-2.16.03-macosx.zip -o "$RUNNER_TEMP/nasm.zip"
    unzip -q "$RUNNER_TEMP/nasm.zip" -d "$RUNNER_TEMP/nasm"
    echo "$RUNNER_TEMP/nasm/nasm-2.16.03" >> "$GITHUB_PATH"
    export PATH="$RUNNER_TEMP/nasm/nasm-2.16.03:$PATH"
  fi
  triplet="x64-osx"
  [[ "$target" != mac-arm64 ]] || triplet="arm64-osx"
else
  sudo apt-get update
  sudo apt-get install -y build-essential clang libclang-dev cmake ninja-build pkg-config nasm yasm \
    libgtk-3-dev libasound2-dev libxdo-dev libxtst-dev libxrandr-dev libxi-dev libxfixes-dev \
    libxcursor-dev libxinerama-dev libpam0g-dev libudev-dev libva-dev libvdpau-dev libdrm-dev \
    libgbm-dev libpulse-dev libxcb-shape0-dev libxcb-xfixes0-dev libunwind-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libayatana-appindicator3-dev \
    dbus-x11 gnome-keyring libsecret-tools xvfb
  triplet="x64-linux"
  [[ "$target" != linux-arm64 ]] || triplet="arm64-linux"
fi
if [[ "$target" == linux-arm64 ]]; then
  sdk="$RUNNER_TEMP/flutter-elinux"
  git clone --no-checkout https://github.com/sony/flutter-elinux.git "$sdk"
  git -C "$sdk" checkout --detach ac5e8387cdeadece7ed747d99da24d02adb354a6
  export PATH="$sdk/bin:$sdk/flutter/bin:$PATH"
  flutter-elinux doctor -v
  flutter-elinux precache --linux
  curl --fail --location https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz -o "$RUNNER_TEMP/flutter-shaders.tar.xz"
  mkdir -p "$RUNNER_TEMP/shaders"
  tar -xJf "$RUNNER_TEMP/flutter-shaders.tar.xz" -C "$RUNNER_TEMP/shaders" flutter/bin/cache/artifacts/engine/linux-x64/shader_lib
  cp -R "$RUNNER_TEMP/shaders/flutter/bin/cache/artifacts/engine/linux-x64/shader_lib" "$sdk/flutter/bin/cache/artifacts/engine/linux-arm64/"
  echo "$sdk/bin" >> "$GITHUB_PATH"
  echo "$sdk/flutter/bin" >> "$GITHUB_PATH"
fi
cargo install cargo-expand --version 1.0.118 --locked
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
export VCPKG_BINARY_SOURCES=clear
(cd client && "$VCPKG_ROOT/vcpkg" install --triplet "$triplet" --host-triplet "$triplet" --x-install-root="$VCPKG_ROOT/installed")
