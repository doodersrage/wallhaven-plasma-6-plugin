#!/usr/bin/env bash
# Check that a release tarball contains everything an install needs.
# usage: verify-archive.sh [archive]   (default: the tarball for metadata.json's version)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' metadata.json)"
archive="${1:-${ROOT}/wallhaven-plasma-${version}.tar.xz}"
[[ -f "${archive}" ]] || { echo "Missing archive: ${archive}" >&2; exit 1; }

required=(
    metadata.json
    CONTRIBUTING.md
    contents/config/main.xml
    contents/code/wallhaven.js
    contents/presets/curated.json
    contents/presets/community.json
    plasmoid/metadata.json
    krunner/org.robertsm.wallhaven.desktop
    metainfo/org.robertsm.wallhaven.metainfo.xml
    tools/wallhaven-dbus.py
    tools/wallhaven-ctl.sh
    share/wallhaven-preset.desktop.in
    share/wallhaven-shortcuts.desktop.in
    share/org.robertsm.Wallhaven.service.in
    packaging/PKGBUILD
    examples/plasma-shortcuts.md
    docs/ARCHITECTURE.md
    docs/CONTROL.md
    docs/KDE_STORE.md
    docs/KWALLET.md
    screenshots/desktop-wallpaper.png
)
# Every QML file in the tree must ship: main.qml loads its components by name.
while IFS= read -r f; do
    required+=("${f}")
done < <(find contents/ui plasmoid/contents/ui -name '*.qml' | sort)
# Every translated locale, as source and compiled.
for po in po/*.po; do
    locale="$(basename "${po}" .po)"
    required+=("po/${locale}.po" "contents/locale/${locale}/LC_MESSAGES/org.robertsm.wallhaven.mo")
done

listing="$(mktemp)"
trap 'rm -f "${listing}"' EXIT
tar -tJf "${archive}" > "${listing}"

missing=0
for path in "${required[@]}"; do
    if ! grep -qxF "${path}" "${listing}"; then
        echo "MISSING from archive: ${path}" >&2
        missing=$((missing + 1))
    fi
done
if grep -qE '(__pycache__|\.pyc$)' "${listing}"; then
    echo "Archive must not ship Python bytecode" >&2
    missing=$((missing + 1))
fi
[[ ${missing} -eq 0 ]] || { echo "==> Archive check FAILED (${missing} problem(s))" >&2; exit 1; }
echo "==> Archive OK: $(basename "${archive}") (${#required[@]} required paths)"
