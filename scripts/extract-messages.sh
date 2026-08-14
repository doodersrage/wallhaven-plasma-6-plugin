#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POT="${ROOT}/po/org.robertsm.wallhaven.pot"

mkdir -p "${ROOT}/po"

{
    echo '# Wallhaven Plasma wallpaper strings'
    echo '#, fuzzy'
    echo 'msgid ""'
    echo 'msgstr ""'
    echo '"Project-Id-Version: org.robertsm.wallhaven\n"'
    echo '"MIME-Version: 1.0\n"'
    echo '"Content-Type: text/plain; charset=UTF-8\n"'
    echo
    rg -o 'i18n\("[^"]*"' "${ROOT}/contents/ui" | sed 's/i18n("//;s/"$//' | sort -u | while read -r line; do
        echo "msgid \"${line}\""
        echo 'msgstr ""'
        echo
    done
} > "${POT}"

echo "Wrote ${POT}"
