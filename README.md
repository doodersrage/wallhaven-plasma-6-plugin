# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 port of the [Wallhaven Wallpaper Engine plugin](../wallhaven-wallpaper-engine). Fetches wallpapers from the [Wallhaven API](https://wallhaven.cc/help/api) with search, collections, favorites, slideshow controls, and visual effects.

## Requirements

- KDE Plasma 6
- Network access to `wallhaven.cc` (unless **Offline only** mode is enabled)
- Optional: [Wallhaven API key](https://wallhaven.cc/settings/account) for NSFW, favorites, and collection picker

## Installation

```bash
./dev-helper.sh install
./dev-helper.sh restart
```

Then open **System Settings → Appearance → Wallpaper**, choose **Wallhaven**, configure, and apply.

### Package install

```bash
./dev-helper.sh package
kpackagetool6 --type Plasma/Wallpaper --install wallhaven-plasma-1.2.0.tar.xz
kquitapp6 plasmashell && plasmashell &
```

## Desktop actions

Right-click desktop → **Wallpaper Actions**:

Reload · Next · Previous · Pause · Copy ID · Copy Tags · Copy URL · Favorite on Wallhaven… · Block · Open in Browser · Save

## Highlights

| Feature | Notes |
|---------|--------|
| Search / collection / favorites | Full Wallhaven API browsing |
| Collection picker | Load collections with API key |
| Search presets | Save/apply named filter profiles |
| Blocklist | Skip wallpapers permanently |
| Slideshow + pause | Timer or manual advance |
| Offline fallback / offline-only | Disk cache when network fails or is disabled |
| Settings backup | Export JSON to clipboard, import from file |
| Effects | Crossfade, Ken Burns, attribution |
| Performance | Screen-sized decode, dual preload, disk cache |

See `README` feature table in repo history for the full list.

## Not ported (Plasma limits)

- Audio reactive / RGB sync — no APIs
- Click desktop to advance — Folder View intercepts clicks
- Overlays above icons — wallpaper layer is underneath
- One-click API favorite — Wallhaven has no public write API (browser fallback provided)

## Development

```bash
./dev-helper.sh test
./dev-helper.sh package
./scripts/extract-messages.sh   # refresh translation template
```

Release steps: `RELEASE.md`

## License

GPL-2.0-or-later
