#!/usr/bin/env bash
set -euo pipefail

META="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell/wallhaven-variety.json"
DEST="${1:-}"

if [[ -z "${DEST}" ]]; then
    echo "Usage: $(basename "$0") /path/to/variety/wallpapers" >&2
    exit 1
fi

sync_once() {
    if [[ ! -f "${META}" ]]; then
        return 0
    fi
    LOCAL="$(python3 - <<PY
import json
with open("${META}", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("localPath") or "")
PY
)"
    [[ -n "${LOCAL}" && -f "${LOCAL}" ]] || return 0
    mkdir -p "${DEST}"
    ln -sf "${LOCAL}" "${DEST}/wallhaven-current.jpg"
    echo "Synced ${LOCAL}"
}

sync_once

if command -v inotifywait >/dev/null 2>&1; then
    echo "Watching ${META} (Ctrl+C to stop)"
    while inotifywait -e close_write,modify,move_self "${META}" >/dev/null 2>&1; do
        sync_once
    done
else
    echo "inotify-tools not installed; run occasionally or use variety-sync.sh"
fi
