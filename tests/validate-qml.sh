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
import xml.etree.ElementTree as ET
path = "${ROOT}/contents/config/main.xml"
tree = ET.parse(path)
entries = [e.attrib["name"] for e in tree.findall(".//{http://www.kde.org/standards/kcfg/1.0}entry")]
required = ["SetupWizardCompleted", "WallpaperOfDayEnabled", "PinnedCacheIdsJson", "DebugLogEnabled",
            "AutoPanelAccentEnabled", "PauseOnBatteryLow", "TagFavoritesJson", "CacheNamespace"]
missing = [k for k in required if k not in entries]
if missing:
    raise SystemExit("main.xml missing: " + ", ".join(missing))
print("QML/config smoke checks passed")
PY
