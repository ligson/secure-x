#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/dev-common.sh"

ensure_dev_dirs
require_command go
require_command python3
write_backend_config

cleanup_stale_pid_file "${BACKEND_PID_FILE}" "${BACKEND_BIN_FILE}"
cleanup_stale_pid_file "${BACKEND_LEGACY_PID_FILE}" "${BACKEND_LEGACY_BIN_FILE}"

existing_pid="$(read_pid_file "${BACKEND_PID_FILE}")"
if [[ -n "${existing_pid}" ]] && pid_matches_pattern "${existing_pid}" "${BACKEND_BIN_FILE}"; then
  echo "secure-x 后端已在运行 (pid ${existing_pid})"
else
  legacy_pid="$(read_pid_file "${BACKEND_LEGACY_PID_FILE}")"
  if [[ -n "${legacy_pid}" ]] && pid_matches_pattern "${legacy_pid}" "${BACKEND_LEGACY_BIN_FILE}"; then
    stop_pid_gracefully "${legacy_pid}" "旧版 securex-be 后端实例"
    rm -f "${BACKEND_LEGACY_PID_FILE}"
  fi
  stop_matching_processes "${BACKEND_LEGACY_BIN_FILE}" "旧版 securex-be 后端残留实例" || true
  stop_matching_processes "${BACKEND_BIN_FILE}" "secure-x 后端残留实例" || true

  echo "正在启动 secure-x 后端：${BACKEND_ADDR}"
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
  echo "secure-x 后端启动失败，请查看 ${BACKEND_LOG_FILE}" >&2
  exit 1
fi

if ! wait_for_backend_ready; then
  echo "secure-x 后端已启动 (pid ${pid})，但健康检查未就绪，请查看 ${BACKEND_LOG_FILE}" >&2
  exit 1
fi

echo "secure-x 后端已启动 (pid ${pid})"
echo "日志：${BACKEND_LOG_FILE}"
