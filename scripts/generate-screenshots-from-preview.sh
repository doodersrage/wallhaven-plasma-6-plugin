#!/usr/bin/env bash
# Generate placeholder KDE Store screenshots from preview.jpg (1280x720 crops).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/screenshots"
PREVIEW="${ROOT}/preview.jpg"

if [[ ! -f "${PREVIEW}" ]]; then
    echo "Missing ${PREVIEW}" >&2
    exit 1
fi

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo "Install ImageMagick (magick) to generate screenshots." >&2
    exit 1
fi

MAGICK=(magick)
if ! command -v magick >/dev/null 2>&1; then
    MAGICK=(convert)
fi

mkdir -p "${OUT}"

declare -a SPECS=(
    "settings-source.png|640x360+0+0"
    "settings-filters.png|640x360+640+0"
    "settings-advanced.png|640x360+0+360"
    "plasmoid-control.png|640x360+640+360"
    "desktop-wallpaper.png|1280x720+0+0"
    "wallpaper-actions.png|960x540+160+90"
)

for spec in "${SPECS[@]}"; do
    file="${spec%%|*}"
    crop="${spec#*|}"
    "${MAGICK[@]}" "${PREVIEW}" -resize 1280x720^ -gravity center -extent 1280x720 \
        -crop "${crop}" +repage "${OUT}/${file}"
    echo "Wrote ${OUT}/${file}"
done

echo "Done. Replace with real captures via scripts/capture-screenshots.sh when possible."
