# Changelog

## 2.5.0 — 2026-08-19

Fun release: seven playful additions layered on the existing search, tagging, and control-bus infrastructure. All opt-in and off by default.

### Added
- **Swipe-to-rate** — drag the panel widget thumbnail right/left (or use its menu) to like/dislike the current wallpaper; like boosts its tags into your favorites, dislike mutes them into the blocklist
- **Music-reactive pacing** — Ken Burns panning speeds up while any MPRIS media player on the session bus is playing (`Effects → Music-reactive pacing`)
- **Weather-reactive search** — biases the search query toward rain/snow/storm/clear-sky tags using free, keyless Open-Meteo geocoding + forecast for a city or `lat,lon` (`Effects → Weather-reactive search`)
- **History scrubber** — the panel widget gets a "Recent wallpapers" popup to jump back to any of the last dozen wallpapers, backed by a new `wallhaven-history.json` status file
- **Time capsules** — schedule a search to kick in automatically on a date; `MM-DD` repeats yearly (birthdays, holidays), `YYYY-MM-DD` fires once (`Schedule → Time Capsule`)
- **System theme sync** — auto panel accent now optionally also pushes the wallpaper's accent color to GTK apps (`gsettings`) and `kdeglobals` directly (`Effects → System theme sync`)
- **Milestone toasts** — optional notifications for wallpaper view-count milestones (10, 50, 100, …) and daily viewing streaks (`Effects → Milestone toasts`)
- **D-Bus `CommandWithQuery`** — generic control-bus method backing the history scrubber; `wallhaven-ctl.sh history <id>`, `wh like`, and `wh dislike` also added
- 8 new pure-function unit tests covering the above (`tests/test-wallhaven.js`)

## 2.4.0 — 2026-08-18

Bugfix release: settings actions that looked like no-ops, plus cache and filter correctness.

### Fixed
- **Import curated/community presets** — load bundled packs from JS instead of blocked local XHR
- **Apply selected preset** — updates form fields, fills omitted category flags, and reloads the wallpaper
- **Per-screen disk cache** — cache files are namespaced by monitor so People-off screens cannot show another screen’s people wallpaper
- **Parallax** — slow pan actually moves (no longer cancelled by `anchors.centerIn`); Ken Burns pan works too
- **Lock screen sync** — writes Plasma 6 `org.kde.image` Image keys and a stable copy, including cache hits
- **Variety symlink** — updates on cache hits, not only first download
- **Client-side filters** — drop people/sketchy/NSFW results that miss the API or cache metadata

### Changed
- Bundled curated/community presets now set category flags explicitly (People off)

## 2.3.0 — 2026-08-14

Store-ready release: shortcuts build fix, Italian i18n, control docs, and distribution polish.

### Added
- **Italian UI translation** — full ~415 string catalog (`po/catalog/it.json`)
- **Control guide** — `docs/CONTROL.md` (plasmoid, shortcuts, KRunner, D-Bus)
- **KDE Store guide** — `docs/KDE_STORE.md` with screenshot checklist and submission steps
- **Settings filter hint** — message when no settings match the filter query
- **Variety D-Bus tests** — `tests/test-variety-dbus.py` for config parsing
- **Desktop screenshot helper** — `scripts/capture-desktop-screenshot.sh` (spectacle)
- **PKGBUILD shortcuts** — `PKGBUILD.release` builds and ships `wallhaven-shortcuts` + autostart
- **Neon CI** — container job builds shortcuts and runs variety tests

### Fixed
- **KGlobalAccel build on Arch** — per-component `KF6GlobalAccel` CMake finds (no umbrella `KF6` module path)
- **`install-shortcuts`** — dependency hints, clean rebuild dir, clearer errors

### Changed
- **Real desktop screenshot** — `screenshots/desktop-wallpaper.png` captured from live session (1280×720)
- **Release tarball** — includes `docs/` directory

## 2.2.0 — 2026-08-14

Discoverability and control release: shortcuts, Spanish i18n, plasmoid polish, Variety watch, and distribution CI.

### Added
- **Spanish UI translation** — full ~409 string catalog (`po/catalog/es.json`)
- **KGlobalAccel shortcuts** — `tools/wallhaven-shortcuts` + `dev-helper.sh install-shortcuts` + autostart desktop
- **Variety watch mode** — optional live import when `variety.conf` search changes (D-Bus service + settings toggle)
- **Plasmoid v3** — click thumbnail to open page, similar/block/copy menu, offline icon + help action
- **Settings D-Bus banner** — top-level warning when `wallhaven-dbus.service` is not running
- **Flatpak manifest validation** — `scripts/validate-flatpak.sh` + CI smoke job
- **CONTRIBUTING.md** — translator workflow and locale registration steps
- **Control bus `similar` command** — plasmoid and external tools can trigger similar-wallpaper search

### Changed
- **`fill-de-po.py`** — thin wrapper delegating to unified `fill-po.py`
- **Settings filter bar** — always visible at top of configuration panel
- **Release CI** — sync-i18n on tag builds; packaging smoke includes Spanish `.mo`

## 2.1.0 — 2026-08-14

Polish release: i18n expansion, store assets, control UX, and packaging automation.

### Added
- **French UI translation** — full ~406 string catalog alongside German
- **Unified i18n pipeline** — `scripts/fill-po.py` replaces locale-specific fillers; `sync-i18n.sh` runs coverage checks
- **KDE Store screenshot gallery** — six 1280×720 assets + AppStream multi-screenshot metadata
- **Plasmoid local cache thumbnail** — status bus publishes `localThumbUrl` from on-disk wallpaper
- **D-Bus offline hints** — Variety bridge and plasmoid show when `wallhaven-dbus.service` is not running
- **Packaging smoke CI** — `scripts/validate-packaging.sh` + PKGBUILD `--nobuild` against release tarball
- **AUR on release tags** — `aur-publish.yml` triggers automatically when `AUR_SSH_PRIVATE_KEY` is set
- **Screenshot generator** — `scripts/generate-screenshots-from-preview.sh` for placeholder store assets
- **Preset handler helper** — `dev-helper.sh register-preset` registers `wallhaven://` MIME handler

### Changed
- **Variety apply** — separate D-Bus availability check before reading Variety config
- **Release tarball** — includes `screenshots/` and compiled French `.mo` files

## 2.0.0 — 2026-08-14

Stable milestone release of the Wallhaven KDE Plasma 6 port.

### Added
- **Variety search preview** — inspect `image_fetch_search` before applying in settings
- **AppStream screenshots** — KDE Store / Discover metadata with preview image
- **Complete Flatpak manifest** — krunner, notifyrc, locales, preset handler, D-Bus permissions
- **Stable AUR PKGBUILD** — `packaging/PKGBUILD.release` for tarball releases
- **`wallhaven-ctl.sh importpreset`** — CLI preset URL import via control bus
- **i18n coverage check** — `scripts/check-i18n.sh` validates shipped translations
- **KRunner French** — translated desktop entry strings

### Changed
- **2.0 stability** — production-ready packaging, CI, and release automation
- **Bug tracker URL** — points to the canonical GitHub repository

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
