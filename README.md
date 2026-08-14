# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 Wallhaven wallpaper plugin with search, collections, slideshow, effects, offline cache, blocklist, presets, external control, and a panel plasmoid.

## Quick start

```bash
./dev-helper.sh install
./dev-helper.sh restart
```

System Settings → Appearance → Wallpaper → **Wallhaven**

Optional: add **Wallhaven Control** widget to panel/desk.

## v1.3.0 highlights

| Feature | Notes |
|---------|--------|
| Similar wallpapers | Desktop action + `like:` search |
| File type filter | JPEG / PNG in Filters |
| Search test + API key test | Source tab |
| Details panel | Views, favorites, tags in settings preview |
| Slideshow jitter | ±% randomness |
| Day/night intervals | Override base interval by time |
| Fade-through-black | Transition mode in Playback |
| Attribution tuning | Corner, auto-hide, font scale |
| Control bus | `tools/wallhaven-ctl.sh next\|prev\|reload\|pause` |
| Sync advance | Multi-monitor same group |
| Metered mode | Cache-only on cellular |
| KWallet | Optional API key load |
| Variety metadata | JSON for external tools |
| Export settings | Clipboard or file |
| Plasmoid | `org.robertsm.wallhaven.control` |

## Commands

```bash
./dev-helper.sh test
./dev-helper.sh translations
./dev-helper.sh package
./tools/wallhaven-ctl.sh next
```

## Flatpak

See `flatpak/org.robertsm.wallhaven.yaml` (packages wallpaper + plasmoid into KDE runtime).

## License

GPL-2.0-or-later
