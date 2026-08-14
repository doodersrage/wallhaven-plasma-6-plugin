#!/usr/bin/env bash
# Fail when shipped locale catalogs have untranslated strings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob

for po in "${ROOT}"/po/*.po; do
    [[ "$(basename "${po}")" == "en.po" ]] && continue
    locale="$(basename "${po}" .po)"
    missing="$(awk '
        /^msgid "/ {
            if (msgid != "" && msgstr == "" && !fuzzy) missing++
        }
        /^msgid "/ { msgid=$0; msgstr=""; fuzzy=0; next }
        /^msgstr "/ { msgstr=$0; next }
        /^#, fuzzy/ { fuzzy=1; next }
        END { print missing+0 }
    ' "${po}")"
    if [[ "${missing}" -gt 0 ]]; then
        echo "FAIL: po/${locale}.po has ${missing} untranslated msgstr entries" >&2
        exit 1
    fi
done

echo "i18n coverage OK"
