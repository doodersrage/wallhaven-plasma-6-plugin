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

    // ---- components (each owns one concern; see docs/ARCHITECTURE.md) ----

    DBusHelper {
        id: dbusHelper
    }

    ApiKeyStore {
        id: apiKeys
        host: root
        dbus: dbusHelper
    }

    ApiHealth {
        id: apiState
        host: root
        dbus: dbusHelper
        engine: engine
    }

    DiskCache {
        id: diskCache
        host: root
        dbus: dbusHelper
    }

    LockScreenSync {
        id: lockSync
        host: root
        dbus: dbusHelper
    }

    ControlBus {
        id: controlBus
        host: root
        dbus: dbusHelper
        engine: engine
        onScreenLockChanged: locked => root.noteScreenLocked(locked)
        onServiceRegisteredChanged: root.refreshServiceAvailability()
        onSignalsActiveChanged: root.refreshServiceAvailability()
    }

    SessionMonitors {
        id: sessionMonitors
        host: root
        dbus: dbusHelper
    }

    // State owned by the components, under the names the engine below, the
    // settings dialog (liveWallpaper.*) and the status snapshot already use.
    property alias _diskCacheIndex: diskCache.cacheIndex
    property alias _rateLimitUntilMs: apiState._rateLimitUntilMs
    property alias _apiLastStatus: apiState._apiLastStatus
    property alias _apiOutageOffline: apiState._apiOutageOffline
    readonly property var apiHealth: apiState.apiHealth
    readonly property string apiHealthSummary: apiState.apiHealthSummary
    property alias lockScreenLastSyncAt: lockSync.lastSyncAt
    property alias lockScreenLastSyncPath: lockSync.lastSyncPath
    property alias lockScreenLastSyncOk: lockSync.lastSyncOk
    readonly property int _batteryPercent: sessionMonitors.batteryPercent
    readonly property bool _sessionIdle: sessionMonitors.sessionIdle
    readonly property bool _musicPlaying: sessionMonitors.musicPlaying
    readonly property string walletStatus: apiKeys.status
    // True when control/sync/lock changes arrive as D-Bus signals (no polling).
    readonly property bool busSignalsActive: controlBus.signalsActive
    // Key used for requests: typed into settings, else loaded from KWallet
    // (in which case it exists only in memory, never in the config file).
    readonly property string effectiveApiKey: apiKeys.effectiveKey

    onEffectiveApiKeyChanged: {
        // The first fetch is still pending during startup and will use the key;
        // cache-only modes never send it.
        if (root._configured && !startupOnlineFetchTimer.running && !root.effectiveOfflineOnly()) {
            engine.resetSlideshow();
        }
    }
    readonly property int seenIdsCount: {
        try {
            return Wallhaven.parseSeenIds(cfg && cfg.SeenIdsJson ? cfg.SeenIdsJson : "[]").length;
        } catch (e) {
            return 0;
        }
    }

    function effectiveOfflineOnly() {
        return cfg.OfflineOnlyMode
            || root._apiOutageOffline
            || apiState.isRateLimitedNow()
            || Wallhaven.tripModeActive(cfg.TripModeUntilMs)
            || cfg.BrowseMode === "playlist"
            || cfg.BrowseMode === "local"
            || (cfg.MeteredCacheOnly && root.meteredConnection);
    }

    function effectsMotionAllowed() {
        return !cfg.ReducedMotion;
    }

    function slideshowActive() {
        return Wallhaven.baseIntervalMinutes(cfg, Wallhaven.isDayPeriod()) > 0;
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
    property bool _infoDetailsFetched: false

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
    property int _fetchRetryCount: 0
    // Resume the same API callback after backoff — never skipForward on retry
    // (that was burning through cache on 429 storms).
    property var _retryOnDone: null
    property var _retryRequestId: 0
    property int _cacheErrorSkipCount: 0
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
    property bool _awaitingTransitionReady: false
    property string _awaitingTransitionMode: ""
    property bool _wasScreenLocked: false
    property string _currentTags: ""
    property int _offlineCacheCursor: -1
    property string _dedupeFingerprint: ""
    property var _localImagePaths: []
    property int _localCursor: -1
    property string _pendingFadeUrl: ""
    property double _lastControlTs: 0
    property double _lastSyncAdvanceTs: 0
    property string _instanceId: Math.random().toString(36).slice(2, 10)
    property string wallpaperDetailsText: ""
    property string wallpaperDetailsResolution: ""
    property string wallpaperDetailsPurity: ""
    property string wallpaperDetailsCategory: ""
    property bool wallpaperDetailsOpen: false
    readonly property string apiKeyDisplayHint: {
        var tail = Wallhaven.apiKeyLastFour(root.effectiveApiKey);
        if (tail) {
            return i18n("Key set (…%1)", tail);
        }
        if (root.walletStatus === "loaded") {
            return i18n("Key loaded from KWallet");
        }
        if (root.walletStatus === "missing") {
            return i18n("KWallet: no key stored");
        }
        if (root.walletStatus === "failed") {
            return i18n("KWallet: load failed");
        }
        if (root.walletStatus === "disabled") {
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
    property bool _rulesPausedSlideshow: false
    property bool _pausedByRules: false
    // Public so config.qml can bind (function getters do not re-evaluate).
    property bool dbusServiceAvailable: false
    property string upscalerBinaryPath: ""
    property bool upscalerStatusKnown: false
    readonly property bool upscalerAvailable: upscalerStatusKnown && upscalerBinaryPath !== ""
    property var wallpaperHistoryEntries: []
    property bool _screenLocked: false

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

    // TransportMedium is a scoped enum: the unscoped Cellular lookup is
    // undefined, so this was never true. isMetered also covers tethered Wi-Fi.
    readonly property bool meteredConnection: cfg.MeteredCacheOnly
        && (NetworkInformation.isMetered
            || NetworkInformation.transportMedium === NetworkInformation.TransportMedium.Cellular)

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

    function warmDiskCache(count) {
        count = Math.max(1, Math.min(48, parseInt(count, 10) || cfg.CacheWarmCount || 12));
        if (cfg.OfflineOnlyMode || cfg.BrowseMode === "playlist" || cfg.BrowseMode === "local") {
            engine.showStatus(i18n("Switch to an online browse mode to warm the cache."), "warn");
            return;
        }
        if ((apiState.isRateLimitedNow() || root._apiOutageOffline) && !root.tripModeActive) {
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
        dbusHelper.listMonitorStatuses(function(list) {
            var targets = Wallhaven.otherMonitorSyncGroups(list, myGroup);
            if (!targets.length) {
                engine.showStatus(i18n("No other monitors to copy search to."), "info");
                return;
            }
            for (var i = 0; i < targets.length; i++) {
                dbusHelper.sendSearch(query, targets[i]);
            }
            engine.showStatus(i18n("Copied search to %1 other screen(s).", targets.length), "info");
            root.refreshMonitorTrustMap();
        });
    }

    function refreshMonitorTrustMap() {
        dbusHelper.listMonitorStatuses(function(list) {
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
        root.configuration.PurityNsfw = !!nsfw && root.effectiveApiKey !== "";
        if (nsfw && root.effectiveApiKey === "") {
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
        root.acknowledgeSearchSettings();
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
            root.acknowledgeSearchSettings();
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
        // On Wayland the unfocused desktop surface cannot set the selection, so
        // TextEdit.copy() silently does nothing. Klipper can; keep TextEdit as a
        // fallback for sessions without it.
        var copyViaTextEdit = function() {
            clipboardHelper.text = text;
            clipboardHelper.selectAll();
            clipboardHelper.copy();
        };
        dbusHelper.setClipboard(text, copyViaTextEdit);
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
            if (root.currentWallpaper) {
                ensureCurrentDetails(function() {
                    if (_currentTags) {
                        copyToClipboard(_currentTags, i18n("Copied tags."));
                    }
                });
            }
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

    // Tags are only prefetched with attribution on or an API key; fetch them now
    // for actions that need them instead of failing with "no tags yet".
    function ensureCurrentDetails(callback) {
        if (_currentTags || !root.currentWallpaper || !root.currentWallpaper.id) {
            callback();
            return;
        }
        engine.fetchWallpaperDetails(root.currentWallpaper, callback);
    }

    function rateCurrentWallpaper(liked) {
        if (!_currentTags && root.currentWallpaper) {
            ensureCurrentDetails(function() {
                if (_currentTags) {
                    rateCurrentWallpaper(liked);
                } else {
                    engine.showStatus(i18n("No tags to rate yet."), "info");
                }
            });
            return;
        }
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
        // Rating changes future searches; it must not replace this wallpaper.
        root.acknowledgeSearchSettings();
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
        dbusHelper.publishStatus(statusJson, function(ok) {
            if (!ok) {
                dbusHelper.writeFile(statusBusFile, statusJson);
            }
        });
        dbusHelper.publishMonitorStatus(diskCacheNamespace, statusJson, function(ok) {
            if (!ok) {
                dbusHelper.writeFile(
                    diskCacheDir + "/wallhaven-status-" + diskCacheNamespace + ".json",
                    statusJson,
                );
            }
        });
        publishDbusConfig();
    }

    property string _lastDbusConfig: ""

    function publishDbusConfig() {
        var config = JSON.stringify({
            varietyWatchEnabled: !!cfg.VarietyWatchEnabled,
            syncGroup: cfg.SyncAdvanceGroup || "default",
        });
        // Rarely changes; no need to rewrite it with every status publish.
        if (config === _lastDbusConfig) {
            return;
        }
        _lastDbusConfig = config;
        dbusHelper.writeFile(dbusConfigFile, config);
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
        dbusHelper.writeFile(historyBusFile, Wallhaven.serializeWallpaperHistory(history, 12));
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
        var source = diskCache.resolveImageSource(wp, remote);
        if (source.indexOf("file:") === 0) {
            // Still in the local disk cache: show the full-resolution cached file directly.
            engine.displayWallpaper(wp, source, true);
            engine.showStatus(i18n("Showing wallpaper #%1 from history.", id), "info");
            return;
        }
        // Not cached locally anymore (LRU evicted it, or disk cache is off): fetch the
        // full wallpaper record so we can display the real image, not just its thumbnail.
        engine.showStatus(i18n("Loading wallpaper #%1 from history…", id), "info");
        engine.requestJson(Wallhaven.buildWallpaperUrl(id, root.effectiveApiKey), function(json) {
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
        dbusHelper.writeFile(historyBusFile, "[]");
        engine.showStatus(i18n("Wallpaper history cleared."), "info");
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
            var path = Wallhaven.urlToLocalPath(source);
            syncLockScreenImage(path, wallpaperId);
            updateVarietySymlink(path);
            return;
        }
        // Remote URL: sync lock screen from the visible frame immediately so
        // locking before the disk-cache write finishes still shows this wallpaper.
        // Disk-cache completion may refresh the lock image again at higher quality.
        if (cfg.SyncLockScreen) {
            var dest = lockSync.lockScreenImagePath(wallpaperId);
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
        dbusHelper.linkVarietyCurrent(cfg.VarietyFolderPath, localPath);
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
            dbusHelper.writeFile(
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
        dbusHelper.syncSystemAccent(kdeColor, gnomeAccent || "");
    }

    function applySmartColorFilter(hexColor) {
        if (!cfg.SmartColorFromWallpaper || !hexColor || !root.configuration) {
            return;
        }
        var nearest = Wallhaven.nearestWallhavenColor(hexColor);
        if (nearest && root.configuration.ColorFilter !== nearest) {
            root.configuration.ColorFilter = nearest;
            scheduleConfigWrite();
            // Applies from the next fetch on; refetching now would chase its own tail.
            root.acknowledgeSearchSettings();
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
        root.acknowledgeSearchSettings();
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
        root.acknowledgeSearchSettings();
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

    function useScreenNameAsSyncGroup() {
        if (!root.configuration) {
            return;
        }
        var group = diskCacheNamespace || "default";
        root._adoptingSyncGroup = true;
        root.configuration.SyncAdvanceEnabled = true;
        root.configuration.SyncAdvanceGroup = group;
        root.configuration.SyncProfilesEnabled = true;
        root._adoptingSyncGroup = false;
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
        if (!root.wallpaperDetailsText && !_currentTags && root.currentWallpaper && !_infoDetailsFetched) {
            _infoDetailsFetched = true;
            ensureCurrentDetails(function() {
                showWallpaperInfo();
                _infoDetailsFetched = false;
            });
            return;
        }
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

    // `key` is the one typed in the settings dialog (not applied yet); callback(ok).
    function saveApiKeyToKWallet(key, callback) {
        apiKeys.save(key, callback);
    }

    function loadApiKeyFromKWallet() {
        apiKeys.load();
    }

    function clearApiKey(keepWallet) {
        apiKeys.clear(keepWallet);
    }

    function testApiKeyNow(callback) {
        var key = root.effectiveApiKey;
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
            apiState.noteApiResult(200, "");
            engine.showStatus(i18n("API key is valid."), "info");
            if (callback)
                callback(true, 200);
        }, function(status) {
            apiState.noteApiResult(status || 0, "key test failed");
            if (callback)
                callback(false, status || 0);
        });
    }

    function exportDebugBundleToFile(destUrl) {
        getDebugInfo(function(info) {
            var dest = Wallhaven.urlToLocalPath(destUrl) || String(destUrl || "");
            if (!dest) {
                engine.showStatus(i18n("Invalid export path."), "warn");
                return;
            }
            dbusHelper.writeFile(dest, info, function() {
                engine.showStatus(i18n("Exported bug report bundle."), "info");
            });
        });
    }

    function isDbusServiceAvailable() {
        return root.dbusServiceAvailable;
    }

    function setServiceAvailable(available) {
        var was = root.dbusServiceAvailable;
        root.dbusServiceAvailable = available;
        if (!available) {
            root.upscalerBinaryPath = "";
            root.upscalerStatusKnown = true;
            return;
        }
        dbusHelper.checkUpscalerAvailable(function(binaryPath) {
            root.upscalerBinaryPath = binaryPath || "";
            root.upscalerStatusKnown = true;
        });
        if (!was && root._configured) {
            // The helper (re)appeared: everything that needed it can catch up.
            root.publishStatus();
            controlBus.pollControl();
            if (cfg.UseKWalletForApiKey && root.walletStatus !== "loaded") {
                apiKeys.load();
            }
        }
    }

    // With bus signals the service's name owner is watched; otherwise ping.
    function refreshServiceAvailability() {
        if (controlBus.signalsActive) {
            setServiceAvailable(controlBus.serviceRegistered);
            return;
        }
        dbusHelper.ping(function() {
            setServiceAvailable(true);
        }, function() {
            setServiceAvailable(false);
        });
    }

    // Screen lock state arrives by signal (or the resume watchdog's poll).
    // Unlocking is treated like a wake: textures are often gone.
    function noteScreenLocked(locked) {
        locked = !!locked;
        if (root._wasScreenLocked && !locked) {
            root.recoverAfterWake("unlock");
        }
        root._wasScreenLocked = locked;
        if (root._screenLocked !== locked) {
            root._screenLocked = locked;
            root.evaluateSlideshowRules();
        }
    }

    function showStatus(message, type, autoHide, opts) {
        engine.showStatus(message, type, autoHide, opts);
    }

    // ---- thin entry points into the components. The settings dialog reaches
    // the wallpaper as `liveWallpaper.<name>`, and components call each other
    // through the root (`host.<name>`) rather than by id.

    function syncLockScreenImage(localPath, wallpaperId) {
        lockSync.syncLockScreenImage(localPath, wallpaperId);
    }

    function ensureLockScreenImage(reason) {
        lockSync.ensureLockScreenImage(reason);
    }

    function enterApiOutageOffline(statusCode, cooldownMs) {
        apiState.enterApiOutageOffline(statusCode, cooldownMs);
    }

    function clearApiOutageOffline(resumeFetch, force) {
        apiState.clearApiOutageOffline(resumeFetch, force);
    }

    function getCacheEntries() {
        return diskCache.getCacheEntries();
    }

    function pinCacheId(id) {
        diskCache.pinCacheId(id);
    }

    function unpinCacheId(id) {
        diskCache.unpinCacheId(id);
    }

    function evictCacheId(id) {
        diskCache.evictCacheId(id);
    }

    function setCacheEntryTags(id, tags) {
        diskCache.setCacheEntryTags(id, tags);
    }

    function clearDiskCache() {
        diskCache.clearDiskCache();
    }

    function pruneUnpinnedCache(keepSlots) {
        return diskCache.pruneUnpinnedCache(keepSlots);
    }

    function reupscaleCachedWallpapers() {
        diskCache.reupscaleCachedWallpapers();
    }

    function clearPreloads() {
        preloadImage.source = "";
        preloadImage2.source = "";
        engine.nextPreloadedUrl = "";
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
        delete profiles[group].ApiKey;
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

    function logDebug(message) {
        if (!cfg.DebugLogEnabled) {
            return;
        }
        var line = new Date().toISOString() + " " + String(message || "");
        dbusHelper.appendFile(debugLogFile, line);
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

    function writeVarietyMetadata(wallpaper, imageUrl) {
        if (!cfg.VarietyMetadataEnabled) {
            return;
        }
        var localPath = diskCache.resolveImageSource(wallpaper, imageUrl);
        if (localPath.indexOf("file:") === 0) {
            localPath = Wallhaven.urlToLocalPath(localPath);
        }
        dbusHelper.writeFile(
            varietyMetadataFile,
            Wallhaven.buildVarietyMetadata(wallpaper, imageUrl, localPath),
        );
    }

    function exportSettingsToFile(destUrl) {
        var json = Wallhaven.exportSettingsSnapshot(cfg);
        dbusHelper.writeFile(settingsExportFile, json, function() {
            dbusHelper.runArgv(["cp", settingsExportFile, Wallhaven.urlToLocalPath(destUrl)]);
            engine.showStatus(i18n("Settings exported."), "info");
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
            // The reply can arrive after the wallpaper item was destroyed.
            if (xhr.readyState !== XMLHttpRequest.DONE || !engine) {
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
            apiState.pollSharedRateLimit();
            if (online) {
                apiState.maybeProbeApiOutageClear();
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
            if (!engine) {
                return;
            }
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
            var resolved = diskCache.resolveImageSource(wallpaper, remote);
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
        // Repair blank lock-screen pages on every monitor (mirrors SyncLockScreen).
        root.ensureLockScreenImage("wake:" + reason);
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
        var destPath = Wallhaven.urlToLocalPath(destUrl);
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
                        controlBus.handleControlCommand(pending);
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
                            diskCache.diskCacheMaxSlots(),
                            diskCache.pinnedCacheIds(),
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
                        var path = diskCache.diskCacheLocalPath(slot);
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
                                diskCache.persistDiskCacheIndex();
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
                                    diskCache.persistDiskCacheIndex();
                                    skipped++;
                                    step();
                                    return;
                                }
                                warmed++;
                                root._warmDone = warmed;
                                diskCache.persistDiskCacheIndex();
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
            root.acknowledgeSearchSettings();
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
            if (apiState.isRateLimitedNow() || root._apiOutageOffline) {
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
                if (root.wallpaperIsVisible() && (apiState.isRateLimitedNow() || root._apiOutageOffline)) {
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
                // Not cfg.ApiKey: with KWallet the key is only held in memory.
                ApiKey: root.effectiveApiKey,
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
                    apiState.noteApiResult(status, text);
                } else if (status === 429) {
                    // Still honor rate limits discovered via detail fetches.
                    apiState.noteApiResult(429, text);
                    apiState.enterApiOutageOffline(429, rateDelayMs);
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
                    apiState.noteApiResult(200, "");
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
            if (apiState.isRateLimitedNow() || root._apiOutageOffline || config.OfflineOnlyMode
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
                        apiState.enterApiOutageOffline(status);
                        endBusy();
                        return;
                    }
                    // Rate limit: soft-offline immediately. Retrying / skipForward
                    // storms made the left monitor jump through cache, and a
                    // favicon "online" check used to clear that latch every 45s.
                    if (status === 429) {
                        root._retryOnDone = null;
                        root._fetchRetryCount = 0;
                        apiState.enterApiOutageOffline(429, rateDelayMs);
                        endBusy();
                        return;
                    }
                    root._fetchRetryCount++;
                    var maxAttempts = Math.max(1, cfg.RetryAttempts || 5);
                    var baseSec = Math.max(1, cfg.RetryDelaySec || 15);
                    if (root._fetchRetryCount > maxAttempts) {
                        root._retryOnDone = null;
                        if (status === 0 || status >= 500) {
                            apiState.enterApiOutageOffline(status);
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
            root.wallpaperDetailsText = "";
            root.syncPreviewMetadata(wallpaper);

            // Cache-only modes make no requests; the tags saved with the
            // cached file keep copy-tags / like / dislike working.
            if (root.effectiveOfflineOnly()) {
                root._currentTags = Wallhaven.diskCacheTagsForId(root._diskCacheIndex, wallpaper.id);
                return;
            }
            if (!cfg.ShowAttribution && !root.effectiveApiKey) {
                return;
            }
            fetchWallpaperDetails(wallpaper, null);
        }

        // Also used on demand (like/dislike/copy tags/info) when attribution is off
        // and there is no API key, so those actions are not dead on that screen.
        function fetchWallpaperDetails(wallpaper, onDone) {
            var done = function() {
                if (onDone) {
                    onDone();
                }
            };
            // Do not probe /w/{id} while rate-limited — those calls were clearing
            // the shared latch on 200 and accelerating the 429 storm. Nor in any
            // other cache-only mode (offline only, playlist, trip, metered).
            if (!wallpaper || !wallpaper.id || root.effectiveOfflineOnly()) {
                done();
                return;
            }
            var resolution = wallpaper.resolution || (wallpaper.dimension_x + "x" + wallpaper.dimension_y);
            var link = wallpaper.url || ("https://wallhaven.cc/w/" + wallpaper.id);

            requestJson(Wallhaven.buildWallpaperUrl(wallpaper.id, root.effectiveApiKey), function(json) {
                // A slow reply must not stamp its tags onto a newer wallpaper.
                if (!json.data || !root.currentWallpaper || String(root.currentWallpaper.id) !== String(wallpaper.id)) {
                    done();
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
                done();
            }, done, { quiet: true });
        }

        function displayWallpaper(wallpaper, url, immediate) {
            if (!url) {
                return false;
            }
            root.currentWallpaper = wallpaper;
            root._pendingRemoteUrl = url;
            root._pendingWallpaperId = wallpaper && wallpaper.id ? String(wallpaper.id) : "";
            var source = diskCache.resolveImageSource(wallpaper, url);
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
                if (!diskCache.resolveImageSource(wp, remote)) {
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
            dbusHelper.listImageFiles(folder, cfg.LocalFolderMaxDepth, cfg.LocalFolderExclude, function(raw) {
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
            if (apiState.isRateLimitedNow() || root._apiOutageOffline) {
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
                var source = diskCache.resolveImageSource(ahead[i], remote);
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
                controlBus.broadcastSyncAdvance();
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
            diskCache.scheduleDiskCacheSave(img);
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
                diskCache.persistDiskCacheIndex();
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

    // Fallback for Plasma builds without D-Bus signal watchers (see ControlBus).
    Timer {
        id: dbusAvailabilityTimer
        interval: 5000
        running: root._configured && !controlBus.signalsActive
        repeat: true
        onTriggered: root.refreshServiceAvailability()
    }

    // Heartbeat only: every real change publishes immediately. The plasmoid
    // treats a status older than 90 s as "engine idle?".
    Timer {
        id: statusPublishTimer
        interval: 30000
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
        }
    }

    Timer {
        id: timeCapsuleTimer
        interval: 3600000
        running: root._configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkTimeCapsules()
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
        id: connectivityTimer
        interval: 45000
        running: root._configured
        repeat: true
        onTriggered: root.checkConnectivity()
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
        // Start high so the first tick queries the current lock state.
        property int lockPollTicks: 6
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

            // ActiveChanged signals normally deliver lock state; ask directly
            // every tick without them, and every 30 s as a safety net with them.
            lockPollTicks++;
            if (controlBus.signalsActive && lockPollTicks < 6) {
                return;
            }
            lockPollTicks = 0;
            dbusHelper.screenSaverCall("GetActive", function(active) {
                root.noteScreenLocked(Wallhaven.dbusReplyIsTrue(active));
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

    // ---- reacting to settings changes ----
    //
    // KConfig keys are capitalized ("SearchText"), and Qt never calls
    // `Connections { function onSearchTextChanged() }` for such a key on a
    // property map: the handler is silently dead (checked against
    // KConfigPropertyMap on Qt 6.11). Bindings do follow those keys, so the
    // settings are watched through derived properties instead.

    // Everything that decides which wallpapers are fetched.
    readonly property string searchSettingsFingerprint: JSON.stringify([
        cfg.SearchText, cfg.BrowseMode, cfg.CollectionUser, cfg.CollectionId, cfg.Sortings,
        cfg.LocalSortings, cfg.Order, cfg.CategoryGeneral, cfg.CategoryAnime, cfg.CategoryPeople,
        cfg.PuritySfw, cfg.PuritySketchy, cfg.PurityNsfw, cfg.MinWidth, cfg.MinHeight, cfg.Ratio,
        cfg.ColorFilter, cfg.TopRange, cfg.ExactResolutions, cfg.UseBlacklist, cfg.DaySearch,
        cfg.NightSearch, cfg.TimeOfDayEnabled, cfg.ImageQuality, cfg.OfflineOnlyMode,
        cfg.FileTypeFilter, cfg.TagBlocklistJson, cfg.TagFavoritesJson, cfg.PreferSharpMatches,
        cfg.WeatherReactiveEnabled, cfg.ScheduleEnabled, cfg.WeekdaySearch, cfg.WeekendSearch,
        cfg.CollectionRotationEnabled, cfg.CollectionRotationJson, cfg.WallpaperOfDayEnabled,
        cfg.WeatherReactiveEnabled ? cfg.WeatherTagCache : "",
        root.meteredConnection,
    ])
    // The fingerprint the engine's current results were fetched for.
    property string _appliedSearchFingerprint: ""

    onSearchSettingsFingerprintChanged: {
        if (root._configured) {
            settingsResetTimer.restart();
        }
    }

    // Call after the plugin itself writes one of those keys and a refetch is
    // not wanted (liking a wallpaper must not replace it).
    function acknowledgeSearchSettings() {
        root._appliedSearchFingerprint = root.searchSettingsFingerprint;
        settingsResetTimer.stop();
    }

    // The settings dialog applies many keys at once; refetch once for all of them.
    Timer {
        id: settingsResetTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root._configured && root.searchSettingsFingerprint !== root._appliedSearchFingerprint) {
                engine.resetSlideshow();
            }
        }
    }

    readonly property string intervalSettingsFingerprint: [
        cfg.SlideshowPaused, cfg.RandomInterval, cfg.DayIntervalMin, cfg.NightIntervalMin,
        cfg.IntervalJitterPercent,
    ].join("|")
    onIntervalSettingsFingerprintChanged: {
        if (root._configured) {
            root.restartIntervalTimer();
        }
    }

    readonly property string parallaxSettingsFingerprint: cfg.ParallaxEnabled + "|" + cfg.ParallaxStrength
    onParallaxSettingsFingerprintChanged: {
        if (!root._configured) {
            return;
        }
        if (cfg.ParallaxEnabled) {
            parallaxPhaseAnim.restart();
        } else {
            parallaxPhaseAnim.stop();
            root.parallaxPhase = 0;
        }
    }

    // Switching sync group applies that group's saved search profile.
    readonly property string watchedSyncGroup: String(cfg.SyncAdvanceGroup || "")
    // Set while the plugin renames the group itself and wants to keep the
    // current search (it is then saved as the new group's profile).
    property bool _adoptingSyncGroup: false
    onWatchedSyncGroupChanged: {
        if (!root._configured || !cfg.SyncProfilesEnabled || root._adoptingSyncGroup) {
            return;
        }
        // After the settings dialog finished writing its other keys, so the
        // profile is not half-overwritten by them.
        Qt.callLater(function() {
            if (root._configured && cfg.SyncProfilesEnabled) {
                root.applySyncProfileForGroup(cfg.SyncAdvanceGroup);
            }
        });
    }

    readonly property bool watchedUseKWallet: !!cfg.UseKWalletForApiKey
    onWatchedUseKWalletChanged: {
        if (root._configured) {
            root.loadApiKeyFromKWallet();
        }
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

    StatusBanner {
        id: statusBanner
        message: root.statusMessage
        type: root.statusType
        shown: root.statusVisible
    }

    AttributionBanner {
        id: attributionBanner
        cfg: root.cfg
        attributionText: root.attributionText
        onClicked: root.showWallpaperInfo()
    }

    DetailsSheet {
        id: detailsSheet
        open: root.wallpaperDetailsOpen
        detailsText: root.wallpaperDetailsText
        onCloseRequested: root.wallpaperDetailsOpen = false
    }

    KenBurns {
        id: kenBurnsAnimation
        host: root
    }

    Component.onCompleted: {
        root.loading = true;
        engine.loadSeenIds();
        engine.loadBlockedIds();
        root.ensureCacheNamespace();
        diskCache.loadDiskCacheIndex();
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
        // Sync-group profiles saved before 3.7 captured the API key into the config.
        if (String(cfg.SyncProfilesJson || "").indexOf("ApiKey") !== -1) {
            root.configuration.SyncProfilesJson = Wallhaven.serializeSyncProfiles(
                Wallhaven.parseSyncProfiles(cfg.SyncProfilesJson));
            scheduleConfigWrite();
        }
        root.loadApiKeyFromKWallet();
        root.refreshServiceAvailability();
        apiState.pollSharedRateLimit();
        // Put something on screen immediately (last preview / cache) so a slow
        // or offline network at login/wake never leaves a blank desktop.
        root.bootstrapWallpaperFromCache();
        root._appliedSearchFingerprint = root.searchSettingsFingerprint;
        root._configured = true;
        scheduleConfigPreviewCapture();
        root.restartIntervalTimer();
        root.publishStatus();
        root._resumeWatchLastMs = Date.now();
        // Every monitor repairs blank lock Image= (mirrors the SyncLockScreen feed).
        Qt.callLater(function() { root.ensureLockScreenImage("startup"); });
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
