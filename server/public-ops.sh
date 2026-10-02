#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="compose.public.yml"
readonly ENV_FILE=".env.public"
readonly ACTION="${1:-help}"
BACKUP_ARCHIVE=""
BACKUP_RESTART_AFTER=false
BACKUP_COMPLETE=false

cd "${SCRIPT_DIR}"

compose() {
  env \
    -u HOMEDESK_PUBLIC_BIND_IP \
    -u HOMEDESK_PUBLIC_RELAY_HOST \
    -u HOMEDESK_PUBLIC_RELAY_PORT \
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

finish_backup() {
  if [[ "${BACKUP_COMPLETE}" != true && -n "${BACKUP_ARCHIVE}" ]]; then
    rm -f -- "${BACKUP_ARCHIVE}"
  fi
  if [[ "${BACKUP_RESTART_AFTER}" == true ]]; then
    compose start hbbr hbbs >/dev/null
  fi
}

require_valid_deployment_config() {
  # 故障排查和备份不能依赖 DNS/接口当下可用；此模式仍检查语法、镜像、服务和端口，且不能启动。
  bash ./verify-public.sh --ops-config-only >/dev/null
}

show_status() {
  require_valid_deployment_config
  for container in homedesk-public-hbbs homedesk-public-hbbr; do
    if ! docker inspect -f '{{.Name}} 状态={{.State.Status}} 重启次数={{.RestartCount}} 镜像={{.Config.Image}}' "${container}" 2>/dev/null; then
      echo "${container} 尚未创建。"
    fi
  done
}

show_stats() {
  require_valid_deployment_config
  docker stats --no-stream \
    --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.PIDs}}' \
    homedesk-public-hbbs homedesk-public-hbbr
}

backup_data() {
  local destination="${2:-}"
  local destination_real source_real archive="" timestamp running_services

  require_valid_deployment_config
  if [[ -z "${destination}" || ! -d "${destination}" ]]; then
    echo "备份目标必须是已存在的受控目录。" >&2
    exit 2
  fi
  destination_real="$(cd -- "${destination}" && pwd -P)"
  if [[ ! -d public-data || ! -s public-data/id_ed25519 || ! -s public-data/id_ed25519.pub ]]; then
    echo "server/public-data 不完整，拒绝生成无法恢复服务器身份的备份。" >&2
    exit 1
  fi
  source_real="$(cd -- public-data && pwd -P)"
  case "${destination_real}" in
    "${source_real}"|"${source_real}"/*)
      echo "备份目标不能等于或位于 server/public-data 内部。" >&2
      exit 1
      ;;
  esac

  BACKUP_ARCHIVE=""
  BACKUP_RESTART_AFTER=false
  BACKUP_COMPLETE=false
  trap finish_backup EXIT

  running_services="$(compose ps --status running --services | sort)"
  case "${running_services}" in
    $'hbbr\nhbbs')
      BACKUP_RESTART_AFTER=true
      compose stop hbbs hbbr >/dev/null
      ;;
    "")
      ;;
    *)
      echo "hbbs/hbbr 运行状态不一致；请先恢复为全运行或全停止后再备份。" >&2
      exit 1
      ;;
  esac

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="${destination_real}/homedesk-public-data-${timestamp}.tar.gz"
  if [[ -e "${archive}" ]]; then
    echo "备份文件已存在，拒绝覆盖。" >&2
    exit 1
  fi
  BACKUP_ARCHIVE="${archive}"
  umask 077
  tar -C "${SCRIPT_DIR}" -czf "${archive}" public-data
  [[ -s "${archive}" ]] || {
    echo "备份文件为空。" >&2
    exit 1
  }
  BACKUP_COMPLETE=true

  if [[ "${BACKUP_RESTART_AFTER}" == true ]]; then
    compose start hbbr hbbs >/dev/null
    BACKUP_RESTART_AFTER=false
  fi
  trap - EXIT
  BACKUP_ARCHIVE=""
  echo "加密材料与运行数据已一致性备份到：${archive}"
  echo "该归档包含服务器私钥，必须保存在加密且限制访问的目录。"
}

case "${ACTION}" in
  status)
    show_status
    ;;
  stats)
    show_stats
    ;;
  backup)
    backup_data "$@"
    ;;
  help|-h|--help)
    echo "用法：$0 status | stats | backup <已存在的受控目录>"
    ;;
  *)
    echo "未知操作：${ACTION}" >&2
    echo "用法：$0 status | stats | backup <已存在的受控目录>" >&2
    exit 2
    ;;
esac
