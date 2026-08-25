# Architecture

Wallhaven for Plasma 6 is a **wallpaper plugin** (runs inside `plasmashell`), a **session D-Bus service**, and a **panel plasmoid** that share JSON status/control files.

## Components

| Piece | Path | Role |
|-------|------|------|
| Wallpaper engine | `contents/ui/main.qml` | Slideshow, fetch, render, cache, effects |
| Pure logic | `contents/code/wallhaven.js` | URLs, picking, cache LRU, presets (`.pragma library`) |
| Settings | `contents/ui/config.qml` | KConfig bindings (`cfg_*`), must not call async getters once |
| Config schema | `contents/config/main.xml` | All persisted keys |
| D-Bus service | `tools/wallhaven-dbus.py` | File I/O, upscaler, MPRIS, Variety watch |
| Plasmoid | `plasmoid/contents/ui/main.qml` | Thumbnail, controls, history popup |
| Control bus | `~/.cache/plasmashell/wallhaven-control.json` | CLI/plasmoid → wallpaper commands |

## Data flow

1. **Fetch**: `engine.configObject()` → `wallhaven.js` URL builders → `XMLHttpRequest` → `pickWallpaper()` → `displayWallpaper()`.
2. **Cache**: On image ready, `allocateDiskCacheSlot()` (LRU) → `grabToImage` or **curl original** → slot file under cache dir.
3. **Status**: `publishStatus()` writes `wallhaven-status.json`; plasmoid reads via D-Bus `ReadTextFile`.
4. **Settings**: Plasma binds `cfg_Foo` ↔ `main.xml`; engine listens on `root.configuration` `onFooChanged` → `resetSlideshow()`.

## Wiring rules (avoid silent no-ops)

1. User toggles need **`property alias cfg_Key`** in `config.qml`.
2. Search-affecting keys need **`Key: cfg.Key`** in `engine.configObject()`.
3. Async D-Bus replies must use **`dbusReplyAsString` / `dbusReplyIsTrue`** — never bare `String(reply)`.
4. Settings UI must **bind properties**, not `someFunction()` once.

Run `./scripts/check-config-wiring.sh` in CI to enforce (2) and warn on (1).

## Sync groups

`SyncAdvanceGroup` names a control-bus group. Optional **sync profiles** (`SyncProfilesJson`) store search settings per group; switching groups applies the saved profile.

## Version

Plugin version lives in `metadata.json`, `wallhaven.js` `pluginVersion()`, and AppStream releases — kept in sync by `scripts/validate.sh`.
