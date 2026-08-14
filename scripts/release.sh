#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

DRY_RUN=0
PUSH=1
NOTES_FILE=""

usage() {
    cat <<EOF
Create a tagged GitHub release for the current metadata.json version.

Usage: $(basename "$0") [options]

Options:
  --dry-run     Print actions without tagging or uploading
  --no-push     Tag locally and create release without git push
  --notes FILE  Release notes file (default: extract from CHANGELOG.md)
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --no-push) PUSH=0; shift ;;
        --notes) NOTES_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' metadata.json)"
tag="v${version}"
archive="${ROOT}/wallhaven-plasma-${version}.tar.xz"
notes_tmp=""

extract_changelog_section() {
    awk -v ver="${version}" '
        $0 ~ "^## " ver " " { found=1; next }
        found && /^## / { exit }
        found { print }
    ' CHANGELOG.md | sed '/^$/d'
}

if [[ -z "${NOTES_FILE}" ]]; then
    notes_tmp="$(mktemp)"
    {
        echo "## Wallhaven Plasma ${version}"
        echo
        extract_changelog_section || true
    } > "${notes_tmp}"
    NOTES_FILE="${notes_tmp}"
fi

echo "==> Release ${tag}"

"${ROOT}/scripts/validate.sh"
"${ROOT}/dev-helper.sh" test
if [[ -d po ]] && compgen -G "po/*.po" >/dev/null; then
    "${ROOT}/dev-helper.sh" translations
fi
"${ROOT}/dev-helper.sh" package

[[ -f "${archive}" ]] || { echo "Missing archive: ${archive}" >&2; exit 1; }

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[dry-run] would tag ${tag}, push, and upload ${archive}"
    echo "[dry-run] notes from ${NOTES_FILE}:"
    head -20 "${NOTES_FILE}"
    [[ -n "${notes_tmp}" ]] && rm -f "${notes_tmp}"
    exit 0
fi

if git rev-parse "${tag}" >/dev/null 2>&1; then
    echo "Tag ${tag} already exists locally"
else
    git tag -a "${tag}" -m "Wallhaven Plasma ${version}"
    echo "Created tag ${tag}"
fi

if [[ ${PUSH} -eq 1 ]]; then
    git push origin HEAD
    git push origin "${tag}"
fi

if gh release view "${tag}" >/dev/null 2>&1; then
    echo "GitHub release ${tag} exists; uploading asset"
    gh release upload "${tag}" "${archive}" --clobber
else
    gh release create "${tag}" "${archive}" \
        --title "Wallhaven Plasma ${version}" \
        --notes-file "${NOTES_FILE}"
fi

echo "==> Published ${tag}"
gh release view "${tag}" --web 2>/dev/null || gh release view "${tag}"

[[ -n "${notes_tmp}" ]] && rm -f "${notes_tmp}"
