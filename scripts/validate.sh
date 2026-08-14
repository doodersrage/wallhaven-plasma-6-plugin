#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "==> Validating Wallhaven Plasma plugin structure"

required=(
    metadata.json
    contents/ui/main.qml
    contents/ui/config.qml
    contents/code/wallhaven.js
    contents/config/main.xml
    plasmoid/metadata.json
    plasmoid/contents/ui/main.qml
    tools/wallhaven-ctl.sh
    tools/wallhaven-dbus.py
    metainfo/org.robertsm.wallhaven.metainfo.xml
    krunner/org.robertsm.wallhaven.desktop
    contents/presets/curated.json
)

for path in "${required[@]}"; do
    [[ -f "${path}" ]] || { echo "Missing required file: ${path}" >&2; exit 1; }
done

version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' metadata.json)"
plasmoid_version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' plasmoid/metadata.json)"
[[ "${version}" == "${plasmoid_version}" ]] || {
    echo "Version mismatch: metadata.json=${version} plasmoid=${plasmoid_version}" >&2
    exit 1
}

grep -q "\"Version\": \"${version}\"" metadata.json
grep -q "return \"${version}\"" contents/code/wallhaven.js || {
    echo "wallhaven.js pluginVersion() must match metadata.json (${version})" >&2
    exit 1
}
grep -q "version=\"${version}\"" metainfo/org.robertsm.wallhaven.metainfo.xml || {
    echo "metainfo.xml missing release entry for ${version}" >&2
    exit 1
}

python3 -m py_compile tools/wallhaven-dbus.py

echo "==> Structure OK (version ${version})"
