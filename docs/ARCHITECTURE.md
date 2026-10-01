# Architecture

Wallhaven for Plasma 6 is a **wallpaper plugin** (runs inside `plasmashell`), a **session D-Bus service**, and a **panel plasmoid** that share JSON status/control files.

## Components

| Piece | Path | Role |
|-------|------|------|
| Wallpaper engine | `contents/ui/main.qml` | Slideshow engine, image layers and transitions, blank/wake recovery, settings watchers |
| D-Bus client | `contents/ui/DBusHelper.qml` | Every call to the helper service; replies unwrapped to plain values |
| API key | `contents/ui/ApiKeyStore.qml` | Key from KWallet held in memory; never written to the config |
| API health | `contents/ui/ApiHealth.qml` | Last result, shared 429 latch, soft-offline entry/exit, quiet outage probe |
| Disk cache | `contents/ui/DiskCache.qml` | LRU slot index, save/prune/pin/evict, size quota, upscale pass |
| Lock screen | `contents/ui/LockScreenSync.qml` | When to sync/repair, last result, one retry |
| Remote control | `contents/ui/ControlBus.qml` + `BusSignals.qml` | Control commands and sync-advance ticks (signals, polling fallback), command dispatcher |
| Session watchers | `contents/ui/SessionMonitors.qml` | Battery, idle, music, weather (each only while enabled) |
| Effects / overlays | `KenBurns.qml`, `StatusBanner.qml`, `AttributionBanner.qml`, `DetailsSheet.qml` | Pan/zoom values and on-desktop UI |
| Pure logic | `contents/code/wallhaven.js` | URLs, picking, cache LRU, presets, migration, bus ingestion (`.pragma library`) |
| Settings | `contents/ui/config.qml` | KConfig bindings (`cfg_*`), Essentials page + 6 tabs (Wallpapers, Filters, Slideshow, Desktop, Storage, Maintenance) |
| Config schema | `contents/config/main.xml` | All persisted keys (`ConfigSchemaVersion`) |
| D-Bus service | `tools/wallhaven-dbus.py` | File I/O, KWallet, lock-screen sync, upscaler, change signals, MPRIS, KRunner, Variety watch |
| Plasmoid | `plasmoid/contents/ui/main.qml` + `StatusWatcher.qml` | Thumbnail, controls, history, per-monitor picker |
| Control bus | `~/.cache/plasmashell/wallhaven-control.json` | CLI/plasmoid → wallpaper commands |
| Status bus | `wallhaven-status.json` + `wallhaven-status-<ns>.json` | Live ID, thumb, screen, sync group |

Logic stays in a **single** `wallhaven.js` pragma library so Plasma QML can import one module without ES-module bundling.

### How the QML pieces fit

`main.qml` instantiates each component with `host: root` (and `dbus`, `engine` where needed). Components reach the rest of the wallpaper only through `host.<member>`; `main.qml` keeps aliases and thin entry points under the names the engine and the settings dialog (`liveWallpaper.<member>`) already use. `tests/check-qml-refs.py` verifies that every `host.*`, `engine.*`, `dbus.*`, `Wallhaven.*` and `liveWallpaper.*` reference resolves.

## Data flow

1. **Fetch**: `engine.configObject()` → `wallhaven.js` URL builders → `XMLHttpRequest` → `pickWallpaper()` → `displayWallpaper()`.
2. **Cache**: On image ready, `allocateDiskCacheSlot()` (LRU) → `grabToImage` or **curl original** → slot file under cache dir.
3. **Status**: `publishStatus()` → `PublishStatusJson` / `PublishMonitorStatusJson` → status files + `StatusChanged` signal; the plasmoid reloads on the signal.
4. **Control**: plasmoid/CLI/KRunner/MPRIS → helper writes `wallhaven-control.json` and emits `ControlChanged` (a directory monitor covers files written by scripts) → `ControlBus` → `Wallhaven.ingestControlPayload()` → dispatcher.
5. **Settings**: Plasma binds `cfg_Foo` ↔ `main.xml`; the engine follows them through **binding fingerprints** (see below).
6. **Schema**: `migrateConfigurationToV3()` runs once when `ConfigSchemaVersion < 3` (XML default is `0` so upgrades migrate).

### Reacting to settings

KConfig keys are capitalized (`SearchText`). Qt does **not** call `Connections { function onSearchTextChanged() }` for such a key on a property map: no warning, the handler simply never runs (true for `KConfigPropertyMap` on Qt 6.11; `valueChanged` fires for every key on every write, so it is no substitute). Bindings do follow those keys. `main.qml` therefore derives:

