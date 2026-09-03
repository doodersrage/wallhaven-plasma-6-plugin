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
    property bool _connectivityOnline: true
    property bool _needsReconnectFetch: false
    property string _currentTags: ""
    property int _offlineCacheCursor: -1
    property var _localImagePaths: []
    property int _localCursor: -1
    property string lockScreenLastSyncAt: ""
    property string lockScreenLastSyncPath: ""
    property bool lockScreenLastSyncOk: false
    property string _pendingFadeUrl: ""
    property int _lastControlTs: 0
    property int _lastSyncAdvanceTs: 0
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
    readonly property var apiHealth: Wallhaven.buildApiHealthSnapshot({
        lastStatus: _apiLastStatus,
        lastError: _apiLastError,
        rateLimitCount: _apiRateLimitCount,
        lastRateLimitAt: _apiLastRateLimitAt,
        lastSuccessAt: _apiLastSuccessAt,
        outageOffline: root._apiOutageOffline,
    })
    readonly property string apiHealthSummary: {
        if (root._apiOutageOffline) {
            return i18n("API down — using cache (%1)", diskCacheEntryCount);
        }
        if (_apiRateLimitCount > 0 && _apiLastStatus === 429) {
            return i18n("Rate limited (429) — %1 time(s)", _apiRateLimitCount);
        }
        if (_apiLastStatus >= 400) {
            return i18n("Last API error: HTTP %1", _apiLastStatus);
        }
        if (_apiLastSuccessAt) {
            return i18n("API OK");
        }
        return i18n("API idle");
    }
    property int _nextSlideshowAt: 0
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
        if (Wallhaven.sanitizeCacheNamespace(cfg.CacheNamespace)) {
            return;
        }
        var ns = diskCacheNamespace;
        if (!ns || ns === "default") {
            ns = "m" + Math.random().toString(36).slice(2, 10);
        }
        root.configuration.CacheNamespace = ns;
        scheduleConfigWrite();
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
            return remoteUrl;
        }
        var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, wallpaper.id);
        if (slot < 0) {
            return remoteUrl;
        }
        Wallhaven.touchDiskCacheId(_diskCacheIndex, wallpaper.id);
        return diskCacheLocalUrl(slot);
    }

    function releaseInactiveLayer() {
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
            ], function() {
                persistDiskCacheIndex();
                if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                    root.syncLockScreenImage(path);
                    root.updateVarietySymlink(path);
                }
                root.maybeUpscaleCachedFile(path, wallpaperForUpscale);
            });
            return;
        }
        req.image.grabToImage(function(result) {
            if (!result) {
                return;
            }
            if (result.saveToFile(path)) {
                persistDiskCacheIndex();
                if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                    root.syncLockScreenImage(path);
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

    function lockScreenImagePath() {
        return diskCacheDir + "/" + Wallhaven.lockScreenImageFileName();
    }

    function syncLockScreenImage(localPath) {
        if (!cfg.SyncLockScreen || !localPath) {
            return;
        }
        var source = urlToLocalPath(localPath);
        if (!source) {
            lockScreenLastSyncOk = false;
            lockScreenLastSyncAt = new Date().toISOString();
            lockScreenLastSyncPath = "";
            publishStatus();
            return;
        }
        var dest = lockScreenImagePath();
        var command = Wallhaven.buildLockScreenSyncCommand(source, dest);
        if (!command) {
            lockScreenLastSyncOk = false;
            lockScreenLastSyncAt = new Date().toISOString();
            lockScreenLastSyncPath = dest;
            publishStatus();
            return;
        }
        dbusHelper.runArgv(["bash", "-lc", command]);
        lockScreenLastSyncOk = true;
        lockScreenLastSyncAt = new Date().toISOString();
        lockScreenLastSyncPath = dest;
        publishStatus();
    }

    function maybeSyncSidecars(img) {
        if (!img) {
            return;
        }
        if (String(img.source) !== String(_pendingImageUrl)) {
            return;
        }
        var source = String(img.source || "");
        if (source.indexOf("file:") === 0) {
            var path = urlToLocalPath(source);
            syncLockScreenImage(path);
            updateVarietySymlink(path);
            return;
        }
        if (!cfg.SyncLockScreen || cfg.DiskCacheEnabled) {
            return;
        }
        var dest = lockScreenImagePath();
        var size = wallpaperSourceSize;
        img.grabToImage(function(result) {
            if (result && result.saveToFile(dest)) {
                syncLockScreenImage(dest);
            }
        }, size);
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
        dbusHelper.runArgv([
            "bash", "-lc",
            "command -v plasma-apply-colors >/dev/null && plasma-apply-colors --accent-color '#"
                + hexColor.replace(/'/g, "") + "' || true",
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

    function enterApiOutageOffline(statusCode) {
        root._apiOutageOffline = true;
        engine.stopRetries();
        var msg = statusCode
            ? i18n("Wallhaven unreachable (%1). Using cache until it recovers.", statusCode)
            : i18n("Using cache until Wallhaven recovers.");
        if (!engine.tryOfflineFallback(msg)) {
            engine.showStatus(msg, "error");
        }
        publishStatus();
    }

    function clearApiOutageOffline(resumeFetch) {
        if (!root._apiOutageOffline) {
            return;
        }
        root._apiOutageOffline = false;
        publishStatus();
        if (resumeFetch && !cfg.OfflineOnlyMode && cfg.BrowseMode !== "playlist" && cfg.BrowseMode !== "local") {
            engine.showStatus(i18n("Wallhaven is back — resuming online search."), "info");
            engine.resetSlideshow();
        }
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
        } else if (status === 200) {
            root._apiLastSuccessAt = new Date().toISOString();
            root._apiLastError = "";
            clearApiOutageOffline(true);
        }
        publishStatus();
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
            return;
        }
        var tmp = urlToLocalPath(diskCacheDir + "/kwallet-apikey.txt");
        dbusHelper.runArgv([
            "bash", "-lc",
            "kwallet-query -r apikey -f org.robertsm.wallhaven -w wallhaven > '"
                + tmp.replace(/'/g, "'\\''") + "' 2>/dev/null",
        ], function() {
            kwalletReadLoader.read(tmp);
        });
    }

    function toggleSlideshowPause() {
        if (!root.configuration) {
            return;
        }
        var paused = !cfg.SlideshowPaused;
        _pausedByRules = false;
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

    function checkConnectivity() {
        var xhr = new XMLHttpRequest();
        xhr.open("HEAD", "https://wallhaven.cc/favicon.ico");
        xhr.timeout = 8000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            var online = xhr.status >= 200 && xhr.status < 400;
            if (online && !_connectivityOnline && _needsReconnectFetch) {
                engine.retryAfterReconnect();
            }
            if (online && root._apiOutageOffline) {
                // Site reachable again — leave soft-offline; next successful API
                // fetch (or explicit resume) clears the outage latch.
                clearApiOutageOffline(true);
            }
            if (!online && _connectivityOnline) {
                _needsReconnectFetch = true;
            }
            _connectivityOnline = online;
        };
        xhr.onerror = function() {
            if (_connectivityOnline) {
                _needsReconnectFetch = true;
            }
            _connectivityOnline = false;
        };
        xhr.send();
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
        }

        function stopRetries() {
            retryTimer.stop();
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
            retryTimer.stop();
            invalidateRequests();
            endBusy();
            root._fetchRetryCount = 0;
            root._imageErrorCount = 0;
            randomSeed = Wallhaven.createRandomSeed();
            page = 1;
            index = 0;
            lastPage = 0;
            total = 0;
            totalShown = 0;
            usedIndices = [];
            clearSeenIds();
            history = [];
            historyIndex = -1;
            apiData = null;
            searchQuery = "";
            favoritesUser = "";
            favoritesId = "";
            nextPreloadedUrl = "";
            cachedApiPage = 0;
            fetchFreshWallpaper(false);
        }

        function fetchFreshWallpaper(fromHistory) {
            if (root.effectiveOfflineOnly()) {
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
                    showStatus(i18n("No wallpapers match your current filters."), "warn");
                    endBusy();
                    return;
                }

                var state = stateObject();
                var wallpaper = Wallhaven.pickWallpaper(configObject(), state, data.data, true);
                if (!wallpaper) {
                    showStatus(i18n("No more wallpapers match your current filters."), "warn");
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

        function scheduleRetry(delayMs, statusCode) {
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
            // System-notify on the first failure only; later retries stay on the desktop banner.
            var opts = { notify: attempt <= 1 };
            var msg;
            if (statusCode === 429) {
                msg = i18n("Rate limited by Wallhaven. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds);
            } else if (statusCode === 0) {
                msg = i18n("Request timed out. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds);
            } else {
                msg = i18n("Request failed (%1). Retry %2/%3 in %4s…", statusCode, attempt, maxAttempts, seconds);
            }
            // Keep a wallpaper on screen from cache while retries continue.
            if (engine.tryOfflineFallback(msg)) {
                // tryOfflineFallback already set the combined status banner.
            } else {
                showStatus(msg, "error", false, opts);
            }
            retryTimer.restart();
        }

        function requestJson(url, onSuccess, onError) {
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
                root.noteApiResult(status, text);
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
                root.noteApiResult(200, "");
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

            if (config.OfflineOnlyMode || config.BrowseMode === "playlist" || config.BrowseMode === "local"
                    || (config.MeteredCacheOnly && root.meteredConnection)) {
                onDone(null);
                return;
            }

            function isStale() {
                return fetchRequestId !== requestId;
            }

            function doFetch() {
                if (isStale()) {
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
                        onDone(null);
                        return;
                    }
                    if (!json.data || !json.data.length) {
                        showStatus(i18n("No wallpapers match your current filters."), "warn");
                        endBusy();
                        onDone(null);
                        return;
                    }
                    json.data = Wallhaven.filterWallpapersByBlocklist(json.data, blockedIds);
                    if (!json.data.length) {
                        showStatus(i18n("All results are blocked. Clear the blocklist or try another search."), "warn");
                        endBusy();
                        onDone(null);
                        return;
                    }
                    json.data = Wallhaven.filterWallpapersByCategories(json.data, config);
                    if (!json.data.length) {
                        showStatus(i18n("No wallpapers match your current filters."), "warn");
                        endBusy();
                        onDone(null);
                        return;
                    }
                    root._fetchRetryCount = 0;
                    apiData = json;
                    lastPage = json.meta.last_page;
                    total = json.meta.total;
                    cachedApiPage = page;
                    onDone(json);
                }, function(status, text, rateDelayMs) {
                    if (isStale()) {
                        onDone(null);
                        return;
                    }
                    // Hard outages: stop hammering Wallhaven and stay on cache.
                    if (status === 502 || status === 503 || status === 504) {
                        root.enterApiOutageOffline(status);
                        endBusy();
                        onDone(null);
                        return;
                    }
                    root._fetchRetryCount++;
                    var maxAttempts = Math.max(1, cfg.RetryAttempts || 5);
                    var baseSec = Math.max(1, cfg.RetryDelaySec || 15);
                    if (root._fetchRetryCount > maxAttempts) {
                        if (status === 0 || status >= 500) {
                            root.enterApiOutageOffline(status);
                            endBusy();
                            onDone(null);
                            return;
                        }
                        var finalMsg = i18n("Wallhaven request failed after %1 attempts.", maxAttempts);
                        if (status)
                            finalMsg = i18n("Request failed (%1). Showing cached wallpaper.", status);
                        if (engine.tryOfflineFallback(finalMsg)) {
                            onDone(null);
                            return;
                        }
                        showStatus(i18n("Wallhaven request failed after %1 attempts.", maxAttempts), "error");
                        endBusy();
                        onDone(null);
                        return;
                    }
                    var delay = rateDelayMs > 0
                        ? rateDelayMs
                        : baseSec * 1000 * Math.pow(2, Math.min(root._fetchRetryCount - 1, 3));
                    delay = Math.min(delay, 300000);
                    if (status === 429 && rateDelayMs <= 0) {
                        delay = Math.max(delay, baseSec * 1000);
                    }
                    scheduleRetry(delay, status);
                    endBusy();
                    onDone(null);
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
            }, function() {});
        }

        function displayWallpaper(wallpaper, url, immediate) {
            if (!url) {
                return;
            }
            root.currentWallpaper = wallpaper;
            root._pendingRemoteUrl = url;
            root._pendingWallpaperId = wallpaper && wallpaper.id ? String(wallpaper.id) : "";
            var source = root.resolveImageSource(wallpaper, url);
            root._pendingUsedCache = source !== url && source.indexOf("file:") === 0;
            _metrics = Wallhaven.recordFetchMetrics(_metrics, 0, root._pendingUsedCache);
            root.showImage(source, immediate);
            updateAttribution(wallpaper);
            writeVarietyMetadata(wallpaper, url);
            root.publishStatus();
            kenBurnsAnimation.restart();
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
            // Already showing a local cache/file image — keep it and only refresh the banner.
            var currentSrc = String(root.currentUrl || "");
            if (currentSrc.indexOf("file:") === 0 && statusOverride) {
                showStatus(statusOverride, "error");
                endBusy();
                return true;
            }
            if (showNextCachedWallpaper(true, false, statusOverride)) {
                endBusy();
                return true;
            }
            return false;
        }

        function showNextCachedWallpaper(immediate, fromHistory, statusOverride) {
            var config = configObject();
            var pick = Wallhaven.pickSmartCachedId(
                root._diskCacheIndex,
                config,
                root._offlineCacheCursor,
            );
            if (!pick.id) {
                return false;
            }
            root._offlineCacheCursor = pick.cursor;
            var id = pick.id;
            var wp = Wallhaven.makeCachedWallpaper(id);
            var remote = Wallhaven.thumbUrlForId(id);
            if (statusOverride) {
                showStatus(statusOverride, "error");
            } else if (cfg.BrowseMode === "playlist") {
                showStatus(i18n("Playlist — cached wallpaper."), "info");
            } else if (cfg.OfflineOnlyMode) {
                showStatus(i18n("Offline mode — showing cached wallpaper."), "info");
            } else {
                showStatus(i18n("Showing cached wallpaper (offline)."), "warn");
            }
            if (!fromHistory) {
                pushHistory({
                    wallpaper: wp,
                    url: remote,
                    index: index,
                    page: page,
                });
            }
            displayWallpaper(wp, remote, immediate !== false);
            notifyRefresh(wp);
            return true;
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
            if (!showNextCachedWallpaper(immediate, fromHistory)) {
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
                return;
            }
            root._needsReconnectFetch = false;
            showStatus(i18n("Network restored. Resuming…"), "info");
            if (!currentUrl) {
                fetchFreshWallpaper(false);
            } else if (cfg.RandomInterval > 0 && !cfg.SlideshowPaused) {
                skipForward();
            }
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

        function skipForward() {
            retryTimer.stop();
            endBusy();
            root.broadcastSyncAdvance();
            maybeAdvanceCollectionRotation();
            if (root.effectiveOfflineOnly()) {
                showStatus(i18n("Loading next cached wallpaper…"), "info");
                showOfflineWallpaper(false, false);
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
        if (baseUrl === currentBase && currentUrl !== "") {
            // Bust Qt image cache for forced reloads; keep file:// paths stable.
            if (baseUrl.indexOf("file:") !== 0) {
                url = baseUrl + "?_t=" + Date.now();
            }
        }

        _pendingImageUrl = url;
        root.stopTransitionAnimations();
        var transitionMode = effectiveTransitionMode();
        var useTransition = cfg.CrossfadeMs > 0 && !immediate && currentUrl !== "";
        if (useTransition && transitionMode === "fadeblack") {
            _pendingFadeUrl = url;
            fadeBlackOut.start();
            currentUrl = url;
            return;
        }
        if (useTransition && transitionMode === "slide") {
            if (activeIsForeground) {
                backgroundImage.source = url;
                slideToBackground.start();
            } else {
                foregroundImage.source = url;
                slideToForeground.start();
            }
            currentUrl = url;
            return;
        }
        if (useTransition && transitionMode === "zoom") {
            if (activeIsForeground) {
                backgroundImage.source = url;
                zoomToBackground.start();
            } else {
                foregroundImage.source = url;
                zoomToForeground.start();
            }
            currentUrl = url;
            return;
        }
        var crossfade = useTransition && transitionMode !== "instant";

        if (crossfade) {
            if (activeIsForeground) {
                backgroundImage.source = url;
                crossfadeToBackground.start();
            } else {
                foregroundImage.source = url;
                crossfadeToForeground.start();
            }
            currentUrl = url;
            return;
        }

        backgroundImage.source = url;
        backgroundLayer.opacity = 1;
        foregroundLayer.opacity = 0;
        foregroundImage.source = "";
        activeIsForeground = false;
        currentUrl = url;
    }

    function handleImageStatus(img) {
        if (!img || String(img.source) !== String(_pendingImageUrl)) {
            return;
        }
        if (img.status === Image.Ready) {
            _imageErrorCount = 0;
            scheduleConfigPreviewCapture();
            scheduleDiskCacheSave(img);
            maybeSyncSidecars(img);
            return;
        }
        if (img.status !== Image.Error) {
            return;
        }

        // Stale/missing cache entry → fall back to the remote URL once.
        if (_pendingUsedCache && _pendingRemoteUrl) {
            _pendingUsedCache = false;
            var slot = Wallhaven.diskCacheSlotForId(_diskCacheIndex, _pendingWallpaperId);
            if (slot >= 0 && _diskCacheIndex.ids) {
                Wallhaven.evictDiskCacheOccupant(_diskCacheIndex, _pendingWallpaperId);
                _diskCacheIndex.ids[slot] = "";
                persistDiskCacheIndex();
            }
            showImage(_pendingRemoteUrl, true);
            return;
        }

        _imageErrorCount++;
        if (currentWallpaper && currentWallpaper.id) {
            engine.markSeen(currentWallpaper.id);
        }
        // When Wallhaven/API is unhealthy, skip remote fetches and cycle local cache.
        if (!root.apiHealth.healthy || root.effectiveOfflineOnly()) {
            if (cfg.DiskCacheEnabled && (cfg.OfflineCacheFallback || root.effectiveOfflineOnly())
                    && engine.showNextCachedWallpaper(true, false,
                        i18n("Image failed to load. Showing cached wallpaper."))) {
                return;
            }
        }
        if (_imageErrorCount >= 5) {
            engine.showStatus(i18n("Could not download wallpaper images. Check your connection."), "error");
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

    function sendSystemNotification(title, text, isError) {
        if (!text) {
            return;
        }
        var notification = notificationComponent.createObject(root, {
            title: title || i18n("Wallhaven"),
            text: text,
            iconName: isError ? "dialog-error" : "preferences-desktop-wallpaper",
            urgency: isError ? Notification.HighUrgency : Notification.LowUrgency,
        });
        if (notification) {
            notification.sendEvent();
        }
    }

    Component {
        id: notificationComponent
        Notification {
            componentName: "org.robertsm.wallhaven"
            eventId: "notification"
            autoDelete: true
        }
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
            wallhavenMessage("WriteTextFile", "ss", [urlToLocalPath(path), text || ""], callback);
        }

        function readFile(path, callback) {
            wallhavenMessage("ReadTextFile", "s", [urlToLocalPath(path)], callback);
        }

        function appendFile(path, line, callback) {
            wallhavenMessage("AppendTextFile", "ss", [urlToLocalPath(path), line || ""], callback);
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
            wallhavenMessage("RunArgv", "s", [JSON.stringify(cleaned)], callback);
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
            dbusHelper.readFile(tmpPath, function(text) {
                if (!root.configuration) {
                    return;
                }
                var key = String(text || "").trim();
                if (key) {
                    root.configuration.ApiKey = key;
                    scheduleConfigWrite();
                }
            });
        }
    }

    Timer {
        id: statusPublishTimer
        interval: 5000
        running: root._configured
        repeat: true
        onTriggered: root.publishStatus()
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
                var cmd = Wallhaven.parseControlCommand(text);
                if (!cmd || cmd.ts <= root._lastControlTs) {
                    return;
                }
                if (cmd.group !== (cfg.SyncAdvanceGroup || "default")) {
                    return;
                }
                root._lastControlTs = cmd.ts;
                switch (cmd.cmd) {
                case "next": engine.skipForward(); break;
                case "prev": engine.previousWallpaper(); break;
                case "reload": root.reloadWallpaper(); break;
                case "pause":
                case "resume":
                    root.toggleSlideshowPause();
                    break;
                case "search":
                    if (cmd.query && root.configuration) {
                        root.configuration.BrowseMode = "search";
                        root.configuration.SearchText = cmd.query;
                        root.configuration.WallpaperOfDayEnabled = false;
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
                    root.clearApiOutageOffline(true);
                    break;
                default: break;
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
                if (sync.issuer === root._instanceId) {
                    return;
                }
                root._lastSyncAdvanceTs = sync.advanceAt;
                if (!engine.busy) {
                    engine.skipForward();
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
        onStarted: activeIsForeground = false
        onFinished: scheduleConfigPreviewCapture()
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

    Timer {
        id: retryTimer
        interval: 60000
        repeat: false
        onTriggered: engine.skipForward()
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
        // Migrate before KWallet so upgrades that flip UseKWalletForApiKey load the key.
        var migration = Wallhaven.migrateConfigurationToV3(root.configuration);
        if (migration.migrated) {
            scheduleConfigWrite();
            logDebug("Migrated config schema " + migration.from + " → " + migration.to);
        }
        root.loadApiKeyFromKWallet();
        engine.fetchFreshWallpaper(false);
        root._configured = true;
        scheduleConfigPreviewCapture();
        root.restartIntervalTimer();
        root.publishStatus();
        if (cfg.PauseOnBatteryLow) {
            batteryPollTimer.start();
        }
        Qt.callLater(function() { root.checkConnectivity(); });
    }

    Component.onDestruction: {
        flushConfigWrite();
    }
}
