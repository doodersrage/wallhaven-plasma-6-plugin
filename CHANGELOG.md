# Changelog

## 2.6.2 — 2026-08-23

### Fixed
- **Prefer sharper matches was a no-op** — the toggle never reached `pickWallpaper` because `PreferSharpMatches` was omitted from `engine.configObject()`
- **Weather-reactive search was a no-op** — `WeatherReactiveEnabled` / `WeatherTagCache` were written by the weather poll but never passed into search query building
- **Music-reactive pacing** — MPRIS `PlaybackStatus` replies were compared with bare `String(status)`, which fails when PDBus wraps the value; now uses `dbusReplyAsString`
- **Screen-lock pause** — `GetActive` replies now go through `dbusReplyIsTrue` so a wrapped false does not look locked forever
- **Like / favorite tags** — changing `TagFavoritesJson` now resets the slideshow so boosted tags affect the next search
- **Settings JSON fields** — tag blocklist, favorite tags, collection rotation, time capsules, and saved presets use `cfg_*` bindings (Plasma Apply/load) instead of one-shot reads from `wallpaperConfiguration`
- **Plasmoid history/status** — `ReadTextFile` replies are unwrapped before `JSON.parse`, so the recent-wallpapers popup and status thumb no longer stay empty when PDBus wraps the string

## 2.6.1 — 2026-08-21

### Fixed
- **Settings D-Bus banner stayed up while the service was running** — two stacked bugs. The settings page called `isDbusServiceAvailable()` once (QML does not re-run that). Worse, `wallhaven-dbus.py` constructed `dbus.service.BusName(...)` as temporaries; dbus-python releases a well-known name when that object is garbage-collected, so systemd showed the unit `active` while `org.robertsm.Wallhaven` was gone from the session bus. Names are now held for the process lifetime, the unit is `Type=dbus`, and settings pings the service directly.
- **Disk cache is rolling again** — the slot count is a ceiling, not a permanent set of N images. Once full, the least-recently-used unpinned wallpaper is aged out so new downloads keep replacing old ones. Revisiting a cached wallpaper (or writing it again) marks it recently used so it stays. Pinned slots are still never evicted.
- **Upscaler status stuck on "Checking…"** — settings called `isUpscalerStatusKnown()` once (QML does not re-run that after the async D-Bus reply). It now binds live wallpaper properties and polls `UpscalerAvailable` itself, same pattern as the D-Bus banner ping.
- **Wallpaper history gallery empty** — the settings "Recent" row used a zero-height `GridView` and read `WallpaperHistoryJson` from a config object the dialog often never loads. It now pulls history from the live wallpaper (same pattern as the cache list), keeps a `cfg_WallpaperHistoryJson` binding, and shows an empty-state message instead of a blank label.

## 2.6.0 — 2026-08-21

Sharper wallpapers and a more honest D-Bus layer: three opt-in image-quality features on top of the existing search/render/cache pipeline, plus six correctness fixes found in a follow-up bug-hunting pass over 2.5.0.

