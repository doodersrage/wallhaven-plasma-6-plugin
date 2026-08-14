# Downstream packaging

## Arch Linux (AUR)

```bash
cd packaging
makepkg -si
```

Or use the `-git` PKGBUILD against the latest main branch.

## Fedora / COPR

```bash
rpmbuild -ba packaging/wallhaven-plasma.spec
```

Adjust `%_sharedstatedir` paths if your target uses `/usr/share/metainfo` instead.

## GitHub AUR publish (manual)

1. Fork or maintain an AUR package repository (e.g. `wallhaven-plasma-git`).
2. Copy `packaging/PKGBUILD` and update `pkgver` / `sha256sums`.
3. Push to AUR with `aur publish` or SSH.

Optional automation: see `.github/workflows/aur-publish.yml` (requires `AUR_SSH_PRIVATE_KEY` secret).

## Contents installed

| Path | Purpose |
|------|---------|
| `plasma/wallpapers/org.robertsm.wallhaven` | Wallpaper plugin |
| `plasma/plasmoids/org.robertsm.wallhaven.control` | Panel control widget |
| `krunner/dplugins/` | KRunner commands |
| `metainfo/` | AppStream metadata |
| `knotifications6/` | Desktop notifications |
| `wallhaven-plasma/tools/` | D-Bus service, CLI, Variety bridge |
| `applications/wallhaven-preset.desktop` | `wallhaven://preset/` URL handler |

User install for development remains `./dev-helper.sh deploy`.
