#!/usr/bin/env bash
# Validate Flatpak manifest structure (no full build).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT}/flatpak/org.robertsm.wallhaven.yaml"

test -f "${MANIFEST}"
grep -q '^id: org.robertsm.wallhaven' "${MANIFEST}"
grep -q 'org.kde.Platform' "${MANIFEST}"
grep -q 'wallhaven-plasma' "${MANIFEST}"
grep -q 'contents/locale' "${MANIFEST}"
grep -q 'wallhaven-dbus' "${MANIFEST}"
grep -q 'path: \.\.' "${MANIFEST}"

echo "Flatpak manifest OK"
