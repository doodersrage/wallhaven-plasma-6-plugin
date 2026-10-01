#!/usr/bin/env bash
# Lightweight QML/config sanity checks (no plasmashell required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in contents/ui/main.qml contents/ui/config.qml plasmoid/contents/ui/main.qml; do
    [[ -f "${ROOT}/${f}" ]] || { echo "Missing ${f}" >&2; exit 1; }
    grep -q "WallpaperItem\|ColumnLayout\|PlasmoidItem" "${ROOT}/${f}"
done

# Every component main.qml instantiates must ship next to it.
for f in ApiHealth ApiKeyStore AttributionBanner BusSignals ControlBus DBusHelper DetailsSheet \
        DiskCache KenBurns LockScreenSync SessionMonitors StatusBanner; do
    [[ -f "${ROOT}/contents/ui/${f}.qml" ]] || { echo "Missing contents/ui/${f}.qml" >&2; exit 1; }
done
[[ -f "${ROOT}/plasmoid/contents/ui/StatusWatcher.qml" ]] || { echo "Missing plasmoid StatusWatcher.qml" >&2; exit 1; }

if rg -q 'Process\s*\{' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: QML Process is unavailable in plasmashell; use D-Bus helper instead" >&2
    exit 1
fi

if rg -q 'QtControls2\.TextEdit|QQC2\.TextEdit' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: Use QtQuick TextEdit, not QtControls2.TextEdit" >&2
    exit 1
fi

if rg '= PDBus\.dbusMessage\(\{' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: PDBus.dbusMessage must be constructed with new" >&2
    exit 1
fi

if rg -U 'OverlaySheet\s*\{[^}]*preferredWidth' "${ROOT}/contents/ui/config.qml" 2>/dev/null; then
    echo "FAIL: Kirigami.OverlaySheet has no preferredWidth; use inline wizard in folder settings" >&2
    exit 1
fi

if rg -q 'xhr\.open\("GET", "file://' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: XMLHttpRequest cannot read local files in plasmashell; use D-Bus ReadTextFile" >&2
    exit 1
fi

if rg -q 'xhr\.open\("GET", fileUrl\)|xhr\.open\("GET", "file://|xhr\.open\("GET", Qt\.resolvedUrl' "${ROOT}/contents/ui/config.qml" 2>/dev/null; then
    echo "FAIL: config.qml must not read local files via XMLHttpRequest; use bundled JS or liveWallpaper D-Bus helpers" >&2
    exit 1
fi

# Plasma 5 leftovers fail to load on Plasma 6 (the Control plasmoid was dead
# from 2.7.0 to 3.5.5 behind a syntax error and PlasmaCore.IconItem).
if rg -n 'PlasmaCore\.IconItem|NetworkInformation\.(Cellular|Ethernet|WiFi|Bluetooth|Unknown)\b' \
        "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: use Kirigami.Icon / NetworkInformation.TransportMedium.<X> (scoped enum)" >&2
    exit 1
fi

# The service has no shell any more: lock sync, Variety links, accent sync and
# KWallet are dedicated D-Bus methods. QML must not try to build scripts again.
if grep -rnE '"bash"|"sh", *"-c"|kwallet-query|kwriteconfig6' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui"; then
    echo "FAIL: QML must call the dedicated D-Bus methods, not shell commands" >&2
    exit 1
fi

# Dangling references, settings-dialog entry points and dead change handlers.
python3 "${ROOT}/tests/check-qml-refs.py"

# Real parse when a Qt 6 qmllint is available (catches unbalanced braces).
QMLLINT=""
for cand in qmllint6 /usr/lib/qt6/bin/qmllint /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint; do
    if command -v "${cand}" >/dev/null 2>&1 && "${cand}" --help 2>&1 | grep -q -- '--json'; then
        QMLLINT="${cand}"
        break
    fi
done
if [[ -n "${QMLLINT}" ]]; then
    for path in "${ROOT}"/contents/ui/*.qml "${ROOT}"/plasmoid/contents/ui/*.qml; do
        f="${path#"${ROOT}"/}"
        if "${QMLLINT}" --json - "${ROOT}/${f}" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
bad = [w for f in d.get("files", []) for w in f.get("warnings", []) if w.get("id") == "syntax"]
for w in bad:
    print("line %s: %s" % (w.get("line"), w.get("message")))
sys.exit(1 if bad else 0)'; then
            :
        else
            echo "FAIL: QML syntax error in ${f}" >&2
            exit 1
        fi
    done
fi

python3 - <<PY
import re
from pathlib import Path
root = Path(r"""${ROOT}""")
# Brace-aware duplicate \`visible:\` in the same QML object (blank Plasma config UI).
src = (root / "contents/ui/config.qml").read_text()
depth = 0
frames = []
prop_re = re.compile(r"^(\s*)([A-Za-z_][\w.]*)\s*:")
issues = []
for li, line in enumerate(src.splitlines(), 1):
    stripped = line.split("//", 1)[0]
    opens = stripped.count("{")
    closes = stripped.count("}")
    m = prop_re.match(line)
    if m and frames and m.group(2) == "visible":
        frames[-1].setdefault("visible", []).append(li)
    for _ in range(opens):
        depth += 1
        frames.append({})
    for _ in range(closes):
        if frames:
            fr = frames.pop()
            if len(fr.get("visible", [])) > 1:
                issues.append(fr["visible"])
        depth = max(0, depth - 1)
if issues:
    raise SystemExit(
        "config.qml: duplicate visible: in same object at lines "
        + "; ".join(",".join(map(str, g)) for g in issues)
        + " (Plasma shows a blank wallpaper config panel)"
    )
PY

python3 - <<PY
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(r"""${ROOT}""")
config = (root / "contents/ui/config.qml").read_text()
alias_targets = re.findall(r"property alias cfg_\w+:\s*([A-Za-z_][\w]*)\.", config)
ids = set(re.findall(r"\bid:\s*([A-Za-z_][\w]*)", config))
missing_ids = sorted(set(alias_targets) - ids)
if missing_ids:
    raise SystemExit(
        "config.qml: property alias targets missing id: "
        + ", ".join(missing_ids)
        + " (Plasma shows a blank wallpaper config panel)"
    )

path = root / "contents/config/main.xml"
tree = ET.parse(path)
entries = [e.attrib["name"] for e in tree.findall(".//{http://www.kde.org/standards/kcfg/1.0}entry")]
required = ["SetupWizardCompleted", "WallpaperOfDayEnabled", "PinnedCacheIdsJson", "DebugLogEnabled",
            "AutoPanelAccentEnabled", "PauseOnBatteryLow", "TagFavoritesJson", "CacheNamespace",
            "ConfigSchemaVersion", "SettingsUiMode", "SmartOfflineEnabled", "ScrubSecretsOnExport",
            "LocalFolderPath", "ReducedMotion", "LocalFolderMaxDepth", "LocalFolderExclude",
            "SmartOfflineDayAware", "LocalPlaylistsJson", "OfflineTagQuery"]
missing = [k for k in required if k not in entries]
if missing:
    raise SystemExit("main.xml missing: " + ", ".join(missing))
print("QML/config smoke checks passed")
PY
