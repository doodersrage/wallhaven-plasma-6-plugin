#!/usr/bin/env bash
# Live regression: burst next while busy must not silently drop every command.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${ROOT}/tools/wallhaven-ctl.sh"

echo "==> Control busy-queue regression"

systemctl --user is-active wallhaven-dbus.service >/dev/null

python3 - "$CTL" <<'PY'
import glob, json, os, sys, time, subprocess
from pathlib import Path

ctl = sys.argv[1]
burst = 5

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

before = {ns: data.get("id") for ns, data in statuses().items()}
if not before:
    raise SystemExit("FAIL: no wallhaven status files (is the wallpaper running?)")

# Fire a tight burst — engines that drop while busy used to lose all of these.
for _ in range(burst):
    subprocess.run([ctl, "next"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.05)

# Allow queue flush + transitions to settle.
time.sleep(8)
after = {ns: data.get("id") for ns, data in statuses().items()}

changed = 0
for ns in before:
    if before.get(ns) and after.get(ns) and before[ns] != after[ns]:
        changed += 1
        print(f"{ns}: {before[ns]} -> {after[ns]}")

print(f"monitors_changed={changed} after burst={burst}")
# At least one monitor should advance (queue must not drop everything).
if changed < 1:
    raise SystemExit("FAIL: busy-queue dropped the entire next burst (0 advances)")
# Must not runaway beyond burst * monitors (fan-out is expected, storm is not).
if changed > len(before) * burst:
    raise SystemExit(f"FAIL: next over-advanced ({changed})")

# Clear leftovers so a failed watermark cannot re-fire next forever.
Path(os.path.expanduser("~/.cache/plasmashell/wallhaven-control.json")).write_text("{}")
print("==> Control busy-queue regression OK")
PY
