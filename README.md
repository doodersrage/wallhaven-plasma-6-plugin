# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 port of the [Wallhaven Wallpaper Engine plugin](../wallhaven-wallpaper-engine). Fetches wallpapers from the [Wallhaven API](https://wallhaven.cc/help/api) with search, collections, favorites, slideshow controls, and visual effects.

## Requirements

- KDE Plasma 6
- Network access to `wallhaven.cc`
- Optional: [Wallhaven API key](https://wallhaven.cc/settings/account) for NSFW, favorites, and collection picker

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
kpackagetool6 --type Plasma/Wallpaper --install wallhaven-plasma-1.1.0.tar.xz
kquitapp6 plasmashell && plasmashell &
```

## Usage

- Set **Browse mode** to Search, Collection, or Favorites
- Settings are grouped under **Source**, **Filters**, **Playback**, and **Advanced**, with a live preview at the top
- **Collection mode**: enter an API key, click **Load collections**, then pick from the dropdown
- **Random interval** (minutes; `0` = manual advance only)
- **Pause slideshow** in Playback settings or via desktop Wallpaper Actions
- Desktop actions: right-click → **Wallpaper Actions** → Reload / Next / Previous / Pause / Copy ID / Open in Browser / Save Wallpaper…
- Search filters (categories, purity, ratio, color, blacklist, time-of-day) apply in **Search** mode only

## Features

| Feature | Status |
|---------|--------|
| Search / collection / favorites | Yes |
| Collection picker (API key) | Yes |
| Categories, purity, ratio, color | Yes (Search mode) |
| API & local sorting | Yes |
| Random interval slideshow + pause | Yes |
| Crossfade & Ken Burns | Yes |
| Attribution overlay | Yes |
| Tag blacklist (API key) | Yes (Search mode) |
| Time-of-day searches | Yes (Search mode) |
| Duplicate avoidance | Yes (persisted) |
| Dual image preload | Yes |
| Status / error overlay | Yes |
| Desktop wallpaper actions | Reload, Next, Previous, Pause, Copy ID, Open, Save |
| Image quality (small / large / original) | Yes |
| Request timeout & rate-limit retry | Yes |
| System notifications (refresh / errors) | Yes |
| Auto-skip failed image downloads | Yes |
| Screen-sized decode + layer release | Yes |
| Local disk cache + offline fallback | Yes |
| Wake / reconnect handling | Yes |

## Not ported (Plasma limitations)

- **Audio reactive effects** — no wallpaper audio API on Plasma
- **RGB LED sync** — no hardware LED plugin API in QML wallpapers
- **Click left/right to advance** — Folder View intercepts desktop clicks
- **Status/attribution above icons** — overlays draw under Folder View icons

## Development

```bash
./dev-helper.sh test      # run wallhaven.js unit tests
./dev-helper.sh package   # build .tar.xz release archive
```

Run plasmashell from a terminal to see QML errors:

```bash
kquitapp6 plasmashell
plasmashell
```

## Releasing

1. Update version in `metadata.json` and `metainfo/org.robertsm.wallhaven.metainfo.xml`
2. Add notes to `CHANGELOG.md`
3. Capture screenshots (see `screenshots/README.md`)
4. `./dev-helper.sh package`
5. Publish the `.tar.xz` to GitHub Releases or the KDE Store

## Project structure

```
metadata.json
metainfo/                     AppStream metadata
contents/
  config/main.xml             Configuration schema
  code/wallhaven.js           API helpers & slideshow logic
  notifications/*.notifyrc    Notification events
  ui/main.qml                 Wallpaper rendering
  ui/config.qml               Settings UI
tests/test-wallhaven.js       Unit tests
dev-helper.sh                 Install / package helper
```

## License

GPL-2.0-or-later
