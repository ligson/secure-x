#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

ensure_dev_dirs
require_command flutter

APP_INSTANCE_NAME="$(new_app_instance_name)"
APP_PID_FILE="$(app_pid_file "${APP_INSTANCE_NAME}")"
APP_LOG_FILE="$(app_log_file "${APP_INSTANCE_NAME}")"
APP_DATA_DIR="$(app_data_dir "${APP_INSTANCE_NAME}")"

mkdir -p "${APP_DATA_DIR}"
cleanup_stale_pid_file "${APP_PID_FILE}"

existing_pid="$(read_pid_file "${APP_PID_FILE}")"
if [[ -n "${existing_pid}" ]] && is_pid_running "${existing_pid}"; then
  echo "securex-app instance ${APP_INSTANCE_NAME} is already running (pid ${existing_pid})"
  echo "Use a different APP_INSTANCE to start another isolated frontend."
  exit 0
fi

echo "Starting securex-app instance ${APP_INSTANCE_NAME} on device ${FLUTTER_DEVICE}"
(
  cd "${ROOT_DIR}/securex-app"
  if [[ "${FLUTTER_DEVICE}" == "macos" ]]; then
    acquire_lock "flutter-macos-build"
    trap 'release_lock "flutter-macos-build"' EXIT
    flutter build macos --debug >"${APP_LOG_FILE}" 2>&1
    release_lock "flutter-macos-build"
    trap - EXIT
    before_pids="$(list_matching_pids "${APP_MACOS_BIN_FILE}" | sort -n || true)"
    open -n \
      --stdout "${APP_LOG_FILE}" \
      --stderr "${APP_LOG_FILE}" \
      --env "SECUREX_DEV_INSTANCE=${APP_INSTANCE_NAME}" \
      --env "SECUREX_DEV_DATA_DIR=${APP_DATA_DIR}" \
      "${APP_MACOS_APP_FILE}"

    app_pid=""
    for _ in {1..40}; do
      after_pids="$(list_matching_pids "${APP_MACOS_BIN_FILE}" | sort -n || true)"
      while IFS= read -r candidate_pid; do
        [[ -n "${candidate_pid}" ]] || continue
        if ! grep -qx "${candidate_pid}" <<<"${before_pids}"; then
          app_pid="${candidate_pid}"
        fi
      done <<<"${after_pids}"

      if [[ -n "${app_pid}" ]] && is_pid_running "${app_pid}"; then
        break
      fi
      sleep 0.25
    done

    if [[ -n "${app_pid}" ]]; then
      echo "${app_pid}" >"${APP_PID_FILE}"
    fi
  else
    nohup sh -c \
      "exec flutter run -d '${FLUTTER_DEVICE}' --dart-define=SECUREX_DEV_INSTANCE='${APP_INSTANCE_NAME}'" \
      >"${APP_LOG_FILE}" 2>&1 < /dev/null &
    echo $! >"${APP_PID_FILE}"
  fi
)

sleep 2
pid="$(read_pid_file "${APP_PID_FILE}")"
if [[ -z "${pid}" ]] || ! is_pid_running "${pid}"; then
  echo "Failed to start securex-app instance ${APP_INSTANCE_NAME}. Check ${APP_LOG_FILE}" >&2
  exit 1
fi

echo "securex-app started (instance ${APP_INSTANCE_NAME}, pid ${pid})"
echo "Log:  ${APP_LOG_FILE}"
echo "Data: ${APP_DATA_DIR}"
echo
echo "Stop this instance with:"
echo "  APP_INSTANCE=${APP_INSTANCE_NAME} ./scripts/stop-dev-app.sh"
