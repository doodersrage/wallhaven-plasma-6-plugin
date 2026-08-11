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
- Configure filters, sorting, and **Random interval** (minutes; `0` = manual)
- **Click navigation**: right half of the desktop skips forward, left half goes back (counts configurable)
- Works best with the **Desktop** layout; folder view may intercept clicks

## Features ported from Wallpaper Engine

| Feature | Plasma port |
|---------|-------------|
| Search / collection / favorites | Yes |
| Categories, purity, ratio, color | Yes |
| API & local sorting | Yes |
| Random interval & click skip | Yes |
| Crossfade & Ken Burns | Yes |
| Attribution overlay | Yes |
| Tag blacklist (API key) | Yes |
| Time-of-day searches | Yes |
| Duplicate avoidance | Session only |
| Image preloading | Yes |
| Status / error overlay | Yes |

## Not ported (Plasma limitations)

- **Audio reactive effects** — no Wallpaper Engine audio API on Plasma
- **RGB LED sync** — no `wpPlugins.led` equivalent in QML wallpapers
- **Persistent seen-ID cache** — dedup is per session only

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
