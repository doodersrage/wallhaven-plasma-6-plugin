# Changelog

## 1.2.0 — 2026-08-14

### Added
- **Copy Tags** and **Copy Page URL** desktop actions
- **Favorite on Wallhaven…** (opens browser; Wallhaven has no public write API)
- **Block This Wallpaper** action + blocklist management in settings
- **Search presets** — save/apply/delete named search profiles
- **Settings import/export** — copy JSON to clipboard or import from file
- **Offline-only mode** — cycle cached wallpapers with no network use
- **Rate-limit header** parsing (`Retry-After`) for smarter backoff
- Cache file deletion on clear (via `rm`)
- Release docs, translation template, shortcut helper, store `preview.jpg`

### Changed
- Blocked wallpapers are filtered from API results and random picks
- Tag metadata is fetched for copy/actions even when attribution overlay is off

## 1.1.0 — 2026-08-14

### Added
- Collection picker in settings (load collections via API key)
- Slideshow pause (settings + desktop Wallpaper Actions)
- Copy wallpaper ID desktop action
- Offline cache fallback when network requests fail
- Wake / reconnect handling with periodic connectivity checks
- Dual wallpaper preload
- Configurable disk cache slot count and clear-cache button
- Custom Wallhaven notification component
- AppStream metadata, CI workflow, and unit tests for `wallhaven.js`

### Changed
- Version bumped to 1.1.0
- README expanded with new capabilities and release instructions

## 1.0.0 — 2026-08-11

- Initial Plasma 6 release
