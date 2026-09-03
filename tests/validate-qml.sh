#!/usr/bin/env bash
# Lightweight QML/config sanity checks (no plasmashell required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in contents/ui/main.qml contents/ui/config.qml plasmoid/contents/ui/main.qml; do
    [[ -f "${ROOT}/${f}" ]] || { echo "Missing ${f}" >&2; exit 1; }
    grep -q "WallpaperItem\|ColumnLayout\|PlasmoidItem" "${ROOT}/${f}"
done

if rg -q 'Process\s*\{' "${ROOT}/contents/ui/main.qml" "${ROOT}/plasmoid/contents/ui/main.qml" 2>/dev/null; then
    echo "FAIL: QML Process is unavailable in plasmashell; use D-Bus helper instead" >&2
    exit 1
fi

if rg -q 'QtControls2\.TextEdit|QQC2\.TextEdit' "${ROOT}/contents/ui" "${ROOT}/plasmoid/contents/ui" 2>/dev/null; then
    echo "FAIL: Use QtQuick TextEdit, not QtControls2.TextEdit" >&2
    exit 1
fi

if rg '= PDBus\.dbusMessage\(\{' "${ROOT}/contents/ui/main.qml" "${ROOT}/plasmoid/contents/ui/main.qml" 2>/dev/null; then
    echo "FAIL: PDBus.dbusMessage must be constructed with new" >&2
    exit 1
fi

if rg -U 'OverlaySheet\s*\{[^}]*preferredWidth' "${ROOT}/contents/ui/config.qml" 2>/dev/null; then
    echo "FAIL: Kirigami.OverlaySheet has no preferredWidth; use inline wizard in folder settings" >&2
    exit 1
fi

if rg -q 'xhr\.open\("GET", "file://' "${ROOT}/contents/ui/main.qml" "${ROOT}/plasmoid/contents/ui/main.qml" 2>/dev/null; then
    echo "FAIL: XMLHttpRequest cannot read local files in plasmashell; use D-Bus ReadTextFile" >&2
    exit 1
fi

if rg -q 'xhr\.open\("GET", fileUrl\)|xhr\.open\("GET", "file://|xhr\.open\("GET", Qt\.resolvedUrl' "${ROOT}/contents/ui/config.qml" 2>/dev/null; then
    echo "FAIL: config.qml must not read local files via XMLHttpRequest; use bundled JS or liveWallpaper D-Bus helpers" >&2
    exit 1
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
