#!/usr/bin/env bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${SECURE_X_RUN_DIR:-${APP_DIR}/run}"
PID_FILE="${SECURE_X_PID_FILE:-${RUN_DIR}/secure-x.pid}"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "secure-x 未运行：找不到 pid 文件 ${PID_FILE}"
  exit 0
fi

pid="$(tr -d '[:space:]' <"${PID_FILE}")"
if [[ -z "${pid}" ]] || ! kill -0 "${pid}" >/dev/null 2>&1; then
  rm -f "${PID_FILE}"
  echo "secure-x 未运行：pid 已失效"
  exit 0
fi

echo "正在停止 secure-x 后端，pid=${pid}..."
kill "${pid}" >/dev/null 2>&1 || true

for _ in {1..30}; do
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    rm -f "${PID_FILE}"
    echo "secure-x 后端已停止"
    exit 0
  fi
  sleep 1
done

echo "进程未在预期时间内退出，执行强制停止。"
kill -9 "${pid}" >/dev/null 2>&1 || true
rm -f "${PID_FILE}"
echo "secure-x 后端已强制停止"
