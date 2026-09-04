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

Usage: $(basename "$0") <command> [args...]

Commands:
  next|prev|reload|pause|resume|like|dislike|pin|unpin|info
  copyid|copyurl|warm|prune|endtrip|undo|clearkey|testkey
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

write_control_file() {
    local cmd="$1"
    local query="${2:-}"
    python3 - <<PY
import json, time
payload = {"cmd": "${cmd}", "ts": int(time.time() * 1000), "group": "${GROUP}"}
query = """${query}"""
if query:
    payload["query"] = query
with open("${CONTROL_FILE}", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
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
    if [[ -f "${DBUS_PY}" ]]; then
        WALLHAVEN_SYNC_GROUP="${GROUP}" python3 "${DBUS_PY}" "${cmd}" ${query@Q} 2>/dev/null && return 0
    fi
    write_control_file "${cmd}" "${query}"
    echo "Sent ${cmd} to ${CONTROL_FILE}"
}

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
    if [[ -f "${DBUS_PY}" ]]; then
        WALLHAVEN_SYNC_GROUP="${GROUP}" python3 "${DBUS_PY}" search ${QUERY@Q} 2>/dev/null && exit 0
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

if [[ "${CMD}" == "history" ]]; then
    shift
    WALLPAPER_ID="${1:-}"
    if [[ -z "${WALLPAPER_ID}" ]]; then
        echo "Usage: $(basename "$0") history <wallpaper id>" >&2
        exit 1
    fi
    send_with_query history "${WALLPAPER_ID}"
    exit 0
fi

if [[ "${CMD}" == "applysearch" || "${CMD}" == "savesearch" ]]; then
    shift
    NAME="$*"
    if [[ -z "${NAME}" ]]; then
        echo "Usage: $(basename "$0") ${CMD} <name>" >&2
        exit 1
    fi
    send_with_query "${CMD}" "${NAME}"
    exit 0
fi

if [[ "${CMD}" == "purity" ]]; then
    shift
    FLAGS="$*"
    if [[ -z "${FLAGS}" ]]; then
        echo "Usage: $(basename "$0") purity <sfw[,sketchy][,nsfw]>" >&2
        exit 1
    fi
    send_with_query purity "${FLAGS}"
    exit 0
fi

if [[ "${CMD}" == "trip" ]]; then
    shift
    HOURS="${1:-24}"
    send_with_query trip "${HOURS}"
    exit 0
fi

if [[ "${CMD}" == "warm" ]]; then
    shift
    COUNT="${1:-}"
    if [[ -n "${COUNT}" ]]; then
        send_with_query warm "${COUNT}"
    else
        if command -v qdbus6 >/dev/null 2>&1; then
            if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup warm "${GROUP}" 2>/dev/null; then
                echo "Sent 'warm' via D-Bus"
                exit 0
            fi
        fi
        if [[ -f "${DBUS_PY}" ]]; then
            WALLHAVEN_SYNC_GROUP="${GROUP}" python3 "${DBUS_PY}" warm 2>/dev/null && exit 0
        fi
        mkdir -p "${CACHE}"
        write_control_file warm
        echo "Sent 'warm' to ${CONTROL_FILE}"
    fi
    exit 0
fi

case "${CMD}" in
    next|prev|reload|pause|resume|like|dislike|pin|unpin|copyid|copyurl|prune|endtrip|undo|clearkey|testkey|outageoffline|resumeonline) ;;
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
write_control_file "${CMD}"
echo "Sent '${CMD}' to ${CONTROL_FILE}"
