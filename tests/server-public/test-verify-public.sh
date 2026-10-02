#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE_DIR="$(mktemp -d)"
export COMPOSE_PROJECT_NAME="homedesk-public-test-$$"
RUNTIME_STARTED=false

cleanup() {
  if [[ "${RUNTIME_STARTED}" == true ]]; then
    (cd "${FIXTURE_DIR}" && docker compose --env-file .env.public \
      -f compose.public.yml -f runtime.override.yml down --volumes --remove-orphans >/dev/null 2>&1) || true
  fi
  rm -rf -- "${FIXTURE_DIR}"
}
trap cleanup EXIT

cp "${REPO_ROOT}/server/compose.public.yml" "${FIXTURE_DIR}/compose.public.yml"
cp "${REPO_ROOT}/server/verify-public.sh" "${FIXTURE_DIR}/verify-public.sh"
cp "${REPO_ROOT}/server/public-ops.sh" "${FIXTURE_DIR}/public-ops.sh"
chmod +x "${FIXTURE_DIR}/verify-public.sh"
chmod +x "${FIXTURE_DIR}/public-ops.sh"
mkdir -p "${FIXTURE_DIR}/bin"
cat > "${FIXTURE_DIR}/bin/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "ahostsv4" ]]; then
  exit 2
fi
case "${2:-}" in
  relay.homedesk.example.net)
    echo "11.22.33.44 STREAM relay.homedesk.example.net"
    ;;
  private-answer.homedesk.example.net)
    echo "10.0.0.8 STREAM private-answer.homedesk.example.net"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "${FIXTURE_DIR}/bin/getent"
cat > "${FIXTURE_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "${*}" != "-4 -o address show" ]]; then
  exit 2
fi
cat <<'OUT'
2: eth0    inet 192.168.50.10/24 brd 192.168.50.255 scope global eth0
3: eth1    inet 11.22.33.45/24 brd 11.22.33.255 scope global eth1
4: eth2    inet 11.22.33.0/23 brd 11.22.33.255 scope global eth2
OUT
EOF
chmod +x "${FIXTURE_DIR}/bin/ip"
export PATH="${FIXTURE_DIR}/bin:${PATH}"

write_config() {
  cat > "${FIXTURE_DIR}/.env.public"
}

expect_failure() {
  local label="$1"
  if (cd "${FIXTURE_DIR}" && ./verify-public.sh --config-only >/dev/null 2>&1); then
    echo "失败：${label} 应被拒绝。" >&2
    exit 1
  fi
}

expect_success() {
  local label="$1"
  if ! (cd "${FIXTURE_DIR}" && ./verify-public.sh --config-only >/dev/null); then
    echo "失败：${label} 应通过校验。" >&2
    exit 1
  fi
}

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_success "私网接口监听与公网域名通告分离"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=11.22.33.45
HOMEDESK_PUBLIC_RELAY_HOST=11.22.33.44
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_success "指定公网接口与公网 IPv4 通告"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=11.22.33.0
HOMEDESK_PUBLIC_RELAY_HOST=11.22.32.255
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_success "/23 中末字节为 .0/.255 的合法主机端点"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=0.0.0.0
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "全部接口监听"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=127.0.0.1
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "生产配置使用回环监听"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.60.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "监听地址不属于当前主机接口"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=192.168.50.10
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "向外部客户端通告私网地址"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=private-answer.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "域名解析到私网地址"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=no-answer.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "域名没有 IPv4 A 记录"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=203.0.113.10
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "通告文档保留地址"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=255.255.255.255
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "受限广播地址"

for abbreviated_ip in 127.1 127.0.1 999.999.999.999 01.2.3.4 0x7f.1; do
  write_config <<EOF
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=${abbreviated_ip}
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
  expect_failure "伪装成域名的非标准数字地址 ${abbreviated_ip}"
