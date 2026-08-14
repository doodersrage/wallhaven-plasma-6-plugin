# KDE Store submission

Wallhaven is distributed as a source tarball plus AppStream metadata. KDE Store / Discover listing is manual.

## Prerequisites

1. Release tarball: `wallhaven-plasma-2.3.0.tar.xz` from GitHub Releases
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

## Submit to KDE Store

1. Create/login at [KDE Developer](https://community.kde.org/Get_Involved/development)
2. Open [KDE Store publisher](https://store.kde.org/publish/)
3. Upload plugin tarball or link GitHub release asset
4. Paste AppStream metadata / screenshots from this repo
5. Set license **GPL-2.0-or-later**, category **Utilities**

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
