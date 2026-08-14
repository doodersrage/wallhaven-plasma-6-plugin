import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
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
    readonly property string previewCacheFile: StandardPaths.writableLocation(StandardPaths.CacheLocation)
        + "/wallhaven-preview.png"
    readonly property string diskCacheDir: StandardPaths.writableLocation(StandardPaths.CacheLocation)
    readonly property string controlBusFile: diskCacheDir + "/wallhaven-control.json"
    readonly property string varietyMetadataFile: diskCacheDir + "/wallhaven-variety.json"
    readonly property string settingsExportFile: diskCacheDir + "/wallhaven-settings-export.json"
    readonly property string statusBusFile: diskCacheDir + "/wallhaven-status.json"
    readonly property string panelTintFile: diskCacheDir + "/wallhaven-panel-tint.json"
    readonly property string debugLogFile: diskCacheDir + "/wallhaven-debug.log"
    readonly property int diskCacheEntryCount: Wallhaven.listCachedIds(_diskCacheIndex).length

    function syncAdvanceFile() {
        var group = (cfg.SyncAdvanceGroup || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
        return diskCacheDir + "/wallhaven-sync-" + group + ".json";
    }

    function effectiveOfflineOnly() {
        return cfg.OfflineOnlyMode
            || (cfg.MeteredCacheOnly && root.meteredConnection);
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
        if (cfg.KenBurnsEnabled) {
            w = Math.round(w * 1.25);
            h = Math.round(h * 1.25);
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
    property var _diskCacheIndex: ({ ids: [], next: 0 })
    property var _diskCacheSaveRequest: null
    property int _fetchRetryCount: 0
    property bool _connectivityOnline: true
    property bool _needsReconnectFetch: false
    property string _currentTags: ""
    property int _offlineCacheCursor: -1
    property string _pendingFadeUrl: ""
    property int _lastControlTs: 0
    property int _lastSyncAdvanceTs: 0
    property string _instanceId: Math.random().toString(36).slice(2, 10)
    property string wallpaperDetailsText: ""
    property int _nextSlideshowAt: 0
    property var _metrics: Wallhaven.createMetricsState()
    property int _batteryPercent: 100
    property bool _rulesPausedSlideshow: false

    readonly property real parallaxOffsetX: {
        if (!cfg.ParallaxEnabled) {
            return 0;
        }
        var strength = Math.max(0, Math.min(100, cfg.ParallaxStrength || 50)) / 100;
        var seed = parseInt(String(_instanceId).slice(0, 4), 36) || 0;
        return ((seed % 50) - 25) / 25 * (root.width || 1920) * 0.02 * strength;
    }

    readonly property real parallaxOffsetY: {
        if (!cfg.ParallaxEnabled) {
            return 0;
        }
        var strength = Math.max(0, Math.min(100, cfg.ParallaxStrength || 50)) / 100;
        var seed = parseInt(String(_instanceId).slice(4, 8), 36) || 0;
        return ((seed % 50) - 25) / 25 * (root.height || 1080) * 0.015 * strength;
    }

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
        copyIdAction, copyTagsAction, copyUrlAction, favoriteAction,
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
        var path = String(url);
        if (path.indexOf("file://") === 0) {
            path = path.substring(7);
        }
        return decodeURIComponent(path);
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
            _diskCacheIndex = { ids: [], next: 0 };
            return;
        }
        _diskCacheIndex = Wallhaven.parseDiskCacheIndex(root.configuration.DiskCacheIndexJson || "");
    }

    function persistDiskCacheIndex() {
        if (!root.configuration) {
            return;
        }
        root.configuration.DiskCacheIndexJson = Wallhaven.serializeDiskCacheIndex(_diskCacheIndex);
        scheduleConfigWrite();
    }

    function diskCacheLocalPath(slot) {
        return diskCacheDir + "/" + Wallhaven.diskCacheFileName(slot);
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
        return diskCacheLocalUrl(slot);
    }

    function releaseInactiveLayer() {
        if (activeIsForeground) {
            backgroundImage.source = "";
        } else {
            foregroundImage.source = "";
        }
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
        );
        if (slot < 0) {
            return;
        }
        var path = diskCacheLocalPath(slot);
        var size = wallpaperSourceSize;
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
            }
        }, size);
    }

    function clearDiskCache() {
        var slots = diskCacheMaxSlots();
        var paths = [];
        for (var i = 0; i < slots; i++) {
            paths.push(diskCacheLocalPath(i));
        }
        cacheFileDeleter.deletePaths(paths);
        _diskCacheIndex = { ids: [], next: 0 };
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
        settingsFileWriter.writeFile(
            statusBusFile,
            Wallhaven.buildStatusSnapshot({
                id: currentWallpaperId !== "wallpaper" ? currentWallpaperId : "",
                thumbUrl: currentWallpaperId !== "wallpaper"
                    ? Wallhaven.thumbUrlForId(currentWallpaperId) : "",
                pageUrl: currentPageUrl,
                tags: _currentTags,
                paused: cfg.SlideshowPaused,
                slideshowActive: slideshowActive(),
                nextChangeMs: nextMs,
                attribution: attributionText,
                syncGroup: cfg.SyncAdvanceGroup || "default",
                metrics: _metrics,
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
        scheduleConfigWrite();
    }

    function getWallpaperHistory() {
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
        engine.displayWallpaper(wp, source.indexOf("file:") === 0 ? source : remote, true);
        engine.showStatus(i18n("Showing wallpaper #%1 from history.", id), "info");
    }

    function clearWallpaperHistory() {
        if (!root.configuration) {
            return;
        }
        root.configuration.WallpaperHistoryJson = "[]";
        scheduleConfigWrite();
        engine.showStatus(i18n("Wallpaper history cleared."), "info");
    }

    function syncLockScreenImage(localPath) {
        if (!cfg.SyncLockScreen || !localPath) {
            return;
        }
        dbusHelper.runArgv([
            "bash", "-lc",
            "kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image && "
                + "kwriteconfig6 --file kscreenlockerrc --group Greeter --key Wallpaper \""
                + localPath.replace(/"/g, '\\"') + "\"",
        ]);
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
        if (cfg.PanelTintEnabled) {
            settingsFileWriter.writeFile(
                panelTintFile,
                Wallhaven.buildPanelTintMetadata(hexColor, wallpaperId),
                cfg.AutoPanelAccentEnabled ? function() {
                    applyPanelAccent(hexColor);
                } : null,
            );
        } else if (cfg.AutoPanelAccentEnabled) {
            applyPanelAccent(hexColor);
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
        try {
            var preset = Wallhaven.importPresetFromShareUrl(url);
            if (!preset || !root.configuration) {
                return;
            }
            Wallhaven.applyPresetToConfig(preset, root.configuration);
            scheduleConfigWrite();
            engine.showStatus(i18n("Imported preset %1.", preset.name || ""), "info");
            engine.resetSlideshow();
        } catch (e) {
            engine.showStatus(i18n("Invalid preset URL."), "error");
        }
    }

    function applyVarietySearch() {
        var path = StandardPaths.writableLocation(StandardPaths.HomeLocation)
            + "/.config/variety/variety.conf";
        varietyConfLoader.load(path);
    }

    function evaluateSlideshowRules() {
        var shouldPause = false;
        if (cfg.PauseOnBatteryLow && _batteryPercent >= 0
                && _batteryPercent <= (cfg.BatteryLowThreshold || 20)) {
            shouldPause = true;
        }
        if (cfg.PauseWhenInactive && Qt.application.state !== Qt.ApplicationActive) {
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
            root.configuration.SlideshowPaused = true;
            scheduleConfigWrite();
            intervalTimer.stop();
            engine.showStatus(i18n("Slideshow paused by power/activity rules."), "info");
        } else if (!shouldPause && cfg.SlideshowPaused && _rulesPausedSlideshow === false) {
            // Only auto-resume if pause was from rules - keep simple: user resumes manually
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
            _diskCacheIndex.ids[slot] = "";
            persistDiskCacheIndex();
            dbusHelper.runArgv(["rm", "-f", diskCacheLocalPath(slot)]);
            logDebug("Evicted cache id " + id);
        }
    }

    function buildDebugBundleText(logTail) {
        return Wallhaven.buildDebugBundle(cfg, {
            version: "1.7.1",
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
        var tmp = diskCacheDir + "/kwallet-apikey.txt";
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
                    if (tryOfflineFallback()) {
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
            if (statusCode === 429) {
                showStatus(i18n("Rate limited by Wallhaven. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds), "error", false, opts);
            } else if (statusCode === 0) {
                showStatus(i18n("Request timed out. Retry %1/%2 in %3s…", attempt, maxAttempts, seconds), "error", false, opts);
            } else {
                showStatus(i18n("Request failed (%1). Retry %2/%3 in %4s…", statusCode, attempt, maxAttempts, seconds), "error", false, opts);
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

            if (config.OfflineOnlyMode || (config.MeteredCacheOnly && root.meteredConnection)) {
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
                    root._fetchRetryCount++;
                    var maxAttempts = Math.max(1, cfg.RetryAttempts || 5);
                    var baseSec = Math.max(1, cfg.RetryDelaySec || 15);
                    if (root._fetchRetryCount > maxAttempts) {
                        if (engine.tryOfflineFallback()) {
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

        function tryOfflineFallback() {
            if (!cfg.DiskCacheEnabled) {
                return false;
            }
            if (!cfg.OfflineCacheFallback && !root.effectiveOfflineOnly()) {
                return false;
            }
            if (showNextCachedWallpaper(true, false)) {
                endBusy();
                return true;
            }
            return false;
        }

        function showNextCachedWallpaper(immediate, fromHistory) {
            var ids = Wallhaven.listCachedIds(root._diskCacheIndex);
            if (!ids.length) {
                return false;
            }
            root._offlineCacheCursor = (root._offlineCacheCursor + 1) % ids.length;
            var id = ids[root._offlineCacheCursor];
            var wp = Wallhaven.makeCachedWallpaper(id);
            var remote = Wallhaven.thumbUrlForId(id);
            if (cfg.OfflineOnlyMode) {
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
            busy = true;
            root.loading = true;
            if (!showNextCachedWallpaper(immediate, fromHistory)) {
                showStatus(i18n("No cached wallpapers available."), "warn");
            }
            endBusy();
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

        function wallhavenMessage(member, signature, args, callback) {
            var msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: member,
                signature: signature,
                arguments: args,
            });
            if (callback) {
                PDBus.SessionBus.asyncCall(msg, callback, function(err) {
                    console.warn("Wallhaven D-Bus call failed:", member, err);
                });
            } else {
                PDBus.SessionBus.asyncCall(msg);
            }
        }

        function writeFile(path, text, callback) {
            wallhavenMessage("WriteTextFile", "ss", [path, text], callback);
        }

        function readFile(path, callback) {
            wallhavenMessage("ReadTextFile", "s", [path], callback);
        }

        function runArgv(argv, callback) {
            wallhavenMessage("RunArgv", "s", [JSON.stringify(argv)], callback);
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
            dbusHelper.runArgv([
                "python3", "-c",
                "import sys; p=sys.argv[1]; l=sys.argv[2]; open(p,'a',encoding='utf-8').write(l+'\\n')",
                debugLogFile, line,
            ]);
        }
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
        id: varietyConfLoader
        function load(path) {
            dbusHelper.readFile(path, function(text) {
                if (!text) {
                    engine.showStatus(i18n("No Variety config found."), "warn");
                    return;
                }
                var search = Wallhaven.parseVarietySearch(text);
                if (!search) {
                    engine.showStatus(i18n("No image_fetch_search in Variety config."), "warn");
                    return;
                }
                if (root.configuration) {
                    root.configuration.BrowseMode = "search";
                    root.configuration.SearchText = search;
                    root.configuration.WallpaperOfDayEnabled = false;
                    scheduleConfigWrite();
                    engine.resetSlideshow();
                    engine.showStatus(i18n("Applied Variety search: %1", search), "info");
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
                case "importpreset":
                    if (cmd.query) {
                        root.importPresetFromUrl(cmd.query);
                    }
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

        Item {
            id: backgroundTransform
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            property real zoomScale: 1
            scale: kenBurnsAnimation.bgScale * zoomScale
            x: kenBurnsAnimation.bgX + root.parallaxOffsetX
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

        Item {
            id: foregroundTransform
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            property real zoomScale: 1
            scale: kenBurnsAnimation.fgScale * zoomScale
            x: kenBurnsAnimation.fgX + root.parallaxOffsetX
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
        NumberAnimation { target: foregroundTransform; property: "x"; from: root.width * 0.08; to: root.parallaxOffsetX; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
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
        NumberAnimation { target: backgroundTransform; property: "x"; from: root.width * 0.08; to: root.parallaxOffsetX; duration: cfg.CrossfadeMs; easing.type: Easing.OutCubic }
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
            if (!cfg.KenBurnsEnabled) {
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
        if (cfg.RandomInterval > 0) {
            return cfg.RandomInterval * 60 * 1000 * 0.9;
        }
        var speed = Math.max(1, Math.min(cfg.KenBurnsSpeed, 100));
        return 120000 - ((speed - 1) / 99) * 90000;
    }

    NumberAnimation { id: bgKenBurns; target: kenBurnsAnimation; property: "bgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgKenBurns; target: kenBurnsAnimation; property: "fgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanX; target: kenBurnsAnimation; property: "bgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanX; target: kenBurnsAnimation; property: "fgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanY; target: kenBurnsAnimation; property: "bgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanY; target: kenBurnsAnimation; property: "fgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }

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
        anchors.margins: 16
        width: parent.width - 32
        height: attributionVisible ? attributionLabel.implicitHeight + 16 : 0
        visible: attributionVisible
        radius: 8
        color: "#000000"
        opacity: 0.65

        readonly property bool attributionVisible: cfg.ShowAttribution && root.attributionText !== ""
        readonly property string corner: cfg.AttributionCorner || "bottom-left"

        anchors.left: corner.indexOf("left") >= 0 ? parent.left : undefined
        anchors.right: corner.indexOf("right") >= 0 ? parent.right : undefined
        anchors.top: corner.indexOf("top") >= 0 ? parent.top : undefined
        anchors.bottom: corner.indexOf("bottom") >= 0 ? parent.bottom : undefined
        anchors.horizontalCenter: corner === "bottom-left" || corner === "bottom-right"
            ? undefined : (corner.indexOf("top") >= 0 ? parent.horizontalCenter : undefined)

        onAttributionVisibleChanged: {
            if (attributionVisible && cfg.AttributionAutoHideSec > 0) {
                visible = true;
                attributionHideTimer.restart();
            }
        }

        QQC2.Label {
            id: attributionLabel
            anchors.centerIn: parent
            width: parent.width - 32
            wrapMode: Text.WordWrap
            color: "#ffffff"
            font.pointSize: Math.max(7, Math.round(9 * (cfg.AttributionFontScale || 100) / 100))
            text: root.attributionText
        }
    }

    Connections {
        target: root.configuration
        function onSearchTextChanged() { if (root._configured) engine.resetSlideshow(); }
        function onApiKeyChanged() { if (root._configured) engine.resetSlideshow(); }
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
        root.loadDiskCacheIndex();
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
