# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 port of the [Wallhaven Wallpaper Engine plugin](../wallhaven-wallpaper-engine). Fetches wallpapers from the [Wallhaven API](https://wallhaven.cc/help/api) with search, collections, favorites, slideshow controls, and visual effects.

## Requirements

- KDE Plasma 6
- Network access to `wallhaven.cc`
- Optional: [Wallhaven API key](https://wallhaven.cc/settings/account) for NSFW and favorites

## Installation

### Quick install (development)

```bash
./dev-helper.sh install
./dev-helper.sh restart
```

Then open **System Settings → Appearance → Wallpaper**, choose **Wallhaven** from the wallpaper type dropdown, configure, and apply.

### Package install

```bash
./dev-helper.sh package
kpackagetool6 --type Plasma/Wallpaper --install wallhaven-plasma-1.0.0.tar.xz
kquitapp6 plasmashell && plasmashell &
```

## Usage

- Set **Browse mode** to Search, Collection, or Favorites
- Settings are grouped under **Source**, **Filters**, **Playback**, and **Advanced**, with a live preview at the top
- **Random interval** (minutes; `0` = manual advance only)
- Desktop actions: right-click → **Wallpaper Actions** → Reload / Next / Previous / Open in Browser / Save Wallpaper…
- Search filters (categories, purity, ratio, color, blacklist, time-of-day) apply in **Search** mode only

## Features ported from Wallpaper Engine

| Feature | Plasma port |
|---------|-------------|
| Search / collection / favorites | Yes |
| Categories, purity, ratio, color | Yes (Search mode) |
| API & local sorting | Yes |
| Random interval slideshow | Yes |
| Crossfade & Ken Burns | Yes |
| Attribution overlay | Yes |
| Tag blacklist (API key) | Yes (Search mode) |
| Time-of-day searches | Yes (Search mode) |
| Duplicate avoidance | Yes (persisted across restarts) |
| Image preloading | Yes |
| Status / error overlay | Yes |
| Desktop wallpaper actions | Reload, Next, Previous, Open in Browser, Save |
| Image quality (small / large / original) | Yes (thumb preview / full `path` / full `path`) |
| Request timeout & rate-limit retry | Yes (configurable timeout, delay, attempts) |
| System notifications (refresh / errors) | Yes (optional) |
| Auto-skip failed image downloads | Yes |
| Screen-sized image decode | Yes (less RAM/VRAM; Ken Burns uses 1.25×) |
| Inactive layer release | Yes (after crossfade) |
| Deferred settings preview writes | Yes |
| Local disk cache | Yes (optional ring cache of recent wallpapers) |

## Not ported (Plasma limitations)

These Wallpaper Engine features have no Plasma equivalent:

- **Audio reactive effects** — no wallpaper audio API on Plasma
- **RGB LED sync** — no hardware LED plugin API in QML wallpapers
- **Click left/right to advance** — Folder View intercepts desktop clicks
- **Status/attribution above icons** — overlays draw on the wallpaper layer under Folder View icons

## Project structure

```
metadata.json                 Plugin metadata (KPackage)
contents/
  config/main.xml             Configuration schema
  code/wallhaven.js           API helpers & slideshow logic
  ui/main.qml                 Wallpaper rendering
  ui/config.qml               Settings UI
dev-helper.sh                 Install / package helper
```

## Debugging

Run plasmashell from a terminal to see QML errors:

```bash
kquitapp6 plasmashell
plasmashell
```

## License

GPL-2.0-or-later
