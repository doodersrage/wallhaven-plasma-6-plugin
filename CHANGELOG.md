# Changelog

## 1.8.0 — 2026-08-14

### Added
- **D-Bus `AppendTextFile`** — rotated debug log writes without shell Python one-liners
- **Settings import via D-Bus** — JSON import from any file under `$HOME` (not blocked XHR)
- **Debug log preview** — show recent log lines from Advanced settings
- **Slideshow rules auto-resume** — resumes when battery/activity conditions clear
- **Complete packaging** — `.mo` locales + systemd user unit for D-Bus service
- **KRunner German** — translated desktop entry strings
- **GitHub issue template** — structured bug reports

### Fixed
- **Attribution overlay** — corner placement no longer uses conflicting anchors or full-width bars
- **Plugin version** — debug bundle reads version from `wallhaven.js` / metadata sync

## 1.7.1 — 2026-08-14

### Fixed
- **Plasmashell crashes** — replace unavailable QML `Process` with D-Bus helper (`WriteTextFile`, `RunArgv`)
- **Empty settings panel** — inline setup wizard instead of broken `Kirigami.OverlaySheet` with invalid `preferredWidth`
- **Local file reads** — route control bus, cache, battery, Variety, and debug log through D-Bus `ReadTextFile` (XHR `file://` disabled in plasmashell)
- **Cache image URLs** — avoid double `file://` prefix on disk cache paths
- **Status banner layout** — remove conflicting horizontal center anchor

## 1.7.0 — 2026-08-14

### Added
- **Full German translation** (~390 UI strings) with extract/sync/compile pipeline
- **Variety bridge `--apply`** + settings button to push Variety search to Wallhaven
- **Live MPRIS metadata** — D-Bus watches status file for KDE Connect/media UI updates
- **Screenshot capture v2** — guided 6-shot checklist for KDE Store assets
- **Complete packaging** — PKGBUILD/RPM install locale, metainfo, notifyrc, tools, preset handler
- **AUR publish workflow template** (manual trigger + SSH secret)

### Fixed
- **i18n extract** no longer embeds source file paths in msgids

## 1.6.0 — 2026-08-14

### Added
- **Full MPRIS** (`org.mpris.MediaPlayer2.wallhaven`) for KDE Connect/media keys
- **`wallhaven://preset/` URL handler** + import from settings
- **KRunner extras** — open, block, copy tags
- **Plasmoid context menu** — open, block, copy tags
- **Auto panel accent** via `plasma-apply-colors`
- **Smart color search** from wallpaper palette
- **Favorite tags** boosted in search queries
- **Slideshow rules** — pause on low battery or inactive session
- **GitHub issue template** in debug bundle
- **Performance metrics** in status + debug export
- **Community presets** pack + variety bridge script
- **Packaging stubs** — AUR PKGBUILD, RPM spec
- **Screenshot capture script** + Neon nightly CI extension

## 1.5.0 — 2026-08-14

### Added
- **Setup wizard** on first run (API key, search, interval, curated presets)
- **Settings filter** search box across tabs
- **Wallpaper of the day** mode (toplist / 24h)
- **Favorites auto-refresh** interval
- **Debug log** + copy debug info bundle
- **Cache manager** with pin/unpin/evict (LRU respects pins)
- **Adaptive preload** count (network/metered aware)
- **WebP** file type filter
- **Curated presets** pack + import + share URL (`wallhaven://preset/…`)
- **KRunner** plugin (`wh next`, `wallhaven search …`)
- **D-Bus player API** at `/Player` (Next/Previous/PlayPause/Metadata)
- **Variety watch** script (`inotifywait`)
- **Webhook bot example** for automation
- **Plasma shortcuts** documentation
- Nightly CI workflow + QML smoke tests

## 1.4.0 — 2026-08-14

### Added
- **Tag blocklist** (local `-tag` exclusions in search)
- **Weekday/weekend schedule** searches
- **Multi-collection rotation** (cycle collections on advance)
- **Wallpaper history gallery** in settings
- **Lock screen sync** when caching wallpapers
- **Slide, zoom, random** transition modes + **parallax** offset
- **Panel tint metadata** JSON for external theming
- **Variety folder symlink** (`wallhaven-current.jpg`)
- **Plasmoid v2** — thumbnail, pause state, countdown
- **D-Bus control** (`tools/wallhaven-dbus.py`)
- **Global shortcuts helper** (optional KGlobalAccel C++ tool)
- **Variety sync** and **panel tint** helper scripts

## 1.3.0 — 2026-08-14

### Added
- **Similar wallpapers** desktop action (`like:` search)
- **File type filter** (JPEG/PNG), **search test**, **API key validation**
- **Wallpaper details panel** in settings preview
- **Interval jitter** and separate **day/night slideshow intervals**
- **Fade-through-black** transition mode
- **Attribution** corner, auto-hide, and font scale options
- **Control bus** (CLI + plasmoid), **multi-monitor sync advance**
- **Wallhaven Control** panel plasmoid and `tools/wallhaven-ctl.sh`
- **Metered network** cache-only mode (cellular)
- **KWallet** API key loading
- **Variety metadata** JSON export
- **Settings export to file**
- Flatpak manifest, translation compile script

## 1.2.0 — 2026-08-14

- Copy tags/URL, blocklist, presets, import/export, offline-only, rate-limit headers

## 1.1.0 — 2026-08-14

- Collection picker, pause, offline fallback, dual preload, shipping polish

## 1.0.0 — 2026-08-11

- Initial Plasma 6 release
