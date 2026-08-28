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
- Session bus names: `org.robertsm.Wallhaven`, MPRIS, notifications, ScreenSaver, login1 — declared in `finish-args`.

## Store listing

Use screenshots from `screenshots/` and metainfo from `metainfo/org.robertsm.wallhaven.metainfo.xml`.
OpenDesktop: https://www.opendesktop.org/p/2368647/

## Checklist (3.0.0)

- [x] Manifest includes ScreenSaver + login1 talk-names for idle/lock
- [x] AppStream release entry for current version in `metainfo/`
- [ ] Runtime `org.kde.Platform` version matches target Plasma (6.8+)
- [ ] `contents/locale/*/LC_MESSAGES/*.mo` compiled before build (`./dev-helper.sh translations`)
- [ ] Test D-Bus + plasmoid inside Flatpak session
- [ ] Submit PR to [flathub/flathub](https://github.com/flathub/flathub) with this manifest
- [ ] After merge, mirror Flathub install instructions on OpenDesktop

## Maintainer submit steps

1. Fork/clone flathub and add `org.robertsm.wallhaven` from this manifest (point `source` at the GitHub `vX.Y.Z` tarball).
2. Run local flatpak-builder + install test on Plasma 6.
3. Open the Flathub PR; link AppStream screenshots and the OpenDesktop page.
4. Once published: `flatpak install flathub org.robertsm.wallhaven` (final ID may follow Flathub naming).
