#!/usr/bin/env bash
# Extract strings, refresh .po files, and compile .mo catalogs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT}/scripts/extract-messages.sh"
python3 "${ROOT}/scripts/fill-po.py"
"${ROOT}/scripts/compile-translations.sh"
"${ROOT}/scripts/check-i18n.sh"

echo "i18n sync complete"
