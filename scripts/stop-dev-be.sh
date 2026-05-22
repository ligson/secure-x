#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

stopped=0
cleanup_stale_pid_file "${BACKEND_PID_FILE}" "${BACKEND_BIN_FILE}"
cleanup_stale_pid_file "${BACKEND_LEGACY_PID_FILE}" "${BACKEND_LEGACY_BIN_FILE}"

pid="$(read_pid_file "${BACKEND_PID_FILE}")"
if [[ -n "${pid}" ]] && pid_matches_pattern "${pid}" "${BACKEND_BIN_FILE}"; then
  stop_pid_gracefully "${pid}" "secure-x 后端"
  stopped=1
fi
rm -f "${BACKEND_PID_FILE}"

legacy_pid="$(read_pid_file "${BACKEND_LEGACY_PID_FILE}")"
if [[ -n "${legacy_pid}" ]] && pid_matches_pattern "${legacy_pid}" "${BACKEND_LEGACY_BIN_FILE}"; then
  stop_pid_gracefully "${legacy_pid}" "旧版 securex-be 后端实例"
  stopped=1
fi
rm -f "${BACKEND_LEGACY_PID_FILE}"

if stop_matching_processes "${BACKEND_LEGACY_BIN_FILE}" "旧版 securex-be 后端残留实例"; then
  stopped=1
fi

if stop_matching_processes "${BACKEND_BIN_FILE}" "secure-x 后端残留实例"; then
  stopped=1
fi

if [[ "${stopped}" == "1" ]]; then
  echo "secure-x 后端已停止"
else
  echo "secure-x 后端未运行"
fi
