#!/usr/bin/env bash
# Read Variety config and bridge search terms to Wallhaven (read-only or --apply).
set -euo pipefail

APPLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply|-a) APPLY=1; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--apply]"
            echo "  Read Variety image_fetch_search and optionally send to Wallhaven control bus."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

VARIETY_CFG="${HOME}/.config/variety/variety.conf"
if [[ ! -f "${VARIETY_CFG}" ]]; then
    echo "No Variety config at ${VARIETY_CFG}" >&2
    exit 1
fi

SEARCH="$(python3 - <<'PY'
import configparser
import os
path = os.path.expanduser("~/.config/variety/variety.conf")
cfg = configparser.ConfigParser()
cfg.read(path)
search = ""
if cfg.has_section("preferences"):
    search = cfg.get("preferences", "image_fetch_search", fallback="").strip()
print(search)
PY
)"

if [[ -z "${SEARCH}" ]]; then
    echo "No image_fetch_search in Variety config" >&2
    exit 1
fi

echo "Variety search: ${SEARCH}"

if [[ ${APPLY} -eq 0 ]]; then
    echo
    echo "Apply to Wallhaven with:"
    echo "  $(basename "$0") --apply"
    echo "  wallhaven-ctl.sh search ${SEARCH@Q}"
    exit 0
fi

CONTROL="${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell/wallhaven-control.json"
GROUP="${WALLHAVEN_SYNC_GROUP:-default}"

python3 - <<PY
import json, os, time
search = ${SEARCH@Q}
group = ${GROUP@Q}
control = ${CONTROL@Q}
payload = {"cmd": "search", "query": search, "ts": int(time.time() * 1000), "group": group}
os.makedirs(os.path.dirname(control), exist_ok=True)
with open(control, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

echo "Sent Variety search to Wallhaven control bus"
