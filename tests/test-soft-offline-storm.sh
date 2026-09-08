#!/usr/bin/env bash
# Live regression: soft-offline must not burn cache by itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${HOME}/.cache/plasmashell"
LATCH="${CACHE}/wallhaven-ratelimit.json"
CTL="${ROOT}/tools/wallhaven-ctl.sh"

echo "==> Soft-offline storm regression"

systemctl --user is-active wallhaven-dbus.service >/dev/null

python3 - "$LATCH" <<'PY'
import json, sys, time
from pathlib import Path
path = Path(sys.argv[1])
until_ms = int(time.time() * 1000) + 5 * 60 * 1000
path.write_text(json.dumps({"untilMs": until_ms, "status": 429, "updatedAt": int(time.time() * 1000)}))
print("wrote latch until", until_ms)
PY

"${CTL}" outageoffline >/dev/null 2>&1 || true
sleep 3

python3 - "$CTL" <<'PY'
import json, glob, os, sys, time, subprocess
from pathlib import Path

ctl = sys.argv[1]

def statuses():
    out = {}
    for path in glob.glob(os.path.expanduser("~/.cache/plasmashell/wallhaven-status-*.json")):
        data = json.loads(Path(path).read_text())
        ns = data.get("cacheNamespace") or Path(path).name
        out[ns] = data
    return out

st = statuses()
offline = [ns for ns, d in st.items() if d.get("outageOffline")]
print("monitors", sorted(st.keys()), "offline", offline)
if not offline:
    # Latch + control should flip soft-offline; fail loudly if engines ignore it.
    raise SystemExit("FAIL: no monitor entered outageOffline after outageoffline + latch")

# Primary proof: idle under soft-offline must not churn (the original storm).
prev = {ns: data.get("id") for ns, data in st.items()}
idle_changes = 0
for i in range(10):
    time.sleep(1)
    st = statuses()
    for ns, data in st.items():
        wid = data.get("id")
        if prev.get(ns) and wid and prev[ns] != wid:
            idle_changes += 1
            print(f"idle +{i+1}s {ns}: {prev[ns]} -> {wid}")
        prev[ns] = wid

print(f"idle_changes={idle_changes} over 10s")
# Pre-fix was ~1 change/sec/monitor. Allow at most one stray interval tick.
if idle_changes > 1:
    raise SystemExit(f"FAIL: soft-offline idle storm ({idle_changes} changes in 10s)")

# Secondary: explicit next still works, but not a runaway (>1 advance per next/monitor).
before = {ns: data.get("id") for ns, data in statuses().items()}
for _ in range(3):
    subprocess.run([ctl, "next"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)
after = {ns: data.get("id") for ns, data in statuses().items()}
next_changes = sum(1 for ns in before if before.get(ns) and after.get(ns) and before[ns] != after[ns])
print(f"next_changes={next_changes} after 3 next commands")
if next_changes > len(before) * 3:
    raise SystemExit(f"FAIL: next fan-out over-advanced ({next_changes})")

print("==> Soft-offline storm regression OK")
PY

python3 - "$LATCH" <<'PY'
import json, sys, time
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"untilMs": 0, "status": 0, "updatedAt": int(time.time() * 1000)}))
PY
"${CTL}" resumeonline >/dev/null 2>&1 || true
"${CTL}" resume >/dev/null 2>&1 || true
# Never leave a stuck next fanout in the control bus — int-overflow builds
# re-fire leftover next forever every 400ms.
printf '%s\n' '{}' > "${HOME}/.cache/plasmashell/wallhaven-control.json"

python3 - "$CTL" <<'PY'
import glob, json, os, sys, time, subprocess
from pathlib import Path

ctl = sys.argv[1]

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

# resumeonline must actually leave soft-offline (force-clear).
deadline = time.time() + 15
stuck = True
while time.time() < deadline:
    st = statuses()
    offline = [ns for ns, d in st.items() if d.get("outageOffline")]
    if st and not offline:
        stuck = False
        break
    time.sleep(0.5)
if stuck:
    subprocess.run([ctl, "resumeonline"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    st = statuses()
    offline = [ns for ns, d in st.items() if d.get("outageOffline")]
    if offline or not st:
        raise SystemExit(f"FAIL: monitors still outageOffline after resumeonline: {offline}")
print("post-cleanup online monitors", sorted(statuses().keys()))
PY

echo "==> Soft-offline storm regression cleaned up"
