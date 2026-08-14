#!/usr/bin/env bash
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell"
META="${CACHE}/wallhaven-variety.json"
DEST="${1:-}"

if [[ -z "${DEST}" ]]; then
    echo "Usage: $(basename "$0") /path/to/variety/wallpapers" >&2
    exit 1
fi

if [[ ! -f "${META}" ]]; then
    echo "No variety metadata at ${META}" >&2
    exit 1
fi

LOCAL="$(python3 - <<PY
import json, sys
with open("${META}", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("localPath") or data.get("image") or "")
PY
)"

if [[ -z "${LOCAL}" || ! -f "${LOCAL}" ]]; then
    echo "No local wallpaper path in metadata" >&2
    exit 1
fi

mkdir -p "${DEST}"
ln -sf "${LOCAL}" "${DEST}/wallhaven-current.jpg"
echo "Linked ${LOCAL} → ${DEST}/wallhaven-current.jpg"
