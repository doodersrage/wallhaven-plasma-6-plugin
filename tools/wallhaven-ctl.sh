#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
GROUP="${WALLHAVEN_SYNC_GROUP:-default}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell"
CONTROL_FILE="${CACHE}/wallhaven-control.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBUS_PY="${SCRIPT_DIR}/wallhaven-dbus.py"

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

if command -v qdbus6 >/dev/null 2>&1; then
    if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup "${CMD}" "${GROUP}" 2>/dev/null; then
        echo "Sent '${CMD}' via D-Bus"
        exit 0
    fi
fi

if [[ -f "${DBUS_PY}" ]]; then
    WALLHAVEN_SYNC_GROUP="${GROUP}" python3 "${DBUS_PY}" "${CMD}" 2>/dev/null && exit 0
fi

mkdir -p "${CACHE}"
python3 - <<PY
import json, time
payload = {"cmd": "${CMD}", "ts": int(time.time() * 1000), "group": "${GROUP}"}
with open("${CONTROL_FILE}", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

echo "Sent '${CMD}' to ${CONTROL_FILE}"
