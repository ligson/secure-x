#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="${ROOT_DIR}/.dev"
PID_DIR="${DEV_DIR}/pids"
LOG_DIR="${DEV_DIR}/logs"
BIN_DIR="${DEV_DIR}/bin"

BACKEND_PID_FILE="${PID_DIR}/securex-be.pid"
APP_PID_FILE="${PID_DIR}/securex-app.pid"

BACKEND_LOG_FILE="${LOG_DIR}/securex-be.log"
APP_LOG_FILE="${LOG_DIR}/securex-app.log"
BACKEND_BIN_FILE="${BIN_DIR}/securex-be"
APP_MACOS_BIN_FILE="${ROOT_DIR}/securex-app/build/macos/Build/Products/Debug/securex_app.app/Contents/MacOS/securex_app"

BACKEND_ADDR="${BACKEND_ADDR:-127.0.0.1:8080}"
BACKEND_DATABASE_DSN="${BACKEND_DATABASE_DSN:-${ROOT_DIR}/.dev/securex.db}"
BACKEND_FILE_DIR="${BACKEND_FILE_DIR:-${ROOT_DIR}/.dev/files}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"

ensure_dev_dirs() {
  mkdir -p "${PID_DIR}" "${LOG_DIR}" "${BIN_DIR}" "${BACKEND_FILE_DIR}"
}

is_pid_running() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  kill -0 "${pid}" >/dev/null 2>&1
}

read_pid_file() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    tr -d '[:space:]' <"${pid_file}"
  fi
}

cleanup_stale_pid_file() {
  local pid_file="$1"
  local pid
  pid="$(read_pid_file "${pid_file}")"

  if [[ -n "${pid}" ]] && ! is_pid_running "${pid}"; then
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

  ps -ax -o pid= -o command= | awk -v pattern="${pattern}" '
    index($0, pattern) > 0 { print $1 }
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