done

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=https://relay.homedesk.example.net/path
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "通告地址包含协议和路径"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net:21117
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "通告主机重复携带端口"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=0
EOF
expect_failure "零端口"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21118
EOF
expect_failure "未验收的自定义中继端口"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
expect_failure "重复配置项"

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
HOMEDESK_CONSOLE_TOKEN=SHOULD_NOT_BE_ACCEPTED
EOF
expect_failure "额外配置项"

injection_sentinel="${FIXTURE_DIR}/command-injection-sentinel"
printf '%s\n' \
  'HOMEDESK_PUBLIC_BIND_IP=192.168.50.10' \
  "HOMEDESK_PUBLIC_RELAY_HOST=\$(touch ${injection_sentinel})" \
  'HOMEDESK_PUBLIC_RELAY_PORT=21117' > "${FIXTURE_DIR}/.env.public"
expect_failure "命令替换文本"
if [[ -e "${injection_sentinel}" ]]; then
  echo "失败：配置内容被作为 shell 命令执行。" >&2
  exit 1
fi

write_config <<'EOF'
HOMEDESK_PUBLIC_BIND_IP=192.168.50.10
HOMEDESK_PUBLIC_RELAY_HOST=relay.homedesk.example.net
HOMEDESK_PUBLIC_RELAY_PORT=21117
EOF
command_output="$(cd "${FIXTURE_DIR}" && ./verify-public.sh --print-command)"
if [[ "${command_output}" != *"bash ./verify-public.sh"* ]] ||
   [[ "${command_output}" == *"docker compose"*" up -d"* ]]; then
  echo "失败：未输出可审查的部署命令。" >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}/public-data/backup-inside-source"
printf 'test-private-key\n' > "${FIXTURE_DIR}/public-data/id_ed25519"
printf 'test-public-key\n' > "${FIXTURE_DIR}/public-data/id_ed25519.pub"
if (cd "${FIXTURE_DIR}" && ./public-ops.sh backup public-data/backup-inside-source >/dev/null 2>&1); then
  echo "失败：备份目标位于 public-data 内部时应被拒绝。" >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}/backup-existing" "${FIXTURE_DIR}/fixed-date-bin"
existing_archive="${FIXTURE_DIR}/backup-existing/homedesk-public-data-20000101T000000Z.tar.gz"
printf 'do-not-delete\n' > "${existing_archive}"
cat > "${FIXTURE_DIR}/fixed-date-bin/date" <<'EOF'
#!/usr/bin/env bash
echo '20000101T000000Z'
EOF
chmod +x "${FIXTURE_DIR}/fixed-date-bin/date"
if (cd "${FIXTURE_DIR}" && PATH="${FIXTURE_DIR}/fixed-date-bin:${PATH}" \
  ./public-ops.sh backup backup-existing >/dev/null 2>&1); then
  echo "失败：已存在的同名备份必须拒绝覆盖。" >&2
  exit 1
fi
if [[ "$(cat "${existing_archive}")" != "do-not-delete" ]]; then
  echo "失败：拒绝覆盖时改动或删除了已有备份。" >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}/offline-bin"
cat > "${FIXTURE_DIR}/offline-bin/ip" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
cat > "${FIXTURE_DIR}/offline-bin/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "${FIXTURE_DIR}/offline-bin/ip" "${FIXTURE_DIR}/offline-bin/getent"
if ! (cd "${FIXTURE_DIR}" && PATH="${FIXTURE_DIR}/offline-bin:${PATH}" ./verify-public.sh --ops-config-only >/dev/null); then
  echo "失败：运维本地校验不应依赖当前接口或 DNS 可用。" >&2
  exit 1
fi
if (cd "${FIXTURE_DIR}" && PATH="${FIXTURE_DIR}/offline-bin:${PATH}" ./verify-public.sh --config-only >/dev/null 2>&1); then
  echo "失败：部署校验不得跳过当前接口和 DNS 检查。" >&2
  exit 1
