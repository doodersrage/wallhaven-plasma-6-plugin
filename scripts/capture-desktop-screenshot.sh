#!/usr/bin/env bash
# Capture desktop screenshot when spectacle is available (non-interactive).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/screenshots/desktop-wallpaper.png"

if ! command -v spectacle >/dev/null 2>&1; then
    echo "spectacle not found; install kf6-spectacle" >&2
    exit 1
fi

mkdir -p "${ROOT}/screenshots"
# Full-screen background capture (no pointer), Wayland/X11 via spectacle
spectacle -b -n -o "${OUT}" 2>/dev/null || spectacle -f -b -o "${OUT}"
echo "Saved ${OUT}"
