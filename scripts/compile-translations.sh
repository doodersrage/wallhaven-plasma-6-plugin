#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCALE_DIR="${ROOT}/contents/locale"
DOMAIN="org.robertsm.wallhaven"

mkdir -p "${LOCALE_DIR}"

for po in "${ROOT}"/po/*.po; do
    [[ -f "${po}" ]] || continue
    if ! command -v msgfmt >/dev/null 2>&1; then
        echo "msgfmt not found; install gettext (e.g. apt install gettext)" >&2
        exit 127
    fi
    lang="$(basename "${po}" .po)"
    outdir="${LOCALE_DIR}/${lang}/LC_MESSAGES"
    mkdir -p "${outdir}"
    msgfmt -o "${outdir}/${DOMAIN}.mo" "${po}"
    echo "Compiled ${outdir}/${DOMAIN}.mo"
done
