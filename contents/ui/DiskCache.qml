import QtQuick
import "../code/wallhaven.js" as Wallhaven

// LRU disk cache of displayed wallpapers: slot index (persisted in the
// wallpaper config), slot files under the plasmashell cache dir, pinning,
// pruning, size quota and the optional upscale pass.
Item {
    id: diskCache

    required property var host   // wallpaper root (main.qml)
    required property var dbus   // DBusHelper
    readonly property var cfg: host.cfg

    property var cacheIndex: ({ ids: [], next: 0, categories: {}, purities: {}, dimensions: {}, tags: {} })
    property var saveRequest: null

    function diskCacheMaxSlots() {
        return Math.max(5, Math.min(200, cfg.DiskCacheMaxSlots || 40));
    }

    function loadDiskCacheIndex() {
        if (!host.configuration) {
            cacheIndex = { ids: [], next: 0, categories: {}, purities: {}, dimensions: {} };
            return;
        }
        cacheIndex = Wallhaven.parseDiskCacheIndex(host.configuration.DiskCacheIndexJson || "");
    }

    function persistDiskCacheIndex() {
        if (!host.configuration) {
            return;
        }
        host.configuration.DiskCacheIndexJson = Wallhaven.serializeDiskCacheIndex(cacheIndex);
        host.scheduleConfigWrite();
    }

    function diskCacheLocalPath(slot) {
        return host.diskCacheDir + "/" + Wallhaven.diskCacheFileName(slot, host.diskCacheNamespace);
    }

    function diskCacheLocalUrl(slot) {
        return Wallhaven.localPathToUrl(diskCacheLocalPath(slot));
    }

    function resolveImageSource(wallpaper, remoteUrl) {
        if (!remoteUrl) {
            return "";
        }
        if (!cfg.DiskCacheEnabled || !wallpaper || !wallpaper.id) {
            // Soft-offline must never open a network image URL.
            if (host.effectiveOfflineOnly()) {
                return "";
            }
            return remoteUrl;
        }
        var slot = Wallhaven.diskCacheSlotForId(cacheIndex, wallpaper.id);
        if (slot < 0) {
            if (host.effectiveOfflineOnly()) {
                return "";
            }
            return remoteUrl;
        }
        Wallhaven.touchDiskCacheId(cacheIndex, wallpaper.id);
        return diskCacheLocalUrl(slot);
    }

    function scheduleDiskCacheSave(img) {
        if (!cfg.DiskCacheEnabled || !img || host._pendingUsedCache || !host._pendingWallpaperId) {
            return;
        }
        if (String(img.source) !== String(host._pendingImageUrl)) {
            return;
        }
        saveRequest = {
            id: host._pendingWallpaperId,
            remoteUrl: host._pendingRemoteUrl,
            image: img,
        };
        diskCacheSaveTimer.restart();
    }

    function writeDiskCacheFromImage() {
        var req = saveRequest;
        saveRequest = null;
        if (!req || !req.image || !req.id || !cfg.DiskCacheEnabled) {
            return;
        }
        if (req.image.status !== Image.Ready) {
            return;
        }
        var slot = Wallhaven.allocateDiskCacheSlot(
            cacheIndex,
            req.id,
            diskCacheMaxSlots(),
            pinnedCacheIds(),
            host.currentWallpaper && host.currentWallpaper.category
                ? host.currentWallpaper.category : "",
            host.currentWallpaper && host.currentWallpaper.purity
                ? host.currentWallpaper.purity : "",
        );
        if (slot < 0) {
            return;
        }
        var path = diskCacheLocalPath(slot);
        var size = host.wallpaperSourceSize;
        var wallpaperForUpscale = host.currentWallpaper;
        Wallhaven.setDiskCacheDimensions(
            cacheIndex,
            req.id,
            wallpaperForUpscale && wallpaperForUpscale.dimension_x,
            wallpaperForUpscale && wallpaperForUpscale.dimension_y,
        );
        Wallhaven.setDiskCacheTags(cacheIndex, req.id, host._currentTags);
        var originalUrl = String(req.remoteUrl || "");
        if (cfg.CacheDownloadOriginal && originalUrl.indexOf("http") === 0) {
            dbus.runArgv([
                "curl", "-fsSL", "--max-time", "120", "-o", path, originalUrl,
            ], function(reply) {
                var text = String(reply || "").trim();
                if (text !== "ok") {
                    host.logDebug("Original cache curl failed for " + req.id + " reply=" + text);
                    Wallhaven.releaseDiskCacheId(cacheIndex, req.id);
                    persistDiskCacheIndex();
                    return;
                }
                dbus.runArgv(["test", "-s", path], function(sizeReply) {
                    var sizeOk = String(sizeReply || "").trim();
                    if (sizeOk !== "ok") {
                        host.logDebug("Original cache empty after curl for " + req.id);
                        Wallhaven.releaseDiskCacheId(cacheIndex, req.id);
                        persistDiskCacheIndex();
                        return;
                    }
                    persistDiskCacheIndex();
                    if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                        host.syncLockScreenImage(path, req.id);
                        host.updateVarietySymlink(path);
                    }
                    diskCache.maybeUpscaleCachedFile(path, wallpaperForUpscale);
                });
            });
            return;
        }
        req.image.grabToImage(function(result) {
            if (!result) {
                return;
            }
            // Wallpaper may have advanced while grabToImage was pending.
            if (String(host._pendingWallpaperId || "") !== String(req.id)) {
                return;
            }
            if (result.saveToFile(path)) {
                persistDiskCacheIndex();
                if (cfg.SyncLockScreen || cfg.VarietySymlinkEnabled) {
                    host.syncLockScreenImage(path, req.id);
                    host.updateVarietySymlink(path);
                }
                diskCache.maybeUpscaleCachedFile(path, wallpaperForUpscale);
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
        var screenWidth = Math.round(host.width) || 1920;
        var screenHeight = Math.round(host.height) || 1080;
        if (!Wallhaven.needsUpscale(wallpaper, screenWidth, screenHeight)) {
            return;
        }
        dbus.checkUpscalerAvailable(function(binaryPath) {
            if (!binaryPath) {
                return;
            }
            dbus.upscale(path, path, function(ok) {
                host.logDebug((ok ? "Upscaled" : "Upscale failed for") + " disk-cache image: " + path);
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
            host.showStatus(i18n("Enable \"Upscale low-res\" first."), "warn");
            return;
        }
        dbus.checkUpscalerAvailable(function(binaryPath) {
            if (!binaryPath) {
                host.showStatus(i18n("No upscaler installed (realesrgan-ncnn-vulkan not found on PATH)."), "warn");
                return;
            }
            var entries = getCacheEntries();
            var screenWidth = Math.round(host.width) || 1920;
            var screenHeight = Math.round(host.height) || 1080;
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
                host.showStatus(i18n("No cached wallpapers need upscaling right now."), "info");
                return;
            }
            var total = queue.length;
            var upscaled = 0;
            var failed = 0;
            var runNext = function() {
                if (!queue.length) {
                    host.showStatus(i18n("Re-upscale finished: %1 upscaled, %2 failed.", upscaled, failed), "info");
                    return;
                }
                var path = queue.shift();
                dbus.upscale(path, path, function(ok) {
                    if (ok) {
                        upscaled++;
                    } else {
                        failed++;
                    }
                    runNext();
                });
            };
            host.showStatus(i18n("Re-upscaling %1 cached wallpaper(s)…", total), "info");
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
        cacheIndex = { ids: [], next: 0, categories: {}, purities: {}, dimensions: {} };
        persistDiskCacheIndex();
        host.clearPreloads();
        host.showStatus(i18n("Disk cache cleared."), "info");
    }

    function pruneUnpinnedCache(keepSlots) {
        var maxKeep = keepSlots !== undefined && keepSlots !== null
            ? keepSlots
            : diskCacheMaxSlots();
        var pinned = Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson);
        var victims = Wallhaven.listUnpinnedCacheIdsOldestFirst(cacheIndex, pinned);
        var occupied = Wallhaven.listCachedIds(cacheIndex).length;
        var paths = [];
        var removed = 0;
        for (var i = 0; i < victims.length && occupied - removed > maxKeep; i++) {
            var id = victims[i];
            var slot = Wallhaven.diskCacheSlotForId(cacheIndex, id);
            if (slot < 0) {
                continue;
            }
            paths.push(diskCacheLocalPath(slot));
            Wallhaven.evictDiskCacheOccupant(cacheIndex, id);
            cacheIndex.ids[slot] = "";
            removed++;
        }
        if (!removed) {
            host.showStatus(i18n("No unpinned cache entries to prune."), "info");
            return 0;
        }
        cacheFileDeleter.deletePaths(paths);
        persistDiskCacheIndex();
        host.showStatus(i18n("Pruned %1 unpinned cache entr(y/ies).", removed), "info");
        host.publishStatus();
        return removed;
    }

    function enforceCacheQuota(sizeMap) {
        var pinned = Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson);
        var removedSlots = Wallhaven.pruneUnpinnedCacheIds(
            cacheIndex,
            pinned,
            diskCacheMaxSlots(),
        );
        var maxMb = Math.max(0, parseInt(cfg.DiskCacheMaxMb, 10) || 0);
        var removedBytes = [];
        if (maxMb > 0 && sizeMap) {
            removedBytes = Wallhaven.pruneCacheToMaxBytes(
                cacheIndex,
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
            if (!String(cacheIndex.ids[s] || "")) {
                paths.push(diskCacheLocalPath(s));
            }
        }
        cacheFileDeleter.deletePaths(paths);
        persistDiskCacheIndex();
        host.publishStatus();
        return removed.length;
    }

    function refreshCacheFileSizes(callback) {
        var ids = Wallhaven.listCachedIds(cacheIndex);
        var paths = [];
        var idByPath = {};
        for (var i = 0; i < ids.length; i++) {
            var slot = Wallhaven.diskCacheSlotForId(cacheIndex, ids[i]);
            if (slot < 0) {
                continue;
            }
            var path = diskCacheLocalPath(slot);
            paths.push(path);
            idByPath[path] = ids[i];
        }
        if (!paths.length) {
            if (callback)
                callback({});
            return;
        }
        dbus.statCacheFiles(paths, function(sizes) {
            var sizeMap = {};
            for (var p = 0; p < paths.length; p++) {
                sizeMap[idByPath[paths[p]]] = parseInt(sizes[paths[p]], 10) || 0;
            }
            if (callback)
                callback(sizeMap);
        });
    }

    function setCacheEntryTags(id, tags) {
        if (!id) {
            return;
        }
        Wallhaven.setDiskCacheTags(cacheIndex, id, tags);
        persistDiskCacheIndex();
    }

    function pinnedCacheIds() {
        return Wallhaven.parsePinnedCacheIds(cfg.PinnedCacheIdsJson || "[]");
    }

    function getCacheEntries() {
        return Wallhaven.listCacheEntries(cacheIndex, pinnedCacheIds());
    }

    function pinCacheId(id) {
        id = String(id || "").trim();
        if (!id || !host.configuration) {
            return;
        }
        var ids = pinnedCacheIds();
        if (ids.indexOf(id) === -1) {
            ids.push(id);
            host.configuration.PinnedCacheIdsJson = Wallhaven.serializePinnedCacheIds(ids);
            host.scheduleConfigWrite();
        }
    }

    function unpinCacheId(id) {
        id = String(id || "").trim();
        if (!id || !host.configuration) {
            return;
        }
        var ids = pinnedCacheIds().filter(function(entry) { return entry !== id; });
        host.configuration.PinnedCacheIdsJson = Wallhaven.serializePinnedCacheIds(ids);
        host.scheduleConfigWrite();
    }

    function evictCacheId(id) {
        id = String(id || "").trim();
        if (!id || pinnedCacheIds().indexOf(id) !== -1) {
            return;
        }
        var slot = Wallhaven.diskCacheSlotForId(cacheIndex, id);
        if (slot >= 0) {
            Wallhaven.evictDiskCacheOccupant(cacheIndex, id);
            cacheIndex.ids[slot] = "";
            persistDiskCacheIndex();
            dbus.runArgv(["rm", "-f", diskCacheLocalPath(slot)]);
            host.logDebug("Evicted cache id " + id);
        }
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
            dbus.runArgv(["rm", "-f", path], deleteNext);
        }
    }

    Timer {
        id: diskCacheSaveTimer
        interval: 700
        repeat: false
        onTriggered: diskCache.writeDiskCacheFromImage()
    }

    // Size quota: checked once a minute (it used to spawn a `stat` per cached
    // file every 5 s from the status heartbeat).
    Timer {
        interval: 60000
        running: host._configured && cfg.DiskCacheEnabled && cfg.DiskCacheMaxMb > 0
        repeat: true
        onTriggered: diskCache.refreshCacheFileSizes(function(sizeMap) {
            diskCache.enforceCacheQuota(sizeMap);
        })
    }
}
