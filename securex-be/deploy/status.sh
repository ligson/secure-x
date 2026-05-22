#!/usr/bin/env bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${SECURE_X_RUN_DIR:-${APP_DIR}/run}"
PID_FILE="${SECURE_X_PID_FILE:-${RUN_DIR}/secure-x.pid}"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "secure-x 状态：未运行"
  exit 3
fi

pid="$(tr -d '[:space:]' <"${PID_FILE}")"
if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
  echo "secure-x 状态：运行中，pid=${pid}"
  exit 0
fi

echo "secure-x 状态：未运行，pid 文件已失效"
exit 1