### Added
- **Prefer sharper matches** — optional bias for random wallpaper selection toward images that fit your screen's resolution and aspect ratio without heavy upscaling or cropping, instead of picking uniformly at random (`Search → Other → Prefer sharper matches`, off by default)
- **Image enhance** — optional brightness/contrast/saturation adjustment applied at render time via `QtQuick.Effects.MultiEffect`, purely client-side on top of the existing crossfade/Ken Burns/parallax pipeline; the cached file on disk is untouched (`Effects → Image enhance`, off by default)
- **External upscaler hook** — when disk cache and the new "Upscale low-res" option are both enabled, a wallpaper whose native resolution genuinely falls short of your screen is run through `realesrgan-ncnn-vulkan` (if it's on your `PATH`) right after it's written to the disk cache, replacing the cached copy in place; later views of that same cached wallpaper (repeats, lock-screen sync, history scrubber, Variety symlink) get the upscaled version. Two new D-Bus methods (`UpscalerAvailable`, `Upscale`) back this from the service side, path-validated the same way as the existing file methods, with a 120s timeout and an atomic temp-file swap so a failed or interrupted run never corrupts the cache. No upscaler installed, or the setting off, means exactly today's plain-scaled behavior (`Performance → Upscale low-res`, off by default)
- **Upscaler visibility** — settings now show whether `realesrgan-ncnn-vulkan` was actually detected (`Performance → Upscaler status`), and a new "Re-upscale cached wallpapers" button retroactively applies the upscaler to wallpapers already sitting in the disk cache from before the setting was turned on. Backed by a new per-entry native-resolution record in the disk-cache index (`DiskCacheIndexJson`'s `dimensions` map, captured once at cache-write time); entries cached before this tracking existed have no recorded resolution and are skipped rather than guessed at
- 5 new pure-function unit tests covering the selection/enhance/upscale/dimension-tracking logic (`tests/test-wallhaven.js`), plus 2 new Python tests for the upscaler-detection helper (`tests/test-variety-dbus.py`)

### Fixed
- **System theme sync** — was writing a raw `#RRGGBB` string to both targets, which neither accepts: `kdeglobals`' `AccentColor` needs KConfig's `r,g,b` decimal `QColor` format, and GNOME's `accent-color` is a fixed 9-name enum. Both syncs silently no-op'd; now the hex is converted to KConfig RGB and mapped to the nearest named GNOME accent
- **"Small" image quality** — the low-bandwidth setting was preferring `thumbs.large`/`thumbs.original` over the actual `thumbs.small` thumbnail, so it rarely downloaded anything smaller than the default; `thumbs.small` is now tried first
- **Overlapping transitions** — starting a new wallpaper change (manual next/prev, a short slideshow interval, or a control-bus command) before the previous crossfade/slide/zoom animation finished left two `ParallelAnimation`s fighting over the same opacity/transform properties, and could clear a layer's image mid-fade; in-flight transitions are now stopped before a new one starts
- **Pinned disk-cache slots** — once every disk-cache slot was pinned, downloading a new wallpaper would silently evict a pinned one anyway (unpinning it) instead of just skipping the cache write; `allocateDiskCacheSlot` now refuses to evict a pinned slot
- **D-Bus availability detection** — `isDbusServiceAvailable()` called `PDBus.SessionBus.nameHasOwner(...)` as if it were a synchronous getter; that's not part of the QML D-Bus API (every other call in this codebase is async via `dbusMessage()`/`asyncCall()`), so the check silently always came back unavailable. The "D-Bus service is not running" settings banner and the Variety preview/apply buttons could stay stuck offline even with `wallhaven-dbus.service` actually running. Now backed by a periodic async `org.freedesktop.DBus.NameHasOwner` call, same pattern as the music-reactive MPRIS poll
- **"Pause when inactive"** (now "screen lock pause") — checked `Qt.application.state !== Qt.ApplicationActive`, which reflects window focus for a normal top-level app; this wallpaper's QML runs inside plasmashell's own desktop view, which doesn't gain/lose focus the way a regular window does, so the check was never a reliable read on whether anyone was actually looking at the session. Now polls the standard `org.freedesktop.ScreenSaver.GetActive` D-Bus method (the same interface kscreenlocker and every other screensaver-aware Linux app use to publish lock state), so the slideshow now actually pauses when the screen locks and resumes on unlock

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
- 6 new pure-function unit tests covering the above (`tests/test-wallhaven.js`)

### Fixed
- **History scrubber image quality** — recalling a wallpaper that had aged out of the disk-cache LRU now fetches the full-resolution image instead of silently falling back to a small thumbnail
- **Settings export/import** — the six new v2.5.0 toggles/fields were missing from the export snapshot and are now included
- **`wallhaven-ctl.sh like`/`dislike`** — could hang or error when falling back to the Python D-Bus helper directly (missing from its CLI allow-list); fixed
- **Plasmoid swipe gesture** — no longer opens the wallpaper's browser page as a side effect when swiping while the D-Bus service is offline

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
