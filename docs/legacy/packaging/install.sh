#!/usr/bin/env bash
set -Eeuo pipefail

upgrade=false
if [[ ${1:-} == "--upgrade" ]]; then
  upgrade=true
elif [[ $# -ne 0 ]]; then
  echo "usage: sudo ./install.sh [--upgrade]" >&2
  exit 2
fi
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "install.sh must run as root" >&2
  exit 1
fi

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
client_source="$root_dir/bin/home-tunnel-client"
gui_source="$root_dir/bin/home-tunnel-gui"
agent_source="$root_dir/lib/home-tunnel-agent"
unit_source="$root_dir/lib/systemd/system/home-tunnel-client.service"
enroll_source="$root_dir/libexec/home-tunnel-enroll"
desktop_source="$root_dir/lib/home-tunnel.desktop"
native_source="$root_dir/bin/home_tunnel_remote_host"
native_checksum="$root_dir/native-remote/worker.sha256"
for required in "$client_source" "$gui_source" "$agent_source" "$unit_source" "$enroll_source"; do
  [[ -f "$required" ]] || { echo "missing package file: $required" >&2; exit 1; }
done
if [[ -e "$native_source" || -L "$native_source" || -e "$native_checksum" || -L "$native_checksum" ]]; then
  [[ -f "$native_source" && ! -L "$native_source" && -f "$native_checksum" && ! -L "$native_checksum" ]] || { echo "Native package is incomplete or linked" >&2; exit 1; }
  [[ $(wc -l < "$native_checksum") -eq 1 ]] && grep -Eq '^[0-9a-f]{64}  bin/home_tunnel_remote_host$' "$native_checksum" || { echo "Invalid native worker checksum" >&2; exit 1; }
  (cd "$root_dir" && sha256sum --check --strict native-remote/worker.sha256) || { echo "Native worker package verification failed" >&2; exit 1; }
fi

client_target=/usr/local/bin/home-tunnel-client
gui_target=/usr/local/bin/home-tunnel-gui
agent_target=/usr/local/lib/home-tunnel/home-tunnel-agent
unit_target=/etc/systemd/system/home-tunnel-client.service
enroll_target=/usr/local/sbin/home-tunnel-enroll
desktop_target=/usr/local/share/applications/home-tunnel.desktop
native_target=/usr/local/bin/home_tunnel_remote_host
if [[ -e "$client_target" || -e "$gui_target" || -e "$agent_target" || -e "$unit_target" || -e "$enroll_target" || -e "$native_target" ]] && ! $upgrade; then
  echo "Home Tunnel Linux client is already installed; use --upgrade to replace binaries" >&2
  exit 1
fi

# Closing a GUI window only hides it to the tray. Require its normal Quit path
# so remote sessions and injected input are released before any files change.
if ! command -v pgrep >/dev/null 2>&1; then
  echo "pgrep is required to verify that the desktop client has exited" >&2
  exit 1
fi
if pgrep -x home-tunnel-gui >/dev/null 2>&1; then
  echo "Choose Quit in every Home Tunnel window or tray and wait for remote sessions to stop before upgrading." >&2
  exit 1
else
  process_check=$?
  if [[ $process_check -ne 1 ]]; then
    echo "Could not verify that the desktop client has exited" >&2
    exit 1
  fi
fi

backup_dir=$(mktemp -d /var/tmp/home-tunnel-install.XXXXXX)
committed=false
backups_complete=false
files_modified=false
service_stopped=false
was_active=false
if systemctl is-active --quiet home-tunnel-client.service; then
  was_active=true
fi
rollback() {
  exit_code=$?
  trap - EXIT INT TERM
  recovery_failed=false
  if ! $committed && $backups_complete && $files_modified; then
    if $service_stopped && ! systemctl stop home-tunnel-client.service; then
      echo "Could not stop the service for rollback; previous files are retained at $backup_dir" >&2
      exit 1
    fi
    for target in "$client_target" "$gui_target" "$agent_target" "$unit_target" "$enroll_target" "$desktop_target" "$native_target"; do
      name=$(printf '%s' "$target" | tr '/' '_')
      if [[ -f "$backup_dir/$name" ]]; then
        if ! cp -p -- "$backup_dir/$name" "$target"; then recovery_failed=true; fi
      elif [[ -e "$target" ]]; then
        if ! rm -f -- "$target"; then recovery_failed=true; fi
      fi
    done
    if ! systemctl daemon-reload; then recovery_failed=true; fi
  fi
  if ! $committed && $service_stopped && ! $recovery_failed; then
    if ! systemctl start home-tunnel-client.service; then recovery_failed=true; fi
  fi
  if $recovery_failed; then
    echo "Upgrade recovery failed; previous files are retained at $backup_dir. Keep the service stopped until recovery is complete." >&2
    exit 1
  fi
  if ! rm -rf -- "$backup_dir"; then
    echo "Could not remove temporary backup directory: $backup_dir" >&2
    if [[ $exit_code -eq 0 ]]; then exit_code=1; fi
  fi
  exit "$exit_code"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for target in "$client_target" "$gui_target" "$agent_target" "$unit_target" "$enroll_target" "$desktop_target" "$native_target"; do
  if [[ -L "$target" ]]; then
    echo "Refusing to replace a linked installation target: $target" >&2
    exit 1
  fi
  if [[ -f "$target" ]]; then
    cp -p -- "$target" "$backup_dir/$(printf '%s' "$target" | tr '/' '_')"
  elif [[ -e "$target" ]]; then
    echo "Refusing to replace a non-file installation target: $target" >&2
    exit 1
  fi
done
backups_complete=true

if $was_active; then
  systemctl stop home-tunnel-client.service
  service_stopped=true
fi

if ! id home-tunnel >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/home-tunnel --shell /usr/sbin/nologin --user-group home-tunnel
fi
install -d -m 0755 /usr/local/bin /usr/local/sbin /usr/local/lib/home-tunnel /usr/local/share/applications
install -d -o home-tunnel -g home-tunnel -m 0700 /var/lib/home-tunnel
files_modified=true
install -m 0755 "$client_source" "$client_target"
install -m 0755 "$gui_source" "$gui_target"
if [[ -f "$native_source" ]]; then
  install -m 0755 "$native_source" "$native_target"
elif [[ -e "$native_target" ]]; then
  # A tunnel-only package must not retain a worker from an older installation.
  rm -f -- "$native_target"
fi
install -m 0755 "$agent_source" "$agent_target"
install -m 0755 "$enroll_source" "$enroll_target"
install -m 0644 "$unit_source" "$unit_target"
if [[ -f "$desktop_source" ]]; then
  install -m 0644 "$desktop_source" "$desktop_target"
fi
systemctl daemon-reload

if $upgrade && [[ -f /var/lib/home-tunnel/state.json ]]; then
  if $was_active; then
    systemctl start home-tunnel-client.service
  fi
  echo "Home Tunnel Linux client upgraded."
else
  echo "Home Tunnel Linux client installed."
  echo "Headless: sudo home-tunnel-enroll"
  echo "Desktop:  home-tunnel-gui"
fi
committed=true
