# Release checklist

## Before tagging

1. Update version in `metadata.json` and `metainfo/org.robertsm.wallhaven.metainfo.xml`
2. Add entry to `CHANGELOG.md`
3. Run `./dev-helper.sh test`
4. Run `./dev-helper.sh package`
5. Capture screenshots (see `screenshots/README.md`)
6. Confirm `preview.jpg` looks good in the wallpaper picker

## Publish

### GitHub Releases

```bash
git tag v1.2.0
git push origin v1.2.0
gh release create v1.2.0 wallhaven-plasma-1.2.0.tar.xz \
  --title "Wallhaven Plasma 1.2.0" \
  --notes-file CHANGELOG.md
```

### KDE Store

1. Upload `wallhaven-plasma-1.2.0.tar.xz`
2. Include AppStream metadata from `metainfo/`
3. Attach 1–3 screenshots (1280×720 or wider)

## Optional shortcuts

Register global shortcuts manually:

```bash
./tools/register-shortcuts.sh
```

Or configure **System Settings → Shortcuts → Custom Shortcuts** using the commands printed by that script.

## Translations

Extract new strings when UI changes:

```bash
./scripts/extract-messages.sh
```

Compile `.po` files to `.qm` and install under `contents/locale/` before packaging localized builds.
