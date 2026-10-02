#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="compose.public.yml"
readonly ENV_FILE=".env.public"
readonly EXPECTED_IMAGE="ghcr.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00"
readonly MODE="${1:-start}"
TEMP_RENDERED=""

cleanup() {
  if [[ -n "${TEMP_RENDERED}" ]]; then
    rm -f -- "${TEMP_RENDERED}"
  fi
}
trap cleanup EXIT

cd "${SCRIPT_DIR}"

if ((BASH_VERSINFO[0] < 4)); then
  echo "verify-public.sh 需要 Bash 4 或更高版本；请勿使用 sh 执行。" >&2
  exit 1
fi

case "${MODE}" in
  start|--config-only|--print-command|--ops-config-only)
    ;;
  *)
    echo "用法：$0 [--config-only|--print-command]" >&2
    exit 2
    ;;
esac

declare -A public_config=()
readonly -a REQUIRED_KEYS=(
  HOMEDESK_PUBLIC_BIND_IP
  HOMEDESK_PUBLIC_RELAY_HOST
  HOMEDESK_PUBLIC_RELAY_PORT
)

is_allowed_key() {
  local candidate="$1"
  local allowed
  for allowed in "${REQUIRED_KEYS[@]}"; do
    [[ "${candidate}" == "${allowed}" ]] && return 0
  done
  return 1
}

read_public_config() {
  local line key value line_number=0

  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "缺少 server/${ENV_FILE}：请先复制 .env.public.example 并填写真实部署地址。" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    ((line_number += 1))
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ ! "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      echo "${ENV_FILE} 第 ${line_number} 行格式无效；仅允许 KEY=value，不支持 export、引号或行内注释。" >&2
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if ! is_allowed_key "${key}"; then
      echo "${ENV_FILE} 第 ${line_number} 行包含未支持的配置项 ${key}。" >&2
      return 1
    fi
    if [[ -v "public_config[${key}]" ]]; then
      echo "${ENV_FILE} 中的 ${key} 重复定义。" >&2
      return 1
    fi
    if [[ -z "${value}" || "${value}" == *REPLACE_WITH_* ]]; then
      echo "${ENV_FILE} 中的 ${key} 尚未填写。" >&2
      return 1
    fi
    public_config["${key}"]="${value}"
  done < "${ENV_FILE}"

  for key in "${REQUIRED_KEYS[@]}"; do
    if [[ ! -v "public_config[${key}]" ]]; then
      echo "${ENV_FILE} 缺少 ${key}。" >&2
      return 1
    fi
  done
}

