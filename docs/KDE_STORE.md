# KDE Store submission

Wallhaven is published on OpenDesktop / KDE Store:

**https://www.opendesktop.org/p/2368647/**

## Updating the listing

When you ship a new release (current: **2.8.0**):

1. Build/publish: `./dev-helper.sh release` → GitHub Release + `wallhaven-plasma-X.Y.Z.tar.xz`
2. Upload the new file on the product **Files** tab at [opendesktop.org/p/2368647](https://www.opendesktop.org/p/2368647/)
3. Paste release notes from `CHANGELOG.md` (2.8.0 section) into the store description / changelog field
4. Replace screenshots if the UI changed (`./scripts/capture-screenshots.sh`)
5. Confirm AppStream in git matches (`metainfo/org.robertsm.wallhaven.metainfo.xml` release entry)

### 2.8.0 store blurb (copy/paste)

```
v2.8.0 — Collections by username, HTTPS preset import, laptop power-saving preset,
wallpaper info action, longer seen-history with clear, per-screen sync-group helper,
bug-report JSON export, and stricter settings wiring CI.
```


## Prerequisites for each release

1. Release tarball from GitHub Releases or `./dev-helper.sh release`
2. Six screenshots at **1280×720** (or wider) in `screenshots/`
3. AppStream file: `metainfo/org.robertsm.wallhaven.metainfo.xml`

## Capture real screenshots

```bash
./dev-helper.sh deploy
# Configure Wallhaven wallpaper + add Wallhaven Control plasmoid to panel
./scripts/capture-screenshots.sh --list
./scripts/capture-screenshots.sh
```

Required files:

| File | Content |
|------|---------|
| `settings-source.png` | Settings → Source tab with preview |
| `settings-filters.png` | Filters tab + tag blocklist |
| `settings-advanced.png` | Advanced tab + history gallery |
| `plasmoid-control.png` | Panel plasmoid with thumb + countdown |
| `desktop-wallpaper.png` | Desktop with wallpaper (+ optional attribution) |
| `wallpaper-actions.png` | Right-click → Wallpaper Actions menu |

Placeholder crops (when UI capture is unavailable):

```bash
./scripts/generate-screenshots-from-preview.sh
```

Commit updated PNGs and push before tagging a release.

## First-time submission (done)

Listing created at [opendesktop.org/p/2368647](https://www.opendesktop.org/p/2368647/).

Publisher portal: [store.kde.org/publish](https://store.kde.org/publish/)

Set license **GPL-2.0-or-later**, category **Utilities**. Metadata reference: `metainfo/org.robertsm.wallhaven.metainfo.xml`.

## Discover (Flatpak)

Flatpak manifest: `flatpak/org.robertsm.wallhaven.yaml`

Build locally (Neon recommended):

```bash
flatpak-builder --force-clean --repo=repo flatpak-build flatpak/org.robertsm.wallhaven.yaml
```

## AUR automation

Add repository secret `AUR_SSH_PRIVATE_KEY` to enable automatic AUR publish on release tags (`.github/workflows/aur-publish.yml`).

Manual:

```bash
cd packaging
makepkg -si   # -git PKGBUILD
```

Stable tarball PKGBUILD: `packaging/PKGBUILD.release`
