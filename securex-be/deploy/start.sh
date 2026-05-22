#!/usr/bin/env bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_FILE="${SECURE_X_BIN:-${APP_DIR}/secure-x}"
CONFIG_FILE="${SECURE_X_CONFIG:-${APP_DIR}/config.yaml}"
RUN_DIR="${SECURE_X_RUN_DIR:-${APP_DIR}/run}"
PID_FILE="${SECURE_X_PID_FILE:-${RUN_DIR}/secure-x.pid}"
BOOT_LOG_FILE="${SECURE_X_BOOT_LOG:-${APP_DIR}/logs/secure-x-console.log}"

mkdir -p "${RUN_DIR}" "$(dirname "${BOOT_LOG_FILE}")"

if [[ ! -x "${BIN_FILE}" ]]; then
  echo "启动失败：找不到可执行文件 ${BIN_FILE}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "启动失败：找不到配置文件 ${CONFIG_FILE}，请先复制 config.example.yaml 为 config.yaml 并修改密钥。" >&2
  exit 1
fi

if [[ -f "${PID_FILE}" ]]; then
  old_pid="$(tr -d '[:space:]' <"${PID_FILE}")"
  if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" >/dev/null 2>&1; then
    echo "secure-x 已在运行，pid=${old_pid}"
    exit 0
  fi
  rm -f "${PID_FILE}"
fi

echo "正在启动 secure-x 后端..."
nohup "${BIN_FILE}" --config "${CONFIG_FILE}" >>"${BOOT_LOG_FILE}" 2>&1 &
pid="$!"
echo "${pid}" >"${PID_FILE}"

sleep 1
if ! kill -0 "${pid}" >/dev/null 2>&1; then
  echo "启动失败：进程已退出，请查看 ${BOOT_LOG_FILE} 或配置中的 logging.dir。" >&2
  exit 1
fi

echo "secure-x 后端已启动，pid=${pid}"
echo "控制台日志：${BOOT_LOG_FILE}"
