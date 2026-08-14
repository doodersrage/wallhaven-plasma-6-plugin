#!/usr/bin/env bash
# Read Variety config and suggest Wallhaven search tags (read-only bridge).
set -euo pipefail

VARIETY_CFG="${HOME}/.config/variety/variety.conf"
if [[ ! -f "${VARIETY_CFG}" ]]; then
    echo "No Variety config at ${VARIETY_CFG}" >&2
    exit 1
fi

python3 - <<'PY'
import configparser
import os
path = os.path.expanduser("~/.config/variety/variety.conf")
cfg = configparser.ConfigParser()
cfg.read(path)
search = ""
if cfg.has_section("preferences"):
    search = cfg.get("preferences", "image_fetch_search", fallback="")
print(search or "(no image_fetch_search in Variety config)")
print("\nPaste into Wallhaven → Search string, or run:")
if search:
    print(f"  wallhaven-ctl.sh search {search!r}")
PY
