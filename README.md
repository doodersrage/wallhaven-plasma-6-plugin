# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 Wallhaven wallpaper plugin with search, collections, slideshow, effects, offline cache, blocklist, presets, external control, and a panel plasmoid.

## Quick start

```bash
./dev-helper.sh install
./dev-helper.sh restart
```

System Settings → Appearance → Wallpaper → **Wallhaven**

Optional: add **Wallhaven Control** widget to panel/desk.

## v1.4.0 highlights

| Feature | Notes |
|---------|--------|
| Tag blocklist | Comma-separated tags excluded from search |
| Weekday/weekend schedule | Separate searches Mon–Fri vs Sat–Sun |
| Collection rotation | `user/id` list, cycles on each advance |
| History gallery | Re-open recent wallpapers from settings |
| Lock screen sync | Uses cached image via `kscreenlockerrc` |
| Transitions | Slide, zoom, random + parallax offset |
| Panel tint hint | Writes dominant color JSON for theming tools |
| Variety symlink | `wallhaven-current.jpg` in a folder you choose |
| Plasmoid v2 | Thumbnail, countdown, pause indicator |
| D-Bus | `python3 tools/wallhaven-dbus.py` (session service) |
| Global shortcuts | `./tools/register-shortcuts.sh` or optional C++ helper |

## Commands

```bash
./dev-helper.sh test
./dev-helper.sh translations
./dev-helper.sh package
./tools/wallhaven-ctl.sh next
python3 tools/wallhaven-dbus.py next    # one-shot
./tools/variety-sync.sh ~/Pictures/Variety
./tools/apply-panel-tint.sh
```

## Per-monitor profiles

Set a **different sync group + search** on each screen in wallpaper settings, or the **same group** to advance together.

## Flatpak

See `flatpak/org.robertsm.wallhaven.yaml` (packages wallpaper + plasmoid into KDE runtime).

## License

GPL-2.0-or-later
