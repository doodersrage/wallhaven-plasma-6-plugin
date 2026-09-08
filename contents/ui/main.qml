import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Window
import QtQuick.Effects
import QtCore
import QtNetwork
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.notification
import org.kde.plasma.workspace.dbus as PDBus
import "../code/wallhaven.js" as Wallhaven

WallpaperItem {
    id: root

    readonly property var cfg: root.configuration
    readonly property string diskCacheNamespace: {
        var screen = "";
        try {
            screen = String(Screen.name || "");
        } catch (e) {
            screen = "";
        }
        var ns = Wallhaven.sanitizeCacheNamespace(screen);
        if (ns) {
            return ns;
        }
        ns = Wallhaven.sanitizeCacheNamespace(cfg && cfg.CacheNamespace);
        return ns || "default";
    }
    readonly property string previewCacheFile: StandardPaths.writableLocation(StandardPaths.CacheLocation)
        + "/wallhaven-preview-" + diskCacheNamespace + ".png"
    readonly property string diskCacheDir: {
        var p = String(StandardPaths.writableLocation(StandardPaths.CacheLocation) || "");
        // Some Qt/Plasma builds return a file:// URL from StandardPaths.
        if (p.indexOf("file://") === 0)
            p = p.substring(7);
        if (p.indexOf("localhost/") === 0)
            p = p.substring(9);
        try {
            return decodeURIComponent(p);
        } catch (e) {
            return p;
        }
    }
    readonly property string controlBusFile: diskCacheDir + "/wallhaven-control.json"
    readonly property string varietyMetadataFile: diskCacheDir + "/wallhaven-variety.json"
    readonly property string settingsExportFile: diskCacheDir + "/wallhaven-settings-export.json"
    readonly property string statusBusFile: diskCacheDir + "/wallhaven-status.json"
    readonly property string historyBusFile: diskCacheDir + "/wallhaven-history.json"
    readonly property string dbusConfigFile: diskCacheDir + "/wallhaven-dbus-config.json"
    readonly property string panelTintFile: diskCacheDir + "/wallhaven-panel-tint.json"
    readonly property string rateLimitBusFile: diskCacheDir + "/wallhaven-ratelimit.json"
    readonly property string debugLogFile: diskCacheDir + "/wallhaven-debug.log"
    readonly property int diskCacheEntryCount: Wallhaven.listCachedIds(_diskCacheIndex).length
    readonly property int seenIdsCount: {
        try {
            return Wallhaven.parseSeenIds(cfg && cfg.SeenIdsJson ? cfg.SeenIdsJson : "[]").length;
        } catch (e) {
            return 0;
        }
    }

    function syncAdvanceFile() {
        var group = (cfg.SyncAdvanceGroup || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
        return diskCacheDir + "/wallhaven-sync-" + group + ".json";
    }

    function effectiveOfflineOnly() {
        return cfg.OfflineOnlyMode
            || root._apiOutageOffline
            || root.isRateLimitedNow()
            || Wallhaven.tripModeActive(cfg.TripModeUntilMs)
            || cfg.BrowseMode === "playlist"
            || cfg.BrowseMode === "local"
            || (cfg.MeteredCacheOnly && root.meteredConnection);
    }

    function isRateLimitedNow() {
        return root._rateLimitUntilMs > 0 && Date.now() < root._rateLimitUntilMs;
    }

    function effectsMotionAllowed() {
        return !cfg.ReducedMotion;
    }

    function slideshowActive() {
        return Wallhaven.baseIntervalMinutes(cfg, Wallhaven.isDayPeriod()) > 0;
    }

    function diskCacheMaxSlots() {
        return Math.max(5, Math.min(200, cfg.DiskCacheMaxSlots || 40));
    }

    // Decode near display size (slightly larger when Ken Burns pans/zooms) to cut RAM/VRAM.
    readonly property size wallpaperSourceSize: {
        var w = Math.max(640, Math.round(width) || 1920);
        var h = Math.max(360, Math.round(height) || 1080);
        if (cfg.KenBurnsEnabled && root.effectsMotionAllowed()) {
            w = Math.round(w * 1.25);
            h = Math.round(h * 1.25);
        }
        if (cfg.ParallaxEnabled && root.effectsMotionAllowed()) {
            var extra = Wallhaven.parallaxScaleForStrength(true, cfg.ParallaxStrength);
            w = Math.round(w * extra);
            h = Math.round(h * extra);
        }
        var maxEdge = 3840;
        var edge = Math.max(w, h);
        if (edge > maxEdge) {
            var scale = maxEdge / edge;
            w = Math.round(w * scale);
            h = Math.round(h * scale);
        }
        return Qt.size(w, h);
    }

    readonly property string systemAccentHex: {
        var c = Kirigami.Theme.highlightColor;
        function channel(value) {
            var hex = Math.max(0, Math.min(255, Math.round(value * 255))).toString(16);
            return hex.length === 1 ? "0" + hex : hex;
        }
        return channel(c.r) + channel(c.g) + channel(c.b);
    }

    onSystemAccentHexChanged: {
        if (root._configured && cfg.ColorFilter === "system") {
            engine.resetSlideshow();
        }
    }

    property string currentUrl: ""
    property string statusMessage: ""
    property string statusType: "info"
    property bool statusVisible: false
    property string attributionText: ""
    property bool activeIsForeground: false
    property var currentWallpaper: null

    property bool _configured: false
    property bool _previewCapturePending: false
    property string _timeOfDayPeriod: currentTimeOfDayPeriod()
    property int _lastScreenWidth: 0
    property int _lastScreenHeight: 0
    property int _imageErrorCount: 0
    property string _pendingImageUrl: ""
    property string _pendingRemoteUrl: ""
    property string _pendingWallpaperId: ""
    property bool _pendingUsedCache: false
    property bool _configWritePending: false
    property var _diskCacheIndex: ({ ids: [], next: 0, categories: {}, purities: {}, dimensions: {}, tags: {} })
    property var _diskCacheSaveRequest: null
    property int _fetchRetryCount: 0
    // Resume the same API callback after backoff — never skipForward on retry
    // (that was burning through cache on 429 storms).
    property var _retryOnDone: null
    property var _retryRequestId: 0
    property int _cacheErrorSkipCount: 0
    // Hard cooldown that survives attribution/detail 200s clearing soft-offline.
    // Search /api/v1 must not run until this timestamp.
    property double _rateLimitUntilMs: 0
    property bool _connectivityOnline: true
    property bool _needsReconnectFetch: false
    property double _resumeWatchLastMs: 0
    property double _lastBlankRecoverMs: 0
    property double _lastCacheAdvanceMs: 0
    property double _imageLoadStartedMs: 0
    property double _fadeBlackStartedMs: 0
    property bool _pendingSyncAdvance: false
    property double _pendingSyncAdvanceAt: 0
    property var _pendingControlCmd: null
    property double _outageProbeAtMs: 0
    property int _outageProbeFailCount: 0
    property bool _awaitingTransitionReady: false
    property string _awaitingTransitionMode: ""
    property bool _wasScreenLocked: false
    property string _currentTags: ""
    property int _offlineCacheCursor: -1
    property string _dedupeFingerprint: ""
    property var _localImagePaths: []
    property int _localCursor: -1
    property string lockScreenLastSyncAt: ""
    property string lockScreenLastSyncPath: ""
    property bool lockScreenLastSyncOk: false
    property int _lockSyncSeq: 0
    property var _lockSyncRetry: null
    property string _pendingFadeUrl: ""
    property double _lastControlTs: 0
    property double _lastSyncAdvanceTs: 0
    property string _instanceId: Math.random().toString(36).slice(2, 10)
    property string wallpaperDetailsText: ""
    property string wallpaperDetailsResolution: ""
    property string wallpaperDetailsPurity: ""
    property string wallpaperDetailsCategory: ""
    property bool wallpaperDetailsOpen: false
    property int _apiLastStatus: 0
    property string _apiLastError: ""
    property int _apiRateLimitCount: 0
    property string _apiLastRateLimitAt: ""
    property string _apiLastSuccessAt: ""
    // Temporary soft-offline while Wallhaven is unreachable; clears on API recovery.
    property bool _apiOutageOffline: false
    property string _walletStatus: "unknown"
    property bool _walletLoadAttempted: false
    readonly property var apiHealth: Wallhaven.buildApiHealthSnapshot({
        lastStatus: _apiLastStatus,
        lastError: _apiLastError,
        rateLimitCount: _apiRateLimitCount,
        lastRateLimitAt: _apiLastRateLimitAt,
        lastSuccessAt: _apiLastSuccessAt,
        outageOffline: root._apiOutageOffline,
        apiKey: cfg ? cfg.ApiKey : "",
        walletStatus: root._walletStatus,
    })
    readonly property string apiHealthSummary: {
        if (root._apiOutageOffline) {
            return i18n("API down — using cache (%1)", diskCacheEntryCount);
        }
        if (_apiLastStatus === 401 || _apiLastStatus === 403) {
            var tail = Wallhaven.apiKeyLastFour(cfg && cfg.ApiKey);
            return tail
                ? i18n("Invalid API key (…%1) — clear or re-enter", tail)
                : i18n("API unauthorized (401/403) — check or clear API key");
        }
        if (_apiRateLimitCount > 0 && _apiLastStatus === 429) {
            return i18n("Rate limited (429) — %1 time(s)", _apiRateLimitCount);
        }
        if (_apiLastStatus >= 400) {
            return i18n("Last API error: HTTP %1", _apiLastStatus);
        }
        if (_apiLastSuccessAt) {
            var keyTail = Wallhaven.apiKeyLastFour(cfg && cfg.ApiKey);
            return keyTail ? i18n("API OK (key …%1)", keyTail) : i18n("API OK");
        }
        return i18n("API idle");
    }
    readonly property string apiKeyDisplayHint: {
        var tail = Wallhaven.apiKeyLastFour(cfg && cfg.ApiKey);
        if (tail) {
            return i18n("Key set (…%1)", tail);
        }
        if (root._walletStatus === "loaded") {
            return i18n("Key loaded from KWallet");
        }
        if (root._walletStatus === "missing") {
            return i18n("KWallet: no key stored");
        }
        if (root._walletStatus === "failed") {
            return i18n("KWallet: load failed");
        }
        if (root._walletStatus === "disabled") {
            return i18n("KWallet disabled");
        }
        return i18n("No API key");
    }
    readonly property bool tripModeActive: Wallhaven.tripModeActive(cfg && cfg.TripModeUntilMs)
    property bool _warmActive: false
    property int _warmDone: 0
    property int _warmTarget: 0
    property bool _warmCancelRequested: false
    property string monitorTrustMapText: ""
    property double _nextSlideshowAt: 0
    property var _metrics: Wallhaven.createMetricsState()
    property int _batteryPercent: 100
    property bool _rulesPausedSlideshow: false
    property bool _pausedByRules: false
    property bool _musicPlaying: false
    property string _weatherLastLocation: ""
    // Public so config.qml can bind (function getters do not re-evaluate).
    property bool dbusServiceAvailable: false
    property string upscalerBinaryPath: ""
    property bool upscalerStatusKnown: false
    readonly property bool upscalerAvailable: upscalerStatusKnown && upscalerBinaryPath !== ""
    property var wallpaperHistoryEntries: []
    property bool _screenLocked: false
    property bool _sessionIdle: false

    property real parallaxPhase: 0
    readonly property real parallaxScreenPhase: {
        var virtualX = 0;
        try {
            virtualX = Screen.virtualX || 0;
        } catch (e) {
            virtualX = 0;
        }
        return Wallhaven.parallaxScreenPhase(virtualX);
    }
    readonly property real parallaxScale: Wallhaven.parallaxScaleForStrength(
        cfg.ParallaxEnabled && root.effectsMotionAllowed(), cfg.ParallaxStrength)
    readonly property real parallaxOffsetX: Wallhaven.parallaxOffsetX(
        cfg.ParallaxEnabled && root.effectsMotionAllowed(), cfg.ParallaxStrength, root.width, parallaxPhase, parallaxScreenPhase)
    readonly property real parallaxOffsetY: Wallhaven.parallaxOffsetY(
        cfg.ParallaxEnabled && root.effectsMotionAllowed(), cfg.ParallaxStrength, root.height, parallaxPhase, parallaxScreenPhase)

    readonly property bool meteredConnection: cfg.MeteredCacheOnly
        && NetworkInformation.transportMedium === NetworkInformation.Cellular

    function currentTimeOfDayPeriod() {
        var hour = new Date().getHours();
        return (hour >= 6 && hour < 20) ? "day" : "night";
    }

    function checkScreenResize() {
        if (!root._configured || cfg.MinWidth || cfg.MinHeight) {
            return;
        }
        var w = Math.round(root.width);
        var h = Math.round(root.height);
        if (root._lastScreenWidth === 0) {
            root._lastScreenWidth = w;
            root._lastScreenHeight = h;
            return;
        }
        if (Math.abs(w - root._lastScreenWidth) > 80 || Math.abs(h - root._lastScreenHeight) > 80) {
            root._lastScreenWidth = w;
            root._lastScreenHeight = h;
            engine.resetSlideshow();
        }
    }

    onWidthChanged: checkScreenResize()
    onHeightChanged: checkScreenResize()

    contextualActions: [
        reloadAction, nextAction, previousAction, pauseResumeAction, similarAction,
        wallpaperInfoAction, copyIdAction, copyTagsAction, copyUrlAction, favoriteAction,
        blockWallpaperAction, openInBrowserAction, saveWallpaperAction,
    ]

    PlasmaCore.Action {
        id: reloadAction
        text: i18n("Reload Wallpaper")
        icon.name: "view-refresh"
        onTriggered: root.reloadWallpaper()
    }

    PlasmaCore.Action {
        id: nextAction
        text: i18n("Next Wallpaper")
        icon.name: "go-next"
        onTriggered: root.advanceWallpaper()
    }

    PlasmaCore.Action {
        id: previousAction
        text: i18n("Previous Wallpaper")
        icon.name: "go-previous"
        onTriggered: engine.previousWallpaper()
    }

    PlasmaCore.Action {
        id: pauseResumeAction
        text: cfg.SlideshowPaused ? i18n("Resume Slideshow") : i18n("Pause Slideshow")
        icon.name: cfg.SlideshowPaused ? "media-playback-start" : "media-playback-pause"
        enabled: root.slideshowActive()
        onTriggered: root.toggleSlideshowPause()
    }

    PlasmaCore.Action {
        id: similarAction
        text: i18n("Similar Wallpapers")
        icon.name: "view-list-icons"
        enabled: root.currentWallpaperId !== "" && root.currentWallpaperId !== "wallpaper"
        onTriggered: root.loadSimilarWallpapers()
    }

    PlasmaCore.Action {
        id: wallpaperInfoAction
        text: i18n("Wallpaper Info")
        icon.name: "help-about"
        enabled: root.wallpaperDetailsText !== "" || (root.currentWallpaperId !== "" && root.currentWallpaperId !== "wallpaper")
        onTriggered: root.showWallpaperInfo()
    }

    PlasmaCore.Action {
        id: copyIdAction
        text: i18n("Copy Wallpaper ID")
        icon.name: "edit-copy"
        enabled: root.currentWallpaperId !== "" && root.currentWallpaperId !== "wallpaper"
        onTriggered: root.copyWallpaperId()
    }

    PlasmaCore.Action {
        id: copyTagsAction
        text: i18n("Copy Tags")
        icon.name: "tag"
        enabled: root._currentTags !== ""
        onTriggered: root.copyCurrentTags()
    }

    PlasmaCore.Action {
        id: copyUrlAction
        text: i18n("Copy Page URL")
        icon.name: "edit-copy"
        enabled: root.currentPageUrl !== ""
        onTriggered: root.copyPageUrl()
    }

    PlasmaCore.Action {
        id: favoriteAction
        text: i18n("Favorite on Wallhaven…")
        icon.name: "bookmark-new"
        enabled: root.currentPageUrl !== ""
        onTriggered: root.favoriteOnWallhaven()
    }

    PlasmaCore.Action {
        id: blockWallpaperAction
        text: i18n("Block This Wallpaper")
        icon.name: "dialog-cancel"
        enabled: root.currentWallpaperId !== "" && root.currentWallpaperId !== "wallpaper"
        onTriggered: root.blockCurrentWallpaper()
    }

    PlasmaCore.Action {
        id: openInBrowserAction
        text: i18n("Open in Browser")
        icon.name: "internet-web-browser"
        enabled: root.currentPageUrl !== ""
        onTriggered: Qt.openUrlExternally(root.currentPageUrl)
    }

    PlasmaCore.Action {
        id: saveWallpaperAction
        text: i18n("Save Wallpaper…")
        icon.name: "document-save"
        enabled: root.currentSaveUrl !== ""
        onTriggered: root.openSaveWallpaperDialog()
    }

    readonly property string currentPageUrl: {
        if (currentWallpaper && currentWallpaper.url) {
            return currentWallpaper.url;
        }
        if (currentWallpaper && currentWallpaper.id) {
            return "https://wallhaven.cc/w/" + currentWallpaper.id;
        }
        if (configuration && configuration.PreviewWallpaperId) {
            return "https://wallhaven.cc/w/" + configuration.PreviewWallpaperId;
        }
        return "";
    }

    readonly property string currentSaveUrl: {
        if (currentWallpaper && currentWallpaper.path) {
            return currentWallpaper.path;
        }
        if (currentUrl) {
            return currentUrl.split("?")[0];
        }
        return "";
    }

    readonly property string currentWallpaperId: {
        if (currentWallpaper && currentWallpaper.id) {
            return String(currentWallpaper.id);
        }
        if (configuration && configuration.PreviewWallpaperId) {
            return String(configuration.PreviewWallpaperId);
        }
        return "wallpaper";
    }

    function urlToLocalPath(url) {
        var path = String(url == null ? "" : url);
        if (!path)
            return "";
        if (path.indexOf("file://") === 0) {
            path = path.substring(7);
            // file://localhost/home/... or leftover host form
            if (path.indexOf("localhost/") === 0)
                path = path.substring(9);
        } else if (path.indexOf("file:") === 0) {
            path = path.substring(5);
        }
        try {
            return decodeURIComponent(path);
        } catch (e) {
            return path;
        }
    }

    function localPathToUrl(path) {
        path = String(path || "");
        if (!path) {
            return "";
        }
        if (path.indexOf("file://") === 0) {
            return path;
        }
        return "file://" + path;
    }

    function scheduleConfigWrite() {
        _configWritePending = true;
        configWriteTimer.restart();
    }

    function flushConfigWrite() {
        if (!_configWritePending || !root.configuration || !root.configuration.writeConfig) {
            _configWritePending = false;
            return;
        }
        _configWritePending = false;
        root.configuration.writeConfig();
    }

    function loadDiskCacheIndex() {
        if (!root.configuration) {
            _diskCacheIndex = { ids: [], next: 0, categories: {}, purities: {}, dimensions: {} };
            return;
        }
        _diskCacheIndex = Wallhaven.parseDiskCacheIndex(root.configuration.DiskCacheIndexJson || "");
    }

    function ensureCacheNamespace() {
        if (!root.configuration) {
            return;
        }
        if (!Wallhaven.sanitizeCacheNamespace(cfg.CacheNamespace)) {
            var ns = diskCacheNamespace;
            if (!ns || ns === "default") {
                ns = "m" + Math.random().toString(36).slice(2, 10);
            }
            root.configuration.CacheNamespace = ns;
            scheduleConfigWrite();
        }
        // Isolate multi-monitor control by default. A shared SyncAdvanceGroup of
        // "default" made search/purity from the plasmoid/CLI overwrite every screen.
        ensureSyncGroupIsolated();
    }

    function ensureSyncGroupIsolated() {
        if (!root.configuration) {
            return;
        }
        var group = String(cfg.SyncAdvanceGroup || "").trim();
        var screen = diskCacheNamespace;
        if (!screen || screen === "default") {
            return;
        }
        // When sync-advance is off, each screen must listen on its own name.
        // Crossed groups (DP-2 ↔ HDMI-A-2) made control-bus searches aimed at one
        // monitor reset the other and stampede the shared API key.
        if (!cfg.SyncAdvanceEnabled && group && group !== "default" && group !== screen) {
            root.configuration.SyncAdvanceGroup = screen;
            scheduleConfigWrite();
            logDebug("SyncAdvanceGroup uncrossed to screen " + screen);
            return;
        }
        if (!group || group === "default") {
            root.configuration.SyncAdvanceGroup = screen;
            // Keep sync-advance off unless the user already enabled it — isolation
            // only changes which control-bus group this screen listens on.
            scheduleConfigWrite();
            logDebug("SyncAdvanceGroup set to screen " + screen);
        }
    }

    function controlCommandTargetsThisScreen(cmd) {
        if (!cmd) {
            return false;
        }
        return Wallhaven.controlCommandTargetsGroup(
            cmd.group,
            cfg.SyncAdvanceGroup || "default",
            diskCacheNamespace || "",
            cmd.cmd,
        );
    }

    function isSettingsControlCommand(cmdName) {
        var name = String(cmdName || "");
        return name === "search" || name === "applysearch" || name === "savesearch"
            || name === "purity" || name === "trip" || name === "endtrip"
            || name === "clearkey" || name === "testkey" || name === "warm"
            || name === "cancelwarm" || name === "copysearch"
            || name === "importpreset";
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
                root._pendingControlCmd = { cmd: cmd.cmd, ts: cmd.ts || Date.now() };
                return;
            }
            root._pendingControlCmd = null;
            if (cmd.cmd === "next") {
                engine.skipForward(false);
            } else if (cmd.cmd === "prev") {
                engine.previousWallpaper();
            } else {
                root.reloadWallpaper();
            }
            break;
        case "pause":
            root.setSlideshowPaused(true);
            break;
        case "resume":
            root.setSlideshowPaused(false);
            break;
        case "search":
            if (cmd.query && root.configuration) {
                root.snapshotSettingsForUndo();
                root.configuration.BrowseMode = "search";
                root.configuration.SearchText = cmd.query;
                root.configuration.WallpaperOfDayEnabled = false;
                root.recordSearchHistory(cmd.query);
                scheduleConfigWrite();
                engine.resetSlideshow();
            }
            break;
        case "open":
            if (root.currentPageUrl) {
                Qt.openUrlExternally(root.currentPageUrl);
            }
            break;
        case "block":
            root.blockCurrentWallpaper();
            break;
        case "copytags":
            root.copyCurrentTags();
            break;
        case "similar":
            root.loadSimilarWallpapers();
            break;
        case "info":
            root.showWallpaperInfo();
            break;
        case "importpreset":
            if (cmd.query) {
                root.importPresetFromUrl(cmd.query);
            }
            break;
        case "like":
            root.rateCurrentWallpaper(true);
            break;
        case "dislike":
            root.rateCurrentWallpaper(false);
            break;
        case "history":
            if (cmd.query) {
                root.showHistoryWallpaper(cmd.query);
            }
            break;
        case "pin":
            if (root.currentWallpaperId && root.currentWallpaperId !== "wallpaper") {
                root.pinCacheId(root.currentWallpaperId);
            }
            break;
        case "unpin":
            if (root.currentWallpaperId && root.currentWallpaperId !== "wallpaper") {
                root.unpinCacheId(root.currentWallpaperId);
            }
            break;
        case "outageoffline":
            root.enterApiOutageOffline(0);
            break;
        case "resumeonline":
            // User/ctl intent — clear even if a rate-limit latch is still active.
            root.clearApiOutageOffline(true, true);
            break;
        case "clearkey":
            root.clearApiKey(false);
            break;
        case "testkey":
            root.testApiKeyNow();
            break;
        case "copyid":
            root.copyWallpaperId();
            break;
        case "copyurl":
            root.copyPageUrl();
            break;
        case "prune":
            root.pruneUnpinnedCache();
            break;
        case "warm":
            root.warmDiskCache(cmd.query ? parseInt(cmd.query, 10) : 0);
            break;
        case "cancelwarm":
            root.cancelWarmCache();
            break;
        case "trip":
            root.enterTripModeWithWarm(cmd.query ? parseInt(cmd.query, 10) : 24, cfg.CacheWarmCount || 12);
            break;
        case "endtrip":
            root.clearTripMode(true);
            break;
        case "copysearch":
            root.copySearchToOtherScreens(cmd.query || "");
            break;
        case "undo":
            root.undoLastSettingsChange();
            break;
        case "savesearch":
            root.saveCurrentAsSavedSearch(cmd.query || "");
            break;
        case "applysearch":
            if (cmd.query) {
                root.applySavedSearch(cmd.query);
            }
            break;
        case "purity":
            if (cmd.query) {
                var bits = String(cmd.query).split(",");
                root.setPurityFlags(
                    bits.indexOf("sfw") !== -1 || bits.indexOf("100") !== -1,
                    bits.indexOf("sketchy") !== -1 || bits.indexOf("010") !== -1 || bits.indexOf("110") !== -1,
                    bits.indexOf("nsfw") !== -1 || bits.indexOf("001") !== -1 || bits.indexOf("111") !== -1,
                );
            }
            break;
        default:
            break;
        }
    }

    function persistDiskCacheIndex() {
        if (!root.configuration) {
            return;
        }
        root.configuration.DiskCacheIndexJson = Wallhaven.serializeDiskCacheIndex(_diskCacheIndex);
        scheduleConfigWrite();
    }

    function diskCacheLocalPath(slot) {
        return diskCacheDir + "/" + Wallhaven.diskCacheFileName(slot, diskCacheNamespace);
    }

    function diskCacheLocalUrl(slot) {
        return localPathToUrl(diskCacheLocalPath(slot));
    }

    function resolveImageSource(wallpaper, remoteUrl) {
        if (!remoteUrl) {
            return "";
        }
        if (!cfg.DiskCacheEnabled || !wallpaper || !wallpaper.id) {
            // Soft-offline must never open a network image URL.
            if (root.effectiveOfflineOnly()) {
                return "";
            }
            return remoteUrl;
        }
        var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, wallpaper.id);
        if (slot < 0) {
            if (root.effectiveOfflineOnly()) {
                return "";
            }
            return remoteUrl;
        }
        Wallhaven.touchDiskCacheId(_diskCacheIndex, wallpaper.id);
        return diskCacheLocalUrl(slot);
    }

    function releaseInactiveLayer() {
        // Never wipe the last good frame after a failed/incomplete transition.
        var active = activeWallpaperImage();
        if (!active || active.status !== Image.Ready) {
            return;
        }
        if (activeIsForeground) {
            backgroundImage.source = "";
        } else {
            foregroundImage.source = "";
        }
    }

    // Crossfade/slide/zoom are plain ParallelAnimations: calling .start() while one
    // is already running is a no-op in QtQuick, so a second wallpaper change inside
    // the same CrossfadeMs window used to leave two animations fighting over the
    // same opacity/transform properties, and let the first one's onFinished clear
    // the layer the second transition was still fading in. Stopping any in-flight
    // transition before starting a new one avoids both problems (mirrors the
    // kenBurnsAnimation.stopAll() pattern already used before each restart()).
    function stopTransitionAnimations() {
        crossfadeToForeground.stop();
        crossfadeToBackground.stop();
        slideToForeground.stop();
        slideToBackground.stop();
        zoomToForeground.stop();
        zoomToBackground.stop();
        // Fade-through-black is a SequentialAnimation with a full-screen overlay.
        // Leaving it mid-flight (or stuck at opacity 1) paints a literal black desktop.
        if (fadeBlackOut.running) {
            fadeBlackOut.stop();
        }
        if (fadeBlackOverlay.opacity > 0) {
            fadeBlackOverlay.opacity = 0;
        }
        root._fadeBlackStartedMs = 0;
        root._awaitingTransitionReady = false;
        root._awaitingTransitionMode = "";
        if (typeof transitionReadyTimer !== "undefined") {
            transitionReadyTimer.stop();
        }
    }

    function clearWallpaperImageSources() {
        backgroundImage.source = "";
        foregroundImage.source = "";
    }

    // Snap layers so an interrupted crossfade/slide/zoom cannot leave both near 0.
    function resetWallpaperLayerVisibility() {
        if (fadeBlackOverlay.opacity > 0) {
            fadeBlackOverlay.opacity = 0;
        }
        backgroundLayer.opacity = 1;
        foregroundLayer.opacity = 0;
        activeIsForeground = false;
        backgroundTransform.slideX = 0;
        foregroundTransform.slideX = 0;
        backgroundTransform.zoomScale = 1;
        foregroundTransform.zoomScale = 1;
    }

    function scheduleDiskCacheSave(img) {
        if (!cfg.DiskCacheEnabled || !img || _pendingUsedCache || !_pendingWallpaperId) {
            return;
        }
        if (String(img.source) !== String(_pendingImageUrl)) {
            return;
        }
        _diskCacheSaveRequest = {
            id: _pendingWallpaperId,
            remoteUrl: _pendingRemoteUrl,
            image: img,
        };
        diskCacheSaveTimer.restart();
    }

    function writeDiskCacheFromImage() {
        var req = _diskCacheSaveRequest;
        _diskCacheSaveRequest = null;
        if (!req || !req.image || !req.id || !cfg.DiskCacheEnabled) {
            return;
        }
        if (req.image.status !== Image.Ready) {
            return;
        }
        var slot = Wallhaven.allocateDiskCacheSlot(
            _diskCacheIndex,
            req.id,
            diskCacheMaxSlots(),
            pinnedCacheIds(),
            root.currentWallpaper && root.currentWallpaper.category
                ? root.currentWallpaper.category : "",
            root.currentWallpaper && root.currentWallpaper.purity
                ? root.currentWallpaper.purity : "",
        );
        if (slot < 0) {
            return;
        }
        var path = diskCacheLocalPath(slot);
        var size = wallpaperSourceSize;
        var wallpaperForUpscale = root.currentWallpaper;
        Wallhaven.setDiskCacheDimensions(
            _diskCacheIndex,
            req.id,
            wallpaperForUpscale && wallpaperForUpscale.dimension_x,
            wallpaperForUpscale && wallpaperForUpscale.dimension_y,
        );
        Wallhaven.setDiskCacheTags(_diskCacheIndex, req.id, root._currentTags);
        var originalUrl = String(req.remoteUrl || "");
        if (cfg.CacheDownloadOriginal && originalUrl.indexOf("http") === 0) {
            dbusHelper.runArgv([
                "curl", "-fsSL", "--max-time", "120", "-o", path, originalUrl,
            ], function(reply) {
                var text = String(reply || "").trim();
                if (text !== "ok") {
                    logDebug("Original cache curl failed for " + req.id + " reply=" + text);
                    Wallhaven.releaseDiskCacheId(_diskCacheIndex, req.id);
                    persistDiskCacheIndex();
                    return;
                }
                dbusHelper.runArgv(["test", "-s", path], function(sizeReply) {
                    var sizeOk = String(sizeReply || "").trim();
                    if (sizeOk !== "ok") {
                        logDebug("Original cache empty after curl for " + req.id);
                        Wallhaven.releaseDiskCacheId(_diskCacheIndex, req.id);
                        persistDiskCacheIndex();
                        return;
                    }
                    persistDiskCacheIndex();
                    if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                        root.syncLockScreenImage(path, req.id);
                        root.updateVarietySymlink(path);
                    }
                    root.maybeUpscaleCachedFile(path, wallpaperForUpscale);
                });
            });
            return;
        }
        req.image.grabToImage(function(result) {
            if (!result) {
                return;
            }
            // Wallpaper may have advanced while grabToImage was pending.
            if (String(root._pendingWallpaperId || "") !== String(req.id)) {
                return;
            }
            if (result.saveToFile(path)) {
                persistDiskCacheIndex();
                if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                    root.syncLockScreenImage(path, req.id);
                    root.updateVarietySymlink(path);
                }
                root.maybeUpscaleCachedFile(path, wallpaperForUpscale);
            }
        }, size);
    }

    // If enabled and this wallpaper's native resolution genuinely falls short
    // of the screen, hand the just-written disk-cache file to an installed
    // external upscaler (e.g. realesrgan-ncnn-vulkan) and overwrite it in
    // place with the upscaled result. Silently does nothing when the setting
    // is off, the wallpaper doesn't need it, or no upscaler is installed --
    // the cached file is left exactly as plain-scaling would have shown it.
    function maybeUpscaleCachedFile(path, wallpaper) {
        if (!cfg.UpscaleEnabled || !path || !wallpaper) {
            return;
        }
        var screenWidth = Math.round(root.width) || 1920;
        var screenHeight = Math.round(root.height) || 1080;
        if (!Wallhaven.needsUpscale(wallpaper, screenWidth, screenHeight)) {
            return;
        }
        dbusHelper.checkUpscalerAvailable(function(binaryPath) {
            if (!binaryPath) {
                return;
            }
            dbusHelper.upscale(path, path, function(ok) {
                root.logDebug((ok ? "Upscaled" : "Upscale failed for") + " disk-cache image: " + path);
            });
        });
    }

    // Retroactively applies the external upscaler to wallpapers already
    // sitting in the disk cache from before "Upscale low-res" was turned on
    // (or from before this dimension-tracking existed at all -- those are
    // silently skipped since there's no recorded native resolution to judge
    // by). Runs the upscale calls one at a time rather than in parallel: each
    // is a real GPU-bound external process, and firing dozens at once would
    // just make them all compete for the same GPU with no net time saved.
    function reupscaleCachedWallpapers() {
        if (!cfg.UpscaleEnabled) {
            engine.showStatus(i18n("Enable \"Upscale low-res\" first."), "warn");
            return;
        }
        dbusHelper.checkUpscalerAvailable(function(binaryPath) {
            if (!binaryPath) {
                engine.showStatus(i18n("No upscaler installed (realesrgan-ncnn-vulkan not found on PATH)."), "warn");
                return;
            }
            var entries = getCacheEntries();
            var screenWidth = Math.round(root.width) || 1920;
            var screenHeight = Math.round(root.height) || 1080;
            var queue = [];
            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i];
                if (!entry.dimensionX || !entry.dimensionY) {
                    continue;
                }
                var wallpaper = { dimension_x: entry.dimensionX, dimension_y: entry.dimensionY };
                if (Wallhaven.needsUpscale(wallpaper, screenWidth, screenHeight)) {
                    queue.push(diskCacheLocalPath(entry.slot));
                }
            }
            if (!queue.length) {
                engine.showStatus(i18n("No cached wallpapers need upscaling right now."), "info");
                return;
            }
            var total = queue.length;
            var upscaled = 0;
            var failed = 0;
            var runNext = function() {
                if (!queue.length) {
                    engine.showStatus(i18n("Re-upscale finished: %1 upscaled, %2 failed.", upscaled, failed), "info");
                    return;
                }
                var path = queue.shift();
                dbusHelper.upscale(path, path, function(ok) {
                    if (ok) {
                        upscaled++;
                    } else {
                        failed++;
                    }
                    runNext();
                });
            };
            engine.showStatus(i18n("Re-upscaling %1 cached wallpaper(s)…", total), "info");
            runNext();
        });
    }

    function clearDiskCache() {
        var slots = diskCacheMaxSlots();
        var paths = [];
        for (var i = 0; i < slots; i++) {
            paths.push(diskCacheLocalPath(i));
        }
        cacheFileDeleter.deletePaths(paths);
        _diskCacheIndex = { ids: [], next: 0, categories: {}, purities: {}, dimensions: {} };
        persistDiskCacheIndex();
        preloadImage.source = "";
        preloadImage2.source = "";
        engine.nextPreloadedUrl = "";
        engine.showStatus(i18n("Disk cache cleared."), "info");
    }

    function pruneUnpinnedCache(keepSlots) {
        var maxKeep = keepSlots !== undefined && keepSlots !== null
            ? keepSlots
            : diskCacheMaxSlots();
        var pinned = Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson);
        var victims = Wallhaven.listUnpinnedCacheIdsOldestFirst(_diskCacheIndex, pinned);
        var occupied = Wallhaven.listCachedIds(_diskCacheIndex).length;
        var paths = [];
        var removed = 0;
        for (var i = 0; i < victims.length && occupied - removed > maxKeep; i++) {
            var id = victims[i];
            var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, id);
            if (slot < 0) {
                continue;
            }
            paths.push(diskCacheLocalPath(slot));
            Wallhaven.evictDiskCacheOccupant(_diskCacheIndex, id);
            _diskCacheIndex.ids[slot] = "";
            removed++;
        }
        if (!removed) {
            engine.showStatus(i18n("No unpinned cache entries to prune."), "info");
            return 0;
        }
        cacheFileDeleter.deletePaths(paths);
        persistDiskCacheIndex();
        engine.showStatus(i18n("Pruned %1 unpinned cache entr(y/ies).", removed), "info");
        publishStatus();
        return removed;
    }

    function enforceCacheQuota(sizeMap) {
        var pinned = Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson);
        var removedSlots = Wallhaven.pruneUnpinnedCacheIds(
            _diskCacheIndex,
            pinned,
            diskCacheMaxSlots(),
        );
        var maxMb = Math.max(0, parseInt(cfg.DiskCacheMaxMb, 10) || 0);
        var removedBytes = [];
        if (maxMb > 0 && sizeMap) {
            removedBytes = Wallhaven.pruneCacheToMaxBytes(
                _diskCacheIndex,
                pinned,
                sizeMap,
                maxMb * 1024 * 1024,
            );
        }
        var removed = removedSlots.concat(removedBytes);
        if (!removed.length) {
            return 0;
        }
        var paths = [];
        var slots = diskCacheMaxSlots();
        for (var s = 0; s < slots; s++) {
            if (!String(_diskCacheIndex.ids[s] || "")) {
                paths.push(diskCacheLocalPath(s));
            }
        }
        cacheFileDeleter.deletePaths(paths);
        persistDiskCacheIndex();
        publishStatus();
        return removed.length;
    }

    function refreshCacheFileSizes(callback) {
        var ids = Wallhaven.listCachedIds(_diskCacheIndex);
        var sizeMap = {};
        var pending = ids.length;
        if (!pending) {
            if (callback)
                callback(sizeMap);
            return;
        }
        function doneOne() {
            pending--;
            if (pending <= 0 && callback) {
                callback(sizeMap);
            }
        }
        for (var i = 0; i < ids.length; i++) {
            (function(id) {
                var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, id);
                if (slot < 0) {
                    doneOne();
                    return;
                }
                var path = diskCacheLocalPath(slot);
                dbusHelper.runArgv(["stat", "-c", "%s", path], function(reply) {
                    var text = Wallhaven.dbusReplyAsString(reply).trim();
                    sizeMap[id] = parseInt(text, 10) || 0;
                    doneOne();
                });
            })(ids[i]);
        }
    }

    function warmDiskCache(count) {
        count = Math.max(1, Math.min(48, parseInt(count, 10) || cfg.CacheWarmCount || 12));
        if (cfg.OfflineOnlyMode || cfg.BrowseMode === "playlist" || cfg.BrowseMode === "local") {
            engine.showStatus(i18n("Switch to an online browse mode to warm the cache."), "warn");
            return;
        }
        if ((root.isRateLimitedNow() || root._apiOutageOffline) && !root.tripModeActive) {
            engine.showStatus(i18n("Cannot warm cache while Wallhaven is unreachable or rate-limited."), "warn");
            return;
        }
        if (root._warmActive) {
            engine.showStatus(i18n("Cache warm already in progress (%1 / %2).", root._warmDone, root._warmTarget), "info");
            return;
        }
        engine.showStatus(i18n("Warming cache with up to %1 wallpaper(s)…", count), "info");
        engine.warmCache(count);
    }

    function cancelWarmCache() {
        if (!root._warmActive) {
            engine.showStatus(i18n("No cache warm in progress."), "info");
            return;
        }
        root._warmCancelRequested = true;
        engine.showStatus(i18n("Cancelling cache warm…"), "info");
        publishStatus();
    }

    function copySearchToOtherScreens(overrideQuery) {
        var query = String(overrideQuery || cfg.SearchText || "").trim();
        if (!query) {
            engine.showStatus(i18n("No search text to copy."), "warn");
            return;
        }
        var myGroup = String(cfg.SyncAdvanceGroup || diskCacheNamespace || "default");
        dbusHelper.wallhavenMessage("ListMonitorStatuses", "", [], function(reply) {
            var list = [];
            try {
                list = JSON.parse(Wallhaven.dbusReplyAsString(reply) || "[]");
            } catch (e) {
                list = [];
            }
            if (!Array.isArray(list)) {
                list = [];
            }
            var targets = Wallhaven.otherMonitorSyncGroups(list, myGroup);
            if (!targets.length) {
                engine.showStatus(i18n("No other monitors to copy search to."), "info");
                return;
            }
            for (var i = 0; i < targets.length; i++) {
                dbusHelper.wallhavenMessage("Search", "ss", [query, targets[i]]);
            }
            engine.showStatus(i18n("Copied search to %1 other screen(s).", targets.length), "info");
            root.refreshMonitorTrustMap();
        });
    }

    function refreshMonitorTrustMap() {
        dbusHelper.wallhavenMessage("ListMonitorStatuses", "", [], function(reply) {
            var list = [];
            try {
                list = JSON.parse(Wallhaven.dbusReplyAsString(reply) || "[]");
            } catch (e) {
                list = [];
            }
            if (!Array.isArray(list)) {
                list = [];
            }
            var lines = Wallhaven.formatMonitorTrustLines(list);
            root.monitorTrustMapText = lines || i18n("(no monitors reporting)");
        });
    }

    function recordSearchHistory(query) {
        if (!root.configuration) {
            return;
        }
        var next = Wallhaven.pushSearchHistory(cfg.SearchHistoryJson, query, 10);
        root.configuration.SearchHistoryJson = Wallhaven.serializeSearchHistory(next);
        scheduleConfigWrite();
        publishStatus();
    }

    function saveCurrentAsSavedSearch(name) {
        if (!root.configuration) {
            return;
        }
        var entry = {
            name: String(name || cfg.SearchText || "").trim(),
            query: String(cfg.SearchText || "").trim(),
            PuritySfw: !!cfg.PuritySfw,
            PuritySketchy: !!cfg.PuritySketchy,
            PurityNsfw: !!cfg.PurityNsfw,
        };
        var list = Wallhaven.upsertSavedSearch(
            Wallhaven.parseSavedSearches(cfg.SavedSearchesJson),
            entry,
            20,
        );
        root.configuration.SavedSearchesJson = Wallhaven.serializeSavedSearches(list);
        scheduleConfigWrite();
        engine.showStatus(i18n("Saved search “%1”.", entry.name), "info");
        publishStatus();
    }

    function applySavedSearch(nameOrQuery) {
        if (!root.configuration) {
            return;
        }
        var item = Wallhaven.findSavedSearch(
            Wallhaven.parseSavedSearches(cfg.SavedSearchesJson),
            nameOrQuery,
        );
        if (!item) {
            engine.showStatus(i18n("Saved search not found."), "warn");
            return;
        }
        snapshotSettingsForUndo();
        root.configuration.BrowseMode = "search";
        root.configuration.SearchText = item.query;
        root.configuration.PuritySfw = item.PuritySfw !== false;
        root.configuration.PuritySketchy = item.PuritySketchy !== false;
        root.configuration.PurityNsfw = !!item.PurityNsfw;
        root.configuration.WallpaperOfDayEnabled = false;
        recordSearchHistory(item.query);
        scheduleConfigWrite();
        engine.resetSlideshow();
        engine.showStatus(i18n("Applied saved search “%1”.", item.name), "info");
    }

    function setPurityFlags(sfw, sketchy, nsfw) {
        if (!root.configuration) {
            return;
        }
        snapshotSettingsForUndo();
        root.configuration.PuritySfw = !!sfw;
        root.configuration.PuritySketchy = !!sketchy;
        root.configuration.PurityNsfw = !!nsfw && !!Wallhaven.sanitizeApiKey(cfg.ApiKey);
        if (nsfw && !Wallhaven.sanitizeApiKey(cfg.ApiKey)) {
            engine.showStatus(i18n("NSFW needs a valid API key."), "warn");
        }
        scheduleConfigWrite();
        engine.resetSlideshow();
        publishStatus();
    }

    function snapshotSettingsForUndo() {
        if (!root.configuration) {
            return;
        }
        root.configuration.SettingsUndoJson = JSON.stringify(
            Wallhaven.buildSettingsUndoSnapshot(cfg),
        );
        scheduleConfigWrite();
    }

    function undoLastSettingsChange() {
        if (!root.configuration || !cfg.SettingsUndoJson) {
            engine.showStatus(i18n("Nothing to undo."), "warn");
            return;
        }
        try {
            var snap = JSON.parse(cfg.SettingsUndoJson);
            if (!Wallhaven.applySettingsUndoSnapshot(snap, root.configuration)) {
                engine.showStatus(i18n("Nothing to undo."), "warn");
                return;
            }
            root.configuration.SettingsUndoJson = "";
            scheduleConfigWrite();
            engine.resetSlideshow();
            engine.showStatus(i18n("Restored previous settings."), "info");
            publishStatus();
        } catch (e) {
            engine.showStatus(i18n("Could not restore settings."), "error");
        }
    }

    function enterTripMode(hours) {
        if (!root.configuration) {
            return;
        }
        hours = Math.max(1, parseInt(hours, 10) || 24);
        snapshotSettingsForUndo();
        root.configuration.TripModeUntilMs = String(Wallhaven.tripModeUntilMsFromHours(hours));
        root.configuration.OfflineOnlyMode = true;
        scheduleConfigWrite();
        engine.stopRetries();
        engine.showStatus(i18n("Trip mode on for %1 hour(s) — cache only.", hours), "info");
        if (!engine.tryOfflineFallback(i18n("Trip mode: using cached wallpapers."))) {
            // keep banner from showStatus
        }
        publishStatus();
        // Opportunistically warm before fully offline if still online.
        if (!root._apiOutageOffline && cfg.BrowseMode !== "local") {
            // Already flipped OfflineOnlyMode; warm must happen before that for online fetch.
        }
    }

    function enterTripModeWithWarm(hours, warmCount) {
        if (!root.configuration) {
            return;
        }
        hours = Math.max(1, parseInt(hours, 10) || 24);
        warmCount = Math.max(0, parseInt(warmCount, 10) || cfg.CacheWarmCount || 12);
        snapshotSettingsForUndo();
        var finish = function() {
            root.configuration.TripModeUntilMs = String(Wallhaven.tripModeUntilMsFromHours(hours));
            root.configuration.OfflineOnlyMode = true;
            scheduleConfigWrite();
            engine.stopRetries();
            engine.showStatus(i18n("Trip mode on for %1 hour(s).", hours), "info");
            engine.tryOfflineFallback(i18n("Trip mode: using cached wallpapers."));
            publishStatus();
        };
        if (warmCount > 0 && !cfg.OfflineOnlyMode && cfg.BrowseMode !== "playlist" && cfg.BrowseMode !== "local") {
            engine.showStatus(i18n("Warming cache before trip mode…"), "info");
            engine.warmCache(warmCount, finish);
        } else {
            finish();
        }
    }

    function clearTripMode(resumeOnline) {
        if (!root.configuration) {
            return;
        }
        root.configuration.TripModeUntilMs = "0";
        if (resumeOnline) {
            root.configuration.OfflineOnlyMode = false;
        }
        scheduleConfigWrite();
        engine.showStatus(i18n("Trip mode cleared."), "info");
        publishStatus();
        if (resumeOnline) {
            engine.resetSlideshow();
        }
    }

    function copyToClipboard(text, successMessage) {
        if (!text) {
            return;
        }
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        if (successMessage) {
            engine.showStatus(successMessage, "info");
        }
    }

    function copyWallpaperId() {
        var id = currentWallpaperId;
        if (!id || id === "wallpaper") {
            return;
        }
        copyToClipboard(id, i18n("Copied wallpaper ID %1.", id));
    }

    function copyCurrentTags() {
        if (!_currentTags) {
            return;
        }
        copyToClipboard(_currentTags, i18n("Copied tags."));
    }

    function copyPageUrl() {
        if (!currentPageUrl) {
            return;
        }
        copyToClipboard(currentPageUrl, i18n("Copied page URL."));
    }

    function favoriteOnWallhaven() {
        if (!currentPageUrl) {
            return;
        }
        Qt.openUrlExternally(currentPageUrl);
        engine.showStatus(
            i18n("Opened on Wallhaven — use the heart button to favorite (no public write API)."),
            "info",
        );
    }

    function blockCurrentWallpaper() {
        var id = currentWallpaperId;
        if (!id || id === "wallpaper" || !root.configuration) {
            return;
        }
        engine.blockId(id);
        engine.showStatus(i18n("Blocked wallpaper %1.", id), "info");
        Qt.callLater(function() {
            engine.skipForward();
        });
    }

    function clearBlockedIds() {
        if (!root.configuration) {
            return;
        }
        engine.blockedIds = [];
        root.configuration.BlockedIdsJson = "[]";
        scheduleConfigWrite();
        engine.showStatus(i18n("Blocklist cleared."), "info");
    }

    function rateCurrentWallpaper(liked) {
        if (!_currentTags || !root.configuration) {
            engine.showStatus(i18n("No tags to rate yet."), "info");
            return;
        }
        var tags = Wallhaven.tagsStringToBlocklistTags(_currentTags, 5);
        if (!tags.length) {
            return;
        }
        if (liked) {
            root.configuration.TagFavoritesJson = Wallhaven.addTagsToJsonList(cfg.TagFavoritesJson, tags, 30);
            root.configuration.TagBlocklistJson = Wallhaven.removeTagsFromJsonList(cfg.TagBlocklistJson, tags);
            engine.showStatus(i18n("Boosted tags: %1", tags.join(", ")), "info");
        } else {
            root.configuration.TagBlocklistJson = Wallhaven.addTagsToJsonList(cfg.TagBlocklistJson, tags, 60);
            root.configuration.TagFavoritesJson = Wallhaven.removeTagsFromJsonList(cfg.TagFavoritesJson, tags);
            engine.showStatus(i18n("Muted tags: %1", tags.join(", ")), "info");
        }
        scheduleConfigWrite();
        if (!liked) {
            Qt.callLater(function() {
                engine.skipForward();
            });
        }
    }

    function checkTimeCapsules() {
        if (!root.configuration) {
            return;
        }
        var entries = Wallhaven.parseTimeCapsules(cfg.TimeCapsulesJson || "[]");
        if (!entries.length) {
            return;
        }
        var now = new Date();
        var full = Wallhaven.isoDateFromParts(now.getFullYear(), now.getMonth() + 1, now.getDate());
        if ((cfg.TimeCapsuleLastAppliedDate || "") === full) {
            return;
        }
        var monthDay = Wallhaven.monthDayFromParts(now.getMonth() + 1, now.getDate());
        var due = Wallhaven.findDueTimeCapsule(entries, full, monthDay);
        if (!due) {
            return;
        }
        root.configuration.BrowseMode = "search";
        root.configuration.SearchText = due.query;
        root.configuration.WallpaperOfDayEnabled = false;
        root.configuration.TimeCapsuleLastAppliedDate = full;
        scheduleConfigWrite();
        engine.resetSlideshow();
        root.sendSystemNotification(
            i18n("Wallhaven time capsule"),
            due.label
                ? i18n("🎉 %1 — now searching \"%2\"", due.label, due.query)
                : i18n("🎉 Scheduled wallpaper switch — now searching \"%1\"", due.query),
            false,
        );
    }

    function recordWallpaperViewed() {
        if (!root.configuration || !cfg.AchievementsEnabled) {
            return;
        }
        var now = new Date();
        var today = Wallhaven.isoDateFromParts(now.getFullYear(), now.getMonth() + 1, now.getDate());
        var previousTotal = cfg.TotalWallpapersViewed || 0;
        var newTotal = previousTotal + 1;
        var isNewDay = (cfg.LastViewDateStr || "") !== today;
        var newStreak = Wallhaven.computeStreak(cfg.LastViewDateStr || "", today, cfg.CurrentStreakDays || 0);
        root.configuration.TotalWallpapersViewed = newTotal;
        root.configuration.CurrentStreakDays = newStreak;
        root.configuration.LastViewDateStr = today;
        scheduleConfigWrite();

        var milestone = Wallhaven.findNewMilestone(
            previousTotal, newTotal, [10, 50, 100, 250, 500, 1000, 2500, 5000, 10000]);
        if (milestone > 0) {
            root.sendSystemNotification(
                i18n("Wallhaven milestone"), i18n("🎉 %1 wallpapers viewed!", milestone), false);
        }
        if (isNewDay && newStreak >= 3) {
            var streakMilestone = Wallhaven.findNewMilestone(newStreak - 1, newStreak, [3, 7, 14, 30, 60, 100, 365]);
            if (streakMilestone > 0) {
                root.sendSystemNotification(
                    i18n("Wallhaven streak"), i18n("🔥 %1-day wallpaper streak!", streakMilestone), false);
            }
        }
    }

    function loadSimilarWallpapers() {
        var id = currentWallpaperId;
        if (!id || id === "wallpaper" || !root.configuration) {
            return;
        }
        root.configuration.BrowseMode = "search";
        root.configuration.SearchText = Wallhaven.buildSimilarSearchQuery(id);
        scheduleConfigWrite();
        engine.showStatus(i18n("Loading wallpapers similar to %1…", id), "info");
        engine.resetSlideshow();
    }

    function restartIntervalTimer() {
        if (!slideshowActive() || cfg.SlideshowPaused) {
            intervalTimer.stop();
            _nextSlideshowAt = 0;
            publishStatus();
            return;
        }
        intervalTimer.interval = Wallhaven.computeIntervalMs(cfg, Wallhaven.isDayPeriod());
        intervalTimer.restart();
        _nextSlideshowAt = Date.now() + intervalTimer.interval;
        publishStatus();
    }

    function publishStatus() {
        var nextMs = 0;
        if (_nextSlideshowAt > 0 && !cfg.SlideshowPaused && slideshowActive()) {
            nextMs = Math.max(0, _nextSlideshowAt - Date.now());
        }
        var layerSource = activeIsForeground ? foregroundImage.source : backgroundImage.source;
        var localThumb = String(layerSource || "").indexOf("file://") === 0 ? String(layerSource) : "";
        var screenName = "";
        try {
            screenName = String(Screen.name || "");
        } catch (e) {
            screenName = "";
        }
        var statusJson = Wallhaven.buildStatusSnapshot({
            id: currentWallpaperId !== "wallpaper" ? currentWallpaperId : "",
            thumbUrl: currentWallpaperId !== "wallpaper"
                ? Wallhaven.thumbUrlForId(currentWallpaperId) : "",
            localThumbUrl: localThumb,
            pageUrl: currentPageUrl,
            tags: _currentTags,
            details: wallpaperDetailsText,
            resolution: wallpaperDetailsResolution,
            purity: wallpaperDetailsPurity,
            category: wallpaperDetailsCategory,
            paused: cfg.SlideshowPaused,
            slideshowActive: slideshowActive(),
            nextChangeMs: nextMs,
            attribution: attributionText,
            syncGroup: cfg.SyncAdvanceGroup || "default",
            browseMode: cfg.BrowseMode || "",
            screenName: screenName,
            cacheNamespace: diskCacheNamespace,
            lockScreenSyncAt: lockScreenLastSyncAt,
            lockScreenSyncPath: lockScreenLastSyncPath,
            lockScreenSyncOk: lockScreenLastSyncOk,
            varietyWatchEnabled: cfg.VarietyWatchEnabled,
            metrics: _metrics,
            apiHealth: root.apiHealth,
            cacheCount: diskCacheEntryCount,
            outageOffline: root._apiOutageOffline,
            searchHistory: Wallhaven.parseSearchHistory(cfg.SearchHistoryJson),
            savedSearches: Wallhaven.parseSavedSearches(cfg.SavedSearchesJson),
            puritySfw: !!cfg.PuritySfw,
            puritySketchy: !!cfg.PuritySketchy,
            purityNsfw: !!cfg.PurityNsfw,
            tripModeUntilMs: parseInt(cfg.TripModeUntilMs, 10) || 0,
            tripModeActive: root.tripModeActive,
            searchText: cfg.SearchText || "",
            warmActive: root._warmActive,
            warmDone: root._warmDone,
            warmTarget: root._warmTarget,
            tripWarmTarget: cfg.CacheWarmCount || 0,
            cacheFillPercent: Wallhaven.tripCacheFillPercent(
                diskCacheEntryCount,
                cfg.CacheWarmCount || 0,
            ),
            statusUpdatedAtMs: Date.now(),
        });
        // Prefer pathless Publish* helpers; fall back to WriteTextFile with a
        // plasmashell-cache path for older helper builds.
        dbusHelper.wallhavenMessage("PublishStatusJson", "s", [statusJson], function(reply) {
            if (!Wallhaven.dbusReplyAsString(reply)) {
                settingsFileWriter.writeFile(statusBusFile, statusJson);
            }
        });
        dbusHelper.wallhavenMessage(
            "PublishMonitorStatusJson",
            "ss",
            [String(diskCacheNamespace || "default"), statusJson],
            function(reply) {
                if (!Wallhaven.dbusReplyAsString(reply)) {
                    settingsFileWriter.writeFile(
                        diskCacheDir + "/wallhaven-status-" + diskCacheNamespace + ".json",
                        statusJson,
                    );
                }
            },
        );
        publishDbusConfig();
    }

    function publishDbusConfig() {
        settingsFileWriter.writeFile(
            dbusConfigFile,
            JSON.stringify({
                varietyWatchEnabled: !!cfg.VarietyWatchEnabled,
                syncGroup: cfg.SyncAdvanceGroup || "default",
            }),
        );
    }

    function persistWallpaperHistory(wallpaper) {
        if (!wallpaper || !wallpaper.id || !root.configuration) {
            return;
        }
        var history = Wallhaven.parseWallpaperHistory(root.configuration.WallpaperHistoryJson || "[]");
        history = Wallhaven.appendWallpaperHistory(history, {
            id: String(wallpaper.id),
            thumbUrl: Wallhaven.thumbUrlForId(String(wallpaper.id)),
            ts: Date.now(),
        }, 30);
        root.configuration.WallpaperHistoryJson = Wallhaven.serializeWallpaperHistory(history, 30);
        wallpaperHistoryEntries = history;
        scheduleConfigWrite();
        settingsFileWriter.writeFile(historyBusFile, Wallhaven.serializeWallpaperHistory(history, 12));
    }

    function loadWallpaperHistory() {
        wallpaperHistoryEntries = Wallhaven.parseWallpaperHistory(
            (root.configuration && root.configuration.WallpaperHistoryJson) || "[]",
        );
    }

    function getWallpaperHistory() {
        if (wallpaperHistoryEntries && wallpaperHistoryEntries.length) {
            return wallpaperHistoryEntries;
        }
        return Wallhaven.parseWallpaperHistory(cfg.WallpaperHistoryJson || "[]");
    }

    function showHistoryWallpaper(id) {
        id = String(id || "").trim();
        if (!id) {
            return;
        }
        var wp = Wallhaven.makeCachedWallpaper(id);
        var remote = Wallhaven.thumbUrlForId(id);
        var source = resolveImageSource(wp, remote);
        if (source.indexOf("file:") === 0) {
            // Still in the local disk cache: show the full-resolution cached file directly.
            engine.displayWallpaper(wp, source, true);
            engine.showStatus(i18n("Showing wallpaper #%1 from history.", id), "info");
            return;
        }
        // Not cached locally anymore (LRU evicted it, or disk cache is off): fetch the
        // full wallpaper record so we can display the real image, not just its thumbnail.
        engine.showStatus(i18n("Loading wallpaper #%1 from history…", id), "info");
        engine.requestJson(Wallhaven.buildWallpaperUrl(id, cfg.ApiKey), function(json) {
            if (!json.data) {
                engine.showStatus(i18n("Could not load wallpaper #%1.", id), "error");
                return;
            }
            var full = Wallhaven.wallpaperUrl(json.data, cfg.ImageQuality);
            engine.displayWallpaper(json.data, full || remote, true);
            engine.showStatus(i18n("Showing wallpaper #%1 from history.", id), "info");
        }, function() {
            engine.showStatus(i18n("Could not load wallpaper #%1 — showing preview instead.", id), "warn");
            engine.displayWallpaper(wp, remote, true);
        });
    }

    function clearWallpaperHistory() {
        if (!root.configuration) {
            return;
        }
        root.configuration.WallpaperHistoryJson = "[]";
        wallpaperHistoryEntries = [];
        scheduleConfigWrite();
        settingsFileWriter.writeFile(historyBusFile, "[]");
        engine.showStatus(i18n("Wallpaper history cleared."), "info");
    }

    function lockScreenImagePath(wallpaperId) {
        return diskCacheDir + "/" + Wallhaven.lockScreenImageFileName(
            wallpaperId || root._pendingWallpaperId || root.currentWallpaperId,
        );
    }

    function syncLockScreenImage(localPath, wallpaperId) {
        if (!cfg.SyncLockScreen || !localPath) {
            return;
        }
        // Flock in buildLockScreenSyncCommand serializes multi-monitor writers.
        // Do not gate on geometric "primary" — SyncLockScreen often lives only on
        // a non-origin screen, and skipping there left the lock image stale forever.
        var source = urlToLocalPath(localPath);
        if (!source) {
            lockScreenLastSyncOk = false;
            lockScreenLastSyncAt = new Date().toISOString();
            lockScreenLastSyncPath = "";
            publishStatus();
            return;
        }
        var dest = lockScreenImagePath(wallpaperId);
        var command = Wallhaven.buildLockScreenSyncCommand(source, dest);
        if (!command) {
            lockScreenLastSyncOk = false;
            lockScreenLastSyncAt = new Date().toISOString();
            lockScreenLastSyncPath = dest;
            publishStatus();
            return;
        }
        var seq = ++root._lockSyncSeq;
        var expectedId = String(wallpaperId || root._pendingWallpaperId || root.currentWallpaperId || "");
        dbusHelper.runArgv(["bash", "-lc", command], function(reply) {
            // A newer sync superseded this one (rapid next / overlapping callbacks).
            if (seq !== root._lockSyncSeq) {
                return;
            }
            var text = String(reply || "").trim();
            lockScreenLastSyncOk = text === "ok";
            lockScreenLastSyncAt = new Date().toISOString();
            lockScreenLastSyncPath = dest;
            publishStatus();
            if (lockScreenLastSyncOk) {
                root._lockSyncRetry = null;
                logDebug("Lock screen synced → " + dest);
                return;
            }
            logDebug("Lock screen sync failed → " + dest + " reply=" + text);
            engine.showStatus(i18n("Lock screen sync failed."), "warn", false, { notify: false });
            // One deferred retry for the same wallpaper id only (settling cache file).
            var priorAttempts = 0;
            if (root._lockSyncRetry && root._lockSyncRetry.id === expectedId) {
                priorAttempts = root._lockSyncRetry.attempts || 0;
            }
            if (priorAttempts < 1) {
                root._lockSyncRetry = { id: expectedId, path: source, attempts: priorAttempts + 1 };
                lockSyncRetryTimer.restart();
            } else {
                root._lockSyncRetry = null;
            }
        });
    }

    function maybeSyncSidecars(img) {
        if (!img) {
            return;
        }
        if (String(img.source) !== String(_pendingImageUrl)) {
            return;
        }
        var source = String(img.source || "");
        var wallpaperId = root._pendingWallpaperId || root.currentWallpaperId;
        if (source.indexOf("file:") === 0) {
            var path = urlToLocalPath(source);
            syncLockScreenImage(path, wallpaperId);
            updateVarietySymlink(path);
            return;
        }
        // Remote URL: sync lock screen from the visible frame immediately so
        // locking before the disk-cache write finishes still shows this wallpaper.
        // Disk-cache completion may refresh the lock image again at higher quality.
        if (cfg.SyncLockScreen) {
            var dest = lockScreenImagePath(wallpaperId);
            var captureId = String(wallpaperId || "");
            img.grabToImage(function(result) {
                if (String(root._pendingWallpaperId || root.currentWallpaperId || "") !== captureId) {
                    return;
                }
                if (result && result.saveToFile(dest)) {
                    syncLockScreenImage(dest, captureId);
                }
            }, wallpaperSourceSize);
        }
    }

    function updateVarietySymlink(localPath) {
        if (!cfg.VarietySymlinkEnabled || !cfg.VarietyFolderPath || !localPath) {
            return;
        }
        var folder = String(cfg.VarietyFolderPath).replace(/"/g, '\\"');
        var source = localPath.replace(/"/g, '\\"');
        dbusHelper.runArgv([
            "bash", "-lc",
            "mkdir -p '" + folder + "' && ln -sf '" + source + "' '"
                + folder + "/" + Wallhaven.varietySymlinkName() + "'",
        ]);
    }

    function writePanelTint(hexColor, wallpaperId) {
        if (!hexColor) {
            return;
        }
        function applyAccents() {
            if (cfg.AutoPanelAccentEnabled) {
                applyPanelAccent(hexColor);
            }
            if (cfg.SystemThemeSyncEnabled) {
                applySystemThemeSync(hexColor);
            }
        }
        if (cfg.PanelTintEnabled) {
            settingsFileWriter.writeFile(
                panelTintFile,
                Wallhaven.buildPanelTintMetadata(hexColor, wallpaperId, cfg.PanelBlurStrength),
                (cfg.AutoPanelAccentEnabled || cfg.SystemThemeSyncEnabled) ? applyAccents : null,
            );
        } else {
            applyAccents();
        }
    }

    function applyPanelAccent(hexColor) {
        if (!hexColor) {
            return;
        }
        var color = String(hexColor).replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
        if (color.length !== 6) {
            return;
        }
        dbusHelper.runArgv([
            "plasma-apply-colors", "--accent-color", "#" + color,
        ]);
    }

    function applySystemThemeSync(hexColor) {
        if (!cfg.SystemThemeSyncEnabled || !hexColor) {
            return;
        }
        var color = String(hexColor).replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
        if (color.length !== 6) {
            return;
        }
        // kdeglobals stores AccentColor as a KConfig QColor ("r,g,b" decimal), and
        // GNOME's accent-color is a fixed name enum — neither accepts a raw hex
        // string, so both values must be translated first or the writes no-op.
        var kdeColor = Wallhaven.hexToKdeAccentColor(color);
        var gnomeAccent = Wallhaven.nearestGnomeAccentColor(color);
        if (!kdeColor) {
            return;
        }
        var script = "kwriteconfig6 --file kdeglobals --group General --key AccentColor '" + kdeColor + "'; ";
        if (gnomeAccent) {
            script += "command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.interface accent-color "
                + "'" + gnomeAccent + "' 2>/dev/null; true";
        }
        dbusHelper.runArgv(["bash", "-lc", script]);
    }

    function applySmartColorFilter(hexColor) {
        if (!cfg.SmartColorFromWallpaper || !hexColor || !root.configuration) {
            return;
        }
        var nearest = Wallhaven.nearestWallhavenColor(hexColor);
        if (nearest && root.configuration.ColorFilter !== nearest) {
            root.configuration.ColorFilter = nearest;
            scheduleConfigWrite();
            logDebug("Smart color filter set to " + nearest);
        }
    }

    function importPresetFromUrl(url) {
        var raw = String(url || "").trim();
        if (!raw) {
            return;
        }
        if (Wallhaven.isHttpPresetUrl(raw)) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", raw);
            xhr.setRequestHeader("Accept", "application/json, text/plain, */*");
            xhr.timeout = 30000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }
                if (xhr.status < 200 || xhr.status >= 300) {
                    engine.showStatus(i18n("Failed to fetch preset (%1).", xhr.status), "error");
                    return;
                }
                root.applyImportedPresetPayload(xhr.responseText);
            };
            xhr.onerror = function() {
                engine.showStatus(i18n("Network error fetching preset."), "error");
            };
            xhr.ontimeout = function() {
                engine.showStatus(i18n("Timed out fetching preset."), "error");
            };
            xhr.send();
            return;
        }
        try {
            root.applyImportedPresetPayload(raw);
        } catch (e) {
            engine.showStatus(i18n("Invalid preset URL."), "error");
        }
    }

    function applyImportedPresetPayload(raw) {
        if (!root.configuration) {
            return;
        }
        var preset = Wallhaven.parseRemotePresetPayload(raw);
        if (!preset) {
            engine.showStatus(i18n("Invalid preset URL."), "error");
            return;
        }
        Wallhaven.applyPresetToConfig(preset, root.configuration);
        scheduleConfigWrite();
        engine.showStatus(i18n("Imported preset %1.", preset.name || ""), "info");
        engine.resetSlideshow();
    }

    function applyLaptopMode() {
        if (!root.configuration) {
            return;
        }
        var settings = Wallhaven.laptopModeSettings();
        var keys = Object.keys(settings);
        for (var i = 0; i < keys.length; i++) {
            root.configuration[keys[i]] = settings[keys[i]];
        }
        scheduleConfigWrite();
        engine.showStatus(i18n("Laptop mode applied (metered, battery, idle pause, lighter effects)."), "info");
    }

    function applyDesktopMode() {
        if (!root.configuration) {
            return;
        }
        var settings = Wallhaven.desktopModeSettings();
        var keys = Object.keys(settings);
        for (var i = 0; i < keys.length; i++) {
            root.configuration[keys[i]] = settings[keys[i]];
        }
        scheduleConfigWrite();
        engine.showStatus(i18n("Desktop mode applied (full quality, smart offline, original downloads)."), "info");
    }

    function applyOfflineMode() {
        if (!root.configuration) {
            return;
        }
        var settings = Wallhaven.offlineModeSettings();
        var keys = Object.keys(settings);
        for (var i = 0; i < keys.length; i++) {
            root.configuration[keys[i]] = settings[keys[i]];
        }
        scheduleConfigWrite();
        engine.showStatus(i18n("Offline mode applied (playlist / cache only, no network fetches)."), "info");
    }

    function enterApiOutageOffline(statusCode, cooldownMs) {
        root._apiOutageOffline = true;
        engine.stopRetries();
        var msg;
        if (statusCode === 429) {
            var cool = Wallhaven.rateLimitCooldownMs(cooldownMs);
            root._rateLimitUntilMs = Math.max(root._rateLimitUntilMs, Date.now() + cool);
            msg = i18n("Rate limited by Wallhaven. Using cache until it recovers.");
            root.publishRateLimitLatch(cool, statusCode);
        } else if (statusCode) {
            msg = i18n("Wallhaven unreachable (%1). Using cache until it recovers.", statusCode);
        } else {
            msg = i18n("Using cache until Wallhaven recovers.");
        }
        if (!engine.tryOfflineFallback(msg)) {
            engine.showStatus(msg, "error");
        }
        publishStatus();
    }

    function clearApiOutageOffline(resumeFetch, force) {
        // Never clear while the hard rate-limit cooldown is still active —
        // wallpaper detail /api/v1/w/{id} 200s used to clear soft-offline and
        // immediately re-open search fetches. Explicit resumeonline may force.
        if (!force && root.isRateLimitedNow()) {
            return;
        }
        if (force) {
            root._rateLimitUntilMs = 0;
            clearRateLimitLatch();
        }
        if (!root._apiOutageOffline) {
            return;
        }
        root._apiOutageOffline = false;
        root._outageProbeFailCount = 0;
        root._outageProbeAtMs = 0;
        publishStatus();
        // Never auto-resetSlideshow here. Favicon/connectivity used to clear the
        // latch and immediately re-fetch, which caused wallpaper jumping + fresh
        // 429 storms. Resume on the normal interval / explicit user action only.
        if (resumeFetch && !cfg.OfflineOnlyMode && cfg.BrowseMode !== "playlist" && cfg.BrowseMode !== "local") {
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
        }
    }

    // Quiet API probe while soft-offline from a non-429 outage. Favicon must never
    // clear outage; only a real /api/v1 200 may. Backs off on repeated failures.
    function maybeProbeApiOutageClear() {
        if (!root._apiOutageOffline) {
            return;
        }
        if (root.isRateLimitedNow()) {
            return;
        }
        // A non-quiet 200 can land while the 429 latch still blocked clear —
        // once the latch is gone, trust that success and leave soft-offline.
        if (root._apiLastStatus === 200) {
            clearApiOutageOffline(false);
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
            return;
        }
        if (root._apiLastStatus === 429) {
            return;
        }
        if (!root.configuration || cfg.OfflineOnlyMode
                || cfg.BrowseMode === "playlist" || cfg.BrowseMode === "local") {
            return;
        }
        var fails = root._outageProbeFailCount || 0;
        var gapMs = Math.min(300000, 30000 * Math.pow(2, Math.min(fails, 3)));
        var now = Date.now();
        if (root._outageProbeAtMs > 0 && (now - root._outageProbeAtMs) < gapMs) {
            return;
        }
        root._outageProbeAtMs = now;
        var url = "https://wallhaven.cc/api/v1/search?categories=100&purity=100&page=1&sorting=date_added&order=desc";
        var key = Wallhaven.sanitizeApiKey(cfg.ApiKey);
        if (key) {
            url += "&apikey=" + encodeURIComponent(key);
        }
        engine.requestJson(url, function(json) {
            if (!root._apiOutageOffline) {
                return;
            }
            if (root.isRateLimitedNow()) {
                return;
            }
            if (!json || typeof json !== "object") {
                root._outageProbeFailCount = fails + 1;
                return;
            }
            root._outageProbeFailCount = 0;
            // Quiet XHR success does not call noteApiResult — clear explicitly.
            root._apiLastStatus = 200;
            root._apiLastSuccessAt = new Date().toISOString();
            root._apiLastError = "";
            clearApiOutageOffline(false);
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
            publishStatus();
        }, function() {
            root._outageProbeFailCount = (root._outageProbeFailCount || 0) + 1;
        }, { quiet: true });
    }

    function publishRateLimitLatch(cooldownMs, statusCode) {
        var cool = Wallhaven.rateLimitCooldownMs(cooldownMs);
        root._rateLimitUntilMs = Math.max(root._rateLimitUntilMs, Date.now() + cool);
        var untilMs = root._rateLimitUntilMs;
        var payload = Wallhaven.buildRateLimitLatch(untilMs, statusCode || 429);
        dbusHelper.writeFile(rateLimitBusFile, payload, function() {});
    }

    function clearRateLimitLatch() {
        if (root.isRateLimitedNow()) {
            return;
        }
        root._rateLimitUntilMs = 0;
        dbusHelper.writeFile(rateLimitBusFile, "{\"untilMs\":0}", function() {});
    }

    function pollSharedRateLimit() {
        dbusHelper.readFile(rateLimitBusFile, function(text) {
            var latch = Wallhaven.parseRateLimitLatch(text);
            var now = Date.now();
            if (Wallhaven.rateLimitLatchActive(latch, now)) {
                root._rateLimitUntilMs = Math.max(root._rateLimitUntilMs, latch.untilMs);
                if (!root._apiOutageOffline) {
                    root._apiOutageOffline = true;
                    engine.stopRetries();
                    if (!engine.tryOfflineFallback(
                            i18n("Rate limited by Wallhaven. Using cache until it recovers."))) {
                        engine.showStatus(
                            i18n("Rate limited by Wallhaven. Using cache until it recovers."),
                            "error",
                        );
                    }
                    publishStatus();
                }
                return;
            }
            // Latch expired — allow online again without forcing a new fetch.
            if (root._rateLimitUntilMs && now >= root._rateLimitUntilMs) {
                root._rateLimitUntilMs = 0;
            }
            // A detail/search 200 can arrive while the latch still blocked
            // clearApiOutageOffline — once the latch is gone, leave soft-offline
            // for both prior-429 and already-healthy (200) states.
            if (Wallhaven.shouldClearSoftOutage(
                    root._apiOutageOffline, root._apiLastStatus, root.isRateLimitedNow())) {
                clearApiOutageOffline(false);
            }
        });
    }

    function setCacheEntryTags(id, tags) {
        if (!id) {
            return;
        }
        Wallhaven.setDiskCacheTags(_diskCacheIndex, id, tags);
        persistDiskCacheIndex();
    }

    function useScreenNameAsSyncGroup() {
        if (!root.configuration) {
            return;
        }
        var group = diskCacheNamespace || "default";
        root.configuration.SyncAdvanceEnabled = true;
        root.configuration.SyncAdvanceGroup = group;
        root.configuration.SyncProfilesEnabled = true;
        scheduleConfigWrite();
        if (root.saveSyncProfileForCurrentGroup) {
            root.saveSyncProfileForCurrentGroup();
        }
        engine.showStatus(i18n("Sync group set to this screen (%1).", group), "info");
    }

    function clearSeenHistory() {
        var count = seenIdsCount;
        engine.clearSeenIds();
        engine.showStatus(i18n("Cleared seen wallpaper history (%1 entries).", count), "info");
    }

    function showWallpaperInfo() {
        var details = root.wallpaperDetailsText || "";
        if (!details && root.currentWallpaperId && root.currentWallpaperId !== "wallpaper") {
            details = i18n("ID: %1", root.currentWallpaperId);
            if (root._currentTags) {
                details += "\n" + root._currentTags;
            }
        }
        if (!details) {
            engine.showStatus(i18n("No wallpaper details yet."), "warn");
            return;
        }
        root.wallpaperDetailsOpen = true;
        engine.showStatus(details, "info", false);
        root.sendSystemNotification(i18n("Wallpaper info"), details, false);
    }

    function saveApiKeyToKWallet() {
        var key = String(cfg.ApiKey || "").trim();
        if (!key) {
            engine.showStatus(i18n("Enter an API key first."), "warn");
            return;
        }
        var escaped = key.replace(/'/g, "'\\''");
        dbusHelper.runArgv([
            "bash", "-lc",
            "printf '%s' '" + escaped + "' | kwallet-query -w wallhaven -f org.robertsm.wallhaven apikey 2>/dev/null"
                + " || printf '%s' '" + escaped + "' | kwallet-query --write-password apikey -f org.robertsm.wallhaven -w kdewallet 2>/dev/null",
        ], function() {
            if (root.configuration) {
                root.configuration.UseKWalletForApiKey = true;
                scheduleConfigWrite();
            }
            engine.showStatus(i18n("API key saved to KWallet (folder org.robertsm.wallhaven)."), "info");
        });
    }

    function noteApiResult(status, errorText) {
        root._apiLastStatus = status || 0;
        root._apiLastError = String(errorText || "");
        if (status === 429) {
            root._apiRateLimitCount = (root._apiRateLimitCount || 0) + 1;
            root._apiLastRateLimitAt = new Date().toISOString();
            _metrics = Wallhaven.recordRateLimitMetrics(_metrics);
        } else if (status === 200) {
            root._apiLastSuccessAt = new Date().toISOString();
            root._apiLastError = "";
            if (root.configuration) {
                root.configuration.ApiKeyValid = !!Wallhaven.sanitizeApiKey(cfg.ApiKey);
            }
            // Clear soft-offline without forcing a new slideshow reset/fetch.
            clearApiOutageOffline(false);
            clearRateLimitLatch();
        } else if (status === 401 || status === 403) {
            if (root.configuration) {
                root.configuration.ApiKeyValid = false;
            }
            // Auth errors are not outages — keep online path so user can clear the key.
            var keyHint = Wallhaven.apiKeyLastFour(cfg.ApiKey);
            engine.showStatus(
                keyHint
                    ? i18n("Wallhaven rejected API key (…%1). Clear or re-enter it.", keyHint)
                    : i18n("Wallhaven unauthorized (%1). Check API key / NSFW settings.", status),
                "error",
            );
            // Still paint something when the current frame is missing/broken.
            if (!root.wallpaperIsVisible()) {
                if (!engine.tryOfflineFallback(i18n("Using cached wallpaper while API key is fixed."))) {
                    root.bootstrapWallpaperFromCache();
                }
            }
        }
        publishStatus();
    }

    function clearApiKey(keepWallet) {
        if (!root.configuration) {
            return;
        }
        root.configuration.ApiKey = "";
        root.configuration.ApiKeyValid = false;
        if (!keepWallet) {
            root.configuration.UseKWalletForApiKey = false;
            root._walletStatus = "disabled";
        }
        scheduleConfigWrite();
        engine.showStatus(i18n("API key cleared."), "info");
        publishStatus();
        if (!root.effectiveOfflineOnly()) {
            engine.resetSlideshow();
        }
    }

    function testApiKeyNow(callback) {
        var key = Wallhaven.sanitizeApiKey(cfg.ApiKey);
        if (!key) {
            engine.showStatus(i18n("Enter an API key first."), "warn");
            if (callback)
                callback(false, 0);
            return;
        }
        var url = Wallhaven.buildSettingsUrl(key);
        if (!url) {
            engine.showStatus(i18n("API key looks invalid."), "warn");
            if (callback)
                callback(false, 0);
            return;
        }
        engine.requestJson(url, function() {
            root.noteApiResult(200, "");
            engine.showStatus(i18n("API key is valid."), "info");
            if (callback)
                callback(true, 200);
        }, function(status) {
            root.noteApiResult(status || 0, "key test failed");
            if (callback)
                callback(false, status || 0);
        });
    }

    function exportDebugBundleToFile(destUrl) {
        getDebugInfo(function(info) {
            var dest = urlToLocalPath(destUrl) || String(destUrl || "");
            if (!dest) {
                engine.showStatus(i18n("Invalid export path."), "warn");
                return;
            }
            settingsFileWriter.writeFile(dest, info, function() {
                engine.showStatus(i18n("Exported bug report bundle."), "info");
            });
        });
    }

    function isDbusServiceAvailable() {
        // Every other D-Bus call in this file goes through the async
        // dbusMessage()+asyncCall() pattern (see dbusAvailabilityLoader.poll()
        // below, or musicReactiveLoader.poll()) because QML cannot block on IPC.
        // This used to call PDBus.SessionBus.nameHasOwner(...) directly as if it
        // were a synchronous getter, which isn't part of that API — the check
        // silently always evaluated as unavailable, so the "D-Bus service is not
        // running" banner and the Variety buttons stayed stuck in the offline
        // state even with `systemctl --user status wallhaven-dbus.service`
        // showing it active. Read the periodically-refreshed cached result instead.
        return root.dbusServiceAvailable;
    }

    // Bindable properties (upscalerStatusKnown / upscalerAvailable) are the
    // source of truth. QML does not re-run these getters when the async poll
    // finishes, so settings must bind the properties rather than call these.
    function isUpscalerAvailable() {
        return root.upscalerAvailable;
    }

    function isUpscalerStatusKnown() {
        return root.upscalerStatusKnown;
    }

    function varietyConfigPath() {
        return StandardPaths.writableLocation(StandardPaths.HomeLocation)
            + "/.config/variety/variety.conf";
    }

    function previewVarietySearch(callback) {
        if (!isDbusServiceAvailable()) {
            engine.showStatus(i18n("Wallhaven D-Bus service is not running. Run: systemctl --user enable --now wallhaven-dbus.service"), "warn");
            if (callback) {
                callback("");
            }
            return;
        }
        dbusHelper.readFile(varietyConfigPath(), function(text) {
            if (!text) {
                if (callback) {
                    callback("");
                }
                return;
            }
            var search = Wallhaven.parseVarietySearch(text);
            if (callback) {
                callback(search || "");
            }
        });
    }

    function applyVarietySearch() {
        if (!isDbusServiceAvailable()) {
            engine.showStatus(i18n("Wallhaven D-Bus service is not running. Run: systemctl --user enable --now wallhaven-dbus.service"), "warn");
            return;
        }
        previewVarietySearch(function(search) {
            if (!search) {
                engine.showStatus(i18n("No image_fetch_search in Variety config."), "warn");
                return;
            }
            if (!root.configuration) {
                return;
            }
            root.configuration.BrowseMode = "search";
            root.configuration.SearchText = search;
            root.configuration.WallpaperOfDayEnabled = false;
            scheduleConfigWrite();
            engine.resetSlideshow();
            engine.showStatus(i18n("Applied Variety search: %1", search), "info");
        });
    }

    function saveSyncProfileForCurrentGroup() {
        if (!root.configuration || !cfg.SyncProfilesEnabled) {
            return;
        }
        var group = String(cfg.SyncAdvanceGroup || "default").trim() || "default";
        var profiles = Wallhaven.parseSyncProfiles(cfg.SyncProfilesJson || "{}");
        profiles[group] = engine.configObject();
        root.configuration.SyncProfilesJson = Wallhaven.serializeSyncProfiles(profiles);
        scheduleConfigWrite();
        engine.showStatus(i18n("Saved search profile for sync group \"%1\".", group), "info");
    }

    function applySyncProfileForGroup(group) {
        if (!root.configuration || !cfg.SyncProfilesEnabled) {
            return;
        }
        group = String(group || "default").trim() || "default";
        var profiles = Wallhaven.parseSyncProfiles(cfg.SyncProfilesJson || "{}");
        var profile = profiles[group];
        if (!profile) {
            return;
        }
        Wallhaven.applySyncProfile(profile, root.configuration);
        scheduleConfigWrite();
        if (root._configured) {
            engine.resetSlideshow();
        }
    }

    function evaluateSlideshowRules() {
        var shouldPause = false;
        if (cfg.PauseOnBatteryLow && _batteryPercent >= 0
                && _batteryPercent <= (cfg.BatteryLowThreshold || 20)) {
            shouldPause = true;
        }
        // Was Qt.application.state !== Qt.ApplicationActive. This wallpaper's
        // QML runs inside plasmashell's own process, not a normal top-level
        // app window -- the desktop/wallpaper view rarely if ever gains or
        // loses window focus the way Qt.application.state is meant to track,
        // so that check was either permanently true or permanently false
        // depending on the session, not a real signal of "nobody's looking at
        // this session right now". Screen-lock state, polled from the
        // standard org.freedesktop.ScreenSaver D-Bus interface (see
        // screenLockLoader.poll() below), is what "session is inactive"
        // actually means for a wallpaper: it's the same interface every other
        // screensaver-aware Linux app uses to detect the lock screen.
        if (cfg.PauseWhenInactive && root._screenLocked) {
            shouldPause = true;
        }
        if (cfg.PauseOnIdleEnabled && root._sessionIdle) {
            shouldPause = true;
        }
        if (shouldPause === _rulesPausedSlideshow) {
            return;
        }
        _rulesPausedSlideshow = shouldPause;
        if (!root.configuration) {
            return;
        }
        if (shouldPause && !cfg.SlideshowPaused) {
            _pausedByRules = true;
            root.configuration.SlideshowPaused = true;
            scheduleConfigWrite();
            intervalTimer.stop();
            engine.showStatus(i18n("Slideshow paused by power/activity rules."), "info");
        } else if (!shouldPause && _pausedByRules && cfg.SlideshowPaused) {
            _pausedByRules = false;
            root.configuration.SlideshowPaused = false;
            scheduleConfigWrite();
            if (cfg.RandomInterval > 0) {
                restartIntervalTimer();
            }
            engine.showStatus(i18n("Slideshow resumed (power/activity rules cleared)."), "info");
            publishStatus();
        }
    }

    function effectiveTransitionMode() {
        return Wallhaven.pickTransitionMode(cfg);
    }

    function pinnedCacheIds() {
        return Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson || "[]");
    }

    function logDebug(message) {
        if (!cfg.DebugLogEnabled) {
            return;
        }
        var line = new Date().toISOString() + " " + String(message || "");
        debugLogWriter.appendLine(line);
    }

    function getCacheEntries() {
        return Wallhaven.listCacheEntries(_diskCacheIndex, pinnedCacheIds());
    }

    function pinCacheId(id) {
        id = String(id || "").trim();
        if (!id || !root.configuration) {
            return;
        }
        var ids = pinnedCacheIds();
        if (ids.indexOf(id) === -1) {
            ids.push(id);
            root.configuration.PinnedCacheIdsJson = Wallhaven.serializePinnedCacheIds(ids);
            scheduleConfigWrite();
        }
    }

    function unpinCacheId(id) {
        id = String(id || "").trim();
        if (!id || !root.configuration) {
            return;
        }
        var ids = pinnedCacheIds().filter(function(entry) { return entry !== id; });
        root.configuration.PinnedCacheIdsJson = Wallhaven.serializePinnedCacheIds(ids);
        scheduleConfigWrite();
    }

    function evictCacheId(id) {
        id = String(id || "").trim();
        if (!id || pinnedCacheIds().indexOf(id) !== -1) {
            return;
        }
        var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, id);
        if (slot >= 0) {
            Wallhaven.evictDiskCacheOccupant(_diskCacheIndex, id);
            _diskCacheIndex.ids[slot] = "";
            persistDiskCacheIndex();
            dbusHelper.runArgv(["rm", "-f", diskCacheLocalPath(slot)]);
            logDebug("Evicted cache id " + id);
        }
    }

    function buildDebugBundleText(logTail) {
        return Wallhaven.buildDebugBundle(cfg, {
            version: Wallhaven.pluginVersion(),
            status: {
                id: currentWallpaperId,
                url: currentUrl,
                paused: cfg.SlideshowPaused,
            },
            metrics: _metrics,
            logTail: String(logTail || "").split("\n").slice(-40).join("\n"),
        });
    }

    function getDebugInfo(onReady) {
        dbusHelper.readFile(debugLogFile, function(logTail) {
            var info = buildDebugBundleText(logTail);
            if (onReady) {
                onReady(info);
            }
        });
    }

    function copyGithubIssue() {
        getDebugInfo(function(info) {
            try {
                var bundle = JSON.parse(info);
                copyToClipboard(bundle.githubIssue || info, i18n("Copied GitHub issue template."));
            } catch (e) {
                copyToClipboard(info, i18n("Copied debug info."));
            }
        });
    }

    function copyDebugInfo() {
        getDebugInfo(function(info) {
            copyToClipboard(info, i18n("Copied debug info."));
        });
    }

    function showDebugLogTail() {
        dbusHelper.readFile(debugLogFile, function(text) {
            var lines = String(text || "").split("\n").filter(function(entry) {
                return entry.length > 0;
            });
            var tail = lines.slice(-20).join("\n");
            engine.showStatus(tail || i18n("Debug log is empty."), tail ? "info" : "warn");
        });
    }

    function importSettingsFromFile(localPath) {
        dbusHelper.readFile(localPath, function(text) {
            if (!text || !root.configuration) {
                engine.showStatus(i18n("Could not read settings file."), "warn");
                return;
            }
            try {
                var settings = Wallhaven.importSettingsSnapshot(text);
                var keys = Object.keys(settings);
                for (var i = 0; i < keys.length; i++) {
                    root.configuration[keys[i]] = settings[keys[i]];
                }
                scheduleConfigWrite();
                engine.resetSlideshow();
                engine.showStatus(i18n("Settings imported."), "info");
            } catch (e) {
                engine.showStatus(i18n("Could not import settings file."), "warn");
            }
        });
    }

    function writeControlCommand(cmd) {
        if (!cfg.ControlBusEnabled) {
            return;
        }
        settingsFileWriter.writeFile(
            controlBusFile,
            Wallhaven.buildControlCommand(cmd, cfg.SyncAdvanceGroup || "default"),
        );
    }

    function pollControlBus() {
        if (!cfg.ControlBusEnabled) {
            return;
        }
        controlBusLoader.load(controlBusFile);
    }

    function broadcastSyncAdvance() {
        if (!cfg.SyncAdvanceEnabled) {
            return;
        }
        settingsFileWriter.writeFile(syncAdvanceFile(), Wallhaven.buildSyncAdvance(_instanceId));
    }

    function pollSyncAdvance() {
        if (!cfg.SyncAdvanceEnabled) {
            return;
        }
        syncAdvanceLoader.load(syncAdvanceFile());
    }

    function writeVarietyMetadata(wallpaper, imageUrl) {
        if (!cfg.VarietyMetadataEnabled) {
            return;
        }
        var localPath = resolveImageSource(wallpaper, imageUrl);
        if (localPath.indexOf("file:") === 0) {
            localPath = urlToLocalPath(localPath);
        }
        settingsFileWriter.writeFile(
            varietyMetadataFile,
            Wallhaven.buildVarietyMetadata(wallpaper, imageUrl, localPath),
        );
    }

    function exportSettingsToFile(destUrl) {
        var json = Wallhaven.exportSettingsSnapshot(cfg);
        settingsFileWriter.writeFile(settingsExportFile, json, function() {
            dbusHelper.runArgv(["cp", settingsExportFile, urlToLocalPath(destUrl)]);
            engine.showStatus(i18n("Settings exported."), "info");
        });
    }

    function loadApiKeyFromKWallet() {
        if (!cfg.UseKWalletForApiKey) {
            root._walletStatus = "disabled";
            return;
        }
        root._walletLoadAttempted = true;
        var tmp = urlToLocalPath(diskCacheDir + "/kwallet-apikey.txt");
        dbusHelper.runArgv([
            "bash", "-lc",
            "kwallet-query -r apikey -f org.robertsm.wallhaven -w wallhaven > '"
                + tmp.replace(/'/g, "'\\''") + "' 2>/dev/null",
        ], function() {
            kwalletReadLoader.read(tmp);
        });
    }

    function setSlideshowPaused(paused) {
        if (!root.configuration) {
            return;
        }
        paused = !!paused;
        _pausedByRules = false;
        if (!!cfg.SlideshowPaused === paused) {
            publishStatus();
            return;
        }
        root.configuration.SlideshowPaused = paused;
        scheduleConfigWrite();
        if (paused) {
            intervalTimer.stop();
            _nextSlideshowAt = 0;
            engine.showStatus(i18n("Slideshow paused."), "info");
        } else {
            if (cfg.RandomInterval > 0) {
                restartIntervalTimer();
            }
            engine.showStatus(i18n("Slideshow resumed."), "info");
        }
        publishStatus();
    }

    function toggleSlideshowPause() {
        setSlideshowPaused(!cfg.SlideshowPaused);
    }

    function checkConnectivity() {
        var xhr = new XMLHttpRequest();
        xhr.open("HEAD", "https://wallhaven.cc/favicon.ico");
        xhr.timeout = 8000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            var online = xhr.status >= 200 && xhr.status < 400;
            if (online && (!_connectivityOnline || _needsReconnectFetch)) {
                engine.retryAfterReconnect();
            }
            // Do NOT clear API outage / rate-limit soft-offline from a favicon
            // HEAD. wallhaven.cc can serve static assets while /api/v1 is still
            // returning 429; clearing here used to resetSlideshow every 45s and
            // burn through wallpapers. Recovery is latch expiry, a real API 200,
            // or maybeProbeApiOutageClear for non-429 soft-offline.
            root.pollSharedRateLimit();
            if (online) {
                root.maybeProbeApiOutageClear();
            }
            if (!online && _connectivityOnline) {
                _needsReconnectFetch = true;
            }
            _connectivityOnline = online;
            // Blank / broken frame after sleep: pull cache even while "online".
            if (online) {
                root.ensureWallpaperVisible("connectivity");
            }
        };
        xhr.onerror = function() {
            if (_connectivityOnline) {
                _needsReconnectFetch = true;
            }
            _connectivityOnline = false;
            root.ensureWallpaperVisible("connectivity-error");
        };
        xhr.send();
    }

    // After suspend/resume the compositor often drops GPU textures while
    // currentUrl is still set — desktop looks empty until something reloads.
    function reloadCurrentImage() {
        var url = String(root.currentUrl || "");
        if (!url) {
            return false;
        }
        // Drop stale GPU bindings first. Reassigning the same file:// source is a
        // no-op in Qt Quick Image, which is exactly what left monitors blank.
        clearWallpaperImageSources();
        resetWallpaperLayerVisibility();
        var wallpaper = root.currentWallpaper;
        var remote = String(root._pendingRemoteUrl || "");
        if (wallpaper && wallpaper.id) {
            if (!remote || remote.indexOf("http") !== 0) {
                remote = Wallhaven.thumbUrlForId(String(wallpaper.id));
            }
            var resolved = resolveImageSource(wallpaper, remote);
            if (!resolved) {
                return false;
            }
            showImage(resolved, true);
            return true;
        }
        if (!url || (root.effectiveOfflineOnly() && url.indexOf("file:") !== 0)) {
            return false;
        }
        showImage(url, true);
        return true;
    }

    function bootstrapWallpaperFromCache() {
        var id = String((cfg && cfg.PreviewWallpaperId) || "").trim();
        if (id === "wallpaper") {
            id = "";
        }
        if (id && Wallhaven.diskCacheSlotForId(_diskCacheIndex, id) >= 0) {
            var wp = Wallhaven.makeCachedWallpaper(id);
            engine.displayWallpaper(wp, Wallhaven.thumbUrlForId(id), true);
            return true;
        }
        // Prefer the wallpaper already on screen / current id — never advance the
        // offline cursor during blank recovery (that caused cache storms).
        var currentId = String(root.currentWallpaperId || (root.currentWallpaper && root.currentWallpaper.id) || "").trim();
        if (currentId && Wallhaven.diskCacheSlotForId(_diskCacheIndex, currentId) >= 0) {
            engine.displayWallpaper(Wallhaven.makeCachedWallpaper(currentId), Wallhaven.thumbUrlForId(currentId), true);
            return true;
        }
        if (cfg.DiskCacheEnabled && engine.showNextCachedWallpaper(true, false, "")) {
            return true;
        }
        return false;
    }

    function activeWallpaperImage() {
        return activeIsForeground ? foregroundImage : backgroundImage;
    }

    function wallpaperIsVisible() {
        // Stuck fade-through-black overlay hides whatever Image reports as Ready.
        if (fadeBlackOverlay.opacity > 0.5) {
            return false;
        }
        if (backgroundLayer.opacity < 0.15 && foregroundLayer.opacity < 0.15) {
            return false;
        }
        var img = activeWallpaperImage();
        if (!root.currentUrl || !img || img.status !== Image.Ready) {
            return false;
        }
        // Note: do not require paintedWidth — with layer effects / async decode Qt
        // often reports Ready with paintedWidth 0, which falsely looked "blank"
        // and drove recovery/cache-advance storms.
        return String(img.source || "") !== "";
    }

    function ensureWallpaperVisible(reason) {
        if (wallpaperIsVisible()) {
            return true;
        }
        logDebug("ensureWallpaperVisible(" + reason + ")");
        if (root.currentUrl && reloadCurrentImage()) {
            return true;
        }
        return bootstrapWallpaperFromCache();
    }

    function wallpaperLooksStuckBlank() {
        if (!root.currentUrl) {
            return false;
        }
        // Fade-through-black that never finishes used to block the watchdog forever.
        if (fadeBlackOut.running) {
            var fadeBudget = Math.max(5000, (cfg.CrossfadeMs || 800) * 3);
            if (root._fadeBlackStartedMs > 0
                    && (Date.now() - root._fadeBlackStartedMs) > fadeBudget) {
                return true;
            }
            return false;
        }
        if (fadeBlackOverlay.opacity > 0.85) {
            return true;
        }
        if (backgroundLayer.opacity < 0.05 && foregroundLayer.opacity < 0.05) {
            return true;
        }
        var img = activeWallpaperImage();
        if (!img) {
            return true;
        }
        if (img.status === Image.Error) {
            return true;
        }
        // Still decoding — allow a window, then treat hung loads as stuck.
        if (img.status === Image.Loading) {
            if (root._imageLoadStartedMs > 0
                    && (Date.now() - root._imageLoadStartedMs) > 12000) {
                return true;
            }
            return false;
        }
        if (String(img.source || "") === "") {
            return true;
        }
        return false;
    }

    // Recover a blank frame without treating it as a full sleep/wake cycle.
    function recoverBlankFrame(reason) {
        var now = Date.now();
        // Throttle so a permanently missing file cannot spin every watchdog tick.
        if (root._lastBlankRecoverMs > 0 && (now - root._lastBlankRecoverMs) < 12000) {
            return false;
        }
        root._lastBlankRecoverMs = now;
        logDebug("recoverBlankFrame: " + reason);
        if (fadeBlackOut.running) {
            fadeBlackOut.stop();
        }
        fadeBlackOverlay.opacity = 0;
        // Only reload the current frame. Advancing cache here raced with offline
        // error handling and burned through every cached wallpaper.
        if (reloadCurrentImage()) {
            return true;
        }
        if (!root.currentUrl) {
            return bootstrapWallpaperFromCache();
        }
        return false;
    }

    function recoverAfterWake(reason) {
        logDebug("recoverAfterWake: " + reason);
        root._needsReconnectFetch = true;
        // Force the next successful connectivity check through retryAfterReconnect.
        root._connectivityOnline = false;
        if (fadeBlackOut.running) {
            fadeBlackOut.stop();
        }
        fadeBlackOverlay.opacity = 0;
        // Always hard-reload: Image.Ready can lie after compositor texture loss.
        clearWallpaperImageSources();
        resetWallpaperLayerVisibility();
        if (!reloadCurrentImage() && !bootstrapWallpaperFromCache()) {
            engine.showStatus(i18n("Restoring wallpaper after sleep…"), "info");
        }
        wakeConnectivityBurst.restart();
    }

    function openSaveWallpaperDialog() {
        if (currentSaveUrl === "") {
            engine.showStatus(i18n("No wallpaper available to save."), "warn");
            return;
        }
        var pictures = StandardPaths.writableLocation(StandardPaths.PicturesLocation);
        if (!pictures) {
            pictures = StandardPaths.writableLocation(StandardPaths.HomeLocation);
        }
        var folderUrl = "file://" + pictures;
        var fileName = "wallhaven-" + currentWallpaperId + ".png";
        saveDialog.currentFolder = folderUrl;
        saveDialog.selectedFile = folderUrl + "/" + fileName;
        saveDialog.open();
    }

    function saveCurrentWallpaper(destUrl) {
        var destPath = urlToLocalPath(destUrl);
        if (!destPath) {
            engine.showStatus(i18n("Could not save wallpaper."), "error");
            return;
        }
        if (destPath.indexOf(".") === -1) {
            destPath += ".png";
        }

        engine.showStatus(i18n("Saving wallpaper…"), "info", false);
        saveSourceImage.pendingPath = destPath;
        // Force reload even if the same source was used before.
        saveSourceImage.source = "";
        saveSourceImage.source = currentSaveUrl;
    }

    QtObject {
        id: engine

        property var apiData: null
        property string randomSeed: Wallhaven.createRandomSeed()
        property int page: 1
        property int index: 0
        property int lastPage: 0
        property int total: 0
        property int totalShown: 0
        property var usedIndices: []
        property var seenIds: []
        property var blockedIds: []
        property var history: []
        property int historyIndex: -1
        property string searchQuery: ""
        property string favoritesUser: ""
        property string favoritesId: ""
        property bool busy: false
        property string nextPreloadedUrl: ""
        property int cachedApiPage: 0
        property int requestId: 0
        property var activeXhrs: []

        function invalidateRequests() {
            requestId++;
            for (var i = 0; i < activeXhrs.length; i++) {
                try {
                    activeXhrs[i].abort();
                } catch (e) {
                }
            }
            activeXhrs = [];
        }

        function endBusy() {
            busy = false;
            root.loading = false;
            // Prefer explicit nav over a pending sync follower — never flush both
            // (that double-advanced and desynced monitors).
            if (root._pendingControlCmd) {
                var pending = root._pendingControlCmd;
                root._pendingControlCmd = null;
                root._pendingSyncAdvance = false;
                root._pendingSyncAdvanceAt = 0;
                Qt.callLater(function() {
                    if (!busy) {
                        root.handleControlCommand(pending);
                    } else {
                        root._pendingControlCmd = pending;
                    }
                });
                return;
            }
            if (root._pendingSyncAdvance) {
                var at = root._pendingSyncAdvanceAt;
                root._pendingSyncAdvance = false;
                root._pendingSyncAdvanceAt = 0;
                if (at > root._lastSyncAdvanceTs) {
                    Qt.callLater(function() {
                        if (busy) {
                            // Do not stamp the watermark until the skip actually runs.
                            root._pendingSyncAdvance = true;
                            root._pendingSyncAdvanceAt = Math.max(
                                root._pendingSyncAdvanceAt || 0,
                                at,
                            );
                            return;
                        }
                        root._lastSyncAdvanceTs = Math.max(root._lastSyncAdvanceTs, at);
                        // fromSync=true: do not rebroadcast (echo storm).
                        skipForward(true);
                    });
                }
            }
        }

        function stopRetries() {
            retryTimer.stop();
            root._retryOnDone = null;
            root._retryRequestId = 0;
        }

        function resumeRetryFetch() {
            var onDone = root._retryOnDone;
            var expectedId = root._retryRequestId;
            if (!onDone) {
                return;
            }
            if (busy) {
                // One-shot timer used to discard the retry forever while busy.
                retryTimer.interval = 2000;
                retryTimer.restart();
                return;
            }
            // Request was superseded (skip / reset) — drop the deferred retry.
            if (expectedId !== requestId) {
                root._retryOnDone = null;
                root._retryRequestId = 0;
                return;
            }
            if (root.effectiveOfflineOnly()) {
                root._retryOnDone = null;
                root._retryRequestId = 0;
                showOfflineWallpaper(false, true);
                return;
            }
            busy = true;
            root.loading = true;
            fetchApiData(onDone, expectedId);
        }

        function warmCache(count, onDone) {
            count = Math.max(1, Math.min(48, parseInt(count, 10) || 12));
            if (root._warmActive) {
                showStatus(i18n("Cache warm already in progress (%1 / %2).", root._warmDone, root._warmTarget), "info");
                return;
            }
            var warmed = 0;
            var skipped = 0;
            root._warmActive = true;
            root._warmDone = 0;
            root._warmTarget = count;
            root._warmCancelRequested = false;
            root.publishStatus();
            function finishWarm() {
                root._warmActive = false;
                root._warmCancelRequested = false;
                root.publishStatus();
                if (onDone)
                    onDone(warmed);
            }
            fetchApiData(function(json) {
                if (!json || !json.data || !json.data.length) {
                    showStatus(i18n("Could not warm cache — no API results."), "warn");
                    finishWarm();
                    return;
                }
                var data = json.data;
                var i = 0;
                function step() {
                    if (root._warmCancelRequested) {
                        showStatus(i18n("Cache warm cancelled (%1 new).", warmed), "info");
                        finishWarm();
                        return;
                    }
                    while (i < data.length && warmed + skipped < count * 3 && warmed < count) {
                        var wp = data[i++];
                        if (!wp || !wp.id) {
                            continue;
                        }
                        var id = String(wp.id);
                        if (Wallhaven.diskCacheSlotForId(root._diskCacheIndex, id) >= 0) {
                            skipped++;
                            continue;
                        }
                        var slot = Wallhaven.allocateDiskCacheSlot(
                            root._diskCacheIndex,
                            id,
                            root.diskCacheMaxSlots(),
                            root.pinnedCacheIds(),
                            wp.category || "",
                            wp.purity || "",
                        );
                        if (slot < 0) {
                            skipped++;
                            continue;
                        }
                        Wallhaven.setDiskCacheDimensions(
                            root._diskCacheIndex,
                            id,
                            wp.dimension_x,
                            wp.dimension_y,
                        );
                        var path = root.diskCacheLocalPath(slot);
                        var url = Wallhaven.wallpaperUrl(wp, cfg.ImageQuality);
                        showStatus(i18n("Warming… %1 / %2", warmed + 1, count), "info");
                        dbusHelper.runArgv([
                            "curl", "-fsSL", "--max-time", "90", "-o", path, url,
                        ], function(reply) {
                            if (root._warmCancelRequested) {
                                showStatus(i18n("Cache warm cancelled (%1 new).", warmed), "info");
                                finishWarm();
                                return;
                            }
                            var text = String(reply || "").trim();
                            if (text !== "ok") {
                                Wallhaven.releaseDiskCacheId(root._diskCacheIndex, id);
                                root.persistDiskCacheIndex();
                                skipped++;
                                step();
                                return;
                            }
                            dbusHelper.runArgv([
                                "test", "-s", path,
                            ], function(sizeReply) {
                                if (root._warmCancelRequested) {
                                    showStatus(i18n("Cache warm cancelled (%1 new).", warmed), "info");
                                    finishWarm();
                                    return;
                                }
                                var sizeOk = String(sizeReply || "").trim();
                                if (sizeOk !== "ok") {
                                    Wallhaven.releaseDiskCacheId(root._diskCacheIndex, id);
                                    root.persistDiskCacheIndex();
                                    skipped++;
                                    step();
                                    return;
                                }
                                warmed++;
                                root._warmDone = warmed;
                                root.persistDiskCacheIndex();
                                root.publishStatus();
                                step();
                            });
                        });
                        return;
                    }
                    showStatus(
                        i18n("Cache warm finished: %1 new, %2 already cached.", warmed, skipped),
                        "info",
                    );
                    finishWarm();
                }
                step();
            });
        }
        function applyState(state) {
            page = state.page;
            index = state.index;
            usedIndices = state.usedIndices;
            searchQuery = state.searchQuery;
            favoritesUser = state.favoritesUser;
            favoritesId = state.favoritesId;
        }

        function loadBlockedIds() {
            if (!root.configuration) {
                blockedIds = [];
                return;
            }
            blockedIds = Wallhaven.parseBlockedIds(root.configuration.BlockedIdsJson || "[]");
        }

        function persistBlockedIds() {
            if (!root.configuration) {
                return;
            }
            root.configuration.BlockedIdsJson = Wallhaven.serializeBlockedIds(blockedIds);
            root.scheduleConfigWrite();
        }

        function blockId(id) {
            blockedIds = Wallhaven.addBlockedId(blockedIds, id);
            persistBlockedIds();
        }

        function loadSeenIds() {
            if (!root.configuration) {
                return;
            }
            seenIds = Wallhaven.parseSeenIds(root.configuration.SeenIdsJson || "[]");
        }

        function persistSeenIds() {
            if (!root.configuration) {
                return;
            }
            root.configuration.SeenIdsJson = Wallhaven.serializeSeenIds(seenIds);
            root.scheduleConfigWrite();
        }

        function clearSeenIds() {
            seenIds = [];
            persistSeenIds();
        }

        function resetSlideshow() {
            stopRetries();
            invalidateRequests();
            endBusy();
            root._fetchRetryCount = 0;
            root._imageErrorCount = 0;
            root._cacheErrorSkipCount = 0;
            randomSeed = Wallhaven.createRandomSeed();
            page = 1;
            index = 0;
            lastPage = 0;
            total = 0;
            totalShown = 0;
            usedIndices = [];
            // Keep seen IDs across routine resets (rate-limit recovery, interval
            // restarts, plasmashell redeploys). Only clear when the search /
            // filter identity actually changes — otherwise Sortings=views +
            // PreferSharpMatches on a portrait screen re-shows the same top hits.
            var fp = Wallhaven.searchDedupeFingerprint(configObject());
            if (fp !== root._dedupeFingerprint) {
                root._dedupeFingerprint = fp;
                clearSeenIds();
            }
            history = [];
            historyIndex = -1;
            apiData = null;
            searchQuery = "";
            favoritesUser = "";
            favoritesId = "";
            nextPreloadedUrl = "";
            cachedApiPage = 0;
            if (root.isRateLimitedNow() || root._apiOutageOffline) {
                // Stay on the current frame during cooldown — advancing cache on
                // every reset was the visible "jump through wallpapers" symptom.
                if (!root.wallpaperIsVisible()) {
                    showOfflineWallpaper(false, true);
                }
                return;
            }
            fetchFreshWallpaper(false);
        }

        function fetchFreshWallpaper(fromHistory) {
            if (root.effectiveOfflineOnly()) {
                // Prefer holding the current image during soft-offline; only pull
                // from cache when the screen would otherwise be empty.
                if (root.wallpaperIsVisible() && (root.isRateLimitedNow() || root._apiOutageOffline)) {
                    return;
                }
                showOfflineWallpaper(fromHistory, true);
                return;
            }
            if (busy) {
                return;
            }
            invalidateRequests();
            busy = true;
            root.loading = true;

            var activeRequest = requestId;

            function finish(wallpaper, url) {
                if (activeRequest !== requestId) {
                    return;
                }
                if (!wallpaper || !url) {
                    if (tryOfflineFallback(i18n("Could not load wallpaper. Showing cached wallpaper."))) {
                        endBusy();
                        return;
                    }
                    showStatus(i18n("Could not load wallpaper."), "warn");
                    endBusy();
                    return;
                }
                markSeen(wallpaper.id);
                if (!fromHistory) {
                    pushHistory({
                        wallpaper: wallpaper,
                        url: url,
                        index: index,
                        page: page,
                    });
                }
                showStatus("");
                displayWallpaper(wallpaper, url, true);
                notifyRefresh(wallpaper);
                preloadNext();
                endBusy();
            }

            function processData(data) {
                if (activeRequest !== requestId) {
                    return;
                }
                if (!data || !data.data || !data.data.length) {
                    var emptyMsg = i18n("No wallpapers match your current filters.");
                    if (!root.wallpaperIsVisible()) {
                        if (tryOfflineFallback(emptyMsg) || root.bootstrapWallpaperFromCache()) {
                            showStatus(emptyMsg, "warn", true, { notify: false });
                            endBusy();
                            return;
                        }
                    }
                    showStatus(emptyMsg, "warn", true, { notify: false });
                    endBusy();
                    return;
                }

                var state = stateObject();
                var wallpaper = Wallhaven.pickWallpaper(configObject(), state, data.data, true);
                if (!wallpaper) {
                    var noMoreMsg = i18n("No more wallpapers match your current filters.");
                    if (!root.wallpaperIsVisible()) {
                        if (tryOfflineFallback(noMoreMsg) || root.bootstrapWallpaperFromCache()) {
                            showStatus(noMoreMsg, "warn", true, { notify: false });
                            endBusy();
                            return;
                        }
                    }
                    showStatus(noMoreMsg, "warn", true, { notify: false });
                    endBusy();
                    return;
                }

                applyState(state);
                totalShown++;
                var url = Wallhaven.wallpaperUrl(wallpaper, cfg.ImageQuality);
                finish(wallpaper, url);
            }

            fetchApiData(processData, activeRequest);
        }

        function configObject() {
            return {
                SearchText: cfg.SearchText,
                ApiKey: cfg.ApiKey,
                BrowseMode: cfg.BrowseMode,
                CollectionUser: cfg.CollectionUser,
                CollectionId: cfg.CollectionId,
                Sortings: cfg.Sortings,
                LocalSortings: cfg.LocalSortings,
                Order: cfg.Order,
                CategoryGeneral: cfg.CategoryGeneral,
                CategoryAnime: cfg.CategoryAnime,
                CategoryPeople: cfg.CategoryPeople,
                PuritySfw: cfg.PuritySfw,
                PuritySketchy: cfg.PuritySketchy,
                PurityNsfw: cfg.PurityNsfw,
                MinWidth: cfg.MinWidth,
                MinHeight: cfg.MinHeight,
                Ratio: cfg.Ratio,
                ColorFilter: cfg.ColorFilter,
                TopRange: cfg.TopRange,
                ExactResolutions: cfg.ExactResolutions,
                UseBlacklist: cfg.UseBlacklist,
                DedupEnabled: cfg.DedupEnabled,
                TimeOfDayEnabled: cfg.TimeOfDayEnabled,
                DaySearch: cfg.DaySearch,
                NightSearch: cfg.NightSearch,
                OfflineOnlyMode: cfg.OfflineOnlyMode,
                MeteredCacheOnly: cfg.MeteredCacheOnly,
                FileTypeFilter: cfg.FileTypeFilter,
                TagBlocklistJson: cfg.TagBlocklistJson,
                ScheduleEnabled: cfg.ScheduleEnabled,
                WeekdaySearch: cfg.WeekdaySearch,
                WeekendSearch: cfg.WeekendSearch,
                CollectionRotationEnabled: cfg.CollectionRotationEnabled,
                CollectionRotationJson: cfg.CollectionRotationJson,
                CollectionRotationIndex: cfg.CollectionRotationIndex,
                WallpaperOfDayEnabled: cfg.WallpaperOfDayEnabled,
                TagFavoritesJson: cfg.TagFavoritesJson,
                PreferSharpMatches: cfg.PreferSharpMatches,
                WeatherReactiveEnabled: cfg.WeatherReactiveEnabled,
                WeatherTagCache: cfg.WeatherTagCache,
                SimilarSourceId: (cfg.BrowseMode === "similar" && root.currentWallpaperId !== "wallpaper")
                    ? String(root.currentWallpaperId) : "",
                SmartOfflineEnabled: cfg.SmartOfflineEnabled,
                SmartOfflineDayAware: cfg.SmartOfflineDayAware,
                OfflineTagQuery: cfg.OfflineTagQuery,
                OfflinePlaylistPinnedOnly: cfg.OfflinePlaylistPinnedOnly,
                PinnedCacheIdsJson: cfg.PinnedCacheIdsJson,
                LocalFolderPath: cfg.LocalFolderPath,
                LocalFolderMaxDepth: cfg.LocalFolderMaxDepth,
                LocalFolderExclude: cfg.LocalFolderExclude,
            };
        }

        function stateObject() {
            return {
                page: page,
                index: index,
                seed: randomSeed,
                lastPage: lastPage,
                total: total,
                totalShown: totalShown,
                usedIndices: usedIndices.slice(),
                seenIds: seenIds.slice(),
                blockedIds: blockedIds.slice(),
                screenWidth: Math.round(root.width) || 1920,
                screenHeight: Math.round(root.height) || 1080,
                searchQuery: searchQuery,
                favoritesUser: favoritesUser,
                favoritesId: favoritesId,
                systemAccentHex: root.systemAccentHex,
            };
        }

        function showStatus(message, type, autoHide, opts) {
            opts = opts || {};
            type = type || "info";
            root.statusMessage = message;
            root.statusType = type;
            var showBanner = cfg.ShowStatusBanner !== false;
            root.statusVisible = showBanner && message !== "";
            if (autoHide !== false && message !== "" && showBanner) {
                statusHideTimer.restart();
            }
            if (message && (type === "error" || type === "warn") && cfg.NotifyOnError && opts.notify !== false) {
                root.sendSystemNotification(i18n("Wallhaven"), message, true);
            }
            if (message) {
                root.logDebug(type + ": " + message);
            }
        }

        function notifyRefresh(wallpaper) {
            if (wallpaper) {
                root.recordWallpaperViewed();
            }
            if (!cfg.NotifyOnRefresh || !wallpaper) {
                return;
            }
            var resolution = wallpaper.resolution || (wallpaper.dimension_x + "x" + wallpaper.dimension_y);
            var text = i18n("Wallpaper #%1", wallpaper.id);
            if (resolution) {
                text += " · " + resolution;
            }
            root.sendSystemNotification(i18n("Wallhaven"), text, false);
        }

        function scheduleRetry(delayMs, statusCode, onDone, expectedRequestId) {
            var baseSec = Math.max(1, cfg.RetryDelaySec || 15);
            var delay = delayMs;
            if (!delay || delay < 1000) {
                delay = baseSec * 1000;
            }
            delay = Math.max(1000, Math.min(delay, 300000));
            retryTimer.interval = delay;
            var seconds = Math.round(delay / 1000);
            var attempt = root._fetchRetryCount;
            var maxAttempts = Math.max(1, cfg.RetryAttempts || 5);
            // Retries stay on the desktop banner only — multi-monitor used to
            // flood the tray with identical rate-limit / timeout notices.
            var opts = { notify: false };
            var msg;
            if (statusCode === 429) {
                msg = i18n("Rate limited by Wallhaven. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds);
            } else if (statusCode === 0) {
                msg = i18n("Request timed out. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds);
            } else {
                msg = i18n("Request failed (%1). Retry %2/%3 in %4s…", statusCode, attempt, maxAttempts, seconds);
            }
            root._retryOnDone = onDone;
            root._retryRequestId = expectedRequestId;
            // Keep the current wallpaper (or one cached frame) while we back off.
            // Do not advance the slideshow here — retryTimer resumes the same fetch.
            if (engine.tryOfflineFallback(msg)) {
                // tryOfflineFallback already set the combined status banner.
            } else {
                showStatus(msg, "error", false, opts);
            }
            retryTimer.restart();
        }

        function requestJson(url, onSuccess, onError, options) {
            options = options || {};
            var quiet = !!options.quiet;
            var xhr = new XMLHttpRequest();
            var settled = false;
            activeXhrs.push(xhr);

            function finishXhr() {
                var idx = activeXhrs.indexOf(xhr);
                if (idx !== -1) {
                    activeXhrs.splice(idx, 1);
                }
            }

            function settleError(status, text, rateDelayMs) {
                if (settled) {
                    return;
                }
                settled = true;
                finishXhr();
                // Attribution/detail probes must not drive search outage / latch state.
                if (!quiet) {
                    root.noteApiResult(status, text);
                } else if (status === 429) {
                    // Still honor rate limits discovered via detail fetches.
                    root.noteApiResult(429, text);
                    root.enterApiOutageOffline(429, rateDelayMs);
                }
                if (status === 0) {
                    root._needsReconnectFetch = true;
                    root._connectivityOnline = false;
                }
                onError(status, text, rateDelayMs || 0);
            }

            function settleSuccess(json) {
                if (settled) {
                    return;
                }
                settled = true;
                finishXhr();
                if (!quiet) {
                    root.noteApiResult(200, "");
                }
                onSuccess(json);
            }

            xhr.open("GET", url);
            xhr.setRequestHeader("Accept", "application/json");
            xhr.timeout = Math.max(5, cfg.RequestTimeoutSec || 30) * 1000;
            xhr.ontimeout = function() {
                settleError(0, "timeout");
            };
            xhr.onerror = function() {
                settleError(0, "network error");
            };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }
                if (xhr.status === 200) {
                    try {
                        settleSuccess(JSON.parse(xhr.responseText));
                    } catch (e) {
                        settleError(0, "invalid json");
                    }
                } else {
                    var rateDelay = Wallhaven.parseRateLimitDelayMs(xhr, xhr.status);
                    settleError(xhr.status, xhr.statusText || "", rateDelay);
                }
            };
            xhr.send();
        }

        function buildBlacklistQuery(callback) {
            var config = configObject();
            if (config.BrowseMode === "similar") {
                var sid = root.currentWallpaperId;
                if (!sid || sid === "wallpaper") {
                    showStatus(i18n("More-like-current mode needs a wallpaper on screen first."), "warn");
                    searchQuery = "";
                    callback();
                    return;
                }
                searchQuery = Wallhaven.buildSimilarSearchQuery(sid);
                callback();
                return;
            }
            var base = Wallhaven.getEffectiveSearchText(config);
            if (!config.UseBlacklist || !config.ApiKey) {
                searchQuery = base;
                callback();
                return;
            }
            requestJson(Wallhaven.buildSettingsUrl(config.ApiKey), function(json) {
                var blacklist = json.data && json.data.tag_blacklist ? json.data.tag_blacklist : [];
                var query = base;
                for (var i = 0; i < blacklist.length; i++) {
                    if (blacklist[i]) {
                        query += " -" + String(blacklist[i]).trim().replace(/\s+/g, "_");
                    }
                }
                searchQuery = query.trim();
                callback();
            }, function() {
                searchQuery = base;
                callback();
            });
        }

        function resolveFavorites(callback) {
            var config = configObject();
            if (!config.ApiKey) {
                showStatus(i18n("API key required for favorites mode."), "error");
                endBusy();
                return;
            }
            requestJson(Wallhaven.buildCollectionsUrl(config.ApiKey), function(json) {
                var favorite = null;
                if (json.data && json.data.length) {
                    for (var i = 0; i < json.data.length; i++) {
                        if (json.data[i].label && json.data[i].label.toLowerCase() === "favorites") {
                            favorite = json.data[i];
                            break;
                        }
                    }
                    if (!favorite) {
                        favorite = json.data[0];
                    }
                }
                if (!favorite) {
                    showStatus(i18n("No favorites collection found."), "error");
                    endBusy();
                    return;
                }
                favoritesUser = config.CollectionUser
                    || favorite.username
                    || (favorite.user && favorite.user.username)
                    || favorite.user
                    || "";
                favoritesId = String(favorite.id);
                callback();
            }, function(status) {
                showStatus(i18n("Failed to load favorites (%1).", status), "error");
                endBusy();
            });
        }

        function fetchApiData(onDone, expectedRequestId) {
            var config = configObject();
            var fetchRequestId = expectedRequestId !== undefined ? expectedRequestId : requestId;

            // Soft-offline (rate-limit / outage latch) must short-circuit here too —
            // otherwise warmCache and resume paths keep hitting /api/v1.
            if (root.isRateLimitedNow() || root._apiOutageOffline || config.OfflineOnlyMode
                    || config.BrowseMode === "playlist"
                    || config.BrowseMode === "local"
                    || (config.MeteredCacheOnly && root.meteredConnection)) {
                onDone(null);
                return;
            }

            function isStale() {
                return fetchRequestId !== requestId;
            }

            function doFetch() {
                if (isStale()) {
                    endBusy();
                    return;
                }
                var url;
                var collectionUser = config.CollectionUser;
                var collectionId = config.CollectionId;
                if (config.BrowseMode === "collection" && config.CollectionRotationEnabled) {
                    var entries = Wallhaven.parseCollectionRotation(config.CollectionRotationJson || "[]");
                    var pick = Wallhaven.pickCollectionRotation(
                        entries,
                        config.CollectionRotationIndex || 0,
                    );
                    if (pick) {
                        collectionUser = pick.entry.user;
                        collectionId = pick.entry.id;
                    }
                }
                if (config.BrowseMode === "collection") {
                    if (!collectionUser || !collectionId) {
                        showStatus(i18n("Collection username and ID are required."), "error");
                        endBusy();
                        return;
                    }
                    var rotConfig = configObject();
                    rotConfig.CollectionUser = collectionUser;
                    rotConfig.CollectionId = collectionId;
                    url = Wallhaven.buildCollectionUrl(rotConfig, stateObject());
                } else if (config.BrowseMode === "favorites") {
                    url = Wallhaven.buildCollectionUrl(config, stateObject());
                } else {
                    url = Wallhaven.buildSearchUrl(config, stateObject());
                }

                requestJson(url, function(json) {
                    if (isStale()) {
                        endBusy();
                        return;
                    }
                    if (!json.data || !json.data.length) {
                        showStatus(i18n("No wallpapers match your current filters."), "warn", true, { notify: false });
                        endBusy();
                        onDone(null);
                        return;
                    }
                    json.data = Wallhaven.filterWallpapersByBlocklist(json.data, blockedIds);
                    if (!json.data.length) {
                        showStatus(i18n("All results are blocked. Clear the blocklist or try another search."), "warn", true, { notify: false });
                        endBusy();
                        onDone(null);
                        return;
                    }
                    json.data = Wallhaven.filterWallpapersByCategories(json.data, config);
                    if (!json.data.length) {
                        showStatus(i18n("No wallpapers match your current filters."), "warn", true, { notify: false });
                        endBusy();
                        onDone(null);
                        return;
                    }
                    root._fetchRetryCount = 0;
                    root._retryOnDone = null;
                    root._retryRequestId = 0;
                    apiData = json;
                    lastPage = json.meta.last_page;
                    total = json.meta.total;
                    cachedApiPage = page;
                    onDone(json);
                }, function(status, text, rateDelayMs) {
                    if (isStale()) {
                        // Drop the callback — a newer request owns the UI now.
                        return;
                    }
                    // Hard outages: stop hammering Wallhaven and stay on cache.
                    if (status === 502 || status === 503 || status === 504) {
                        root._retryOnDone = null;
                        root.enterApiOutageOffline(status);
                        endBusy();
                        return;
                    }
                    // Rate limit: soft-offline immediately. Retrying / skipForward
                    // storms made the left monitor jump through cache, and a
                    // favicon "online" check used to clear that latch every 45s.
                    if (status === 429) {
                        root._retryOnDone = null;
                        root._fetchRetryCount = 0;
                        root.enterApiOutageOffline(429, rateDelayMs);
                        endBusy();
                        return;
                    }
                    root._fetchRetryCount++;
                    var maxAttempts = Math.max(1, cfg.RetryAttempts || 5);
                    var baseSec = Math.max(1, cfg.RetryDelaySec || 15);
                    if (root._fetchRetryCount > maxAttempts) {
                        root._retryOnDone = null;
                        if (status === 0 || status >= 500) {
                            root.enterApiOutageOffline(status);
                            endBusy();
                            return;
                        }
                        var finalMsg = i18n("Wallhaven request failed after %1 attempts.", maxAttempts);
                        if (status)
                            finalMsg = i18n("Request failed (%1). Showing cached wallpaper.", status);
                        if (engine.tryOfflineFallback(finalMsg)) {
                            return;
                        }
                        showStatus(i18n("Wallhaven request failed after %1 attempts.", maxAttempts), "error");
                        endBusy();
                        return;
                    }
                    var delay = rateDelayMs > 0
                        ? rateDelayMs
                        : baseSec * 1000 * Math.pow(2, Math.min(root._fetchRetryCount - 1, 3));
                    delay = Math.min(delay, 300000);
                    // Resume the same onDone after backoff — do not treat this as
                    // an empty result set (that produced a false "no match" banner).
                    scheduleRetry(delay, status, onDone, fetchRequestId);
                    endBusy();
                });
            }

            if (config.BrowseMode === "favorites" && !favoritesId) {
                resolveFavorites(doFetch);
                return;
            }
            if (config.BrowseMode === "search") {
                buildBlacklistQuery(doFetch);
                return;
            }
            doFetch();
        }

        function markSeen(id) {
            if (!cfg.DedupEnabled || !id) {
                return;
            }
            var idStr = String(id);
            if (seenIds.indexOf(idStr) === -1) {
                seenIds.push(idStr);
                if (seenIds.length > 500) {
                    seenIds = seenIds.slice(-500);
                }
                persistSeenIds();
            }
        }

        function updateAttribution(wallpaper) {
            if (!wallpaper) {
                root.attributionText = "";
                root._currentTags = "";
                root.syncPreviewMetadata(null);
                return;
            }
            var resolution = wallpaper.resolution || (wallpaper.dimension_x + "x" + wallpaper.dimension_y);
            var link = wallpaper.url || ("https://wallhaven.cc/w/" + wallpaper.id);
            root.attributionText = "Wallhaven #" + wallpaper.id + "\n"
                + resolution + " · " + wallpaper.category + " · " + wallpaper.purity + "\n"
                + link;
            root._currentTags = "";
            root.syncPreviewMetadata(wallpaper);

            if (!cfg.ShowAttribution && !cfg.ApiKey) {
                return;
            }
            // Do not probe /w/{id} while rate-limited — those calls were clearing
            // the shared latch on 200 and accelerating the 429 storm.
            if (root.isRateLimitedNow() || root._apiOutageOffline) {
                return;
            }

            requestJson(Wallhaven.buildWallpaperUrl(wallpaper.id, cfg.ApiKey), function(json) {
                if (!json.data) {
                    return;
                }
                root._currentTags = Wallhaven.tagsToCopyString(json.data.tags);
                root.wallpaperDetailsText = Wallhaven.formatWallpaperDetails(wallpaper, json.data);
                root.wallpaperDetailsResolution = resolution;
                root.wallpaperDetailsPurity = String(json.data.purity || wallpaper.purity || "");
                root.wallpaperDetailsCategory = String(json.data.category || wallpaper.category || "");
                root.publishStatus();
                if (root.configuration) {
                    root.configuration.PreviewWallpaperDetails = root.wallpaperDetailsText;
                    scheduleConfigWrite();
                }
                var tint = Wallhaven.dominantColorFromWallhaven(json.data.colors);
                if (tint) {
                    root.writePanelTint(tint, wallpaper.id);
                    root.applySmartColorFilter(tint);
                }
                var tags = Wallhaven.formatTags(json.data.tags);
                if (tags) {
                    root.attributionText = "Wallhaven #" + wallpaper.id + "\n"
                        + resolution + " · " + wallpaper.category + " · " + wallpaper.purity + "\n"
                        + tags + "\n" + link;
                    root.syncPreviewMetadata(wallpaper);
                }
            }, function() {}, { quiet: true });
        }

        function displayWallpaper(wallpaper, url, immediate) {
            if (!url) {
                return false;
            }
            root.currentWallpaper = wallpaper;
            root._pendingRemoteUrl = url;
            root._pendingWallpaperId = wallpaper && wallpaper.id ? String(wallpaper.id) : "";
            var source = root.resolveImageSource(wallpaper, url);
            if (!source) {
                // Soft-offline with no local file — caller should pick another id.
                return false;
            }
            root._pendingUsedCache = source.indexOf("file:") === 0;
            _metrics = Wallhaven.recordFetchMetrics(_metrics, 0, root._pendingUsedCache);
            root.showImage(source, immediate);
            updateAttribution(wallpaper);
            writeVarietyMetadata(wallpaper, url);
            root.publishStatus();
            kenBurnsAnimation.restart();
            return true;
        }

        function pushHistory(entry) {
            history = history.slice(0, historyIndex + 1);
            history.push(entry);
            if (history.length > 50) {
                history.shift();
                historyIndex--;
            }
            historyIndex = history.length - 1;
            if (entry && entry.wallpaper) {
                root.persistWallpaperHistory(entry.wallpaper);
            }
        }

        function maybeAdvanceCollectionRotation() {
            if (cfg.BrowseMode !== "collection" || !cfg.CollectionRotationEnabled || !root.configuration) {
                return;
            }
            var entries = Wallhaven.parseCollectionRotation(cfg.CollectionRotationJson || "[]");
            if (entries.length < 2) {
                return;
            }
            var next = ((cfg.CollectionRotationIndex || 0) + 1) % entries.length;
            root.configuration.CollectionRotationIndex = next;
            root.scheduleConfigWrite();
            apiData = null;
            cachedApiPage = 0;
            page = 1;
            index = 0;
        }

        function tryOfflineFallback(statusOverride) {
            if (!cfg.DiskCacheEnabled) {
                return false;
            }
            if (!cfg.OfflineCacheFallback && !root.effectiveOfflineOnly()) {
                return false;
            }
            // Keep the current wallpaper during retries/outages only when it is
            // actually visible — a stale Error/blank currentUrl used to block
            // cache cycling and leave the desktop empty.
            var currentSrc = String(root.currentUrl || "");
            if (currentSrc && root.wallpaperIsVisible()) {
                if (statusOverride) {
                    showStatus(statusOverride, "error", false, { notify: false });
                }
                endBusy();
                return true;
            }
            if (showNextCachedWallpaper(true, false, statusOverride || "")) {
                endBusy();
                return true;
            }
            return false;
        }

        function showNextCachedWallpaper(immediate, fromHistory, statusOverride) {
            var now = Date.now();
            // Error/recovery paths used to call this in a tight loop under 429
            // soft-offline and burn through the whole disk cache in seconds.
            // Throttle whenever a recovery override is provided (including "").
            // Normal offline slideshow ticks omit the 3rd arg (undefined).
            if (Wallhaven.shouldThrottleCacheAdvance(
                    fromHistory, statusOverride, root._lastCacheAdvanceMs, now, 3000)) {
                // Not a successful advance — callers must not burn skip budget.
                return false;
            }
            var config = configObject();
            var attempts = 0;
            var maxAttempts = 12;
            while (attempts < maxAttempts) {
                attempts++;
                var pick = Wallhaven.pickSmartCachedId(
                    root._diskCacheIndex,
                    config,
                    root._offlineCacheCursor,
                    seenIds,
                );
                if (!pick.id) {
                    return false;
                }
                root._offlineCacheCursor = pick.cursor;
                var id = pick.id;
                var wp = Wallhaven.makeCachedWallpaper(id);
                var remote = Wallhaven.thumbUrlForId(id);
                // Probe resolve before committing history / status — soft-offline
                // skips ids that have no local file instead of painting a remote URL.
                if (!root.resolveImageSource(wp, remote)) {
                    markSeen(id);
                    continue;
                }
                root._lastCacheAdvanceMs = now;
                if (statusOverride) {
                    showStatus(statusOverride, "error", false, { notify: false });
                } else if (cfg.BrowseMode === "playlist") {
                    showStatus(i18n("Playlist — cached wallpaper."), "info");
                } else if (cfg.OfflineOnlyMode) {
                    showStatus(i18n("Offline mode — showing cached wallpaper."), "info");
                } else {
                    showStatus(i18n("Showing cached wallpaper (offline)."), "warn", true, { notify: false });
                }
                markSeen(id);
                if (!fromHistory) {
                    pushHistory({
                        wallpaper: wp,
                        url: remote,
                        index: index,
                        page: page,
                    });
                }
                // Always immediate while soft-offline — transitions + error retries raced.
                if (!displayWallpaper(wp, remote, true)) {
                    continue;
                }
                notifyRefresh(wp);
                return true;
            }
            return false;
        }

        function showOfflineWallpaper(fromHistory, immediate) {
            if (busy) {
                return;
            }
            if (cfg.BrowseMode === "local") {
                showLocalFolderWallpaper(fromHistory, immediate);
                return;
            }
            busy = true;
            root.loading = true;
            if (!showNextCachedWallpaper(immediate !== false, fromHistory)) {
                var emptyMsg = cfg.BrowseMode === "playlist"
                    ? (cfg.OfflinePlaylistPinnedOnly
                        ? i18n("Playlist is empty — pin wallpapers in the disk cache first.")
                        : i18n("Playlist is empty — enable disk cache and download some wallpapers first."))
                    : i18n("No cached wallpapers available.");
                showStatus(emptyMsg, "warn");
                if ((cfg.OfflineOnlyMode || cfg.BrowseMode === "playlist") && cfg.NotifyOnError) {
                    root.sendSystemNotification(
                        i18n("Wallhaven"),
                        emptyMsg,
                        true,
                    );
                }
            }
            endBusy();
        }

        function showLocalFolderWallpaper(fromHistory, immediate) {
            if (busy) {
                return;
            }
            busy = true;
            root.loading = true;
            var folder = String(cfg.LocalFolderPath || "").trim();
            if (!folder) {
                showStatus(i18n("Set a local folder path in Source settings."), "warn");
                endBusy();
                return;
            }
            dbusHelper.listImageFiles(folder, function(raw) {
                var paths = [];
                try {
                    paths = Wallhaven.listLocalImagePaths(
                        JSON.parse(raw || "[]"),
                        cfg.LocalFolderExclude,
                    );
                    paths = Wallhaven.orderLocalImagePaths(paths, cfg.LocalSortings);
                } catch (e) {
                    paths = [];
                }
                root._localImagePaths = paths;
                if (!paths.length) {
                    showStatus(i18n("No images found in the local folder."), "warn");
                    endBusy();
                    return;
                }
                if (cfg.LocalSortings === "random") {
                    root._localCursor = Math.floor(Math.random() * paths.length);
                } else {
                    root._localCursor = (root._localCursor + 1) % paths.length;
                }
                var path = paths[root._localCursor];
                var id = "local-" + String(root._localCursor);
                var wp = {
                    id: id,
                    path: path,
                    url: "file://" + path,
                    category: "local",
                    purity: "sfw",
                    dimension_x: 0,
                    dimension_y: 0,
                };
                showStatus(i18n("Local folder wallpaper."), "info");
                if (!fromHistory) {
                    pushHistory({
                        wallpaper: wp,
                        url: "file://" + path,
                        index: index,
                        page: page,
                    });
                }
                displayWallpaper(wp, "file://" + path, immediate !== false);
                notifyRefresh(wp);
                endBusy();
            });
        }

        function retryAfterReconnect() {
            if (busy) {
                return;
            }
            if (cfg.OfflineOnlyMode) {
                root.ensureWallpaperVisible("reconnect-offline");
                return;
            }
            root._needsReconnectFetch = false;
            showStatus(i18n("Network restored. Resuming…"), "info");
            // Prefer a visible cached frame over advancing into a flaky post-sleep
            // network fetch (that used to leave monitors blank).
            if (!root.wallpaperIsVisible()) {
                if (!root.bootstrapWallpaperFromCache()) {
                    fetchFreshWallpaper(false);
                    return;
                }
            } else {
                root.reloadCurrentImage();
            }
            if (root.isRateLimitedNow() || root._apiOutageOffline) {
                return;
            }
            // Soft online refresh once a frame is on screen.
            Qt.callLater(function() {
                if (!busy && !root.effectiveOfflineOnly()) {
                    fetchFreshWallpaper(false);
                }
            });
        }

        function preloadUrl(url) {
            if (!url) {
                return;
            }
            if (url !== nextPreloadedUrl) {
                nextPreloadedUrl = url;
                preloadImage.source = url;
            }
        }

        function preloadNext() {
            if (!apiData || !apiData.data || !apiData.data.length) {
                preloadImage2.source = "";
                return;
            }
            var state = stateObject();
            var count = Wallhaven.computePreloadCount(
                cfg,
                root._connectivityOnline,
                root.meteredConnection,
            );
            if (count <= 0) {
                preloadImage.source = "";
                preloadImage2.source = "";
                nextPreloadedUrl = "";
                return;
            }
            var ahead = Wallhaven.peekAheadWallpapers(configObject(), state, apiData.data, count);
            var urls = [];
            for (var i = 0; i < ahead.length; i++) {
                var remote = Wallhaven.wallpaperUrl(ahead[i], cfg.ImageQuality);
                var source = root.resolveImageSource(ahead[i], remote);
                if (source && urls.indexOf(source) === -1) {
                    urls.push(source);
                }
            }
            if (urls.length > 0) {
                preloadUrl(urls[0]);
            } else {
                preloadImage.source = "";
                nextPreloadedUrl = "";
            }
            preloadImage2.source = urls.length > 1 ? urls[1] : "";
        }

        function advanceToNextPage() {
            page++;
            var wrapped = false;
            if (lastPage > 0 && page > lastPage) {
                page = 1;
                randomSeed = Wallhaven.createRandomSeed();
                wrapped = true;
            }
            index = 0;
            usedIndices = [];
            // Only clear dedup when the catalog wraps, so duplicates stay avoided across pages.
            if (wrapped) {
                clearSeenIds();
            }
            apiData = null;
            cachedApiPage = 0;
        }

        function skipForward(fromSync) {
            stopRetries();
            // This advance satisfies queued nav/sync — clear without endBusy()
            // re-scheduling a second skip.
            root._pendingControlCmd = null;
            if (root._pendingSyncAdvance) {
                var pendingAt = root._pendingSyncAdvanceAt;
                root._pendingSyncAdvance = false;
                root._pendingSyncAdvanceAt = 0;
                if (pendingAt > root._lastSyncAdvanceTs) {
                    root._lastSyncAdvanceTs = pendingAt;
                }
            }
            busy = false;
            root.loading = false;
            // Followers must not rebroadcast — that ping-ponged sync ticks forever.
            if (Wallhaven.shouldBroadcastSyncAdvance(fromSync)) {
                root.broadcastSyncAdvance();
            }
            maybeAdvanceCollectionRotation();
            if (root.effectiveOfflineOnly()) {
                // During rate-limit cooldown, interval advances may rotate cache at
                // the normal slideshow pace — that is intentional. Rapid callers
                // (reset loops) are gated in fetchFreshWallpaper/resetSlideshow.
                showStatus(i18n("Loading next cached wallpaper…"), "info");
                showOfflineWallpaper(false, true);
                return;
            }
            showStatus(i18n("Loading next wallpaper…"), "info");
            nextWallpaper(false);
        }

        function nextWallpaper(fromHistory) {
            if (root.effectiveOfflineOnly()) {
                showOfflineWallpaper(fromHistory, false);
                return;
            }
            if (busy) {
                return;
            }
            invalidateRequests();
            busy = true;
            root.loading = true;

            var activeRequest = requestId;

            function finish(wallpaper, url) {
                if (activeRequest !== requestId) {
                    return;
                }
                if (!wallpaper || !url) {
                    if (tryOfflineFallback(i18n("Could not load the next wallpaper. Showing cached wallpaper."))) {
                        endBusy();
                        return;
                    }
                    showStatus(i18n("Could not load the next wallpaper."), "warn");
                    endBusy();
                    return;
                }
                markSeen(wallpaper.id);
                if (!fromHistory) {
                    pushHistory({
                        wallpaper: wallpaper,
                        url: url,
                        index: index,
                        page: page,
                    });
                }
                showStatus("");
                displayWallpaper(wallpaper, url, false);
                notifyRefresh(wallpaper);
                preloadNext();
                endBusy();
            }

            function processData(data, depth) {
                if (activeRequest !== requestId) {
                    return;
                }
                if (!data || !data.data || !data.data.length) {
                    if (depth > 0 && activeRequest === requestId) {
                        showStatus(i18n("No more wallpapers match your current filters."), "warn");
                    }
                    endBusy();
                    return;
                }

                depth = depth || 0;
                var state = stateObject();
                var result = Wallhaven.pickNextWallpaper(configObject(), state, data.data);

                if (!result.wallpaper) {
                    if (depth >= 20) {
                        clearSeenIds();
                        showStatus(i18n("No more wallpapers match your current filters."), "warn");
                        endBusy();
                        return;
                    }
                    advanceToNextPage();
                    fetchApiData(function(nextData) {
                        processData(nextData, depth + 1);
                    }, activeRequest);
                    return;
                }

                Wallhaven.updatePageState(configObject(), state, data.data.length);
                if (state.needsNewSeed) {
                    randomSeed = Wallhaven.createRandomSeed();
                    apiData = null;
                    cachedApiPage = 0;
                }
                if (state.needsSeenClear) {
                    clearSeenIds();
                }
                applyState(state);
                totalShown++;

                if (cachedApiPage !== page) {
                    apiData = null;
                    cachedApiPage = 0;
                }

                var url = Wallhaven.wallpaperUrl(result.wallpaper, cfg.ImageQuality);
                finish(result.wallpaper, url);
            }

            if (apiData && apiData.data && apiData.data.length && cachedApiPage === page) {
                processData(apiData, 0);
                return;
            }
            fetchApiData(function(data) {
                processData(data, 0);
            }, activeRequest);
        }

        function previousWallpaper() {
            if (historyIndex <= 0) {
                showStatus(i18n("No previous wallpaper in history."), "info");
                return;
            }
            historyIndex--;
            var entry = history[historyIndex];
            index = entry.index;
            page = entry.page;
            displayWallpaper(entry.wallpaper, entry.url, true);
        }
    }

    function syncPreviewMetadata(wallpaper) {
        if (!root.configuration) {
            return;
        }
        root.configuration.PreviewAttribution = root.attributionText;
        root.configuration.PreviewWallpaperId = wallpaper ? String(wallpaper.id) : "";
        root.configuration.PreviewThumbUrl = wallpaper ? Wallhaven.thumbUrlForId(String(wallpaper.id)) : "";
        scheduleConfigPreviewCapture();
        scheduleConfigWrite();
    }

    function scheduleConfigPreviewCapture() {
        previewCaptureTimer.restart();
    }

    function captureConfigPreview() {
        if (!root.configuration || _previewCapturePending) {
            return false;
        }

        var layer = backgroundLayer.opacity > 0 ? backgroundLayer : foregroundLayer;
        var img = layer === backgroundLayer ? backgroundImage : foregroundImage;
        if (img.status !== Image.Ready || !img.source) {
            return false;
        }

        var captureW = 480;
        var captureH = 270;
        if (root.height > root.width && root.width > 0) {
            captureW = 270;
            captureH = 480;
        } else if (root.width > 0 && root.height > 0) {
            captureH = Math.max(180, Math.round(captureW * root.height / root.width));
        }

        _previewCapturePending = true;
        layer.grabToImage(function(result) {
            _previewCapturePending = false;
            if (!result || !root.configuration) {
                return;
            }
            if (result.saveToFile(previewCacheFile)) {
                root.configuration.PreviewImage = Qt.resolvedUrl(previewCacheFile).toString();
                scheduleConfigWrite();
            }
        }, Qt.size(captureW, captureH));
        return true;
    }

    function showImage(url, immediate) {
        if (!url) {
            return;
        }

        var baseUrl = url.split("#")[0].split("?")[0];
        var currentBase = currentUrl.split("#")[0].split("?")[0];
        var sameAsCurrent = baseUrl === currentBase && currentUrl !== "";
        if (sameAsCurrent) {
            // Bust Qt image cache for remote reloads. For file://, query suffixes
            // can break local loads, so forced reloads clear sources instead.
            if (baseUrl.indexOf("file:") !== 0) {
                url = baseUrl + "?_t=" + Date.now();
            }
        }

        _pendingImageUrl = url;
        root._imageLoadStartedMs = Date.now();
        root._awaitingTransitionReady = false;
        root._awaitingTransitionMode = "";
        transitionReadyTimer.stop();
        root.stopTransitionAnimations();
        if (immediate) {
            // Immediate path is used for wake/blank recovery: never leave a mid
            // transition or same-path Image binding that refuses to re-upload.
            if (sameAsCurrent && baseUrl.indexOf("file:") === 0) {
                clearWallpaperImageSources();
            }
            resetWallpaperLayerVisibility();
        }
        var transitionMode = effectiveTransitionMode();
        var useTransition = cfg.CrossfadeMs > 0 && !immediate && currentUrl !== "";
        if (useTransition && transitionMode !== "instant") {
            // Load onto the inactive layer first; start the animation only when
            // Ready so a failed URL cannot wipe the last good frame mid-fade.
            currentUrl = url;
            root._awaitingTransitionReady = true;
            root._awaitingTransitionMode = transitionMode;
            if (activeIsForeground) {
                backgroundImage.source = url;
            } else {
                foregroundImage.source = url;
            }
            transitionReadyTimer.restart();
            Qt.callLater(root.tryStartPendingTransition);
            return;
        }

        backgroundImage.source = url;
        backgroundLayer.opacity = 1;
        foregroundLayer.opacity = 0;
        foregroundImage.source = "";
        activeIsForeground = false;
        currentUrl = url;
    }

    function pendingTransitionImage() {
        return activeIsForeground ? backgroundImage : foregroundImage;
    }

    function tryStartPendingTransition() {
        if (!root._awaitingTransitionReady) {
            return;
        }
        var mode = root._awaitingTransitionMode;
        var url = _pendingImageUrl;
        var img = pendingTransitionImage();
        if (!img) {
            return;
        }
        if (img.status === Image.Loading || img.status === Image.Null) {
            return;
        }
        if (img.status === Image.Error) {
            root._awaitingTransitionReady = false;
            root._awaitingTransitionMode = "";
            transitionReadyTimer.stop();
            return;
        }
        if (img.status !== Image.Ready) {
            return;
        }
        root._awaitingTransitionReady = false;
        root._awaitingTransitionMode = "";
        transitionReadyTimer.stop();
        if (mode === "fadeblack") {
            _pendingFadeUrl = url;
            root._fadeBlackStartedMs = Date.now();
            fadeBlackOut.start();
            return;
        }
        if (mode === "slide") {
            if (activeIsForeground) {
                slideToBackground.start();
            } else {
                slideToForeground.start();
            }
            return;
        }
        if (mode === "zoom") {
            if (activeIsForeground) {
                zoomToBackground.start();
            } else {
                zoomToForeground.start();
            }
            return;
        }
        // crossfade (default)
        if (activeIsForeground) {
            crossfadeToBackground.start();
        } else {
            crossfadeToForeground.start();
        }
    }

    function abortPendingTransitionKeepVisible() {
        root._awaitingTransitionReady = false;
        root._awaitingTransitionMode = "";
        transitionReadyTimer.stop();
        root.stopTransitionAnimations();
        if (backgroundImage.status === Image.Ready && String(backgroundImage.source || "")) {
            backgroundLayer.opacity = 1;
            foregroundLayer.opacity = 0;
            activeIsForeground = false;
            if (foregroundImage.status === Image.Error) {
                foregroundImage.source = "";
            }
        } else if (foregroundImage.status === Image.Ready && String(foregroundImage.source || "")) {
            foregroundLayer.opacity = 1;
            backgroundLayer.opacity = 0;
            activeIsForeground = true;
            if (backgroundImage.status === Image.Error) {
                backgroundImage.source = "";
            }
        } else {
            resetWallpaperLayerVisibility();
        }
    }

    function handleImageStatus(img) {
        if (!img || String(img.source) !== String(_pendingImageUrl)) {
            return;
        }
        if (img.status === Image.Ready) {
            _imageErrorCount = 0;
            // Only clear the offline skip budget after a real local-cache hit.
            // Remote Ready (shouldn't happen soft-offline) must not reopen the
            // "skip entire cache" floodgate.
            if (root._pendingUsedCache || !root.effectiveOfflineOnly()) {
                _cacheErrorSkipCount = 0;
            }
            root._imageLoadStartedMs = 0;
            root.tryStartPendingTransition();
            scheduleConfigPreviewCapture();
            scheduleDiskCacheSave(img);
            maybeSyncSidecars(img);
            return;
        }
        if (img.status !== Image.Error) {
            return;
        }

        root.abortPendingTransitionKeepVisible();

        // Stale/missing cache entry.
        if (_pendingUsedCache && _pendingRemoteUrl) {
            var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, _pendingWallpaperId);
            if (slot >= 0 && _diskCacheIndex.ids) {
                Wallhaven.evictDiskCacheOccupant(_diskCacheIndex, _pendingWallpaperId);
                _diskCacheIndex.ids[slot] = "";
                persistDiskCacheIndex();
            }
            // Soft-offline / rate-limit: never fall back to a remote thumb — that
            // fails under 429 and used to skip through the entire cache in seconds.
            if (root.effectiveOfflineOnly()) {
                _pendingUsedCache = false;
                _imageErrorCount++;
                if (_cacheErrorSkipCount >= 3) {
                    engine.showStatus(i18n("Could not load cached wallpapers. Waiting for Wallhaven…"), "error");
                    return;
                }
                if (cfg.DiskCacheEnabled
                        && engine.showNextCachedWallpaper(true, false,
                            i18n("Cached file missing. Showing another…"))) {
                    _cacheErrorSkipCount++;
                }
                return;
            }
            _pendingUsedCache = false;
            showImage(_pendingRemoteUrl, true);
            return;
        }

        _imageErrorCount++;
        if (currentWallpaper && currentWallpaper.id) {
            engine.markSeen(currentWallpaper.id);
        }
        // When Wallhaven/API is unhealthy, skip remote fetches and cycle local cache.
        // Cap consecutive skips so a bad index/CDN storm cannot burn the whole cache.
        if (!root.apiHealth.healthy || root.effectiveOfflineOnly()) {
            if (_cacheErrorSkipCount >= 3) {
                engine.showStatus(i18n("Could not load cached wallpapers. Waiting for Wallhaven…"), "error");
                root._needsReconnectFetch = true;
                return;
            }
            if (cfg.DiskCacheEnabled && (cfg.OfflineCacheFallback || root.effectiveOfflineOnly())
                    && engine.showNextCachedWallpaper(true, false,
                        i18n("Image failed to load. Showing cached wallpaper."))) {
                _cacheErrorSkipCount++;
                return;
            }
            engine.showStatus(i18n("Could not load cached wallpapers. Waiting for Wallhaven…"), "error");
            return;
        }
        if (_imageErrorCount >= 5) {
            engine.showStatus(i18n("Could not download wallpaper images. Check your connection."), "error");
            if (!root.wallpaperIsVisible()) {
                if (!engine.tryOfflineFallback("") && !root.bootstrapWallpaperFromCache()) {
                    root._needsReconnectFetch = true;
                }
            }
            return;
        }
        engine.showStatus(i18n("Image failed to load. Trying another…"), "warn");
        Qt.callLater(function() {
            engine.skipForward();
        });
    }

    function reloadWallpaper() {
        engine.showStatus(i18n("Reloading wallpapers…"), "info");
        engine.resetSlideshow();
    }

    function advanceWallpaper() {
        engine.skipForward();
    }

    property double _lastNotifyAtMs: 0
    property string _lastNotifyText: ""

    function sendSystemNotification(title, text, isError) {
        if (!text) {
            return;
        }
        // Multi-monitor + retries used to flood the notification tray. Keep the
        // desktop banner, but only pop one system notification per unique text
        // within a quiet window (and at most one error/warn every 45s).
        var now = Date.now();
        if (Wallhaven.shouldThrottleNotification(
            root._lastNotifyAtMs,
            root._lastNotifyText,
            now,
            text,
            isError,
        )) {
            return;
        }
        root._lastNotifyAtMs = now;
        root._lastNotifyText = String(text);
        var props = {
            title: title || i18n("Wallhaven"),
            text: text,
            iconName: isError ? "dialog-error" : "preferences-desktop-wallpaper",
            urgency: isError ? Notification.HighUrgency : Notification.LowUrgency,
        };
        var notification = notificationComponent.createObject(root, props);
        if (!notification) {
            return;
        }
        // Actions only on non-error refresh-style notices — error floods were
        // already noisy; keep actions on intentional refresh notifications.
        if (!isError && cfg.NotifyWithActions !== false) {
            try {
                var nextAct = notificationActionComponent.createObject(notification, {
                    label: i18n("Next"),
                });
                if (nextAct) {
                    nextAct.activated.connect(function() { engine.skipForward(); });
                }
                var pauseAct = notificationActionComponent.createObject(notification, {
                    label: cfg.SlideshowPaused ? i18n("Resume") : i18n("Pause"),
                });
                if (pauseAct) {
                    pauseAct.activated.connect(function() { root.toggleSlideshowPause(); });
                }
                var openAct = notificationActionComponent.createObject(notification, {
                    label: i18n("Open"),
                });
                if (openAct) {
                    openAct.activated.connect(function() {
                        if (root.currentPageUrl)
                            Qt.openUrlExternally(root.currentPageUrl);
                    });
                }
                var acts = [];
                if (nextAct)
                    acts.push(nextAct);
                if (pauseAct)
                    acts.push(pauseAct);
                if (openAct)
                    acts.push(openAct);
                notification.actions = acts;
            } catch (e) {
                // Older notification plugins may lack actions — banner still sends.
            }
        }
        notification.sendEvent();
    }

    Component {
        id: notificationComponent
        Notification {
            componentName: "org.robertsm.wallhaven"
            eventId: "notification"
            autoDelete: true
        }
    }

    Component {
        id: notificationActionComponent
        NotificationAction {}
    }

    TextEdit {
        id: clipboardHelper
        visible: false
        width: 1
        height: 1
    }

    QtObject {
        id: cacheFileDeleter
        property var pendingPaths: []

        function deletePaths(paths) {
            pendingPaths = paths || [];
            deleteNext();
        }

        function deleteNext() {
            if (!pendingPaths.length) {
                return;
            }
            var path = pendingPaths.shift();
            dbusHelper.runArgv(["rm", "-f", path], deleteNext);
        }
    }

    QtObject {
        id: dbusHelper

        function wallhavenNormalizeSignature(signature) {
            var sig = String(signature || "").trim();
            if (!sig)
                return "";
            // Plasma's D-Bus encoder expects parenthesized signatures, e.g. "(ss)".
            if (sig.charAt(0) !== "(")
                sig = "(" + sig + ")";
            return sig;
        }

        function wallhavenTypedArgs(signature, args) {
            // Prefer typed wrappers when available; fall back to plain values.
            var out = [];
            var sig = String(signature || "").replace(/[()]/g, "");
            var list = args || [];
            var ai = 0;
            var hasStringCtor = typeof PDBus.string === "function";
            var hasBoolCtor = typeof PDBus.bool === "function";
            for (var i = 0; i < sig.length && ai < list.length; i++) {
                var ch = sig.charAt(i);
                var value = list[ai++];
                if (ch === "s" && hasStringCtor)
                    out.push(new PDBus.string(String(value == null ? "" : value)));
                else if (ch === "b" && hasBoolCtor)
                    out.push(new PDBus.bool(!!value));
                else
                    out.push(value);
            }
            while (ai < list.length)
                out.push(list[ai++]);
            return out;
        }

        function wallhavenMessage(member, signature, args, callback) {
            var normalized = wallhavenNormalizeSignature(signature);
            var msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: member,
                signature: normalized,
                arguments: wallhavenTypedArgs(normalized, args),
            });
            PDBus.SessionBus.asyncCall(msg, function(reply) {
                if (callback)
                    callback(reply);
            }, function(err) {
                var detail = "";
                try {
                    if (err && err.error)
                        detail = String(err.error.message || err.error.name || "");
                    else if (err && err.message)
                        detail = String(err.message);
                } catch (e) {}
                console.warn("Wallhaven D-Bus call failed:", member, detail || err);
                if (callback)
                    callback("");
            });
        }

        function writeFile(path, text, callback) {
            wallhavenMessage("WriteTextFile", "ss", [urlToLocalPath(path), text || ""], function(reply) {
                if (callback)
                    callback(Wallhaven.dbusReplyAsString(reply));
            });
        }

        function readFile(path, callback) {
            wallhavenMessage("ReadTextFile", "s", [urlToLocalPath(path)], function(reply) {
                if (callback)
                    callback(Wallhaven.dbusReplyAsString(reply));
            });
        }

        function appendFile(path, line, callback) {
            wallhavenMessage("AppendTextFile", "ss", [urlToLocalPath(path), line || ""], function(reply) {
                if (callback)
                    callback(Wallhaven.dbusReplyAsString(reply));
            });
        }

        function runArgv(argv, callback) {
            var cleaned = [];
            for (var i = 0; i < (argv || []).length; i++) {
                var arg = String(argv[i] == null ? "" : argv[i]);
                // Never pass file:// URLs to shell tools (cp, bash redirects, etc.).
                if (arg.indexOf("file://") === 0 || arg.indexOf("file:") === 0)
                    arg = urlToLocalPath(arg);
                cleaned.push(arg);
            }
            wallhavenMessage("RunArgv", "s", [JSON.stringify(cleaned)], function(reply) {
                if (callback)
                    callback(Wallhaven.dbusReplyAsString(reply));
            });
        }

        function listImageFiles(folder, callback) {
            var options = JSON.stringify({
                maxDepth: Math.max(0, Math.min(8, parseInt(cfg.LocalFolderMaxDepth, 10) || 3)),
                exclude: String(cfg.LocalFolderExclude || ""),
            });
            wallhavenMessage("ListImageFiles", "ss", [folder || "", options], function(reply) {
                if (callback) {
                    callback(Wallhaven.dbusReplyAsString(reply));
                }
            });
        }

        // callback(binaryPath) -- binaryPath is "" when no upscaler is installed
        // or the D-Bus method fails (old service, missing binary, etc.).
        function checkUpscalerAvailable(callback) {
            var done = function(reply) {
                if (callback) {
                    callback(Wallhaven.dbusReplyAsString(reply));
                }
            };
            var msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: "UpscalerAvailable",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, done, function() {
                done("");
            });
        }

        // callback(ok) -- ok is false on any failure (not installed, timed out,
        // tool errored); callers should just keep using the plain-scaled image.
        function upscale(inputPath, outputPath, callback) {
            wallhavenMessage("Upscale", "ss", [inputPath, outputPath], callback);
        }
    }

    QtObject {
        id: settingsFileWriter
        function writeFile(path, text, callback) {
            dbusHelper.writeFile(path, text, callback);
        }
    }

    QtObject {
        id: kwalletReadLoader
        function read(tmpPath) {
            dbusHelper.readFile(tmpPath, function(reply) {
                if (!root.configuration) {
                    return;
                }
                var key = Wallhaven.sanitizeApiKey(reply);
                if (key) {
                    root.configuration.ApiKey = key;
                    root._walletStatus = "loaded";
                    scheduleConfigWrite();
                } else if (root._walletLoadAttempted) {
                    root._walletStatus = "missing";
                }
                publishStatus();
            });
        }
    }

    Timer {
        id: statusPublishTimer
        interval: 5000
        running: root._configured
        repeat: true
        onTriggered: {
            if (root.tripModeActive === false
                && cfg.TripModeUntilMs
                && parseInt(cfg.TripModeUntilMs, 10) > 0
                && !Wallhaven.tripModeActive(cfg.TripModeUntilMs)) {
                // Trip window ended — clear latch but keep OfflineOnly if user set it manually.
                root.configuration.TripModeUntilMs = "0";
                scheduleConfigWrite();
                engine.showStatus(i18n("Trip mode ended."), "info");
            }
            root.publishStatus();
            if (cfg.DiskCacheMaxMb > 0) {
                root.refreshCacheFileSizes(function(sizeMap) {
                    root.enforceCacheQuota(sizeMap);
                });
            }
        }
    }

    QtObject {
        id: debugLogWriter
        function appendLine(line) {
            dbusHelper.appendFile(debugLogFile, line);
        }
    }

    QtObject {
        id: dbusAvailabilityLoader

        function poll() {
            if (typeof PDBus === "undefined" || !PDBus.SessionBus) {
                root.dbusServiceAvailable = false;
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: "Ping",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function() {
                root.dbusServiceAvailable = true;
                pollUpscaler();
            }, function() {
                root.dbusServiceAvailable = false;
                root.upscalerBinaryPath = "";
                root.upscalerStatusKnown = true;
            });
        }

        // Piggybacks on the same 5s cadence as the D-Bus availability poll
        // above (only reachable once that poll confirms the service is up):
        // shutil.which() on the service side is cheap, and realesrgan-ncnn-vulkan
        // being installed/removed mid-session is rare enough that re-checking
        // this often is plenty responsive without being wasteful.
        function pollUpscaler() {
            dbusHelper.checkUpscalerAvailable(function(binaryPath) {
                root.upscalerBinaryPath = binaryPath || "";
                root.upscalerStatusKnown = true;
            });
        }
    }

    Timer {
        id: dbusAvailabilityTimer
        interval: 5000
        running: root._configured
        repeat: true
        triggeredOnStart: true
        onTriggered: dbusAvailabilityLoader.poll()
    }

    QtObject {
        id: musicReactiveLoader

        function poll() {
            if (!cfg.MusicReactiveEnabled) {
                root._musicPlaying = false;
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.freedesktop.DBus",
                path: "/org/freedesktop/DBus",
                iface: "org.freedesktop.DBus",
                member: "ListNames",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function(names) {
                var found = "";
                for (var i = 0; names && i < names.length; i++) {
                    var name = String(names[i]);
                    if (name.indexOf("org.mpris.MediaPlayer2.") === 0 && name !== "org.mpris.MediaPlayer2.wallhaven") {
                        found = name;
                        break;
                    }
                }
                if (!found) {
                    root._musicPlaying = false;
                    return;
                }
                queryPlayback(found);
            }, function() {
                root._musicPlaying = false;
            });
        }

        function queryPlayback(service) {
            var msg = new PDBus.dbusMessage({
                service: service,
                path: "/org/mpris/MediaPlayer2",
                iface: "org.freedesktop.DBus.Properties",
                member: "Get",
                signature: "ss",
                arguments: ["org.mpris.MediaPlayer2.Player", "PlaybackStatus"],
            });
            PDBus.SessionBus.asyncCall(msg, function(status) {
                // Same PDBus variant/array wrapping as UpscalerAvailable / Ping replies.
                root._musicPlaying = Wallhaven.dbusReplyAsString(status) === "Playing";
            }, function() {
                root._musicPlaying = false;
            });
        }
    }

    Timer {
        id: musicReactiveTimer
        interval: 4000
        running: root._configured && cfg.MusicReactiveEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: musicReactiveLoader.poll()
    }

    QtObject {
        id: weatherLoader

        function fetchJson(url, onSuccess, onError) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", url);
            xhr.setRequestHeader("Accept", "application/json");
            xhr.timeout = 10000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }
                if (xhr.status === 200) {
                    try {
                        onSuccess(JSON.parse(xhr.responseText));
                    } catch (e) {
                        onError();
                    }
                } else {
                    onError();
                }
            };
            xhr.onerror = function() { onError(); };
            xhr.ontimeout = function() { onError(); };
            xhr.send();
        }

        function refresh() {
            if (!cfg.WeatherReactiveEnabled || !root.configuration) {
                return;
            }
            var location = String(cfg.WeatherLocation || "").trim();
            if (!location) {
                return;
            }
            if (location === root._weatherLastLocation && cfg.WeatherResolvedLat) {
                fetchWeather(cfg.WeatherResolvedLat, cfg.WeatherResolvedLon);
                return;
            }
            var direct = Wallhaven.parseLatLon(location);
            if (direct) {
                root._weatherLastLocation = location;
                root.configuration.WeatherResolvedLat = String(direct.lat);
                root.configuration.WeatherResolvedLon = String(direct.lon);
                scheduleConfigWrite();
                fetchWeather(direct.lat, direct.lon);
                return;
            }
            var geocodeUrl = "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
                + encodeURIComponent(location);
            fetchJson(geocodeUrl, function(json) {
                var place = Wallhaven.parseGeocodeResponse(json);
                if (!place) {
                    return;
                }
                root._weatherLastLocation = location;
                root.configuration.WeatherResolvedLat = String(place.lat);
                root.configuration.WeatherResolvedLon = String(place.lon);
                scheduleConfigWrite();
                fetchWeather(place.lat, place.lon);
            }, function() {});
        }

        function fetchWeather(lat, lon) {
            var url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat
                + "&longitude=" + lon + "&current_weather=true";
            fetchJson(url, function(json) {
                var current = Wallhaven.parseCurrentWeatherResponse(json);
                if (!current || !root.configuration) {
                    return;
                }
                var tag = Wallhaven.mapWeatherCodeToTag(current.code);
                if (tag && tag !== cfg.WeatherTagCache) {
                    root.configuration.WeatherTagCache = tag;
                    scheduleConfigWrite();
                    logDebug("Weather-reactive tag set to " + tag);
                }
            }, function() {});
        }
    }

    Timer {
        id: weatherReactiveTimer
        interval: 1800000
        running: root._configured && cfg.WeatherReactiveEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherLoader.refresh()
    }

    Timer {
        id: timeCapsuleTimer
        interval: 3600000
        running: root._configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkTimeCapsules()
    }

    QtObject {
        id: batteryPollLoader
        property var paths: [
            "/sys/class/power_supply/BAT0/capacity",
            "/sys/class/power_supply/BAT1/capacity",
        ]

        function tryPath(index) {
            if (index >= paths.length) {
                return;
            }
            dbusHelper.readFile(paths[index], function(text) {
                var pct = parseInt(String(text || "").trim(), 10);
                if (!isNaN(pct)) {
                    root._batteryPercent = pct;
                    root.evaluateSlideshowRules();
                    return;
                }
                tryPath(index + 1);
            });
        }
    }

    Timer {
        id: batteryPollTimer
        interval: 60000
        running: root._configured && cfg.PauseOnBatteryLow
        repeat: true
        onTriggered: batteryPollLoader.tryPath(0)
    }

    QtObject {
        id: screenLockLoader

        // org.freedesktop.ScreenSaver is the standard cross-desktop-environment
        // interface kscreenlocker (and every other screensaver-aware Linux app)
        // uses to publish lock state; GetActive() takes no arguments and
        // returns a bool. Polled the same way as dbusAvailabilityLoader/
        // musicReactiveLoader elsewhere in this file, since PDBus has no QML
        // API for subscribing to the interface's ActiveChanged signal directly.
        function poll() {
            if (typeof PDBus === "undefined" || !PDBus.SessionBus) {
                root._screenLocked = false;
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.freedesktop.ScreenSaver",
                path: "/org/freedesktop/ScreenSaver",
                iface: "org.freedesktop.ScreenSaver",
                member: "GetActive",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function(active) {
                root._screenLocked = Wallhaven.dbusReplyIsTrue(active);
                root.evaluateSlideshowRules();
            }, function() {
                root._screenLocked = false;
            });
        }
    }

    Timer {
        id: screenLockTimer
        interval: 5000
        running: root._configured && cfg.PauseWhenInactive
        repeat: true
        triggeredOnStart: true
        onTriggered: screenLockLoader.poll()
    }

    QtObject {
        id: idleSessionLoader

        function poll() {
            if (typeof PDBus === "undefined" || !PDBus.SessionBus) {
                root._sessionIdle = false;
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.freedesktop.ScreenSaver",
                path: "/org/freedesktop/ScreenSaver",
                iface: "org.freedesktop.ScreenSaver",
                member: "GetSessionIdleTime",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function(seconds) {
                var idleSec = Number(Wallhaven.dbusReplyAsString(seconds)) || 0;
                var threshold = Math.max(1, cfg.IdlePauseMinutes || 5) * 60;
                root._sessionIdle = idleSec >= threshold;
                root.evaluateSlideshowRules();
            }, function() {
                root._sessionIdle = false;
            });
        }
    }

    Timer {
        id: idleSessionTimer
        interval: 15000
        running: root._configured && cfg.PauseOnIdleEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: idleSessionLoader.poll()
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            root.evaluateSlideshowRules();
            if (Qt.application.state !== Qt.ApplicationActive) {
                return;
            }
            Qt.callLater(function() {
                root.checkConnectivity();
            });
        }
    }

    Timer {
        id: favoritesRefreshTimer
        interval: Math.max(60000, (cfg.FavoritesRefreshMin || 0) * 60000)
        running: root._configured && cfg.BrowseMode === "favorites"
            && (cfg.FavoritesRefreshMin || 0) > 0
        repeat: true
        onTriggered: {
            engine.favoritesId = "";
            engine.resetSlideshow();
            logDebug("Favorites collection refresh");
        }
    }

    Timer {
        id: varietyWatchTimer
        interval: 5000
        running: root._configured && cfg.VarietySymlinkEnabled && cfg.VarietyFolderPath !== ""
        repeat: true
        property string lastPath: ""
        onTriggered: {
            dbusHelper.readFile(varietyMetadataFile, function(text) {
                try {
                    var meta = JSON.parse(text || "{}");
                    if (meta.localPath && meta.localPath !== lastPath) {
                        lastPath = meta.localPath;
                        updateVarietySymlink(meta.localPath);
                    }
                } catch (e) {
                }
            });
        }
    }

    QtObject {
        id: controlBusLoader
        function load(path) {
            dbusHelper.readFile(path, function(text) {
                if (!text) {
                    return;
                }
                var commands = Wallhaven.parseControlCommands(text);
                if (!commands.length) {
                    var single = Wallhaven.parseControlCommand(text);
                    commands = single ? [single] : [];
                }
                for (var ci = 0; ci < commands.length; ci++) {
                    var cmd = commands[ci];
                    if (!cmd || cmd.ts <= root._lastControlTs) {
                        continue;
                    }
                    // Drop stale leftovers (ms timestamps must not live in property int).
                    if (!Wallhaven.isFreshBusTimestamp(cmd.ts, Date.now(), 300000)) {
                        root._lastControlTs = Math.max(root._lastControlTs, cmd.ts);
                        continue;
                    }
                    if (!root.controlCommandTargetsThisScreen(cmd)) {
                        // Still advance the watermark so foreign-group cmds are
                        // not re-scanned every 400ms.
                        root._lastControlTs = Math.max(root._lastControlTs, cmd.ts);
                        continue;
                    }
                    root._lastControlTs = Math.max(root._lastControlTs, cmd.ts);
                    root.handleControlCommand(cmd);
                }
            });
        }
    }

    QtObject {
        id: syncAdvanceLoader
        function load(path) {
            dbusHelper.readFile(path, function(text) {
                if (!text) {
                    return;
                }
                var sync = Wallhaven.parseSyncAdvance(text);
                if (!sync || sync.advanceAt <= root._lastSyncAdvanceTs) {
                    return;
                }
                if (!Wallhaven.isFreshBusTimestamp(sync.advanceAt, Date.now(), 300000)) {
                    root._lastSyncAdvanceTs = Math.max(root._lastSyncAdvanceTs, sync.advanceAt);
                    return;
                }
                if (sync.issuer === root._instanceId) {
                    root._lastSyncAdvanceTs = Math.max(root._lastSyncAdvanceTs, sync.advanceAt);
                    return;
                }
                // Don't stamp the tick until we can advance — busy used to
                // permanently drop sync advances on multi-monitor setups.
                if (engine.busy) {
                    root._pendingSyncAdvance = true;
                    root._pendingSyncAdvanceAt = Math.max(
                        root._pendingSyncAdvanceAt || 0,
                        sync.advanceAt,
                    );
                    return;
                }
                root._lastSyncAdvanceTs = sync.advanceAt;
                engine.skipForward(true);
            });
        }
    }

    Rectangle {
        id: fadeBlackOverlay
        z: 90
        anchors.fill: parent
        color: "#000000"
        opacity: 0
    }

    SequentialAnimation {
        id: fadeBlackOut
        NumberAnimation { target: fadeBlackOverlay; property: "opacity"; to: 1; duration: cfg.CrossfadeMs / 2 }
        ScriptAction {
            script: {
                var url = _pendingFadeUrl;
                backgroundImage.source = url;
                foregroundImage.source = "";
                backgroundLayer.opacity = 1;
                foregroundLayer.opacity = 0;
                activeIsForeground = false;
                _pendingImageUrl = url;
            }
        }
        NumberAnimation { target: fadeBlackOverlay; property: "opacity"; to: 0; duration: cfg.CrossfadeMs / 2 }
        onStarted: {
            activeIsForeground = false;
            root._fadeBlackStartedMs = Date.now();
        }
        onFinished: {
            root._fadeBlackStartedMs = 0;
            scheduleConfigPreviewCapture();
        }
    }

    Item {
        id: backgroundLayer
        anchors.fill: parent
        clip: true
        layer.enabled: cfg.ImageEnhanceEnabled
        layer.effect: MultiEffect {
            brightness: cfg.EnhanceBrightness / 100
            contrast: cfg.EnhanceContrast / 100
            saturation: cfg.EnhanceSaturation / 100
        }

        Item {
            id: backgroundTransform
            width: parent.width
            height: parent.height
            property real zoomScale: 1
            property real slideX: 0
            transformOrigin: Item.Center
            scale: kenBurnsAnimation.bgScale * zoomScale * root.parallaxScale
            x: kenBurnsAnimation.bgX + root.parallaxOffsetX + slideX
            y: kenBurnsAnimation.bgY + root.parallaxOffsetY

            Image {
                id: backgroundImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: root.wallpaperSourceSize
                onStatusChanged: root.handleImageStatus(backgroundImage)
            }
        }
    }

    Item {
        id: foregroundLayer
        anchors.fill: parent
        clip: true
        opacity: 0
        layer.enabled: cfg.ImageEnhanceEnabled
        layer.effect: MultiEffect {
            brightness: cfg.EnhanceBrightness / 100
            contrast: cfg.EnhanceContrast / 100
            saturation: cfg.EnhanceSaturation / 100
        }

        Item {
            id: foregroundTransform
            width: parent.width
            height: parent.height
            property real zoomScale: 1
            property real slideX: 0
            transformOrigin: Item.Center
            scale: kenBurnsAnimation.fgScale * zoomScale * root.parallaxScale
            x: kenBurnsAnimation.fgX + root.parallaxOffsetX + slideX
            y: kenBurnsAnimation.fgY + root.parallaxOffsetY

            Image {
                id: foregroundImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: root.wallpaperSourceSize
                onStatusChanged: root.handleImageStatus(foregroundImage)
            }
        }
    }

    Image {
        id: preloadImage
        visible: false
        width: 1
        height: 1
        asynchronous: true
        cache: false
        sourceSize: root.wallpaperSourceSize
    }

    Image {
        id: preloadImage2
        visible: false
        width: 1
        height: 1
        asynchronous: true
        cache: false
        sourceSize: root.wallpaperSourceSize
    }

    Image {
        id: saveSourceImage
        visible: false
        asynchronous: true
        cache: false
        property string pendingPath: ""

        onStatusChanged: {
            if (!pendingPath) {
                return;
            }
            if (status === Image.Error) {
                var failedPath = pendingPath;
                pendingPath = "";
                engine.showStatus(i18n("Could not download wallpaper to save."), "error");
                return;
            }
            if (status !== Image.Ready) {
                return;
            }

            var destPath = pendingPath;
            pendingPath = "";
            var width = sourceSize.width > 0 ? sourceSize.width : 1920;
            var height = sourceSize.height > 0 ? sourceSize.height : 1080;
            // Cap extremely large images so grab stays reliable.
            var maxEdge = 5120;
            if (width > maxEdge || height > maxEdge) {
                var scale = maxEdge / Math.max(width, height);
                width = Math.round(width * scale);
                height = Math.round(height * scale);
            }

            grabToImage(function(result) {
                if (result && result.saveToFile(destPath)) {
                    engine.showStatus(i18n("Wallpaper saved."), "info");
                } else {
                    engine.showStatus(i18n("Could not save wallpaper."), "error");
                }
            }, Qt.size(width, height));
        }
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        title: i18n("Save Wallpaper")
        nameFilters: [
            i18n("PNG image (*.png)"),
            i18n("JPEG image (*.jpg *.jpeg)"),
        ]
        defaultSuffix: "png"
        onAccepted: root.saveCurrentWallpaper(selectedFile)
    }

    ParallelAnimation {
        id: crossfadeToForeground
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = true
        onFinished: {
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    ParallelAnimation {
        id: crossfadeToBackground
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = false
        onFinished: {
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    ParallelAnimation {
        id: slideToForeground
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: foregroundTransform; property: "slideX"; from: root.width * 0.08; to: 0; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = true
        onFinished: {
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    ParallelAnimation {
        id: slideToBackground
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: backgroundTransform; property: "slideX"; from: root.width * 0.08; to: 0; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = false
        onFinished: {
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    ParallelAnimation {
        id: zoomToForeground
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: foregroundTransform; property: "zoomScale"; from: 1.08; to: 1; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = true
        onFinished: {
            foregroundTransform.zoomScale = 1;
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    ParallelAnimation {
        id: zoomToBackground
        NumberAnimation { target: backgroundLayer; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: backgroundTransform; property: "zoomScale"; from: 1.08; to: 1; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: foregroundLayer; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = false
        onFinished: {
            backgroundTransform.zoomScale = 1;
            root.releaseInactiveLayer();
            scheduleConfigPreviewCapture();
        }
    }

    QtObject {
        id: kenBurnsAnimation
        property real bgScale: 1
        property real fgScale: 1
        property real bgX: 0
        property real bgY: 0
        property real fgX: 0
        property real fgY: 0

        function stopAll() {
            bgKenBurns.stop();
            fgKenBurns.stop();
            bgPanX.stop();
            fgPanX.stop();
            bgPanY.stop();
            fgPanY.stop();
        }

        function restart() {
            stopAll();
            if (!cfg.KenBurnsEnabled || !root.effectsMotionAllowed()) {
                bgScale = fgScale = 1;
                bgX = bgY = fgX = fgY = 0;
                return;
            }
            var panX = (Math.random() - 0.5) * root.width * 0.04;
            var panY = (Math.random() - 0.5) * root.height * 0.03;
            if (activeIsForeground) {
                fgScale = 1.06;
                fgX = panX;
                fgY = panY;
                fgKenBurns.from = 1.06;
                fgKenBurns.to = 1.14;
                fgPanX.from = panX;
                fgPanX.to = -panX;
                fgPanY.from = panY;
                fgPanY.to = -panY;
                fgKenBurns.start();
                fgPanX.start();
                fgPanY.start();
            } else {
                bgScale = 1.06;
                bgX = panX;
                bgY = panY;
                bgKenBurns.from = 1.06;
                bgKenBurns.to = 1.14;
                bgPanX.from = panX;
                bgPanX.to = -panX;
                bgPanY.from = panY;
                bgPanY.to = -panY;
                bgKenBurns.start();
                bgPanX.start();
                bgPanY.start();
            }
        }
    }

    property int kenBurnsDuration: {
        var duration;
        if (cfg.RandomInterval > 0) {
            duration = cfg.RandomInterval * 60 * 1000 * 0.9;
        } else {
            var speed = Math.max(1, Math.min(cfg.KenBurnsSpeed, 100));
            duration = 120000 - ((speed - 1) / 99) * 90000;
        }
        var multiplier = Wallhaven.musicReactiveSpeedMultiplier(
            cfg.MusicReactiveIntensity, cfg.MusicReactiveEnabled && root._musicPlaying);
        return Math.round(duration / multiplier);
    }

    NumberAnimation { id: bgKenBurns; target: kenBurnsAnimation; property: "bgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgKenBurns; target: kenBurnsAnimation; property: "fgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanX; target: kenBurnsAnimation; property: "bgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanX; target: kenBurnsAnimation; property: "fgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanY; target: kenBurnsAnimation; property: "bgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanY; target: kenBurnsAnimation; property: "fgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }

    NumberAnimation {
        id: parallaxPhaseAnim
        target: root
        property: "parallaxPhase"
        from: 0
        to: 1
        duration: Wallhaven.parallaxCycleMs(cfg.ParallaxStrength)
        loops: Animation.Infinite
        running: root._configured && cfg.ParallaxEnabled
        easing.type: Easing.Linear
    }

    Timer {
        id: previewCaptureTimer
        interval: 1200
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++;
            if (captureConfigPreview() || attempts >= 8) {
                stop();
            }
        }
        onRunningChanged: if (running) attempts = 0
    }

    Timer {
        id: configWriteTimer
        interval: 1500
        repeat: false
        onTriggered: root.flushConfigWrite()
    }

    Timer {
        id: diskCacheSaveTimer
        interval: 700
        repeat: false
        onTriggered: root.writeDiskCacheFromImage()
    }

    Timer {
        id: intervalTimer
        interval: Wallhaven.computeIntervalMs(cfg, Wallhaven.isDayPeriod())
        running: root.slideshowActive() && !cfg.SlideshowPaused
        repeat: false
        onTriggered: {
            engine.skipForward();
            root.restartIntervalTimer();
        }
    }

    Timer {
        id: controlBusTimer
        interval: 400
        running: root._configured && cfg.ControlBusEnabled
        repeat: true
        onTriggered: root.pollControlBus()
    }

    Timer {
        id: syncAdvanceTimer
        interval: 800
        running: root._configured && cfg.SyncAdvanceEnabled
        repeat: true
        onTriggered: root.pollSyncAdvance()
    }

    Timer {
        id: attributionHideTimer
        interval: Math.max(1, cfg.AttributionAutoHideSec) * 1000
        repeat: false
        onTriggered: attributionBanner.visible = false
    }

    Timer {
        id: connectivityTimer
        interval: 45000
        running: root._configured
        repeat: true
        onTriggered: root.checkConnectivity()
    }

    // Faster probe cadence while non-429 soft-offline so recovery is not stuck
    // waiting on the 45s favicon timer alone.
    Timer {
        id: outageProbeTimer
        interval: 30000
        running: root._configured && root._apiOutageOffline && root._apiLastStatus !== 429
        repeat: true
        onTriggered: root.maybeProbeApiOutageClear()
    }

    // Detect suspend/resume via wall-clock gaps and unlock transitions. After
    // sleep the Image textures are often gone while currentUrl is still set.
    // Also heal stuck black overlays / zero-opacity layers without a wake event.
    Timer {
        id: resumeWatchTimer
        interval: 5000
        running: root._configured
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now();
            if (root._resumeWatchLastMs > 0 && (now - root._resumeWatchLastMs) > 90000) {
                root.recoverAfterWake("clock-gap");
            }
            root._resumeWatchLastMs = now;

            // Blank-frame watchdog: stuck fade overlay, zero-opacity layers, or
            // Ready-but-unpainted textures — not ordinary Loading.
            if (root.wallpaperLooksStuckBlank()) {
                root.recoverBlankFrame("watchdog");
            }

            if (typeof PDBus === "undefined" || !PDBus.SessionBus) {
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.freedesktop.ScreenSaver",
                path: "/org/freedesktop/ScreenSaver",
                iface: "org.freedesktop.ScreenSaver",
                member: "GetActive",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function(active) {
                var locked = Wallhaven.dbusReplyIsTrue(active);
                if (root._wasScreenLocked && !locked) {
                    root.recoverAfterWake("unlock");
                }
                root._wasScreenLocked = locked;
                root._screenLocked = locked;
                root.evaluateSlideshowRules();
            }, function() {});
        }
    }

    Timer {
        id: wakeConnectivityBurst
        interval: 2000
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.checkConnectivity();
            ticks++;
            if (ticks >= 6) {
                stop();
                ticks = 0;
            }
        }
        onRunningChanged: if (running) ticks = 0
    }

    Timer {
        id: startupOnlineFetchTimer
        interval: 3500
        repeat: false
        onTriggered: {
            if (root.effectiveOfflineOnly()) {
                root.ensureWallpaperVisible("startup-offline");
                return;
            }
            if (!engine.busy) {
                engine.fetchFreshWallpaper(false);
            }
        }
    }

    Timer {
        id: transitionReadyTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root._awaitingTransitionReady) {
                return;
            }
            var url = root._pendingImageUrl;
            root._awaitingTransitionReady = false;
            root._awaitingTransitionMode = "";
            // Hung decode — snap to immediate paint instead of fading to a blank layer.
            if (url) {
                root.showImage(url, true);
            }
        }
    }

    Timer {
        id: lockSyncRetryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            var retry = root._lockSyncRetry;
            if (!retry || !retry.path || !cfg.SyncLockScreen) {
                root._lockSyncRetry = null;
                return;
            }
            if (retry.id && String(root.currentWallpaperId || "") !== String(retry.id)
                    && String(root._pendingWallpaperId || "") !== String(retry.id)) {
                root._lockSyncRetry = null;
                return;
            }
            // Keep _lockSyncRetry so a second failure sees attempts and stops.
            root.syncLockScreenImage(retry.path, retry.id);
        }
    }

    Timer {
        id: retryTimer
        interval: 60000
        repeat: false
        onTriggered: engine.resumeRetryFetch()
    }

    Timer {
        id: statusHideTimer
        interval: 5000
        repeat: false
        onTriggered: root.statusVisible = false
    }

    Timer {
        id: timeOfDayTimer
        interval: 60000
        running: cfg.TimeOfDayEnabled
        repeat: true
        onTriggered: {
            var period = root.currentTimeOfDayPeriod();
            if (period !== root._timeOfDayPeriod) {
                root._timeOfDayPeriod = period;
                engine.resetSlideshow();
            }
        }
    }

    Rectangle {
        id: statusBanner
        z: 100
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: statusVisible ? statusLabel.implicitHeight + 16 : 0
        visible: root.statusVisible
        radius: 8
        color: root.statusType === "error" ? "#cc1e1e"
             : root.statusType === "warn" ? "#785014"
             : "#1e3c64"
        opacity: 0.9

        QQC2.Label {
            id: statusLabel
            anchors.centerIn: parent
            width: parent.width - 32
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: root.statusMessage
        }
    }

    Rectangle {
        id: attributionBanner
        z: 100
        radius: 8
        color: "#000000"
        opacity: 0.65
        visible: attributionVisible

        readonly property bool attributionVisible: cfg.ShowAttribution && root.attributionText !== ""
        readonly property string corner: cfg.AttributionCorner || "bottom-left"
        readonly property bool cornerCentered: corner === "top-center" || corner === "bottom-center"

        width: Math.min(Math.max(attributionLabel.implicitWidth + 32, 120), parent.width - 32)
        height: attributionVisible ? attributionLabel.implicitHeight + 16 : 0

        anchors.left: !cornerCentered && corner.indexOf("left") >= 0 ? parent.left : undefined
        anchors.right: corner.indexOf("right") >= 0 ? parent.right : undefined
        anchors.top: corner.indexOf("top") >= 0 ? parent.top : undefined
        anchors.bottom: corner.indexOf("bottom") >= 0 ? parent.bottom : undefined
        anchors.horizontalCenter: cornerCentered ? parent.horizontalCenter : undefined
        anchors.margins: 16

        onAttributionVisibleChanged: {
            if (attributionVisible && cfg.AttributionAutoHideSec > 0) {
                visible = true;
                attributionHideTimer.restart();
            }
        }

        QQC2.Label {
            id: attributionLabel
            anchors.centerIn: parent
            width: Math.min(attributionBanner.parent.width - 64, 420)
            wrapMode: Text.WordWrap
            color: "#ffffff"
            font.pointSize: Math.max(7, Math.round(9 * (cfg.AttributionFontScale || 100) / 100))
            text: root.attributionText
        }

        MouseArea {
            anchors.fill: parent
            enabled: attributionBanner.attributionVisible
            onClicked: root.showWallpaperInfo()
        }
    }

    Rectangle {
        id: detailsSheet
        z: 120
        anchors.fill: parent
        color: "#99000000"
        visible: root.wallpaperDetailsOpen
        enabled: visible

        MouseArea {
            anchors.fill: parent
            onClicked: root.wallpaperDetailsOpen = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 480)
            height: Math.min(detailsSheetLabel.implicitHeight + 72, parent.height - 48)
            radius: 10
            color: "#e6101014"

            MouseArea {
                anchors.fill: parent
                onClicked: { /* keep open */ }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                QQC2.Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "white"
                    font.bold: true
                    text: i18n("Wallpaper details")
                }

                QQC2.ScrollView {
                    width: parent.width
                    height: parent.height - 56
                    clip: true
                    QQC2.Label {
                        id: detailsSheetLabel
                        width: detailsSheet.width - 80
                        wrapMode: Text.WordWrap
                        color: "#f0f0f0"
                        text: root.wallpaperDetailsText || i18n("No details yet.")
                    }
                }

                QQC2.Button {
                    text: i18n("Close")
                    onClicked: root.wallpaperDetailsOpen = false
                }
            }
        }
    }

    Connections {
        target: root.configuration
        function onSearchTextChanged() { if (root._configured) engine.resetSlideshow(); }
        function onApiKeyChanged() { if (root._configured) engine.resetSlideshow(); }
        function onSyncAdvanceGroupChanged() {
            if (root._configured && cfg.SyncProfilesEnabled) {
                root.applySyncProfileForGroup(cfg.SyncAdvanceGroup);
            }
        }
        function onBrowseModeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionUserChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionIdChanged() { if (root._configured) engine.resetSlideshow(); }
        function onSortingsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onLocalSortingsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onOrderChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryGeneralChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryAnimeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryPeopleChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPuritySfwChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPuritySketchyChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPurityNsfwChanged() { if (root._configured) engine.resetSlideshow(); }
        function onMinWidthChanged() { if (root._configured) engine.resetSlideshow(); }
        function onMinHeightChanged() { if (root._configured) engine.resetSlideshow(); }
        function onRatioChanged() { if (root._configured) engine.resetSlideshow(); }
        function onColorFilterChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTopRangeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onExactResolutionsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onUseBlacklistChanged() { if (root._configured) engine.resetSlideshow(); }
        function onDaySearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onNightSearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTimeOfDayEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onImageQualityChanged() { if (root._configured) engine.resetSlideshow(); }
        function onKenBurnsEnabledChanged() { kenBurnsAnimation.restart(); }
        function onKenBurnsSpeedChanged() { if (cfg.KenBurnsEnabled) kenBurnsAnimation.restart(); }
        function onParallaxEnabledChanged() {
            if (cfg.ParallaxEnabled) {
                parallaxPhaseAnim.restart();
            } else {
                parallaxPhaseAnim.stop();
                root.parallaxPhase = 0;
            }
        }
        function onParallaxStrengthChanged() {
            if (cfg.ParallaxEnabled) {
                parallaxPhaseAnim.restart();
            }
        }
        function onSlideshowPausedChanged() {
            root.restartIntervalTimer();
        }
        function onOfflineOnlyModeChanged() {
            if (root._configured) {
                engine.resetSlideshow();
            }
        }
        function onMeteredCacheOnlyChanged() {
            if (root._configured && root.effectiveOfflineOnly()) {
                engine.resetSlideshow();
            }
        }
        function onRandomIntervalChanged() { root.restartIntervalTimer(); }
        function onDayIntervalMinChanged() { root.restartIntervalTimer(); }
        function onNightIntervalMinChanged() { root.restartIntervalTimer(); }
        function onIntervalJitterPercentChanged() { root.restartIntervalTimer(); }
        function onFileTypeFilterChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTagBlocklistJsonChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTagFavoritesJsonChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPreferSharpMatchesChanged() { if (root._configured) engine.resetSlideshow(); }
        function onWeatherReactiveEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onWeatherTagCacheChanged() {
            if (root._configured && cfg.WeatherReactiveEnabled) {
                engine.resetSlideshow();
            }
        }
        function onScheduleEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onWeekdaySearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onWeekendSearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionRotationEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionRotationJsonChanged() { if (root._configured) engine.resetSlideshow(); }
        function onWallpaperOfDayEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onFavoritesRefreshMinChanged() { favoritesRefreshTimer.restart(); }
        function onUseKWalletForApiKeyChanged() { root.loadApiKeyFromKWallet(); }
    }

    Timer {
        id: scheduleTimer
        interval: 60000
        running: cfg.ScheduleEnabled && !cfg.TimeOfDayEnabled
        repeat: true
        property bool weekend: Wallhaven.isWeekend()
        onTriggered: {
            var nowWeekend = Wallhaven.isWeekend();
            if (nowWeekend !== weekend) {
                weekend = nowWeekend;
                if (root._configured) {
                    engine.resetSlideshow();
                }
            }
        }
    }

    Component.onCompleted: {
        root.loading = true;
        engine.loadSeenIds();
        engine.loadBlockedIds();
        root.ensureCacheNamespace();
        root.loadDiskCacheIndex();
        root.loadWallpaperHistory();
        root._dedupeFingerprint = Wallhaven.searchDedupeFingerprint({
            BrowseMode: cfg.BrowseMode,
            SearchText: cfg.SearchText,
            Sortings: cfg.Sortings,
            Order: cfg.Order,
            Ratio: cfg.Ratio,
            MinWidth: cfg.MinWidth,
            MinHeight: cfg.MinHeight,
            CategoryGeneral: cfg.CategoryGeneral,
            CategoryAnime: cfg.CategoryAnime,
            CategoryPeople: cfg.CategoryPeople,
            PuritySfw: cfg.PuritySfw,
            PuritySketchy: cfg.PuritySketchy,
            PurityNsfw: cfg.PurityNsfw,
            ColorFilter: cfg.ColorFilter,
            ExactResolutions: cfg.ExactResolutions,
            TopRange: cfg.TopRange,
            CollectionUser: cfg.CollectionUser,
            CollectionId: cfg.CollectionId,
            FileTypeFilter: cfg.FileTypeFilter,
            TagBlocklistJson: cfg.TagBlocklistJson,
        });
        // Migrate before KWallet so upgrades that flip UseKWalletForApiKey load the key.
        var migration = Wallhaven.migrateConfigurationToV3(root.configuration);
        if (migration.migrated || migration.apiKeyScrubbed) {
            scheduleConfigWrite();
            if (migration.migrated) {
                logDebug("Migrated config schema " + migration.from + " → " + migration.to);
            }
            if (migration.apiKeyScrubbed) {
                logDebug("Cleared corrupted ApiKey value from wallpaper config");
                engine.showStatus(i18n("Cleared a bad API key from settings. Re-enter it if you need NSFW/favorites."), "warn");
            }
        }
        root.loadApiKeyFromKWallet();
        root.pollSharedRateLimit();
        // Put something on screen immediately (last preview / cache) so a slow
        // or offline network at login/wake never leaves a blank desktop.
        root.bootstrapWallpaperFromCache();
        root._configured = true;
        scheduleConfigPreviewCapture();
        root.restartIntervalTimer();
        root.publishStatus();
        root._resumeWatchLastMs = Date.now();
        if (cfg.PauseOnBatteryLow) {
            batteryPollTimer.start();
        }
        // Defer the first online fetch so NetworkManager / Wi-Fi / VPN can come
        // up, and so sibling monitors can publish a shared rate-limit latch.
        startupOnlineFetchTimer.start();
        Qt.callLater(function() { root.checkConnectivity(); });
        // Second-chance paint after the scene graph settles (login compositors
        // often drop the first texture upload).
        startupVisibilityTimer.start();
    }

    Timer {
        id: startupVisibilityTimer
        interval: 1500
        repeat: false
        onTriggered: root.ensureWallpaperVisible("startup-settle")
    }

    Component.onDestruction: {
        flushConfigWrite();
    }
}
