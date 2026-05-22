#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/stop-dev-app.sh"
"${SCRIPT_DIR}/stop-dev-be.sh"
