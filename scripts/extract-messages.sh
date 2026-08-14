#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POT="${ROOT}/po/org.robertsm.wallhaven.pot"

mkdir -p "${ROOT}/po"

extract_strings() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        rg --no-filename -o 'i18n\("[^"]*"' "${dir}" 2>/dev/null | sed 's/i18n("//;s/"$//' || true
    fi
}

{
    echo '# Wallhaven Plasma wallpaper strings'
    echo '#, fuzzy'
    echo 'msgid ""'
    echo 'msgstr ""'
    echo '"Project-Id-Version: org.robertsm.wallhaven\n"'
    echo '"MIME-Version: 1.0\n"'
    echo '"Content-Type: text/plain; charset=UTF-8\n"'
    echo
    {
        extract_strings "${ROOT}/contents/ui"
        extract_strings "${ROOT}/plasmoid/contents/ui"
    } | sort -u | while read -r line; do
        [[ -n "${line}" ]] || continue
        escaped="${line//\"/\\\"}"
        echo "msgid \"${escaped}\""
        echo 'msgstr ""'
        echo
    done
} > "${POT}"

if [[ -f "${ROOT}/po/en.po" ]]; then
    echo "Update po/en.po from ${POT} with: msgmerge -U po/en.po ${POT}"
fi

echo "Wrote ${POT}"
