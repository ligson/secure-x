#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

stopped=0
cleanup_stale_pid_file "${BACKEND_PID_FILE}" "${BACKEND_BIN_FILE}"

pid="$(read_pid_file "${BACKEND_PID_FILE}")"
if [[ -n "${pid}" ]] && pid_matches_pattern "${pid}" "${BACKEND_BIN_FILE}"; then
  stop_pid_gracefully "${pid}" "securex-be"
  stopped=1
fi
rm -f "${BACKEND_PID_FILE}"

if stop_matching_processes "${BACKEND_BIN_FILE}" "securex-be stray instance"; then
  stopped=1
fi

if [[ "${stopped}" == "1" ]]; then
  echo "securex-be stopped"
else
  echo "securex-be is not running"
fi
