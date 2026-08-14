# Release

Most steps are automated via `dev-helper.sh` and GitHub Actions.

## One-command local release

```bash
./dev-helper.sh check
./dev-helper.sh release          # tag vX.Y.Z, push, gh release + tarball
```

Dry run:

```bash
./scripts/release.sh --dry-run
```

## One-command deploy (dev machine)

```bash
./dev-helper.sh deploy
```

This validates, runs tests, installs the plugin + plasmoid, enables the user D-Bus
service, and restarts plasmashell.

## CI

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ci.yml` | push/PR to main | validate, test, package |
| `release.yml` | push tag `v*` | validate, test, package, attach to GitHub Release |

## Before bumping version

1. Update `metadata.json`, `plasmoid/metadata.json`, `CHANGELOG.md`, `metainfo/`
2. `./dev-helper.sh check && ./dev-helper.sh package`
3. Capture screenshots: `./scripts/capture-screenshots.sh --list` then run interactively
4. Sync translations: `./dev-helper.sh sync-i18n`
5. `./dev-helper.sh release`

## KDE Store

Manual upload of `wallhaven-plasma-*.tar.xz` plus AppStream metadata and screenshots.
No public KDE Store API automation is configured in this repo.

## Shortcuts

```bash
./tools/register-shortcuts.sh     # documents Custom Shortcuts setup
./dev-helper.sh dbus-install      # persistent D-Bus control (recommended)
```

Optional KGlobalAccel binary (requires KDE dev packages):

```bash
cmake -S tools/wallhaven-shortcuts -B build-shortcuts
cmake --build build-shortcuts
```

## Translations

```bash
./dev-helper.sh extract-i18n      # refresh po/org.robertsm.wallhaven.pot
./dev-helper.sh translations      # compile .po → contents/locale/
```

Packaging auto-compiles translations when `po/*.po` exists.
