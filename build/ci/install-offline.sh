#!/usr/bin/env bash
# 验证本地包与架构后离线安装；不访问网络、不自动关闭安全中心。
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
sha256sum -c SHA256SUMS
if [[ "${XDG_SESSION_TYPE:-}" == wayland ]]; then
  echo '当前为 Wayland；锁屏和无人值守验收请切换到 X11 会话。' >&2
fi
arch="$(dpkg --print-architecture)"
for package in debs/*.deb; do
  package_arch="$(dpkg-deb -f "$package" Architecture)"
  [[ "$package_arch" == all || "$package_arch" == "$arch" ]] || { echo '离线包包含其他架构，拒绝安装' >&2; exit 1; }
done
if (( EUID != 0 )); then echo '请使用 sudo bash install-offline.sh 执行安装' >&2; exit 1; fi
apt-get --no-download install ./debs/*.deb
echo '安装完成。请在安全中心允许应用与开机自启动，并按冒烟清单验证。'
