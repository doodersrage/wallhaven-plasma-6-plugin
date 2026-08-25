# Flathub submission notes

Manifest: `flatpak/org.robertsm.wallhaven.yaml`

## Build locally

```bash
flatpak-builder --user --install-deps-from=flathub --force-clean build-dir flatpak/org.robertsm.wallhaven.yaml
flatpak-builder --user --repo=repo build-dir flatpak/org.robertsm.wallhaven.yaml
```

## Limitations

- Wallpaper plugins install into the user's Plasma session; the Flatpak targets `plasmashell` and needs the host Plasma 6 runtime.
- D-Bus tools ship in `/app/bin`; enable the user service manually or via portal after install.
- Session bus names: `org.robertsm.Wallhaven`, MPRIS, notifications — declared in `finish-args`.

## Store listing

Use screenshots from `screenshots/` and metainfo from `metainfo/org.robertsm.wallhaven.metainfo.xml`.
OpenDesktop: https://www.opendesktop.org/p/2368647/

## Checklist

- [ ] Runtime `org.kde.Platform` version matches target Plasma (6.8+)
- [ ] `contents/locale/*/LC_MESSAGES/*.mo` compiled before build
- [ ] Test D-Bus + plasmoid inside Flatpak session
- [ ] Submit PR to [flathub/flathub](https://github.com/flathub/flathub) with this manifest
