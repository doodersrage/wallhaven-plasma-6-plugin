#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
if [[ -z "${URL}" ]]; then
    echo "Usage: $(basename "$0") 'wallhaven://preset/...'" >&2
    exit 1
fi

CONTROL="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell/wallhaven-control.json"
GROUP="${WALLHAVEN_SYNC_GROUP:-default}"

python3 - <<PY
import json, time, os
url = ${URL@Q}
group = ${GROUP@Q}
control = ${CONTROL@Q}
payload = {"cmd": "importpreset", "query": url, "ts": int(time.time() * 1000), "group": group}
os.makedirs(os.path.dirname(control), exist_ok=True)
with open(control, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

echo "Sent preset import to control bus"
