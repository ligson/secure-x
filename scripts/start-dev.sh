#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

START_BACKEND="${START_BACKEND:-1}"
START_APP="${START_APP:-1}"

ensure_dev_dirs

start_backend() {
  cleanup_stale_pid_file "${BACKEND_PID_FILE}"

  local existing_pid
  existing_pid="$(read_pid_file "${BACKEND_PID_FILE}")"
  if [[ -n "${existing_pid}" ]] && is_pid_running "${existing_pid}"; then
    echo "securex-be is already running (pid ${existing_pid})"
    return
  fi

  stop_matching_processes "${BACKEND_BIN_FILE}" "securex-be stray instance" || true

  echo "Starting securex-be on ${BACKEND_ADDR}"
  (
    cd "${ROOT_DIR}/securex-be"
    go build -o "${BACKEND_BIN_FILE}" ./cmd/server
    nohup sh -c \
      "exec env SECUREX_SERVER_ADDR='${BACKEND_ADDR}' SECUREX_DATABASE_DSN='${BACKEND_DATABASE_DSN}' SECUREX_FILE_DIR='${BACKEND_FILE_DIR}' '${BACKEND_BIN_FILE}'" \
      >"${BACKEND_LOG_FILE}" 2>&1 < /dev/null &
    echo $! >"${BACKEND_PID_FILE}"
  )

  sleep 1
  local pid
  pid="$(read_pid_file "${BACKEND_PID_FILE}")"
  if [[ -z "${pid}" ]] || ! is_pid_running "${pid}"; then
    echo "Failed to start securex-be. Check ${BACKEND_LOG_FILE}" >&2
    exit 1
  fi

  echo "securex-be started (pid ${pid})"
}

start_app() {
  cleanup_stale_pid_file "${APP_PID_FILE}"

  if [[ "${FLUTTER_DEVICE}" == "macos" ]]; then
    local running_pids=()
    local running_pid
    while IFS= read -r running_pid; do
      [[ -n "${running_pid}" ]] || continue
      running_pids+=("${running_pid}")
    done < <(list_matching_pids "${APP_MACOS_BIN_FILE}")

    if [[ "${#running_pids[@]}" -eq 1 ]]; then
      echo "${running_pids[0]}" >"${APP_PID_FILE}"
      echo "securex-app is already running (pid ${running_pids[0]})"
      return
    fi
    if [[ "${#running_pids[@]}" -gt 1 ]]; then
      stop_matching_processes "${APP_MACOS_BIN_FILE}" "securex-app duplicate instance" || true
    fi
  fi

  local existing_pid
  existing_pid="$(read_pid_file "${APP_PID_FILE}")"
  if [[ -n "${existing_pid}" ]] && is_pid_running "${existing_pid}"; then
    echo "securex-app is already running (pid ${existing_pid})"
    return
  fi

  stop_matching_processes "${APP_MACOS_BIN_FILE}" "securex-app stray instance" || true

  echo "Starting securex-app on device ${FLUTTER_DEVICE}"
  (
    cd "${ROOT_DIR}/securex-app"
    if [[ "${FLUTTER_DEVICE}" == "macos" ]]; then
      flutter build macos --debug >"${APP_LOG_FILE}" 2>&1
      nohup "${APP_MACOS_BIN_FILE}" >>"${APP_LOG_FILE}" 2>&1 < /dev/null &
      echo $! >"${APP_PID_FILE}"
    else
      nohup sh -c "exec flutter run -d '${FLUTTER_DEVICE}'" >"${APP_LOG_FILE}" 2>&1 < /dev/null &
      echo $! >"${APP_PID_FILE}"
    fi
  )

  sleep 2
  local pid
  pid="$(read_pid_file "${APP_PID_FILE}")"
  if [[ -z "${pid}" ]] || ! is_pid_running "${pid}"; then
    echo "Failed to start securex-app. Check ${APP_LOG_FILE}" >&2
    exit 1
  fi

  echo "securex-app started (pid ${pid})"
}

if [[ "${START_BACKEND}" == "1" ]]; then
  require_command go
  start_backend
fi

if [[ "${START_APP}" == "1" ]]; then
  require_command flutter
  start_app
fi

echo
echo "Logs:"
echo "  backend: ${BACKEND_LOG_FILE}"
echo "  app:     ${APP_LOG_FILE}"
echo
echo "Stop with:"
echo "  ./scripts/stop-dev.sh"
