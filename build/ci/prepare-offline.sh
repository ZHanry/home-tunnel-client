#!/usr/bin/env bash
# 在与目标麒麟版本/架构一致的联网机器准备完整依赖集，不修改已安装软件。
set -Eeuo pipefail
if (( $# != 2 )); then echo '用法：prepare-offline.sh /绝对路径/客户端.deb /新的输出目录' >&2; exit 2; fi
package="$(realpath -- "$1")"
output="$(realpath -m -- "$2")"
[[ -f "$package" && "$package" == *.deb ]] || { echo '找不到 deb 安装包' >&2; exit 1; }
[[ ! -e "$output" ]] || { echo '输出目录已存在，请指定新目录' >&2; exit 1; }
expected="$(dpkg-deb -f "$package" Architecture)"
[[ "$expected" == "$(dpkg --print-architecture)" ]] || { echo '安装包架构与依赖准备机不同' >&2; exit 1; }
mkdir -p "$output/debs/partial"
cp -- "$package" "$output/debs/"
apt-get -y --download-only -o "Dir::Cache::archives=$output/debs" -o 'Dir::State::status=/dev/null' install "$package"
cp -- "$(dirname -- "$0")/install-offline.sh" "$output/"
cp -- /etc/os-release "$output/build-os-release.txt"
(cd "$output" && sha256sum debs/*.deb > SHA256SUMS)
echo "离线依赖已保存到 $output；请在同系统版本的目标机执行 install-offline.sh"
