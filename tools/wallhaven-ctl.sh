#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
GROUP="${WALLHAVEN_SYNC_GROUP:-default}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell"
CONTROL_FILE="${CACHE}/wallhaven-control.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Send commands to the Wallhaven wallpaper plugin.

Usage: $(basename "$0") <command> [args...]

Commands:
  next|prev|reload|pause|resume|like|dislike|pin|unpin|info
  copyid|copyurl|warm|cancelwarm|prune|endtrip|undo|clearkey|testkey
  copysearch [query]
  outageoffline|resumeonline
  search <query>
  history <wallpaper-id>
  applysearch <name>
  savesearch <name>
  purity <sfw[,sketchy][,nsfw]>
  trip [hours]          (default 24)
  importpreset <url>

Environment:
  WALLHAVEN_SYNC_GROUP   Control/sync group name (default: default)
EOF
}

# Always write via env vars — never interpolate query into Python source, and
# never start wallhaven-dbus.py (unknown argv used to fall into MainLoop).
write_control_file() {
    local cmd="$1"
    local query="${2:-}"
    mkdir -p "${CACHE}"
    WALLHAVEN_CTL_CMD="${cmd}" \
    WALLHAVEN_CTL_QUERY="${query}" \
    WALLHAVEN_CTL_GROUP="${GROUP}" \
    WALLHAVEN_CTL_FILE="${CONTROL_FILE}" \
    python3 - <<'PY'
import json, os, time

payload = {
    "cmd": os.environ.get("WALLHAVEN_CTL_CMD", ""),
    "ts": int(time.time() * 1000),
    "group": os.environ.get("WALLHAVEN_CTL_GROUP", "default") or "default",
}
query = os.environ.get("WALLHAVEN_CTL_QUERY", "")
if query:
    payload["query"] = query
path = os.environ["WALLHAVEN_CTL_FILE"]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

send_simple() {
    local cmd="$1"
    if command -v qdbus6 >/dev/null 2>&1; then
        if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup \
            "${cmd}" "${GROUP}" 2>/dev/null; then
            echo "Sent '${cmd}' via D-Bus"
            return 0
        fi
    fi
    write_control_file "${cmd}"
    echo "Sent '${cmd}' to ${CONTROL_FILE}"
}

send_with_query() {
    local cmd="$1"
    local query="$2"
    if command -v qdbus6 >/dev/null 2>&1; then
        if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandWithQuery \
            "${cmd}" "${query}" "${GROUP}" 2>/dev/null; then
            echo "Sent ${cmd} via D-Bus"
            return 0
        fi
    fi
    write_control_file "${cmd}" "${query}"
    echo "Sent ${cmd} to ${CONTROL_FILE}"
}

if [[ -z "${CMD}" || "${CMD}" == "-h" || "${CMD}" == "--help" || "${CMD}" == "help" ]]; then
    usage
    exit 0
fi

if [[ "${CMD}" == "search" ]]; then
    shift
    QUERY="$*"
    if [[ -z "${QUERY}" ]]; then
        echo "Usage: $(basename "$0") search <query>" >&2
        exit 1
    fi
    if command -v qdbus6 >/dev/null 2>&1; then
        if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Search "${QUERY}" "${GROUP}" 2>/dev/null; then
            echo "Sent search via D-Bus"
            exit 0
        fi
    fi
    write_control_file search "${QUERY}"
    echo "Sent search to ${CONTROL_FILE}"
    exit 0
fi

if [[ "${CMD}" == "importpreset" ]]; then
    shift
    PRESET_URL="$*"
    if [[ -z "${PRESET_URL}" ]]; then
        echo "Usage: $(basename "$0") importpreset <wallhaven://preset/...|https://.../preset.json>" >&2
        exit 1
    fi
    write_control_file importpreset "${PRESET_URL}"
    echo "Sent preset import to ${CONTROL_FILE}"
    exit 0
fi

if [[ "${CMD}" == "info" ]]; then
    if command -v qdbus6 >/dev/null 2>&1; then
        if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup info "${GROUP}" 2>/dev/null; then
            echo "Sent 'info' via D-Bus"
            exit 0
        fi
    fi
    write_control_file info
    echo "Sent 'info' to ${CONTROL_FILE}"
    exit 0
fi

if [[ "${CMD}" == "history" || "${CMD}" == "applysearch" || "${CMD}" == "savesearch" \
        || "${CMD}" == "purity" || "${CMD}" == "trip" || "${CMD}" == "warm" \
        || "${CMD}" == "copysearch" ]]; then
    shift
    if [[ "${CMD}" == "trip" ]]; then
        QUERY="${1:-24}"
    elif [[ "${CMD}" == "warm" ]]; then
        QUERY="${1:-}"
    else
        QUERY="$*"
        if [[ -z "${QUERY}" && "${CMD}" != "warm" ]]; then
            echo "Usage: $(basename "$0") ${CMD} <arg>" >&2
            exit 1
        fi
    fi
    if [[ "${CMD}" == "warm" && -z "${QUERY}" ]]; then
        send_simple warm
        exit 0
    fi
    send_with_query "${CMD}" "${QUERY}"
    exit 0
fi

case "${CMD}" in
    next|prev|reload|pause|resume|like|dislike|pin|unpin|copyid|copyurl|prune|endtrip|undo|clearkey|testkey|outageoffline|resumeonline|cancelwarm)
        send_simple "${CMD}"
        ;;
    *)
        echo "Unknown command: ${CMD}" >&2
        usage
        exit 1
        ;;
esac
