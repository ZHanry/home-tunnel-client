#!/usr/bin/env bash
set -Eeuo pipefail

readonly IMAGE="ghcr.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00"
readonly TEST_ID="homedesk-public-smoke-$$"
readonly NETWORK="${TEST_ID}"
readonly HBBS="${TEST_ID}-hbbs"
readonly HBBR="${TEST_ID}-hbbr"
readonly DATA_VOLUME="${TEST_ID}-data"
readonly KEY_COPY_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "${HBBS}" "${HBBR}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
  docker volume rm -f "${DATA_VOLUME}" >/dev/null 2>&1 || true
  rm -rf -- "${KEY_COPY_DIR}"
}
trap cleanup EXIT

docker image inspect "${IMAGE}" >/dev/null
# 独立 bridge 只用于两个夹具容器互联；所有宿主机发布都显式限制在 127.0.0.1。
docker network create "${NETWORK}" >/dev/null
docker volume create "${DATA_VOLUME}" >/dev/null

docker run -d --name "${HBBR}" \
  --network "${NETWORK}" --network-alias hbbr \
  --read-only --cap-drop ALL --security-opt no-new-privileges:true --pids-limit 128 \
  --mount "type=volume,src=${DATA_VOLUME},dst=/root" \
  -p 127.0.0.1::21117/tcp \
  "${IMAGE}" hbbr -k _ >/dev/null

docker run -d --name "${HBBS}" \
  --network "${NETWORK}" \
  --read-only --cap-drop ALL --security-opt no-new-privileges:true --pids-limit 128 \
  --mount "type=volume,src=${DATA_VOLUME},dst=/root" \
  -p 127.0.0.1::21115/tcp \
  -p 127.0.0.1::21116/tcp \
  -p 127.0.0.1::21116/udp \
  "${IMAGE}" hbbs -k _ -r hbbr:21117 >/dev/null

ready=false
for ((attempt = 0; attempt < 20; attempt++)); do
  hbbs_state="$(docker inspect -f '{{.State.Running}}' "${HBBS}")"
  hbbr_state="$(docker inspect -f '{{.State.Running}}' "${HBBR}")"
  if [[ "${hbbs_state}" == "true" && "${hbbr_state}" == "true" ]]; then
    if docker cp "${HBBS}:/root/id_ed25519.pub" "${KEY_COPY_DIR}/id_ed25519.pub" >/dev/null 2>&1 &&
       [[ -s "${KEY_COPY_DIR}/id_ed25519.pub" ]]; then
      ready=true
      break
    fi
  fi
  sleep 1
done

if [[ "${ready}" != true ]]; then
  echo "失败：隔离容器未就绪。" >&2
  docker inspect -f '{{.Name}} running={{.State.Running}} exit={{.State.ExitCode}}' "${HBBS}" "${HBBR}" >&2 || true
  exit 1
fi

published="$( { docker port "${HBBS}"; docker port "${HBBR}"; } | sort)"
if [[ "${published}" == *"0.0.0.0:"* || "${published}" == *":::"* ]] ||
   [[ "$(grep -c '127.0.0.1:' <<< "${published}")" -ne 4 ]]; then
  echo "失败：隔离测试端口未全部限制在回环地址。" >&2
  printf '%s\n' "${published}" >&2
  exit 1
fi

tcp_port() {
  local container="$1"
  local target="$2"
  docker port "${container}" "${target}/tcp" | sed -n 's/^127\.0\.0\.1://p'
}

check_tcp_ports() {
  python3 - \
    "$(tcp_port "${HBBS}" 21115)" \
    "$(tcp_port "${HBBS}" 21116)" \
    "$(tcp_port "${HBBR}" 21117)" <<'PY'
import socket
import sys

for port_text in sys.argv[1:]:
    if not port_text.isdigit():
        raise SystemExit("未获得有效的回环映射端口")
    with socket.create_connection(("127.0.0.1", int(port_text)), timeout=2):
        pass
PY
}

check_tcp_ports
first_key_hash="$(sha256sum "${KEY_COPY_DIR}/id_ed25519.pub" | awk '{print $1}')"

docker restart "${HBBR}" "${HBBS}" >/dev/null
for ((attempt = 0; attempt < 20; attempt++)); do
  if [[ "$(docker inspect -f '{{.State.Running}}' "${HBBS}")" == "true" &&
        "$(docker inspect -f '{{.State.Running}}' "${HBBR}")" == "true" ]] &&
     check_tcp_ports >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
check_tcp_ports
rm -f -- "${KEY_COPY_DIR}/id_ed25519.pub"
docker cp "${HBBS}:/root/id_ed25519.pub" "${KEY_COPY_DIR}/id_ed25519.pub" >/dev/null
second_key_hash="$(sha256sum "${KEY_COPY_DIR}/id_ed25519.pub" | awk '{print $1}')"
if [[ "${first_key_hash}" != "${second_key_hash}" ]]; then
  echo "失败：容器重启后服务端公钥发生变化。" >&2
  exit 1
fi

echo "锁定镜像隔离启动、回环 TCP 可达与重启密钥持久化测试通过。"
