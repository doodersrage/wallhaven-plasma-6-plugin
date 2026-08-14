#!/usr/bin/env bash
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell"
TINT="${CACHE}/wallhaven-panel-tint.json"

if [[ ! -f "${TINT}" ]]; then
    echo "No panel tint file at ${TINT}" >&2
    exit 1
fi

HEX="$(python3 - <<PY
import json
with open("${TINT}", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("color", ""))
PY
)"

if [[ -z "${HEX}" ]]; then
    echo "No color in tint metadata" >&2
    exit 1
fi

echo "Dominant wallpaper color: #${HEX}"
if command -v plasma-apply-colors >/dev/null 2>&1; then
    echo "Run manually if desired: plasma-apply-colors --accent-color \"#${HEX}\""
else
    echo "Install plasma-workspace for plasma-apply-colors, or use the hex in your theme."
fi