- `searchSettingsFingerprint` – every key that changes which wallpapers are fetched. A change arms a 250 ms timer that calls `engine.resetSlideshow()` once per Apply. `resetSlideshow()` records the fingerprint it fetched for; code that writes such a key itself and does not want a refetch (liking a wallpaper, smart colour, trip mode) calls `acknowledgeSearchSettings()`.
- `intervalSettingsFingerprint`, `parallaxSettingsFingerprint`, `watchedSyncGroup`, `watchedUseKWallet`, and `KenBurns.settingsFingerprint` for the rest.

### Signals instead of polling

| Signal (`org.robertsm.Wallhaven`) | Emitted when | Consumer |
|---|---|---|
| `ControlChanged(payload)` | `wallhaven-control.json` rewritten | wallpaper |
| `SyncAdvanced(group, payload)` | `wallhaven-sync-<group>.json` rewritten | wallpaper |
| `StatusChanged(namespace, payload)` | a status snapshot published | plasmoid |

`BusSignals.qml` / `StatusWatcher.qml` use `SignalWatcher` and `DBusServiceWatcher` and are loaded through a `Loader`. `SignalWatcher` exists from Plasma 6.4; on 6.2/6.3 (the minimum, where the module's `asyncCall` API first appeared) the files fail to load and timers poll at the old cadence; with signals the same timers run every 30 s as a safety net. Watermarks (`_lastControlTs`, `_lastSyncAdvanceTs`, epoch ms in `property double`) make a signal and a poll of the same file idempotent.

## D-Bus helpers

| Method | Purpose |
|--------|---------|
| `GetStatus` | Primary `wallhaven-status.json` text |
| `ListMonitorStatuses` | JSON array of per-monitor status snapshots |
| `GetPluginVersion` | Semver string matching `metadata.json` |
| `ListImageFiles(folder, optionsJson)` | Image paths under `$HOME` (depth/exclude options) |
| `GetApiKey` / `SetApiKey(key)` | KWallet read/write (stdin/stdout only) |
| `SyncLockScreen(source, dest)` / `EnsureLockScreen` | Lock-screen copy + `kscreenlockerrc`, under a flock |
| `LinkVarietyCurrent(folder, source)` | `wallhaven-current.jpg` symlink |
| `SyncSystemAccent(kdeColor, gnomeAccent)` | Accent colour to `kdeglobals` / GNOME |
| `StatCacheFiles(pathsJson)` | Sizes of cache files in one call |
| `RunArgv(argvJson)` | Allow-listed argv only: `rm`, `cp`, `curl` (wallhaven.cc → cache), `test`, `stat`, `systemsettings`, `plasma-apply-colors`. **No shell.** |

Slow methods (`RunArgv`, `Upscale`, lock sync, KWallet) run in a worker thread and reply asynchronously, so the service keeps answering.

## Wiring rules (avoid silent no-ops)

1. User toggles need **`property alias cfg_Key`** in `config.qml`.
2. Search-affecting keys need **`Key: cfg.Key`** in `engine.configObject()`.
3. Async D-Bus replies must use **`dbusReplyAsString` / `dbusReplyIsTrue`** — never bare `String(reply)` (`DBusHelper` does this for you).
4. Settings UI must **bind properties**, not `someFunction()` once.
5. Never two **`visible:`** bindings on the same QML object.
6. Never react to a config key with `Connections { function onFooChanged() }` — it is never called. Add the key to a fingerprint binding.
7. New service behaviour gets its **own D-Bus method**; do not widen `RunArgv`.

`./scripts/check-config-wiring.sh` enforces (2) and warns on (1); `tests/check-qml-refs.py` enforces (6) and dangling references.

## Tests

| Test | Needs | Covers |
|------|-------|--------|
| `tests/test-wallhaven.js` | node | Pure logic |
| `tests/test-control-fanout.py`, `tests/test-variety-dbus.py` | python-dbus | Helper functions (imported, no bus) |
| `tests/test-dbus-service.py` | `dbus-run-session` | Helper methods and signals on a private bus, fake wallet/kconfig |
| `tests/validate-qml.sh` → `tests/check-qml-refs.py` | optional qmllint | Structure, dangling references, dead handlers |
| `tests/test-qml-runtime.py` | PyQt6 or PySide6 + Plasma QML modules | Loads the real wallpaper and plasmoid headless and drives them |
| `tests/test-*-storm.sh`, `test-control-busy-queue.sh` | a deployed, running wallpaper | Live regressions |

The runtime test stubs only the two Plasma host types plasmashell alone can create (`tests/qml-stubs`); the configuration object is a real `QQmlPropertyMap`, the base class of Plasma's.

## Sync groups

`SyncAdvanceGroup` names a control-bus group. Optional **sync profiles** (`SyncProfilesJson`) store search settings per group; switching groups applies the saved profile. The plasmoid routes commands to the selected monitor’s group.

## Version

Plugin version lives in `metadata.json`, `wallhaven.js` `pluginVersion()`, D-Bus `GetPluginVersion`, and AppStream releases — kept in sync by `scripts/validate.sh`.
