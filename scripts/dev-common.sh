#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="${ROOT_DIR}/.dev"
PID_DIR="${DEV_DIR}/pids"
LOG_DIR="${DEV_DIR}/logs"
BIN_DIR="${DEV_DIR}/bin"
LOCK_DIR="${DEV_DIR}/locks"

BACKEND_PID_FILE="${PID_DIR}/secure-x.pid"
BACKEND_LEGACY_PID_FILE="${PID_DIR}/securex-be.pid"

BACKEND_LOG_FILE="${LOG_DIR}/securex-be.log"
BACKEND_BIN_FILE="${BIN_DIR}/secure-x"
BACKEND_LEGACY_BIN_FILE="${BIN_DIR}/securex-be"
BACKEND_CONFIG_FILE="${DEV_DIR}/securex-be.yaml"
APP_MACOS_APP_FILE="${ROOT_DIR}/securex-app/build/macos/Build/Products/Debug/secure-x.app"
APP_MACOS_BIN_FILE="${ROOT_DIR}/securex-app/build/macos/Build/Products/Debug/secure-x.app/Contents/MacOS/secure-x"

BACKEND_ADDR="${BACKEND_ADDR:-127.0.0.1:8080}"
BACKEND_DATABASE_DSN="${BACKEND_DATABASE_DSN:-${ROOT_DIR}/.dev/securex.db}"
BACKEND_FILE_DIR="${BACKEND_FILE_DIR:-${ROOT_DIR}/.dev/files}"
BACKEND_JWT_SECRET="${BACKEND_JWT_SECRET:-securex-dev-secret}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
BACKEND_HEALTHCHECK_URL="${BACKEND_HEALTHCHECK_URL:-http://${BACKEND_ADDR}/healthz}"

ensure_dev_dirs() {
  mkdir -p "${PID_DIR}" "${LOG_DIR}" "${BIN_DIR}" "${LOCK_DIR}" "${BACKEND_FILE_DIR}"
}

lock_path() {
  local name="$1"
  printf '%s/%s.lock' "${LOCK_DIR}" "${name}"
}

acquire_lock() {
  local lock_name="$1"
  local lock_path_value
  lock_path_value="$(lock_path "${lock_name}")"
  local attempts=0

  while ! mkdir "${lock_path_value}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if (( attempts > 240 )); then
      echo "Timed out waiting for lock: ${lock_name}" >&2
      return 1
    fi
    sleep 0.5
  done
}

release_lock() {
  local lock_name="$1"
  rm -rf "$(lock_path "${lock_name}")"
}

write_backend_config() {
  umask 077
  cat >"${BACKEND_CONFIG_FILE}" <<EOF
server:
  addr: "${BACKEND_ADDR}"
database:
  dsn: "${BACKEND_DATABASE_DSN}"
storage:
  fileDir: "${BACKEND_FILE_DIR}"
logging:
  dir: "${LOG_DIR}"
  appFile: "secure-x.log"
  accessFile: "access.log"
auth:
  jwtSecret: "${BACKEND_JWT_SECRET}"
realtime:
  iceServers: []
  livekit:
    enabled: false
    url: ""
    apiKey: ""
    apiSecret: ""
    turnMode: ""
EOF
}

sanitize_instance_name() {
  local value="$1"
  value="${value//[^a-zA-Z0-9_.-]/-}"
  if [[ -z "${value}" ]]; then
    value="default"
  fi
  printf '%s' "${value}"
}

new_app_instance_name() {
  sanitize_instance_name "${APP_INSTANCE:-app-$(date +%Y%m%d%H%M%S)-$$}"
}

app_pid_file() {
  local instance="$1"
  printf '%s/securex-app-%s.pid' "${PID_DIR}" "$(sanitize_instance_name "${instance}")"
}

app_log_file() {
  local instance="$1"
  printf '%s/securex-app-%s.log' "${LOG_DIR}" "$(sanitize_instance_name "${instance}")"
}

app_data_dir() {
  local instance="$1"
  printf '%s/app-data/%s' "${DEV_DIR}" "$(sanitize_instance_name "${instance}")"
}

is_pid_running() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  kill -0 "${pid}" >/dev/null 2>&1
}

pid_command() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  ps -p "${pid}" -o command= 2>/dev/null
}

pid_matches_pattern() {
  local pid="$1"
  local pattern="$2"

  if [[ -z "${pid}" ]] || [[ -z "${pattern}" ]] || ! is_pid_running "${pid}"; then
    return 1
  fi

  local command
  command="$(pid_command "${pid}")"
  [[ -n "${command}" ]] && [[ "${command}" == *"${pattern}"* ]]
}

read_pid_file() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    tr -d '[:space:]' <"${pid_file}"
  fi
}

cleanup_stale_pid_file() {
  local pid_file="$1"
  local pattern="${2:-}"
  local pid
  pid="$(read_pid_file "${pid_file}")"

  if [[ -n "${pid}" ]] && ! is_pid_running "${pid}"; then
    rm -f "${pid_file}"
    return
  fi

  if [[ -n "${pid}" ]] && [[ -n "${pattern}" ]] && ! pid_matches_pattern "${pid}" "${pattern}"; then
    rm -f "${pid_file}"
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

list_matching_pids() {
  local pattern="$1"
  pgrep -f -- "${pattern}" 2>/dev/null | awk -v self="$$" -v parent="${PPID:-0}" '
    $1 != self && $1 != parent { print $1 }
  '
}

stop_pid_gracefully() {
  local pid="$1"
  local label="$2"

  if [[ -z "${pid}" ]] || ! is_pid_running "${pid}"; then
    return 0
  fi

  echo "Stopping ${label} (pid ${pid})"
  kill "${pid}" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! is_pid_running "${pid}"; then
      return 0
    fi
    sleep 0.5
  done

  echo "${label} did not stop gracefully, forcing shutdown"
  kill -9 "${pid}" >/dev/null 2>&1 || true
}

stop_matching_processes() {
  local pattern="$1"
  local label="$2"
  local found=1
  local pid

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    found=0
    stop_pid_gracefully "${pid}" "${label}"
  done < <(list_matching_pids "${pattern}")

  return "${found}"
}

activate_macos_app() {
  if [[ "${FLUTTER_DEVICE}" != "macos" ]]; then
    return 0
  fi

  open -a "${APP_MACOS_APP_FILE}" >/dev/null 2>&1 || true
}

wait_for_backend_ready() {
  local attempts="${1:-40}"
  local delay_seconds="${2:-0.5}"
  local attempt

  require_command curl

  for attempt in $(seq 1 "${attempts}"); do
    if curl -fsS "${BACKEND_HEALTHCHECK_URL}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay_seconds}"
  done

  return 1
}
