#!/usr/bin/env bash
# Lightweight QML/config sanity checks (no plasmashell required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in contents/ui/main.qml contents/ui/config.qml plasmoid/contents/ui/main.qml; do
    [[ -f "${ROOT}/${f}" ]] || { echo "Missing ${f}" >&2; exit 1; }
    grep -q "WallpaperItem\|ColumnLayout\|PlasmoidItem" "${ROOT}/${f}"
done

python3 - <<PY
import xml.etree.ElementTree as ET
path = "${ROOT}/contents/config/main.xml"
tree = ET.parse(path)
entries = [e.attrib["name"] for e in tree.findall(".//{http://www.kde.org/standards/kcfg/1.0}entry")]
required = ["SetupWizardCompleted", "WallpaperOfDayEnabled", "PinnedCacheIdsJson", "DebugLogEnabled",
            "AutoPanelAccentEnabled", "PauseOnBatteryLow", "TagFavoritesJson"]
missing = [k for k in required if k not in entries]
if missing:
    raise SystemExit("main.xml missing: " + ", ".join(missing))
print("QML/config smoke checks passed")
PY
