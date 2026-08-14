#!/usr/bin/env bash
# Guided screenshot capture for KDE Store / GitHub releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/screenshots"
LIST_ONLY=0

SHOTS=(
    "settings-source.png|System Settings → Appearance → Wallpaper → Wallhaven → Source tab"
    "settings-filters.png|Filters tab with tag blocklist visible"
    "settings-advanced.png|Advanced tab with history gallery"
    "plasmoid-control.png|Wallhaven Control plasmoid on panel (thumbnail + countdown)"
    "desktop-wallpaper.png|Desktop with wallpaper and optional attribution overlay"
    "wallpaper-actions.png|Right-click desktop → Wallpaper Actions menu"
)

usage() {
    cat <<EOF
Capture KDE Store screenshots into ${OUT}/

Usage: $(basename "$0") [options]

Options:
  --list        Print shot checklist and exit
  --out-dir DIR Output directory (default: screenshots/)
  -h, --help    Show this help

Requires spectacle (kf6-spectacle) for automated full-screen captures.
Each step prompts before capture; press Enter to skip a shot.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) LIST_ONLY=1; shift ;;
        --out-dir) OUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "${OUT}"

if [[ ${LIST_ONLY} -eq 1 ]]; then
    idx=1
    for entry in "${SHOTS[@]}"; do
        file="${entry%%|*}"
        hint="${entry#*|}"
        echo "${idx}. ${file} — ${hint}"
        idx=$((idx + 1))
    done
    exit 0
fi

if ! command -v spectacle >/dev/null 2>&1; then
    echo "Install spectacle (kf6-spectacle) for automated captures." >&2
    echo "Manual checklist: ./$(basename "$0") --list" >&2
    exit 1
fi

echo "Screenshot capture — output: ${OUT}"
echo "See screenshots/README.md for composition tips."
echo

idx=1
for entry in "${SHOTS[@]}"; do
    file="${entry%%|*}"
    hint="${entry#*|}"
    dest="${OUT}/${file}"
    echo "[${idx}/${#SHOTS[@]}] ${hint}"
    echo "Target: ${dest}"
    read -r -p "Press Enter to capture (s to skip): " choice
    if [[ "${choice}" == "s" || "${choice}" == "S" ]]; then
        echo "Skipped."
    else
        spectacle -f -o "${dest}" || echo "Capture failed for ${file}" >&2
        [[ -f "${dest}" ]] && echo "Saved ${dest}"
    fi
    echo
    idx=$((idx + 1))
done

echo "Done. Upload PNGs manually for KDE Store (see RELEASE.md)."
