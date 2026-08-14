#!/usr/bin/env python3
"""Fill .po files from POT and JSON translation catalogs."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POT = ROOT / "po" / "org.robertsm.wallhaven.pot"
CATALOG_DIR = ROOT / "po" / "catalog"
METADATA = ROOT / "metadata.json"

LOCALES: tuple[tuple[str, str, Path], ...] = (
    ("de", "de", CATALOG_DIR / "de.json"),
    ("fr", "fr", CATALOG_DIR / "fr.json"),
)


def parse_pot(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    msgids: list[str] = []
    for block in re.split(r"\n\n+", text):
        m = re.search(r'^msgid "(.*)"$', block, re.M)
        if not m:
            continue
        msgid = m.group(1).replace('\\"', '"').replace("\\n", "\n")
        if msgid:
            msgids.append(msgid)
    return msgids


def load_catalog(path: Path) -> dict[str, str]:
    if not path.exists():
        print(f"Missing catalog {path}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print(f"Invalid catalog format in {path}", file=sys.stderr)
        sys.exit(1)
    return {str(k): str(v) for k, v in data.items()}


def get_version() -> str:
    version = "2.0.0"
    if METADATA.exists():
        m = re.search(r'"Version"\s*:\s*"([^"]+)"', METADATA.read_text(encoding="utf-8"))
        if m:
            version = m.group(1)
    return version


def escape_po(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def write_po(path: Path, lang: str, version: str, entries: list[tuple[str, str]]) -> None:
    lines = [
        'msgid ""',
        'msgstr ""',
        f'"Project-Id-Version: org.robertsm.wallhaven {version}\\n"',
        f'"Language: {lang}\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        "",
    ]
    for msgid, msgstr in entries:
        lines.append(f'msgid "{escape_po(msgid)}"')
        lines.append(f'msgstr "{escape_po(msgstr)}"')
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def build_entries(
    msgids: list[str], catalog: dict[str, str]
) -> tuple[list[tuple[str, str]], list[str]]:
    entries: list[tuple[str, str]] = []
    missing: list[str] = []
    for msgid in msgids:
        if msgid not in catalog:
            missing.append(msgid)
            entries.append((msgid, msgid))
        else:
            entries.append((msgid, catalog[msgid]))
    return entries, missing


def report_missing(lang: str, missing: list[str]) -> None:
    if not missing:
        print(f"{lang}: complete ({len(missing)} missing)")
        return
    print(f"{lang}: {len(missing)} missing translation(s):")
    for item in missing[:10]:
        print(f"  - {item}")
    if len(missing) > 10:
        print(f"  ... and {len(missing) - 10} more")


def main() -> int:
    if not POT.exists():
        print(f"Missing {POT}; run scripts/extract-messages.sh first", file=sys.stderr)
        return 1

    version = get_version()
    msgids = parse_pot(POT)

    en_entries = [(msgid, msgid) for msgid in msgids]
    write_po(ROOT / "po" / "en.po", "en", version, en_entries)

    for lang_code, catalog_name, catalog_path in LOCALES:
        catalog = load_catalog(catalog_path)
        extra = set(catalog) - set(msgids)
        if extra:
            print(
                f"Warning: {catalog_name}.json has {len(extra)} string(s) not in POT "
                f"(ignored)",
                file=sys.stderr,
            )

        entries, missing = build_entries(msgids, catalog)
        write_po(ROOT / "po" / f"{lang_code}.po", lang_code, version, entries)
        report_missing(lang_code, missing)

    print(f"Updated po/en.po, po/de.po, po/fr.po ({len(msgids)} strings, version {version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
