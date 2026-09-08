#!/usr/bin/env bash
# Live regression: SyncAdvance peers must not echo-ping-pong every poll tick.
# Skips when wallhaven-dbus is down. Requires SyncAdvanceEnabled on monitors
# to exercise the real path; still useful as an idle-churn guard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Sync-advance storm regression"

systemctl --user is-active wallhaven-dbus.service >/dev/null

python3 <<'PY'
import glob, json, os, time
from pathlib import Path

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
    raise SystemExit("FAIL: no wallhaven status files (is the wallpaper running?)")

prev = {ns: data.get("id") for ns, data in st.items()}
idle_changes = 0
# Sync poll is 800ms; echo ping-pong would churn many times in 8s.
for i in range(8):
    time.sleep(1)
    st = statuses()
    for ns, data in st.items():
        wid = data.get("id")
        if prev.get(ns) and wid and prev[ns] != wid:
            idle_changes += 1
            print(f"idle +{i+1}s {ns}: {prev[ns]} -> {wid}")
        prev[ns] = wid

print(f"idle_changes={idle_changes} over 8s")
# Allow at most one legitimate interval tick across all monitors.
if idle_changes > 1:
    raise SystemExit(f"FAIL: sync-advance idle storm ({idle_changes} changes in 8s)")

print("==> Sync-advance storm regression OK")
PY
