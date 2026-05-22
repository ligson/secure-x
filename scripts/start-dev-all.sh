#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/start-dev-be.sh"
"${SCRIPT_DIR}/start-dev-app.sh"

echo
echo "Development stack started."
echo "Start another isolated frontend with:"
echo "  APP_INSTANCE=user-b ./scripts/start-dev-app.sh"
