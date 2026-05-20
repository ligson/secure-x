#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

stop_process() {
  local name="$1"
  local pid_file="$2"
  local pattern="$3"
  local stopped=0

  cleanup_stale_pid_file "${pid_file}"

  local pid
  pid="$(read_pid_file "${pid_file}")"
  if [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
    stop_pid_gracefully "${pid}" "${name}"
    stopped=1
  fi
  rm -f "${pid_file}"

  if stop_matching_processes "${pattern}" "${name} stray instance"; then
    stopped=1
  fi

  if [[ "${stopped}" == "1" ]]; then
    echo "${name} stopped"
  else
    echo "${name} is not running"
  fi
}

stop_process "securex-app" "${APP_PID_FILE}" "${APP_MACOS_BIN_FILE}"
stop_process "securex-be" "${BACKEND_PID_FILE}" "${BACKEND_BIN_FILE}"
