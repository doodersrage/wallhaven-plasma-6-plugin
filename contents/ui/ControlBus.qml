import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Remote control for the wallpaper: commands from the plasmoid, CLI, KRunner,
// MPRIS and global shortcuts (wallhaven-control.json), and "advance together"
// ticks between monitors in a sync group (wallhaven-sync-<group>.json).
//
// wallhaven-dbus.py announces writes to those files as D-Bus signals, so
// nothing is polled while BusSignals.qml is loaded. If it cannot load (older
// Plasma without SignalWatcher) the timers below fall back to the previous
// 400 ms / 800 ms polling; with signals they are only a slow safety net.
Item {
    id: controlBus

    required property var host     // wallpaper root (main.qml)
    required property var dbus     // DBusHelper
    required property var engine   // slideshow engine (main.qml)
    readonly property var cfg: host.cfg

    readonly property bool signalsActive: signalsLoader.status === Loader.Ready
    // Only meaningful while signalsActive; main.qml pings otherwise.
    readonly property bool serviceRegistered: signalsActive && signalsLoader.item.serviceRegistered
    signal screenLockChanged(bool locked)

    function syncAdvanceFile() {
        var group = (cfg.SyncAdvanceGroup || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
        return host.diskCacheDir + "/wallhaven-sync-" + group + ".json";
    }

    function syncAdvanceGroupName() {
        return (cfg.SyncAdvanceGroup || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
    }

    function broadcastSyncAdvance() {
        if (!cfg.SyncAdvanceEnabled) {
            return;
        }
        dbus.writeFile(syncAdvanceFile(), Wallhaven.buildSyncAdvance(host._instanceId));
    }

    function ingestControl(text) {
        if (!text || !cfg.ControlBusEnabled) {
            return;
        }
        var result = Wallhaven.ingestControlPayload(
            text,
            host._lastControlTs,
            Date.now(),
            cfg.SyncAdvanceGroup || "default",
            host.diskCacheNamespace || "",
            300000,
        );
        // Watermarks are epoch ms: keep them in a double property (an int
        // overflowed and re-fired a leftover next on every poll).
        host._lastControlTs = result.watermark;
        for (var i = 0; i < result.run.length; i++) {
            handleControlCommand(result.run[i]);
        }
    }

    function ingestSync(text) {
        if (!text || !cfg.SyncAdvanceEnabled) {
            return;
        }
        var result = Wallhaven.ingestSyncAdvance(
            text, host._lastSyncAdvanceTs, Date.now(), host._instanceId, engine.busy, 300000);
        if (result.action === "queue") {
            // Don't stamp the tick until we can advance — busy used to
            // permanently drop sync advances on multi-monitor setups.
            host._pendingSyncAdvance = true;
            host._pendingSyncAdvanceAt = Math.max(host._pendingSyncAdvanceAt || 0, result.advanceAt);
            return;
        }
        host._lastSyncAdvanceTs = result.watermark;
        if (result.action === "advance") {
            // fromSync=true: followers never rebroadcast (echo storm).
            engine.skipForward(true);
        }
    }

    function pollControl() {
        if (!cfg.ControlBusEnabled) {
            return;
        }
        dbus.readFile(host.controlBusFile, ingestControl);
    }

    function pollSync() {
        if (!cfg.SyncAdvanceEnabled) {
            return;
        }
        dbus.readFile(syncAdvanceFile(), ingestSync);
    }

    function handleControlCommand(cmd) {
        if (!cmd || !cmd.cmd) {
            return;
        }
        switch (cmd.cmd) {
        case "next":
        case "prev":
        case "reload":
            // Queue nav while a fetch is in flight — stamping ts then no-op used
            // to drop KRunner/ctl/MPRIS commands forever.
            if (engine.busy) {
                host._pendingControlCmd = { cmd: cmd.cmd, ts: cmd.ts || Date.now() };
                return;
            }
            host._pendingControlCmd = null;
            if (cmd.cmd === "next") {
                engine.skipForward(false);
            } else if (cmd.cmd === "prev") {
                engine.previousWallpaper();
            } else {
                host.reloadWallpaper();
            }
            break;
        case "pause":
            host.setSlideshowPaused(true);
            break;
        case "resume":
            host.setSlideshowPaused(false);
            break;
        case "search":
            if (cmd.query && host.configuration) {
                host.snapshotSettingsForUndo();
                host.configuration.BrowseMode = "search";
                host.configuration.SearchText = cmd.query;
                host.configuration.WallpaperOfDayEnabled = false;
                host.recordSearchHistory(cmd.query);
                host.scheduleConfigWrite();
                engine.resetSlideshow();
            }
            break;
        case "open":
            if (host.currentPageUrl) {
                Qt.openUrlExternally(host.currentPageUrl);
            }
            break;
        case "block":
            host.blockCurrentWallpaper();
            break;
        case "copytags":
            host.copyCurrentTags();
            break;
        case "similar":
            host.loadSimilarWallpapers();
            break;
        case "info":
            host.showWallpaperInfo();
            break;
        case "importpreset":
            if (cmd.query) {
                host.importPresetFromUrl(cmd.query);
            }
            break;
        case "like":
            host.rateCurrentWallpaper(true);
            break;
        case "dislike":
            host.rateCurrentWallpaper(false);
            break;
        case "history":
            if (cmd.query) {
                host.showHistoryWallpaper(cmd.query);
            }
            break;
        case "pin":
            if (host.currentWallpaperId && host.currentWallpaperId !== "wallpaper") {
                host.pinCacheId(host.currentWallpaperId);
            }
            break;
        case "unpin":
            if (host.currentWallpaperId && host.currentWallpaperId !== "wallpaper") {
                host.unpinCacheId(host.currentWallpaperId);
            }
            break;
        case "outageoffline":
            host.enterApiOutageOffline(0);
            break;
        case "resumeonline":
            // User/ctl intent — clear even if a rate-limit latch is still active.
            host.clearApiOutageOffline(true, true);
            break;
        case "clearkey":
            host.clearApiKey(false);
            break;
        case "testkey":
            host.testApiKeyNow();
            break;
        case "copyid":
            host.copyWallpaperId();
            break;
        case "copyurl":
            host.copyPageUrl();
            break;
        case "prune":
            host.pruneUnpinnedCache();
            break;
        case "warm":
            host.warmDiskCache(cmd.query ? parseInt(cmd.query, 10) : 0);
            break;
        case "cancelwarm":
            host.cancelWarmCache();
            break;
        case "trip":
            host.enterTripModeWithWarm(cmd.query ? parseInt(cmd.query, 10) : 24, cfg.CacheWarmCount || 12);
            break;
        case "endtrip":
            host.clearTripMode(true);
            break;
        case "copysearch":
            host.copySearchToOtherScreens(cmd.query || "");
            break;
        case "undo":
            host.undoLastSettingsChange();
            break;
        case "savesearch":
            host.saveCurrentAsSavedSearch(cmd.query || "");
            break;
        case "applysearch":
            if (cmd.query) {
                host.applySavedSearch(cmd.query);
            }
            break;
        case "purity":
            if (cmd.query) {
                var purity = Wallhaven.parsePurityQuery(cmd.query);
                if (purity.sfw || purity.sketchy || purity.nsfw) {
                    host.setPurityFlags(purity.sfw, purity.sketchy, purity.nsfw);
                }
            }
            break;
        default:
            break;
        }
    }

    Loader {
        id: signalsLoader
        source: "BusSignals.qml"
    }

    Connections {
        target: signalsLoader.item
        ignoreUnknownSignals: true

        function onControlChanged(payload) {
            controlBus.ingestControl(payload);
        }

        function onSyncAdvanced(group, payload) {
            if (group === controlBus.syncAdvanceGroupName()) {
                controlBus.ingestSync(payload);
            }
        }

        function onScreenLockChanged(locked) {
            controlBus.screenLockChanged(locked);
        }
    }

    Timer {
        interval: controlBus.signalsActive ? 30000 : 400
        running: controlBus.host._configured && controlBus.cfg.ControlBusEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: controlBus.pollControl()
    }

    Timer {
        interval: controlBus.signalsActive ? 30000 : 800
        running: controlBus.host._configured && controlBus.cfg.SyncAdvanceEnabled
        repeat: true
        onTriggered: controlBus.pollSync()
    }
}