fi
if ! (cd "${FIXTURE_DIR}" && PATH="${FIXTURE_DIR}/offline-bin:${PATH}" ./public-ops.sh status >/dev/null); then
  echo "失败：DNS/接口故障时仍应能查看本地容器状态。" >&2
  exit 1
fi

for protected_container in homedesk-public-hbbs homedesk-public-hbbr; do
  if docker inspect "${protected_container}" >/dev/null 2>&1; then
    echo "失败：固定名称的公网容器已存在，无法安全执行备份恢复夹具。" >&2
    exit 1
  fi
done
cat > "${FIXTURE_DIR}/runtime.override.yml" <<'EOF'
services:
  hbbs:
    volumes: !override
      - runtime-data:/root
    ports: !override
      - "127.0.0.1::21115/tcp"
      - "127.0.0.1::21116/tcp"
      - "127.0.0.1::21116/udp"
  hbbr:
    volumes: !override
      - runtime-data:/root
    ports: !override
      - "127.0.0.1::21117/tcp"
volumes:
  runtime-data:
EOF
rm -rf -- "${FIXTURE_DIR}/public-data"
mkdir -p "${FIXTURE_DIR}/public-data"
printf 'test-private-key\n' > "${FIXTURE_DIR}/public-data/id_ed25519"
printf 'test-public-key\n' > "${FIXTURE_DIR}/public-data/id_ed25519.pub"
mkdir -p "${FIXTURE_DIR}/backup-outside-source"
RUNTIME_STARTED=true
(cd "${FIXTURE_DIR}" && docker compose --env-file .env.public \
  -f compose.public.yml -f runtime.override.yml up -d >/dev/null 2>&1)
for ((attempt = 0; attempt < 20; attempt++)); do
  running="$(cd "${FIXTURE_DIR}" && docker compose --env-file .env.public \
    -f compose.public.yml -f runtime.override.yml ps --status running --services | sort)"
  if [[ "${running}" == $'hbbr\nhbbs' ]]; then
    break
  fi
  sleep 1
done
if [[ "${running:-}" != $'hbbr\nhbbs' ]]; then
  echo "失败：备份恢复夹具容器未就绪。" >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}/failing-bin"
cat > "${FIXTURE_DIR}/failing-bin/tar" <<'EOF'
#!/usr/bin/env bash
previous=""
for argument in "$@"; do
  if [[ "${previous}" == "-czf" ]]; then
    : > "${argument}"
    break
  fi
  previous="${argument}"
done
exit 1
EOF
chmod +x "${FIXTURE_DIR}/failing-bin/tar"
set +e
backup_output="$(cd "${FIXTURE_DIR}" && PATH="${FIXTURE_DIR}/failing-bin:${PATH}" \
  ./public-ops.sh backup backup-outside-source 2>&1)"
backup_status=$?
set -e
if [[ "${backup_status}" -eq 0 || "${backup_output}" == *"一致性备份到"* ]]; then
  echo "失败：归档失败时不得报告备份完成。" >&2
  exit 1
fi
if find "${FIXTURE_DIR}/backup-outside-source" -mindepth 1 -print -quit | grep -q .; then
  echo "失败：归档失败后残留半成品备份。" >&2
  exit 1
fi
running="$(cd "${FIXTURE_DIR}" && docker compose --env-file .env.public \
  -f compose.public.yml -f runtime.override.yml ps --status running --services | sort)"
if [[ "${running}" != $'hbbr\nhbbs' ]]; then
  echo "失败：归档失败后未恢复 hbbs/hbbr 原运行状态。" >&2
  exit 1
fi
(cd "${FIXTURE_DIR}" && docker compose --env-file .env.public \
  -f compose.public.yml -f runtime.override.yml down --volumes --remove-orphans >/dev/null 2>&1)
RUNTIME_STARTED=false

echo "公网部署配置校验测试通过。"
