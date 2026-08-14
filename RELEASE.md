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
./dev-helper.sh install-shortcuts   # optional Meta+Alt+arrows
```

This validates, runs tests, installs the plugin + plasmoid, enables the user D-Bus
service, and restarts plasmashell.

## CI

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ci.yml` | push/PR to main | validate, i18n, test, package, packaging smoke, flatpak manifest |
| `release.yml` | push tag `v*` | validate, sync-i18n, package, GitHub Release asset |
| `aur-publish.yml` | tag or manual | AUR PKGBUILD push (needs `AUR_SSH_PRIVATE_KEY`) |
| `nightly.yml` | daily cron | full check + package |

## Before bumping version

1. Update `metadata.json`, `plasmoid/metadata.json`, `contents/code/wallhaven.js`, `CHANGELOG.md`, `metainfo/`
2. `./dev-helper.sh sync-i18n && ./scripts/check-i18n.sh`
3. `./dev-helper.sh check && ./dev-helper.sh package && ./scripts/validate-packaging.sh`
4. Capture screenshots: `./scripts/capture-screenshots.sh --list` then run interactively
5. `./dev-helper.sh release`

## KDE Store

Manual upload of `wallhaven-plasma-*.tar.xz` plus AppStream metadata and screenshots.
Replace placeholder PNGs in `screenshots/` with real captures when possible.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Shortcuts

```bash
./tools/register-shortcuts.sh        # documents Custom Shortcuts setup
./dev-helper.sh install-shortcuts    # KGlobalAccel binary + autostart (needs cmake + KF6 dev)
./dev-helper.sh dbus-install         # persistent D-Bus control (recommended)
./dev-helper.sh register-preset      # wallhaven:// URL handler
```

## Translations

```bash
./dev-helper.sh sync-i18n            # extract, fill catalogs, compile, check
./dev-helper.sh extract-i18n         # refresh po/org.robertsm.wallhaven.pot only
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for adding a new locale.

Packaging auto-compiles translations when `po/*.po` exists.
