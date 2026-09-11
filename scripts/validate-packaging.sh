#!/usr/bin/env bash
# Smoke-check downstream packaging without full distro builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' metadata.json)"
archive="${ROOT}/wallhaven-plasma-${version}.tar.xz"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo "==> Validating packaging metadata (${version})"

grep -q "pkgver=${version}" packaging/PKGBUILD.release \
    || fail "packaging/PKGBUILD.release pkgver must be ${version}"
grep -q "pkgver=${version}.r" packaging/PKGBUILD || grep -q "pkgver=${version}" packaging/PKGBUILD \
    || fail "packaging/PKGBUILD pkgver must start with ${version}"
grep -q "^Version:[[:space:]]*${version}$" packaging/wallhaven-plasma.spec \
    || fail "packaging/wallhaven-plasma.spec Version must be ${version}"
grep -q 'wallhaven-plasma-${pkgver}.tar.xz' packaging/PKGBUILD.release \
    || fail "packaging/PKGBUILD.release must download wallhaven-plasma-\${pkgver}.tar.xz"

test -f flatpak/org.robertsm.wallhaven.yaml \
    || fail "missing flatpak/org.robertsm.wallhaven.yaml"
grep -q "org.robertsm.wallhaven" flatpak/org.robertsm.wallhaven.yaml \
    || fail "flatpak manifest missing org.robertsm.wallhaven"
grep -q "contents/locale" flatpak/org.robertsm.wallhaven.yaml \
    || fail "flatpak manifest missing contents/locale"

if [[ ! -f "${archive}" ]]; then
    echo "Building local tarball for PKGBUILD smoke check..."
    ./dev-helper.sh package
fi

work="${ROOT}/.packaging-smoke"
rm -rf "${work}"
mkdir -p "${work}/extract"
tar -xJf "${archive}" -C "${work}/extract"
test -f "${work}/extract/metadata.json" \
    || fail "archive missing metadata.json"
test -f "${work}/extract/contents/ui/main.qml" \
    || fail "archive missing contents/ui/main.qml"
test -f "${work}/extract/contents/locale/es/LC_MESSAGES/org.robertsm.wallhaven.mo" \
    || fail "archive missing es locale"
test -f "${work}/extract/contents/locale/it/LC_MESSAGES/org.robertsm.wallhaven.mo" \
    || fail "archive missing it locale"
test -f "${work}/extract/docs/CONTROL.md" \
    || fail "archive missing docs/CONTROL.md"
test -f "${work}/extract/screenshots/desktop-wallpaper.png" \
    || fail "archive missing screenshots/desktop-wallpaper.png"

rm -rf "${work}"
echo "==> Packaging smoke OK (${version})"
