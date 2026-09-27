#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
if [[ -z "${URL}" ]]; then
    echo "Usage: $(basename "$0") 'wallhaven://preset/...'" >&2
    exit 1
fi

# URLs arrive from browsers: hand them to wallhaven-ctl.sh as argv (never
# interpolated into code), which also routes "default" to a real screen.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/wallhaven-ctl.sh" importpreset "${URL}"
