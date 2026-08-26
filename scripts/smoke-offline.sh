#!/usr/bin/env bash
# Offline / CI-safe smoke checks (no live Plasma session required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "==> Offline smoke"

test -x tools/wallhaven-ctl.sh
tools/wallhaven-ctl.sh help >/dev/null

python3 -m py_compile tools/wallhaven-dbus.py
python3 -c "
import ast, pathlib
ast.parse(pathlib.Path('tools/wallhaven-dbus.py').read_text())
print('wallhaven-dbus.py parses')
"

# Optional live Ping when the user service is up (skip quietly in CI).
if command -v qdbus6 >/dev/null 2>&1; then
    if qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Ping 2>/dev/null | grep -qi ok; then
        echo "D-Bus Ping: ok"
    else
        echo "D-Bus Ping: skipped (service not on session bus)"
    fi
else
    echo "D-Bus Ping: skipped (qdbus6 not installed)"
fi

# Status/history JSON shape when files exist from a prior deploy.
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
for f in plasmashell/wallhaven-status.json plasmashell/wallhaven-history.json; do
    path="${CACHE}/${f}"
    if [[ -f "${path}" ]]; then
        python3 -c "import json,sys; json.load(open(sys.argv[1])); print('parsed', sys.argv[1])" "${path}"
    fi
done

echo "==> Offline smoke OK"
