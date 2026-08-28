# Architecture

Wallhaven for Plasma 6 is a **wallpaper plugin** (runs inside `plasmashell`), a **session D-Bus service**, and a **panel plasmoid** that share JSON status/control files.

## Components

| Piece | Path | Role |
|-------|------|------|
| Wallpaper engine | `contents/ui/main.qml` | Slideshow, fetch, render, cache, effects |
| Pure logic | `contents/code/wallhaven.js` | URLs, picking, cache LRU, presets, migration (`.pragma library`) |
| Settings | `contents/ui/config.qml` | KConfig bindings (`cfg_*`), Simple/Advanced UI |
| Config schema | `contents/config/main.xml` | All persisted keys (`ConfigSchemaVersion`) |
| D-Bus service | `tools/wallhaven-dbus.py` | File I/O, upscaler, MPRIS, Variety watch, status helpers |
| Plasmoid | `plasmoid/contents/ui/main.qml` | Thumbnail, controls, history, per-monitor picker |
| Control bus | `~/.cache/plasmashell/wallhaven-control.json` | CLI/plasmoid → wallpaper commands |
| Status bus | `wallhaven-status.json` + `wallhaven-status-<ns>.json` | Live ID, thumb, screen, sync group |

Logic stays in a **single** `wallhaven.js` pragma library so Plasma QML can import one module without ES-module bundling.

## Data flow

1. **Fetch**: `engine.configObject()` → `wallhaven.js` URL builders → `XMLHttpRequest` → `pickWallpaper()` → `displayWallpaper()`.
2. **Cache**: On image ready, `allocateDiskCacheSlot()` (LRU) → `grabToImage` or **curl original** → slot file under cache dir.
3. **Status**: `publishStatus()` writes primary + per-namespace status JSON; plasmoid uses `GetStatus` / `ListMonitorStatuses`.
4. **Settings**: Plasma binds `cfg_Foo` ↔ `main.xml`; engine listens on `root.configuration` `onFooChanged` → `resetSlideshow()`.
5. **Schema**: `migrateConfigurationToV3()` runs once when `ConfigSchemaVersion < 3` (XML default is `0` so upgrades migrate).

## D-Bus helpers (3.0)

| Method | Purpose |
|--------|---------|
| `GetStatus` | Primary `wallhaven-status.json` text |
| `ListMonitorStatuses` | JSON array of per-monitor status snapshots |
| `GetPluginVersion` | Semver string matching `metadata.json` |
| `ListImageFiles(folder)` | Image paths under `$HOME` (local browse mode) |

## Wiring rules (avoid silent no-ops)

1. User toggles need **`property alias cfg_Key`** in `config.qml`.
2. Search-affecting keys need **`Key: cfg.Key`** in `engine.configObject()`.
3. Async D-Bus replies must use **`dbusReplyAsString` / `dbusReplyIsTrue`** — never bare `String(reply)`.
4. Settings UI must **bind properties**, not `someFunction()` once.
5. Never two **`visible:`** bindings on the same QML object.

Run `./scripts/check-config-wiring.sh` in CI to enforce (2) and warn on (1).

## Sync groups

`SyncAdvanceGroup` names a control-bus group. Optional **sync profiles** (`SyncProfilesJson`) store search settings per group; switching groups applies the saved profile. The plasmoid routes commands to the selected monitor’s group.

## Version

Plugin version lives in `metadata.json`, `wallhaven.js` `pluginVersion()`, D-Bus `GetPluginVersion`, and AppStream releases — kept in sync by `scripts/validate.sh`.
