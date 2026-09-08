#!/usr/bin/env bash
# Live regression: a stuck control-bus "next" fanout must not re-fire every poll.
# Root cause was property int overflow on epoch-ms timestamps (re-fire forever).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL_FILE="${HOME}/.cache/plasmashell/wallhaven-control.json"

echo "==> Control-bus timestamp storm regression"

systemctl --user is-active wallhaven-dbus.service >/dev/null

python3 - "$CTL_FILE" <<'PY'
import glob, json, os, sys, time
from pathlib import Path

ctl = Path(sys.argv[1])

def statuses():
    out = {}
    for path in glob.glob(os.path.expanduser("~/.cache/plasmashell/wallhaven-status-*.json")):
        try:
            data = json.loads(Path(path).read_text())
        except Exception:
            continue
        ns = data.get("cacheNamespace") or Path(path).name
        out[ns] = data
    return out

st = statuses()
if not st:
    raise SystemExit("FAIL: no wallhaven status files")

groups = sorted(st.keys())
base = int(time.time() * 1000)
payload = {
    "commands": [
        {"cmd": "next", "ts": base + i, "group": g}
        for i, g in enumerate(groups)
    ]
}
ctl.write_text(json.dumps(payload))
print("wrote fanout next for", groups)

# Allow one apply pass.
time.sleep(2.5)
prev = {ns: data.get("id") for ns, data in statuses().items()}

# With int overflow, this would churn ~1 change / 400ms forever.
idle_changes = 0
for i in range(8):
    time.sleep(1)
    st = statuses()
    for ns, data in st.items():
        wid = data.get("id")
        if prev.get(ns) and wid and prev[ns] != wid:
            idle_changes += 1
            print(f"idle +{i+1}s {ns}: {prev[ns]} -> {wid}")
        prev[ns] = wid

print(f"idle_changes={idle_changes} over 8s after stuck next fanout")
if idle_changes > 1:
    raise SystemExit(f"FAIL: control-bus timestamp storm ({idle_changes} changes)")

# Leave a benign empty control file so leftovers cannot confuse later runs.
ctl.write_text("{}")
print("==> Control-bus timestamp storm regression OK")
PY
