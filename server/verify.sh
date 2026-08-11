#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly EXPECTED_IMAGE="ghcr.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00"
readonly MODE="${1:-start}"

cd "${SCRIPT_DIR}"

if (( BASH_VERSINFO[0] < 4 )); then
  echo "verify.sh 需要 Bash 4 或更高版本；请勿使用 sh 执行。" >&2
  exit 1
fi

case "${MODE}" in
  start|--config-only)
    ;;
  *)
    echo "用法：$0 [--config-only]" >&2
    exit 2
    ;;
esac

read_env_value() {
  local name="$1"
  local assignment
  local value

  assignment="$(grep -E "^${name}=" .env | tail -n 1 || true)"
  value="${assignment#*=}"
  if [[ -z "${assignment}" ]] || [[ "${value}" == *REPLACE_WITH_* ]] || [[ -z "${value}" ]]; then
    echo "server/.env 中的 ${name} 未填写，请设置 NAS 固定内网 IP。" >&2
    return 1
  fi
  printf '%s' "${value}"
}

is_rfc1918_ipv4() {
  local ip="$1"
  local a b c d extra octet

  IFS=. read -r a b c d extra <<< "${ip}"
  if [[ -n "${extra:-}" ]] || [[ -z "${a:-}" ]] || [[ -z "${b:-}" ]] || [[ -z "${c:-}" ]] || [[ -z "${d:-}" ]]; then
    return 1
  fi
  for octet in "${a}" "${b}" "${c}" "${d}"; do
    if [[ ! "${octet}" =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((10#${octet} > 255)); then
      return 1
    fi
  done
  ((10#${a} == 10)) ||
    ((10#${a} == 172 && 10#${b} >= 16 && 10#${b} <= 31)) ||
    ((10#${a} == 192 && 10#${b} == 168))
}

if [[ ! -f .env ]]; then
  echo "缺少 server/.env：请先复制 .env.example 并填写 NAS 固定内网 IP。" >&2
  exit 1
fi

bind_ip="$(read_env_value HOMEDESK_BIND_IP)" || exit 1
server_host="$(read_env_value HOMEDESK_SERVER_HOST)" || exit 1

if ! is_rfc1918_ipv4 "${bind_ip}"; then
  echo "HOMEDESK_BIND_IP 必须是 RFC1918 私网 IPv4（10/8、172.16/12 或 192.168/16），拒绝绑定公网或全部接口。" >&2
  exit 1
fi
if ! is_rfc1918_ipv4 "${server_host}"; then
  echo "HOMEDESK_SERVER_HOST 必须是 RFC1918 私网 IPv4。" >&2
  exit 1
fi
if [[ "${bind_ip}" != "${server_host}" ]]; then
  echo "T-00 单机部署要求 HOMEDESK_BIND_IP 与 HOMEDESK_SERVER_HOST 为同一个 NAS 内网 IP。" >&2
  exit 1
fi

# 以已校验的 .env 值覆盖调用者环境，避免 Compose 的环境变量优先级绕过内网检查。
export HOMEDESK_BIND_IP="${bind_ip}"
export HOMEDESK_SERVER_HOST="${server_host}"

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令。请先在 fnOS 启用 Docker/Compose。" >&2
  exit 1
fi

docker compose version
docker compose config --quiet

mapfile -t configured_images < <(docker compose config --images)
if [[ "${#configured_images[@]}" -ne 2 ]] ||
   [[ "${configured_images[0]}" != "${EXPECTED_IMAGE}" ]] ||
   [[ "${configured_images[1]}" != "${EXPECTED_IMAGE}" ]]; then
  echo "Compose 展开的镜像引用与 T-00 锁定值不一致：" >&2
  printf '  %s\n' "${configured_images[@]}" >&2
  exit 1
fi

echo "Compose 配置与固定镜像校验通过。"

if [[ "${MODE}" == "--config-only" ]]; then
  exit 0
fi

docker compose pull
docker compose up -d

services_ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
  running_services="$(docker compose ps --status running --services | sort)"
  if [[ "${running_services}" == $'hbbr\nhbbs' ]] && [[ -s data/id_ed25519.pub ]]; then
    services_ready=true
    break
  fi
  sleep 1
done

if [[ "${services_ready}" != true ]]; then
  echo "hbbs/hbbr 未在 30 秒内全部进入 running，或公钥尚未生成。" >&2
  docker compose ps >&2 || true
  echo "请执行：docker compose logs --tail 100 hbbs hbbr" >&2
  exit 1
fi

for container in homedesk-hbbs homedesk-hbbr; do
  restart_policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "${container}")"
  if [[ "${restart_policy}" != "unless-stopped" ]]; then
    echo "${container} 的重启策略异常：${restart_policy}" >&2
    exit 1
  fi
done

docker compose ps
echo "T-00 服务端启动验收通过。"
echo "公钥位于：${SCRIPT_DIR}/data/id_ed25519.pub"
echo "请勿复制或泄露同目录下没有 .pub 后缀的私钥。"
