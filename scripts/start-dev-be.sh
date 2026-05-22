#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

ensure_dev_dirs
require_command go
require_command python3
write_backend_config

cleanup_stale_pid_file "${BACKEND_PID_FILE}" "${BACKEND_BIN_FILE}"

existing_pid="$(read_pid_file "${BACKEND_PID_FILE}")"
if [[ -n "${existing_pid}" ]] && pid_matches_pattern "${existing_pid}" "${BACKEND_BIN_FILE}"; then
  echo "securex-be is already running (pid ${existing_pid})"
else
  stop_matching_processes "${BACKEND_BIN_FILE}" "securex-be stray instance" || true

  echo "Starting securex-be on ${BACKEND_ADDR}"
  (
    cd "${ROOT_DIR}/securex-be"
    go build -o "${BACKEND_BIN_FILE}" ./cmd/server
    bootstrap_pid="$(
      python3 - "${BACKEND_LOG_FILE}" "${BACKEND_BIN_FILE}" --config "${BACKEND_CONFIG_FILE}" <<'PY'
import os
import subprocess
import sys

log_path = sys.argv[1]
command = sys.argv[2:]
env = os.environ.copy()

with open(log_path, "ab", buffering=0) as log_file:
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        env=env,
        start_new_session=True,
        close_fds=True,
    )

print(process.pid)
PY
    )"

    actual_pid=""
    for _ in {1..20}; do
      while IFS= read -r running_pid; do
        [[ -n "${running_pid}" ]] || continue
        actual_pid="${running_pid}"
        break
      done < <(list_matching_pids "${BACKEND_BIN_FILE}")

      [[ -n "${actual_pid}" ]] && break
      sleep 0.5
    done

    echo "${actual_pid:-${bootstrap_pid}}" >"${BACKEND_PID_FILE}"
  )
fi

sleep 1
pid="$(read_pid_file "${BACKEND_PID_FILE}")"
if [[ -z "${pid}" ]] || ! is_pid_running "${pid}"; then
  echo "Failed to start securex-be. Check ${BACKEND_LOG_FILE}" >&2
  exit 1
fi

if ! wait_for_backend_ready; then
  echo "securex-be started (pid ${pid}) but health check did not become ready. Check ${BACKEND_LOG_FILE}" >&2
  exit 1
fi

echo "securex-be started (pid ${pid})"
echo "Log: ${BACKEND_LOG_FILE}"
