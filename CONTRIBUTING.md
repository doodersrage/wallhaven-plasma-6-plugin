# Contributing

## Translations

Wallhaven uses JSON translation catalogs under `po/catalog/` and compiles them to `.po`/`.mo` files.

### Add or update a locale

1. Copy `po/catalog/fr.json` to `po/catalog/<lang>.json` (or extend an existing catalog).
2. Translate every English msgid key to natural UI text for your language.
3. Register the locale in `scripts/fill-po.py` (`LOCALES` tuple).
4. Run:

```bash
./dev-helper.sh sync-i18n
./scripts/check-i18n.sh
```

5. Submit a pull request with `po/catalog/<lang>.json` and generated `po/<lang>.po` + `contents/locale/<lang>/LC_MESSAGES/*.mo`.

### Rules

- Keys must match the English msgids from `po/org.robertsm.wallhaven.pot` exactly.
- Do not translate Wallhaven IDs, URLs, CLI commands, or `wallhaven://` scheme strings unless the target language convention requires it.
- Keep `%1`, `%2`, … placeholders unchanged and in the same order.
- Prefer KDE/Plasma terminology used in your locale’s official KDE translations (e.g. *fondo de escritorio*, *Diaporama*, *Plasmoide*).

### Shipped locales

| Code | Language | Catalog |
|------|----------|---------|
| de | German | `po/catalog/de.json` |
| fr | French | `po/catalog/fr.json` |
| es | Spanish | `po/catalog/es.json` |
| it | Italian | `po/catalog/it.json` |
| en | English (source) | keys in POT / `po/en.po` |

## Development workflow

```bash
./dev-helper.sh check
./dev-helper.sh deploy
./dev-helper.sh install-shortcuts   # optional Meta+Alt+arrows
```

## Screenshots (KDE Store)

Capture real UI shots when possible:

```bash
./scripts/capture-screenshots.sh --list
./scripts/capture-screenshots.sh
```

Placeholder crops from `preview.jpg`:

```bash
./scripts/generate-screenshots-from-preview.sh
```

## Release checklist

See [RELEASE.md](RELEASE.md).
