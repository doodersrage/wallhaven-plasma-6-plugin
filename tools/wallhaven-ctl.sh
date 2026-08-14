#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
GROUP="${WALLHAVEN_SYNC_GROUP:-default}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell"
CONTROL_FILE="${CACHE}/wallhaven-control.json"

usage() {
    cat <<EOF
Send commands to the Wallhaven wallpaper plugin.

Usage: $(basename "$0") <next|prev|reload|pause|resume>

Environment:
  WALLHAVEN_SYNC_GROUP   Control/sync group name (default: default)
EOF
}

case "${CMD}" in
    next|prev|reload|pause|resume) ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "Unknown command: ${CMD}"; usage; exit 1 ;;
esac

mkdir -p "${CACHE}"
python3 - <<PY
import json, time
payload = {"cmd": "${CMD}", "ts": int(time.time() * 1000), "group": "${GROUP}"}
with open("${CONTROL_FILE}", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

echo "Sent '${CMD}' to ${CONTROL_FILE}"