parse_ipv4() {
  local ip="$1"
  local a b c d extra octet

  IFS=. read -r a b c d extra <<< "${ip}"
  if [[ -n "${extra:-}" || -z "${a:-}" || -z "${b:-}" || -z "${c:-}" || -z "${d:-}" ]]; then
    return 1
  fi
  for octet in "${a}" "${b}" "${c}" "${d}"; do
    if [[ ! "${octet}" =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((10#${octet} > 255)); then
      return 1
    fi
  done
  IPV4_A=$((10#${a}))
  IPV4_B=$((10#${b}))
  IPV4_C=$((10#${c}))
  IPV4_D=$((10#${d}))
}

is_private_ipv4() {
  local ip="$1"
  parse_ipv4 "${ip}" || return 1
  ((IPV4_A == 10)) ||
    ((IPV4_A == 172 && IPV4_B >= 16 && IPV4_B <= 31)) ||
    ((IPV4_A == 192 && IPV4_B == 168))
}

is_special_ipv4() {
  local ip="$1"
  parse_ipv4 "${ip}" || return 0

  ((IPV4_A == 0 || IPV4_A == 127 || IPV4_A >= 224)) ||
    ((IPV4_A == 100 && IPV4_B >= 64 && IPV4_B <= 127)) ||
    ((IPV4_A == 169 && IPV4_B == 254)) ||
    ((IPV4_A == 192 && IPV4_B == 0 && IPV4_C == 0)) ||
    ((IPV4_A == 192 && IPV4_B == 0 && IPV4_C == 2)) ||
    ((IPV4_A == 192 && IPV4_B == 88 && IPV4_C == 99)) ||
    ((IPV4_A == 198 && (IPV4_B == 18 || IPV4_B == 19))) ||
    ((IPV4_A == 198 && IPV4_B == 51 && IPV4_C == 100)) ||
    ((IPV4_A == 203 && IPV4_B == 0 && IPV4_C == 113))
}

is_bind_ipv4() {
  local ip="$1"
  parse_ipv4 "${ip}" || return 1
  ! is_special_ipv4 "${ip}"
}

is_global_ipv4() {
  local ip="$1"
  parse_ipv4 "${ip}" || return 1
  ! is_private_ipv4 "${ip}" && ! is_special_ipv4 "${ip}"
}

validate_bind_interface() {
  local bind_ip="$1"

  if ! command -v ip >/dev/null 2>&1; then
    echo "监听地址核验需要 iproute2 的 ip 命令；请安装后重试。" >&2
    return 1
  fi
  if ! ip -4 -o address show | awk -v wanted="${bind_ip}" '
    $3 == "inet" {
      address = $4
      sub(/\/.*/, "", address)
      if (address == wanted) found = 1
    }
    END { exit(found ? 0 : 1) }
  '; then
    echo "HOMEDESK_PUBLIC_BIND_IP 不属于当前主机的任何 IPv4 接口。" >&2
    return 1
  fi
}

is_public_domain() {
  local host="$1"
  local label
  local last_label
  local -a labels

  ((${#host} >= 4 && ${#host} <= 253)) || return 1
  [[ "${host}" == *.* ]] || return 1
  [[ "${host}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  # 拒绝 inet_aton 风格缩写、带前导零和越界的伪 IPv4，避免其被 DNS 名称分支接纳。
  [[ ! "${host}" =~ ^[0-9.]+$ ]] || return 1
  [[ "${host}" != .* && "${host}" != *. && "${host}" != *..* ]] || return 1
  case "${host,,}" in
    localhost|*.localhost|*.local|*.invalid|*.test|*.example)
      return 1
      ;;
  esac

  IFS=. read -r -a labels <<< "${host}"
  last_label="${labels[$((${#labels[@]} - 1))]}"
  [[ ! "${last_label}" =~ ^[0-9]+$ ]] || return 1
  for label in "${labels[@]}"; do
    ((${#label} >= 1 && ${#label} <= 63)) || return 1
    [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

validate_public_dns() {
  local host="$1"
  local resolved_ip
  local -a resolved_ipv4=()

  if ! command -v getent >/dev/null 2>&1; then
    echo "域名通告需要 getent 以核验 A 记录；请安装系统解析工具后重试。" >&2
    return 1
  fi
  mapfile -t resolved_ipv4 < <(getent ahostsv4 "${host}" | awk '{print $1}' | sort -u)
  if [[ "${#resolved_ipv4[@]}" -eq 0 ]]; then
    echo "HOMEDESK_PUBLIC_RELAY_HOST 当前没有可解析的 IPv4 A 记录。" >&2
    return 1
  fi
  for resolved_ip in "${resolved_ipv4[@]}"; do
    if ! is_global_ipv4 "${resolved_ip}"; then
      echo "HOMEDESK_PUBLIC_RELAY_HOST 的 A 记录包含私网、回环、链路本地、保留或测试地址。" >&2
      return 1
    fi
  done
}

validate_public_config() {
  local bind_ip="${public_config[HOMEDESK_PUBLIC_BIND_IP]}"
  local relay_host="${public_config[HOMEDESK_PUBLIC_RELAY_HOST]}"
  local relay_port="${public_config[HOMEDESK_PUBLIC_RELAY_PORT]}"

  if ! is_bind_ipv4 "${bind_ip}"; then
    echo "HOMEDESK_PUBLIC_BIND_IP 必须是主机实际拥有的单个普通 IPv4；拒绝全部接口、回环、链路本地、组播、保留及测试地址。" >&2
    return 1
  fi
  if [[ "${MODE}" != "--ops-config-only" ]]; then
    validate_bind_interface "${bind_ip}" || return 1
  fi
  if parse_ipv4 "${relay_host}"; then
    if ! is_global_ipv4 "${relay_host}"; then
      echo "HOMEDESK_PUBLIC_RELAY_HOST 的数字地址必须是公网 IPv4；主机私网监听地址请只填入 BIND_IP。" >&2
      return 1
    fi
  else
    if ! is_public_domain "${relay_host}"; then
      echo "HOMEDESK_PUBLIC_RELAY_HOST 必须是公网 IPv4 或 ASCII 公网域名，不能包含协议、路径、端口、通配符或本地域名。" >&2
      return 1
    fi
    if [[ "${MODE}" != "--ops-config-only" ]]; then
      validate_public_dns "${relay_host}" || return 1
    fi
  fi
  if [[ ! "${relay_port}" =~ ^[0-9]+$ ]] || ((10#${relay_port} < 1 || 10#${relay_port} > 65535)); then
    echo "HOMEDESK_PUBLIC_RELAY_PORT 必须是 1–65535 的十进制端口。" >&2
    return 1
  fi
  if [[ "${relay_port}" != "21117" ]]; then
    echo "当前公网基线只允许中继端口 21117；自定义端口尚未纳入客户端和防火墙验收。" >&2
    return 1
  fi
}

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

check_expanded_compose() {
  local rendered ports expected_ports
  local -a configured_images services

  compose config --quiet
  mapfile -t configured_images < <(compose config --images)
  if [[ "${#configured_images[@]}" -ne 2 ]]; then
    echo "公网 Compose 必须且只能包含 hbbs/hbbr 两个锁定镜像。" >&2
    return 1
  fi
  for image in "${configured_images[@]}"; do
    if [[ "${image}" != "${EXPECTED_IMAGE}" ]]; then
      echo "公网 Compose 的镜像引用与锁定的 OSS 1.1.16 digest 不一致。" >&2
      return 1
    fi
  done

  mapfile -t services < <(compose config --services | sort)
  if [[ "${services[*]}" != "hbbr hbbs" ]]; then
    echo "公网 Compose 只能启动 hbbs 与 hbbr，禁止捎带 Console 或其他服务。" >&2
    return 1
  fi

  rendered="$(mktemp)"
  TEMP_RENDERED="${rendered}"
  compose config --format json > "${rendered}"
  ports="$(awk '
    /"ports": \[/ { in_ports = 1; next }
    in_ports && /^      \]/ { in_ports = 0 }
    in_ports && /"host_ip":/ { value = $0; sub(/^.*"host_ip": "/, "", value); sub(/".*$/, "", value); host = value }
    in_ports && /"target": [0-9]+/ { value = $0; sub(/^.*"target": /, "", value); sub(/,.*/, "", value); target = value }
    in_ports && /"published":/ { value = $0; sub(/^.*"published": "/, "", value); sub(/".*$/, "", value); published = value }
    in_ports && /"protocol":/ { value = $0; sub(/^.*"protocol": "/, "", value); sub(/".*$/, "", value); protocol = value }
    in_ports && /^        }/ && target != "" { print host "|" target "|" published "|" protocol; host = target = published = protocol = "" }
  ' "${rendered}" | sort)"
  expected_ports="$(printf '%s\n' \
    "${public_config[HOMEDESK_PUBLIC_BIND_IP]}|21115|21115|tcp" \
    "${public_config[HOMEDESK_PUBLIC_BIND_IP]}|21116|21116|tcp" \
    "${public_config[HOMEDESK_PUBLIC_BIND_IP]}|21116|21116|udp" \
    "${public_config[HOMEDESK_PUBLIC_BIND_IP]}|21117|21117|tcp" | sort)"
  if [[ "${ports}" != "${expected_ports}" ]]; then
    rm -f -- "${rendered}"
    TEMP_RENDERED=""
    echo "公网 Compose 展开的端口不符合白名单（仅 TCP 21115/21116/21117 与 UDP 21116）。" >&2
    return 1
  fi
  if ! grep -Fq -- "\"${public_config[HOMEDESK_PUBLIC_RELAY_HOST]}:${public_config[HOMEDESK_PUBLIC_RELAY_PORT]}\"" "${rendered}"; then
    rm -f -- "${rendered}"
    TEMP_RENDERED=""
    echo "公网 Compose 未正确分离监听地址与中继通告地址。" >&2
    return 1
  fi
  if [[ "$(grep -c '"_"' "${rendered}")" -ne 2 ]]; then
    rm -f -- "${rendered}"
    TEMP_RENDERED=""
    echo "公网 Compose 必须为 hbbs 与 hbbr 同时启用 -k _ 密钥校验。" >&2
    return 1
  fi
  rm -f -- "${rendered}"
  TEMP_RENDERED=""
}

read_public_config
validate_public_config

# 覆盖调用者环境，Compose 只能看到已经逐项校验的值；配置文件从不作为 shell 代码执行。
export HOMEDESK_PUBLIC_BIND_IP="${public_config[HOMEDESK_PUBLIC_BIND_IP]}"
export HOMEDESK_PUBLIC_RELAY_HOST="${public_config[HOMEDESK_PUBLIC_RELAY_HOST]}"
export HOMEDESK_PUBLIC_RELAY_PORT="${public_config[HOMEDESK_PUBLIC_RELAY_PORT]}"

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令；请先安装 Docker Engine 与 Compose v2。" >&2
  exit 1
fi

docker compose version
check_expanded_compose
if [[ "${MODE}" == "--ops-config-only" ]]; then
  echo "本地配置结构、固定镜像、服务集合和端口白名单校验通过。"
else
  echo "公网地址、固定镜像、服务集合和端口白名单校验通过。"
fi

if [[ "${MODE}" == "--config-only" || "${MODE}" == "--ops-config-only" ]]; then
  exit 0
fi

if [[ "${MODE}" == "--print-command" ]]; then
  echo "经审查后可手动执行："
  echo "  bash ./verify-public.sh"
  exit 0
fi

compose pull
compose up -d

services_ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
  running_services="$(compose ps --status running --services | sort)"
  if [[ "${running_services}" == $'hbbr\nhbbs' && -s public-data/id_ed25519.pub ]]; then
    services_ready=true
    break
  fi
  sleep 1
done

if [[ "${services_ready}" != true ]]; then
  echo "hbbs/hbbr 未在 30 秒内全部进入 running，或公钥尚未生成。" >&2
  echo "请在部署主机本地检查：docker compose --env-file .env.public -f compose.public.yml logs --tail 100 hbbs hbbr" >&2
  exit 1
fi

for container in homedesk-public-hbbs homedesk-public-hbbr; do
  restart_policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "${container}")"
  if [[ "${restart_policy}" != "unless-stopped" ]]; then
    echo "${container} 的重启策略异常。" >&2
    exit 1
  fi
done

echo "公网 hbbs/hbbr 已启动；公钥文件位于 server/public-data/id_ed25519.pub。"
echo "公钥用于核验服务器身份，不是秘密，也不会授予设备访问权限；私钥不得复制给客户端。"
echo "真实公网可达性、跨网 P2P、中继兜底和加密状态仍需按部署文档在独立网络验收。"
