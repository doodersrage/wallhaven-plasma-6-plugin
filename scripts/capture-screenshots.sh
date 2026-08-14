#!/usr/bin/env bash
# Optional screenshot helper for KDE Store / GitHub releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/screenshots"
mkdir -p "${OUT}"

echo "Open System Settings → Appearance → Wallpaper → Wallhaven, then press Enter."
read -r _

if command -v spectacle >/dev/null 2>&1; then
    spectacle -f -o "${OUT}/settings-wallhaven.png" || true
    echo "Saved ${OUT}/settings-wallhaven.png"
else
    echo "Install spectacle (kf6-spectacle) for automated captures."
fi

echo "Manual shots still recommended — see screenshots/README.md"
