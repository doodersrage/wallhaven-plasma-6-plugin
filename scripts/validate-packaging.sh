#!/usr/bin/env bash
# Smoke-check downstream packaging without full distro builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' metadata.json)"
archive="${ROOT}/wallhaven-plasma-${version}.tar.xz"

echo "==> Validating packaging metadata"

grep -q "pkgver=${version}" packaging/PKGBUILD.release
grep -q "pkgver=${version}.r" packaging/PKGBUILD || grep -q "pkgver=${version}" packaging/PKGBUILD
grep -q 'wallhaven-plasma-${pkgver}.tar.xz' packaging/PKGBUILD.release

test -f flatpak/org.robertsm.wallhaven.yaml
grep -q "org.robertsm.wallhaven" flatpak/org.robertsm.wallhaven.yaml
grep -q "contents/locale" flatpak/org.robertsm.wallhaven.yaml

if [[ ! -f "${archive}" ]]; then
    echo "Building local tarball for PKGBUILD smoke check..."
    ./dev-helper.sh package
fi

work="${ROOT}/.packaging-smoke"
rm -rf "${work}"
mkdir -p "${work}/extract"
tar -xJf "${archive}" -C "${work}/extract"
test -f "${work}/extract/metadata.json"
test -f "${work}/extract/contents/ui/main.qml"
test -f "${work}/extract/contents/locale/es/LC_MESSAGES/org.robertsm.wallhaven.mo"
test -f "${work}/extract/share/wallhaven-shortcuts.desktop.in"
test -f "${work}/extract/screenshots/desktop-wallpaper.png"

rm -rf "${work}"
echo "==> Packaging smoke OK (${version})"
