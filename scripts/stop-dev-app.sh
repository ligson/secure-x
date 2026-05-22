#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

stop_app_pid_file() {
  local pid_file="$1"
  local label="$2"
  local stopped=1
  local pid

  cleanup_stale_pid_file "${pid_file}"
  pid="$(read_pid_file "${pid_file}")"
  if [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
    stop_pid_gracefully "${pid}" "${label}"
    stopped=0
  fi
  rm -f "${pid_file}"
  return "${stopped}"
}

stopped=0

if [[ -n "${APP_INSTANCE:-}" ]]; then
  APP_INSTANCE_NAME="$(sanitize_instance_name "${APP_INSTANCE}")"
  if stop_app_pid_file "$(app_pid_file "${APP_INSTANCE_NAME}")" "securex-app ${APP_INSTANCE_NAME}"; then
    stopped=1
  fi
else
  shopt -s nullglob
  for pid_file in "${PID_DIR}"/securex-app-*.pid "${PID_DIR}"/securex-app.pid; do
    instance="$(basename "${pid_file}")"
    instance="${instance#securex-app-}"
    instance="${instance%.pid}"
    if stop_app_pid_file "${pid_file}" "securex-app ${instance}"; then
      stopped=1
    fi
  done
  shopt -u nullglob

  if stop_matching_processes "${APP_MACOS_BIN_FILE}" "securex-app stray instance"; then
    stopped=1
  fi
fi

if [[ "${stopped}" == "1" ]]; then
  echo "securex-app stopped"
else
  echo "securex-app is not running"
fi
