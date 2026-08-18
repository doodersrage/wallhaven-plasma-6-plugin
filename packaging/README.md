# Downstream packaging

## Arch Linux (AUR)

```bash
cd packaging
makepkg -si
```

Or use the `-git` PKGBUILD against the latest main branch.

After install, enable the D-Bus helper:

```bash
systemctl --user enable --now wallhaven-dbus.service
```

Register the preset URL handler (optional):

```bash
update-desktop-database ~/.local/share/applications 2>/dev/null || true
xdg-mime default wallhaven-preset.desktop x-scheme-handler/wallhaven
```

## Fedora / COPR

```bash
rpmbuild -ba packaging/wallhaven-plasma.spec
```

Adjust `%_sharedstatedir` paths if your target uses `/usr/share/metainfo` instead.

## GitHub AUR publish (manual)

1. Fork or maintain an AUR package repository (e.g. `wallhaven-plasma-git`).
2. Copy `packaging/PKGBUILD` and update `pkgver` / `sha256sums`.
3. Push to AUR with SSH or the workflow below.

Optional automation: `.github/workflows/aur-publish.yml` (requires `AUR_SSH_PRIVATE_KEY` secret).

### Stable release (tarball)

Use `packaging/PKGBUILD.release` for versioned GitHub releases (`wallhaven-plasma-2.4.0.tar.xz`).

Optional global shortcuts (requires KDE dev packages to build):

```bash
# Arch — only extra-cmake-modules is usually missing if Plasma is installed
sudo pacman -S extra-cmake-modules
./dev-helper.sh install-shortcuts
```

## Contents installed

| Path | Purpose |
|------|---------|
| `plasma/wallpapers/org.robertsm.wallhaven` | Wallpaper plugin |
| `plasma/plasmoids/org.robertsm.wallhaven.control` | Panel control widget |
| `krunner/dplugins/` | KRunner commands |
| `metainfo/` | AppStream metadata |
| `knotifications6/` | Desktop notifications |
| `locale/*/LC_MESSAGES/*.mo` | Translations (German, French, Spanish, Italian, English) |
| `/usr/bin/wallhaven-shortcuts` | Optional global shortcuts (Meta+Alt+arrows, release PKGBUILD) |
| `lib/systemd/user/wallhaven-dbus.service` | D-Bus control + MPRIS service |
| `wallhaven-plasma/tools/` | CLI, Variety bridge, preset import |
| `applications/wallhaven-preset.desktop` | `wallhaven://preset/` URL handler |

User install for development remains `./dev-helper.sh deploy`.
