.pragma library

var WALLPAPERS_PER_PAGE = 24;

function createRandomSeed() {
    return Math.random().toString(36).slice(2, 10);
}

function boolTriplet(values) {
    var result = "";
    for (var i = 0; i < values.length; i++) {
        result += values[i] ? "1" : "0";
    }
    return result;
}

function thumbsObject(wallpaper) {
    if (!wallpaper) {
        return null;
    }
    return wallpaper.thumbs || null;
}

function wallpaperUrl(wallpaper, quality) {
    if (!wallpaper) {
        return "";
    }
    var thumbs = thumbsObject(wallpaper);
    // Wallhaven only serves full wallpapers at `path`. thumbs.* are previews.
    // small = low-bandwidth preview thumb; large/original = full wallpaper file.
    if (quality === "small") {
        return (thumbs && thumbs.large)
            || (thumbs && thumbs.original)
            || wallpaper.thumb
            || (thumbs && thumbs.small)
            || thumbUrlForId(wallpaper.id)
            || wallpaper.path
            || "";
    }
    return wallpaper.path
        || wallpaper.large
        || (thumbs && thumbs.original)
        || (thumbs && thumbs.large)
        || thumbUrlForId(wallpaper.id)
        || "";
}

function thumbUrl(wallpaper) {
    if (!wallpaper) {
        return "";
    }
    var thumbs = thumbsObject(wallpaper);
    if (thumbs && thumbs.large) {
        return thumbs.large;
    }
    if (thumbs && thumbs.original) {
        return thumbs.original;
    }
    if (wallpaper.thumb) {
        return wallpaper.thumb;
    }
    if (thumbs && thumbs.small) {
        return thumbs.small;
    }
    return thumbUrlForId(wallpaper.id);
}

function thumbUrlForId(id) {
    id = String(id || "");
    if (id.length >= 2) {
        return "https://th.wallhaven.cc/lg/" + id.substring(0, 2) + "/" + id + ".jpg";
    }
    return "";
}

function parseSeenIds(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.length) {
            return parsed.map(function(id) { return String(id); });
        }
    } catch (e) {
        // fall through
    }
    return String(raw).split(",").map(function(id) {
        return id.trim();
    }).filter(function(id) {
        return id.length > 0;
    });
}

function serializeSeenIds(ids) {
    if (!ids || !ids.length) {
        return "[]";
    }
    return JSON.stringify(ids.slice(-500));
}

function parseIdList(raw) {
    return parseSeenIds(raw);
}

function serializeIdList(ids, max) {
    max = max || 1000;
    if (!ids || !ids.length) {
        return "[]";
    }
    return JSON.stringify(ids.slice(-max));
}

function parseBlockedIds(raw) {
    return parseIdList(raw);
}

function serializeBlockedIds(ids) {
    return serializeIdList(ids, 1000);
}

function isBlocked(id, blockedIds) {
    return blockedIds && blockedIds.indexOf(String(id)) !== -1;
}

function addBlockedId(blockedIds, id) {
    id = String(id || "");
    if (!id) {
        return blockedIds || [];
    }
    var list = (blockedIds || []).slice();
    if (list.indexOf(id) !== -1) {
        return list;
    }
    list.push(id);
    if (list.length > 1000) {
        list = list.slice(-1000);
    }
    return list;
}

function filterWallpapersByBlocklist(wallpapers, blockedIds) {
    if (!wallpapers || !wallpapers.length || !blockedIds || !blockedIds.length) {
        return wallpapers || [];
    }
    return wallpapers.filter(function(wallpaper) {
        return !isBlocked(wallpaper.id, blockedIds);
    });
}

function parseSearchPresets(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        return parsed && parsed.length ? parsed : [];
    } catch (e) {
        return [];
    }
}

function serializeSearchPresets(presets) {
    if (!presets || !presets.length) {
        return "[]";
    }
    return JSON.stringify(presets);
}

var EXPORTABLE_SETTINGS_KEYS = [
    "SearchText", "ApiKey", "BrowseMode", "CollectionUser", "CollectionId",
    "RandomInterval", "SlideshowPaused", "CrossfadeMs", "ImageQuality",
    "Sortings", "LocalSortings", "Order", "CategoryGeneral", "CategoryAnime",
    "CategoryPeople", "PuritySfw", "PuritySketchy", "PurityNsfw",
    "MinWidth", "MinHeight", "Ratio", "ColorFilter", "TopRange",
    "ExactResolutions", "UseBlacklist", "DedupEnabled", "KenBurnsEnabled",
    "KenBurnsSpeed", "ShowAttribution", "RequestTimeoutSec", "RetryDelaySec",
    "RetryAttempts", "NotifyOnRefresh", "NotifyOnError", "ShowStatusBanner",
    "DiskCacheEnabled", "DiskCacheMaxSlots", "OfflineCacheFallback",
    "OfflineOnlyMode", "TimeOfDayEnabled", "DaySearch", "NightSearch",
    "BlockedIdsJson", "SearchPresetsJson", "FileTypeFilter", "IntervalJitterPercent",
    "DayIntervalMin", "NightIntervalMin", "TransitionMode", "AttributionCorner",
    "AttributionAutoHideSec", "AttributionFontScale", "UseKWalletForApiKey",
    "MeteredCacheOnly", "SyncAdvanceEnabled", "SyncAdvanceGroup",
    "VarietyMetadataEnabled", "ControlBusEnabled",
    "TagBlocklistJson", "ScheduleEnabled", "WeekdaySearch", "WeekendSearch",
    "CollectionRotationEnabled", "CollectionRotationJson",
    "SyncLockScreen", "PanelTintEnabled", "ParallaxEnabled", "ParallaxStrength",
    "VarietyFolderPath", "VarietySymlinkEnabled",
    "WallpaperOfDayEnabled", "FavoritesRefreshMin", "DebugLogEnabled",
    "PinnedCacheIdsJson", "AdaptivePreloadEnabled", "PreloadCount",
    "AutoPanelAccentEnabled", "PauseOnBatteryLow", "BatteryLowThreshold",
    "PauseWhenInactive", "SmartColorFromWallpaper", "TagFavoritesJson",
];

function exportSettingsSnapshot(cfg) {
    var snapshot = {
        version: 5,
        plugin: "org.robertsm.wallhaven",
        exportedAt: new Date().toISOString(),
        settings: {},
    };
    for (var i = 0; i < EXPORTABLE_SETTINGS_KEYS.length; i++) {
        var key = EXPORTABLE_SETTINGS_KEYS[i];
        if (cfg && cfg[key] !== undefined) {
            snapshot.settings[key] = cfg[key];
        }
    }
    return JSON.stringify(snapshot, null, 2);
}

function importSettingsSnapshot(raw) {
    var parsed = JSON.parse(raw);
    if (!parsed || parsed.plugin !== "org.robertsm.wallhaven" || !parsed.settings) {
        throw new Error("invalid snapshot");
    }
    return parsed.settings;
}

function buildPresetFromConfig(name, cfg) {
    return {
        name: String(name || "").trim(),
        SearchText: cfg.SearchText || "",
        Sortings: cfg.Sortings || "random",
        Order: cfg.Order || "desc",
        TopRange: cfg.TopRange || "1M",
        CategoryGeneral: !!cfg.CategoryGeneral,
        CategoryAnime: !!cfg.CategoryAnime,
        CategoryPeople: !!cfg.CategoryPeople,
        PuritySfw: !!cfg.PuritySfw,
        PuritySketchy: !!cfg.PuritySketchy,
        PurityNsfw: !!cfg.PurityNsfw,
        MinWidth: cfg.MinWidth || "",
        MinHeight: cfg.MinHeight || "",
        Ratio: cfg.Ratio || "landscape",
        ColorFilter: cfg.ColorFilter || "",
        ExactResolutions: cfg.ExactResolutions || "",
        UseBlacklist: !!cfg.UseBlacklist,
        TimeOfDayEnabled: !!cfg.TimeOfDayEnabled,
        DaySearch: cfg.DaySearch || "",
        NightSearch: cfg.NightSearch || "",
    };
}

function applyPresetToConfig(preset, configuration) {
    if (!preset || !configuration) {
        return false;
    }
    var keys = Object.keys(preset);
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (key === "name") {
            continue;
        }
        configuration[key] = preset[key];
    }
    return true;
}

function parseRateLimitDelayMs(xhr, statusCode) {
    if (!xhr) {
        return 0;
    }
    if (statusCode === 429) {
        var retryAfter = xhr.getResponseHeader("Retry-After");
        if (retryAfter) {
            var seconds = parseInt(retryAfter, 10);
            if (!isNaN(seconds) && seconds > 0) {
                return seconds * 1000;
            }
        }
    }
    return 0;
}

function buildWallpaperPageUrl(id) {
    id = String(id || "");
    return id ? ("https://wallhaven.cc/w/" + id) : "";
}

function tagsToCopyString(tags) {
    if (!tags || !tags.length) {
        return "";
    }
    var names = [];
    for (var i = 0; i < tags.length; i++) {
        if (tags[i] && tags[i].name) {
            names.push(String(tags[i].name));
        }
    }
    return names.join(", ");
}

function appendSearchModifiers(query, cfg) {
    query = String(query || "").trim();
    if (cfg.FileTypeFilter === "jpg" || cfg.FileTypeFilter === "png" || cfg.FileTypeFilter === "webp") {
        query = (query ? query + " " : "") + "type:" + cfg.FileTypeFilter;
    }
    if (cfg.TagBlocklistJson) {
        query = appendTagBlocklist(query, parseTagBlocklist(cfg.TagBlocklistJson));
    }
    return query.trim();
}

function parseTagBlocklist(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.length) {
            return [];
        }
        return parsed.map(function(tag) {
            return String(tag || "").trim().replace(/\s+/g, "_");
        }).filter(function(tag) { return tag.length > 0; });
    } catch (e) {
        return [];
    }
}

function serializeTagBlocklist(tags) {
    if (!tags || !tags.length) {
        return "[]";
    }
    var cleaned = [];
    for (var i = 0; i < tags.length; i++) {
        var tag = String(tags[i] || "").trim();
        if (tag && cleaned.indexOf(tag) === -1) {
            cleaned.push(tag);
        }
    }
    return JSON.stringify(cleaned);
}

function appendTagBlocklist(query, tags) {
    query = String(query || "").trim();
    if (!tags || !tags.length) {
        return query;
    }
    for (var i = 0; i < tags.length; i++) {
        if (tags[i]) {
            query += " -" + tags[i];
        }
    }
    return query.trim();
}

function isWeekend() {
    var day = new Date().getDay();
    return day === 0 || day === 6;
}

function buildSimilarSearchQuery(wallpaperId) {
    wallpaperId = String(wallpaperId || "").trim();
    return wallpaperId ? ("like:" + wallpaperId) : "";
}

var DISK_CACHE_SLOTS = 40;

function diskCacheSlotCount() {
    return DISK_CACHE_SLOTS;
}

function parseDiskCacheIndex(raw) {
    var empty = { ids: [], next: 0 };
    if (!raw) {
        return empty;
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.ids || !parsed.ids.length) {
            return {
                ids: [],
                next: Math.max(0, parseInt(parsed && parsed.next, 10) || 0),
            };
        }
        return {
            ids: parsed.ids.map(function(id) { return id === null || id === undefined ? "" : String(id); }),
            next: Math.max(0, parseInt(parsed.next, 10) || 0),
        };
    } catch (e) {
        return empty;
    }
}

function serializeDiskCacheIndex(index) {
    if (!index) {
        return "{\"ids\":[],\"next\":0}";
    }
    return JSON.stringify({
        ids: index.ids || [],
        next: index.next || 0,
    });
}

function diskCacheSlotForId(index, id) {
    if (!index || !index.ids || !id) {
        return -1;
    }
    return index.ids.indexOf(String(id));
}

function allocateDiskCacheSlot(index, id, maxSlots, pinnedIds) {
    maxSlots = maxSlots || DISK_CACHE_SLOTS;
    id = String(id || "");
    if (!id) {
        return -1;
    }
    if (!index.ids) {
        index.ids = [];
    }
    pinnedIds = pinnedIds || [];
    var existing = index.ids.indexOf(id);
    if (existing !== -1) {
        return existing;
    }
    while (index.ids.length < maxSlots) {
        index.ids.push("");
    }
    var slot = (index.next || 0) % maxSlots;
    var attempts = 0;
    while (attempts < maxSlots) {
        var occupant = String(index.ids[slot] || "");
        if (!occupant || pinnedIds.indexOf(occupant) === -1) {
            break;
        }
        slot = (slot + 1) % maxSlots;
        attempts++;
    }
    index.ids[slot] = id;
    index.next = (slot + 1) % maxSlots;
    return slot;
}

function diskCacheFileName(slot) {
    var n = Math.max(0, parseInt(slot, 10) || 0);
    var padded = n < 10 ? ("0" + n) : String(n);
    return "wallhaven-cache-" + padded + ".jpg";
}

function listCachedIds(index) {
    if (!index || !index.ids) {
        return [];
    }
    var ids = [];
    for (var i = 0; i < index.ids.length; i++) {
        var id = String(index.ids[i] || "").trim();
        if (id && ids.indexOf(id) === -1) {
            ids.push(id);
        }
    }
    return ids;
}

function pickRandomCachedId(index) {
    var ids = listCachedIds(index);
    if (!ids.length) {
        return "";
    }
    return ids[(Math.random() * ids.length) | 0];
}

function makeCachedWallpaper(id) {
    id = String(id || "");
    return {
        id: id,
        url: "https://wallhaven.cc/w/" + id,
        category: "cached",
        purity: "cached",
        resolution: "",
        dimension_x: 0,
        dimension_y: 0,
    };
}

function cloneSlideshowState(state) {
    return {
        page: state.page,
        index: state.index,
        seed: state.seed,
        lastPage: state.lastPage,
        total: state.total,
        totalShown: state.totalShown,
        usedIndices: state.usedIndices.slice(),
        seenIds: state.seenIds.slice(),
        blockedIds: (state.blockedIds || []).slice(),
        screenWidth: state.screenWidth,
        screenHeight: state.screenHeight,
        searchQuery: state.searchQuery,
        favoritesUser: state.favoritesUser,
        favoritesId: state.favoritesId,
    };
}

function peekAheadWallpapers(cfg, state, wallpapers, count) {
    count = Math.max(1, count || 1);
    var preview = cloneSlideshowState(state);
    var results = [];
    for (var i = 0; i < count; i++) {
        var result = findNextWallpaper(cfg, preview, wallpapers);
        if (!result.wallpaper) {
            break;
        }
        results.push(result.wallpaper);
        preview.totalShown++;
        updatePageState(cfg, preview, wallpapers.length);
    }
    return results;
}

function normalizeCollectionEntry(entry) {
    if (!entry) {
        return null;
    }
    var username = entry.username
        || (entry.user && entry.user.username)
        || entry.user
        || "";
    var id = entry.id !== undefined && entry.id !== null ? String(entry.id) : "";
    if (!username || !id) {
        return null;
    }
    var label = entry.label || entry.name || ("Collection " + id);
    return {
        username: String(username),
        id: id,
        label: String(label),
        display: username + " · " + label + " (#" + id + ")",
    };
}

function parseCollectionsResponse(json) {
    var results = [];
    if (!json || !json.data || !json.data.length) {
        return results;
    }
    for (var i = 0; i < json.data.length; i++) {
        var normalized = normalizeCollectionEntry(json.data[i]);
        if (normalized) {
            results.push(normalized);
        }
    }
    return results;
}

function getEffectiveSearchText(cfg) {
    var base = "";
    if (cfg.TimeOfDayEnabled) {
        var hour = new Date().getHours();
        var isDay = hour >= 6 && hour < 20;
        base = isDay ? (cfg.DaySearch || "") : (cfg.NightSearch || "");
    } else if (cfg.ScheduleEnabled) {
        base = isWeekend() ? (cfg.WeekendSearch || "") : (cfg.WeekdaySearch || "");
    } else {
        base = cfg.SearchText || "";
    }
    return appendTagFavorites(base, parseTagFavorites(cfg.TagFavoritesJson));
}

function parseTagFavorites(raw) {
    return parseTagBlocklist(raw);
}

function appendTagFavorites(query, tags) {
    query = String(query || "").trim();
    if (!tags || !tags.length) {
        return query;
    }
    for (var i = 0; i < tags.length; i++) {
        if (tags[i]) {
            query += (query ? " " : "") + tags[i].replace(/_/g, " ");
        }
    }
    return query.trim();
}

function isDayPeriod() {
    var hour = new Date().getHours();
    return hour >= 6 && hour < 20;
}

function baseIntervalMinutes(cfg, dayPeriod) {
    if (dayPeriod && cfg.DayIntervalMin > 0) {
        return cfg.DayIntervalMin;
    }
    if (!dayPeriod && cfg.NightIntervalMin > 0) {
        return cfg.NightIntervalMin;
    }
    return Math.max(0, cfg.RandomInterval || 0);
}

function computeIntervalMs(cfg, dayPeriod) {
    var minutes = baseIntervalMinutes(cfg, dayPeriod);
    if (minutes <= 0) {
        return 0;
    }
    var ms = minutes * 60 * 1000;
    var jitter = Math.max(0, Math.min(50, cfg.IntervalJitterPercent || 0));
    if (jitter > 0) {
        var spread = ms * (jitter / 100);
        ms = ms - spread / 2 + (Math.random() * spread);
    }
    return Math.max(60000, Math.round(ms));
}

function formatWallpaperDetails(wallpaper, apiData) {
    if (!wallpaper) {
        return "";
    }
    var data = apiData || wallpaper;
    var lines = [];
    lines.push("Wallhaven #" + wallpaper.id);
    var resolution = wallpaper.resolution
        || ((wallpaper.dimension_x || data.dimension_x || "?")
            + "x"
            + (wallpaper.dimension_y || data.dimension_y || "?"));
    lines.push(resolution);
    if (data.views !== undefined) {
        lines.push("Views: " + data.views);
    }
    if (data.favorites !== undefined) {
        lines.push("Favorites: " + data.favorites);
    }
    if (data.category || wallpaper.category) {
        lines.push("Category: " + (data.category || wallpaper.category));
    }
    if (data.purity || wallpaper.purity) {
        lines.push("Purity: " + (data.purity || wallpaper.purity));
    }
    if (data.uploader && data.uploader.username) {
        lines.push("Uploader: " + data.uploader.username);
    }
    if (data.tags && data.tags.length) {
        lines.push("Tags: " + tagsToCopyString(data.tags));
    }
    lines.push(buildWallpaperPageUrl(wallpaper.id));
    return lines.join("\n");
}

function buildVarietyMetadata(wallpaper, imageUrl, localPath) {
    return JSON.stringify({
        id: wallpaper ? String(wallpaper.id) : "",
        url: buildWallpaperPageUrl(wallpaper && wallpaper.id),
        image: imageUrl || "",
        localPath: localPath || "",
        updatedAt: new Date().toISOString(),
    }, null, 2);
}

function base64EncodeUtf8(str) {
    var bytes = [];
    for (var i = 0; i < str.length; i++) {
        var code = str.charCodeAt(i);
        if (code < 0x80) {
            bytes.push(code);
        } else if (code < 0x800) {
            bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
        } else {
            bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
        }
    }
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var output = "";
    for (var j = 0; j < bytes.length; j += 3) {
        var b1 = bytes[j];
        var b2 = j + 1 < bytes.length ? bytes[j + 1] : 0;
        var b3 = j + 2 < bytes.length ? bytes[j + 2] : 0;
        var triplet = (b1 << 16) | (b2 << 8) | b3;
        output += chars.charAt((triplet >> 18) & 63);
        output += chars.charAt((triplet >> 12) & 63);
        output += j + 1 < bytes.length ? chars.charAt((triplet >> 6) & 63) : "=";
        output += j + 2 < bytes.length ? chars.charAt(triplet & 63) : "=";
    }
    return output;
}

function parseControlCommand(raw) {
    if (!raw) {
        return null;
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.cmd) {
            return null;
        }
        return {
            cmd: String(parsed.cmd),
            ts: parseInt(parsed.ts, 10) || 0,
            group: parsed.group ? String(parsed.group) : "default",
            query: parsed.query ? String(parsed.query) : "",
        };
    } catch (e) {
        return null;
    }
}

function buildControlCommand(cmd, group, query) {
    var payload = {
        cmd: cmd,
        ts: Date.now(),
        group: group || "default",
    };
    if (query) {
        payload.query = String(query);
    }
    return JSON.stringify(payload);
}

function parseVarietySearch(iniText) {
    if (!iniText) {
        return "";
    }
    var lines = String(iniText).split("\n");
    var inPrefs = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "");
        if (line === "[preferences]") {
            inPrefs = true;
            continue;
        }
        if (line.length && line.charAt(0) === "[") {
            inPrefs = false;
            continue;
        }
        if (inPrefs && line.indexOf("image_fetch_search") === 0) {
            var parts = line.split("=", 2);
            return parts.length > 1 ? parts[1].replace(/^\s+|\s+$/g, "") : "";
        }
    }
    return "";
}

function parseSyncAdvance(raw) {
    if (!raw) {
        return null;
    }
    try {
        var parsed = JSON.parse(raw);
        return {
            advanceAt: parseInt(parsed.advanceAt, 10) || 0,
            issuer: parsed.issuer ? String(parsed.issuer) : "",
        };
    } catch (e) {
        return null;
    }
}

function buildSyncAdvance(issuer) {
    return JSON.stringify({
        advanceAt: Date.now(),
        issuer: issuer || "wallhaven",
    });
}

function parseCollectionRotation(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.length) {
            return [];
        }
        var results = [];
        for (var i = 0; i < parsed.length; i++) {
            var entry = parsed[i];
            if (!entry || !entry.user || !entry.id) {
                continue;
            }
            results.push({
                user: String(entry.user).trim(),
                id: String(entry.id).trim(),
                label: entry.label ? String(entry.label) : "",
            });
        }
        return results;
    } catch (e) {
        return [];
    }
}

function serializeCollectionRotation(entries) {
    if (!entries || !entries.length) {
        return "[]";
    }
    return JSON.stringify(entries);
}

function parseCollectionRotationLines(text) {
    var lines = String(text || "").split(/\r?\n/);
    var results = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || line.charAt(0) === "#") {
            continue;
        }
        var parts = line.split(/[\/:]/);
        if (parts.length < 2) {
            continue;
        }
        results.push({
            user: parts[0].trim(),
            id: parts[1].trim(),
            label: parts.slice(2).join(":").trim(),
        });
    }
    return results;
}

function formatCollectionRotationLines(entries) {
    if (!entries || !entries.length) {
        return "";
    }
    return entries.map(function(entry) {
        var line = entry.user + "/" + entry.id;
        if (entry.label) {
            line += "  # " + entry.label;
        }
        return line;
    }).join("\n");
}

function pickCollectionRotation(entries, index) {
    if (!entries || !entries.length) {
        return null;
    }
    var idx = Math.max(0, parseInt(index, 10) || 0) % entries.length;
    return {
        entry: entries[idx],
        index: idx,
        nextIndex: (idx + 1) % entries.length,
    };
}

function parseWallpaperHistory(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.length) {
            return [];
        }
        return parsed.filter(function(entry) {
            return entry && entry.id;
        }).map(function(entry) {
            return {
                id: String(entry.id),
                thumbUrl: entry.thumbUrl ? String(entry.thumbUrl) : thumbUrlForId(String(entry.id)),
                ts: parseInt(entry.ts, 10) || 0,
            };
        });
    } catch (e) {
        return [];
    }
}

function serializeWallpaperHistory(entries, maxEntries) {
    maxEntries = maxEntries || 30;
    if (!entries || !entries.length) {
        return "[]";
    }
    var slice = entries.slice(-maxEntries);
    return JSON.stringify(slice);
}

function appendWallpaperHistory(history, entry, maxEntries) {
    history = history ? history.slice() : [];
    if (!entry || !entry.id) {
        return history;
    }
    var id = String(entry.id);
    for (var i = history.length - 1; i >= 0; i--) {
        if (history[i].id === id) {
            history.splice(i, 1);
        }
    }
    history.push({
        id: id,
        thumbUrl: entry.thumbUrl || thumbUrlForId(id),
        ts: entry.ts || Date.now(),
    });
    maxEntries = maxEntries || 30;
    if (history.length > maxEntries) {
        history = history.slice(-maxEntries);
    }
    return history;
}

function buildStatusSnapshot(data) {
    return JSON.stringify({
        id: data.id || "",
        thumbUrl: data.thumbUrl || "",
        pageUrl: data.pageUrl || "",
        tags: data.tags || "",
        paused: !!data.paused,
        slideshowActive: !!data.slideshowActive,
        nextChangeMs: Math.max(0, parseInt(data.nextChangeMs, 10) || 0),
        attribution: data.attribution || "",
        syncGroup: data.syncGroup || "default",
        metrics: data.metrics || null,
        updatedAt: new Date().toISOString(),
    }, null, 2);
}

function pickTransitionMode(cfg) {
    var mode = cfg && cfg.TransitionMode ? String(cfg.TransitionMode) : "crossfade";
    if (mode !== "random") {
        return mode;
    }
    var modes = ["crossfade", "fadeblack", "slide", "zoom"];
    return modes[Math.floor(Math.random() * modes.length)];
}

function dominantColorFromWallhaven(colors) {
    if (!colors || !colors.length) {
        return "";
    }
    var first = colors[0];
    if (typeof first === "string") {
        return String(first).replace("#", "").trim().toLowerCase();
    }
    if (first && first.hex) {
        return String(first.hex).replace("#", "").trim().toLowerCase();
    }
    return "";
}

function buildPanelTintMetadata(hexColor, wallpaperId) {
    return JSON.stringify({
        wallpaperId: wallpaperId ? String(wallpaperId) : "",
        color: hexColor || "",
        updatedAt: new Date().toISOString(),
    }, null, 2);
}

function varietySymlinkName() {
    return "wallhaven-current.jpg";
}

function parsePinnedCacheIds(raw) {
    return parseIdList(raw);
}

function serializePinnedCacheIds(ids) {
    return serializeIdList(ids, 100);
}

function computePreloadCount(cfg, networkOnline, metered) {
    var base = Math.max(0, Math.min(4, cfg.PreloadCount || 2));
    if (!cfg.AdaptivePreloadEnabled) {
        return base;
    }
    if (!networkOnline || metered) {
        return Math.max(0, base - 1);
    }
    return base;
}

function parseCuratedPresets(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.length) {
            return [];
        }
        return parsed;
    } catch (e) {
        return [];
    }
}

function mergePresetLists(existing, curated) {
    var out = existing ? existing.slice() : [];
    for (var i = 0; i < curated.length; i++) {
        var preset = curated[i];
        if (!preset || !preset.name) {
            continue;
        }
        var found = false;
        for (var j = 0; j < out.length; j++) {
            if (out[j].name === preset.name) {
                found = true;
                break;
            }
        }
        if (!found) {
            out.push(preset);
        }
    }
    return out;
}

function encodePresetSharePayload(preset) {
    if (!preset) {
        return "";
    }
    var json = JSON.stringify(preset);
    return base64EncodeUtf8(json);
}

function decodePresetSharePayload(encoded) {
    if (!encoded) {
        throw new Error("empty preset payload");
    }
    var binary = atobPolyfill(String(encoded).trim());
    return JSON.parse(binary);
}

function atobPolyfill(input) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    var str = String(input).replace(/=+$/, "");
    var output = "";
    for (var bc = 0, bs = 0, buffer, i = 0; (buffer = str.charAt(i++));) {
        buffer = chars.indexOf(buffer);
        if (buffer === -1) {
            continue;
        }
        bs = bc % 4 ? bs * 64 + buffer : buffer;
        if (bc++ % 4) {
            output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
        }
    }
    return output;
}

function buildPresetShareUrl(preset) {
    var payload = encodePresetSharePayload(preset);
    return "wallhaven://preset/" + payload;
}

function pluginVersion() {
    return "2.0.0";
}

function appendDebugLogLine(existing, line, maxLines) {
    maxLines = maxLines || 200;
    var lines = String(existing || "").split("\n").filter(function(entry) { return entry.length > 0; });
    lines.push(String(line || ""));
    if (lines.length > maxLines) {
        lines = lines.slice(-maxLines);
    }
    return lines.join("\n") + "\n";
}

function buildDebugBundle(cfg, extras) {
    extras = extras || {};
    return JSON.stringify({
        plugin: "org.robertsm.wallhaven",
        version: extras.version || "",
        exportedAt: new Date().toISOString(),
        settings: exportSettingsSnapshot(cfg),
        status: extras.status || null,
        metrics: extras.metrics || null,
        logTail: extras.logTail || "",
        githubIssue: buildGithubIssueBody(cfg, extras),
    }, null, 2);
}

function buildGithubIssueBody(cfg, extras) {
    extras = extras || {};
    var lines = [
        "## Wallhaven Plasma bug report",
        "",
        "**Version:** " + (extras.version || "unknown"),
        "**Wallpaper ID:** " + ((extras.status && extras.status.id) || "n/a"),
        "",
        "### Steps",
        "1. ",
        "",
        "### Expected",
        "",
        "### Actual",
        "",
        "### Metrics",
        "```json",
        JSON.stringify(extras.metrics || {}, null, 2),
        "```",
        "",
        "<details><summary>Settings snapshot</summary>",
        "",
        "```json",
        exportSettingsSnapshot(cfg),
        "```",
        "",
        "</details>",
    ];
    return lines.join("\n");
}

function createMetricsState() {
    return {
        fetchCount: 0,
        cacheHits: 0,
        cacheMisses: 0,
        imageErrors: 0,
        rateLimits: 0,
        lastFetchMs: 0,
        avgFetchMs: 0,
    };
}

function recordFetchMetrics(metrics, elapsedMs, fromCache) {
    metrics = metrics || createMetricsState();
    metrics.fetchCount = (metrics.fetchCount || 0) + 1;
    if (fromCache) {
        metrics.cacheHits = (metrics.cacheHits || 0) + 1;
    } else {
        metrics.cacheMisses = (metrics.cacheMisses || 0) + 1;
    }
    if (elapsedMs > 0) {
        metrics.lastFetchMs = elapsedMs;
        var count = metrics.fetchCount;
        metrics.avgFetchMs = Math.round(
            ((metrics.avgFetchMs || 0) * (count - 1) + elapsedMs) / count,
        );
    }
    return metrics;
}

function importPresetFromShareUrl(url) {
    var raw = String(url || "").trim();
    var prefix = "wallhaven://preset/";
    if (raw.indexOf(prefix) === 0) {
        raw = raw.substring(prefix.length);
    }
    return decodePresetSharePayload(raw);
}

function listCacheEntries(index, pinnedIds) {
    pinnedIds = pinnedIds || [];
    if (!index || !index.ids) {
        return [];
    }
    var entries = [];
    for (var i = 0; i < index.ids.length; i++) {
        var id = String(index.ids[i] || "").trim();
        if (!id) {
            continue;
        }
        entries.push({
            id: id,
            slot: i,
            pinned: pinnedIds.indexOf(id) !== -1,
            thumbUrl: thumbUrlForId(id),
        });
    }
    return entries;
}

// Wallhaven only accepts these palette values for the colors= filter.
var WALLHAVEN_COLORS = [
    "660000", "990000", "cc0000", "cc3333", "ea4c88",
    "993399", "663399", "333399", "0066cc", "0099cc",
    "66cccc", "77cc33", "669900", "336600", "666600",
    "999900", "cccc33", "ffff00", "ffcc33", "ff9900",
    "ff6600", "cc6633", "996633", "663300", "000000",
    "999999", "cccccc", "ffffff", "424153",
];

function parseHexColor(hex) {
    hex = String(hex || "").replace("#", "").trim().toLowerCase();
    if (hex.length === 3) {
        hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    }
    if (hex.length !== 6 || !/^[0-9a-f]{6}$/.test(hex)) {
        return null;
    }
    return {
        hex: hex,
        r: parseInt(hex.substring(0, 2), 16),
        g: parseInt(hex.substring(2, 4), 16),
        b: parseInt(hex.substring(4, 6), 16),
    };
}

function nearestWallhavenColor(hex) {
    var color = parseHexColor(hex);
    if (!color) {
        return "";
    }
    var best = "";
    var bestDist = Infinity;
    for (var i = 0; i < WALLHAVEN_COLORS.length; i++) {
        var candidate = parseHexColor(WALLHAVEN_COLORS[i]);
        var dr = color.r - candidate.r;
        var dg = color.g - candidate.g;
        var db = color.b - candidate.b;
        var dist = dr * dr + dg * dg + db * db;
        if (dist < bestDist) {
            bestDist = dist;
            best = WALLHAVEN_COLORS[i];
        }
    }
    return best;
}

function getEffectiveColorFilter(cfg, state) {
    if (!cfg.ColorFilter) {
        return "";
    }
    if (cfg.ColorFilter === "system") {
        return nearestWallhavenColor(state && state.systemAccentHex);
    }
    return cfg.ColorFilter;
}

function buildSearchUrl(cfg, state) {
    var url = "https://wallhaven.cc/api/v1/search?";
    var params = [];

    var sorting = cfg.Sortings || "random";
    var topRange = cfg.TopRange || "1M";
    if (cfg.WallpaperOfDayEnabled) {
        sorting = "toplist";
        topRange = "1d";
    }

    params.push("sorting=" + encodeURIComponent(sorting));
    params.push("order=" + encodeURIComponent(cfg.Order || "desc"));
    params.push("page=" + encodeURIComponent(String(state.page)));

    if (sorting === "random") {
        params.push("seed=" + encodeURIComponent(state.seed));
    }
    if (sorting === "toplist" && topRange) {
        params.push("topRange=" + encodeURIComponent(topRange));
    }

    var query = state.searchQuery || getEffectiveSearchText(cfg);
    query = appendSearchModifiers(query, cfg);
    if (query) {
        params.push("q=" + encodeURIComponent(query));
    }

    params.push("categories=" + boolTriplet([
        cfg.CategoryGeneral,
        cfg.CategoryAnime,
        cfg.CategoryPeople,
    ]));
    params.push("purity=" + boolTriplet([
        cfg.PuritySfw,
        cfg.PuritySketchy,
        cfg.PurityNsfw && cfg.ApiKey,
    ]));

    var width = cfg.MinWidth || state.screenWidth;
    var height = cfg.MinHeight || state.screenHeight;
    params.push("atleast=" + encodeURIComponent(width + "x" + height));

    if (cfg.ExactResolutions) {
        params.push("resolutions=" + encodeURIComponent(cfg.ExactResolutions));
    }
    if (cfg.Ratio) {
        params.push("ratios=" + encodeURIComponent(cfg.Ratio));
    }
    var colorFilter = getEffectiveColorFilter(cfg, state);
    if (colorFilter) {
        params.push("colors=" + encodeURIComponent(colorFilter));
    }
    if (cfg.ApiKey) {
        params.push("apikey=" + encodeURIComponent(cfg.ApiKey.trim()));
    }

    return url + params.join("&");
}

function buildCollectionUrl(cfg, state) {
    var user = cfg.CollectionUser;
    var id = cfg.CollectionId;
    if (cfg.BrowseMode === "favorites" && state.favoritesUser && state.favoritesId) {
        user = state.favoritesUser;
        id = state.favoritesId;
    }
    var url = "https://wallhaven.cc/api/v1/collections/"
        + encodeURIComponent(user) + "/"
        + encodeURIComponent(id) + "?page=" + encodeURIComponent(String(state.page));
    if (cfg.ApiKey) {
        url += "&apikey=" + encodeURIComponent(cfg.ApiKey.trim());
    }
    return url;
}

function buildSettingsUrl(apiKey) {
    return "https://wallhaven.cc/api/v1/settings?apikey=" + encodeURIComponent(apiKey.trim());
}

function buildCollectionsUrl(apiKey) {
    return "https://wallhaven.cc/api/v1/collections?apikey=" + encodeURIComponent(apiKey.trim());
}

function buildWallpaperUrl(wallpaperId, apiKey) {
    var url = "https://wallhaven.cc/api/v1/w/" + encodeURIComponent(String(wallpaperId));
    if (apiKey) {
        url += "?apikey=" + encodeURIComponent(apiKey.trim());
    }
    return url;
}

function formatTags(tags) {
    if (!tags || !tags.length) {
        return "";
    }
    var result = "";
    var limit = Math.min(tags.length, 8);
    for (var i = 0; i < limit; i++) {
        if (i) {
            result += ", ";
        }
        result += tags[i].name;
    }
    return result;
}

function pickRandomIndex(wallpapers, usedIndices, seenIds, dedupEnabled, blockedIds) {
    var available = [];
    for (var i = 0; i < wallpapers.length; i++) {
        if (usedIndices.indexOf(i) !== -1) {
            continue;
        }
        if (isBlocked(wallpapers[i].id, blockedIds)) {
            continue;
        }
        if (dedupEnabled && seenIds.indexOf(String(wallpapers[i].id)) !== -1) {
            continue;
        }
        available.push(i);
    }

    if (!available.length) {
        for (var j = 0; j < wallpapers.length; j++) {
            if (usedIndices.indexOf(j) !== -1) {
                continue;
            }
            if (isBlocked(wallpapers[j].id, blockedIds)) {
                continue;
            }
            available.push(j);
        }
    }

    if (!available.length) {
        return -1;
    }

    return available[(Math.random() * available.length) | 0];
}

function findNextWallpaper(cfg, state, wallpapers) {
    var pageLength = wallpapers.length;
    if (!pageLength) {
        return { wallpaper: null, exhausted: true };
    }

    var blockedIds = state.blockedIds || [];
    var index = state.index;
    var usedIndices = state.usedIndices.slice();

    switch (cfg.LocalSortings) {
    case "random":
        index = pickRandomIndex(
            wallpapers,
            usedIndices,
            state.seenIds,
            cfg.DedupEnabled,
            blockedIds,
        );
        if (index < 0) {
            return { wallpaper: null, exhausted: true };
        }
        usedIndices.push(index);
        break;
    case "descending":
        if (state.totalShown > 0) {
            index--;
        }
        if (index < 0) {
            index = pageLength - 1;
        }
        break;
    case "ascending":
    default:
        if (state.totalShown > 0) {
            index++;
        }
        if (index >= pageLength) {
            return { wallpaper: null, exhausted: true };
        }
        break;
    }

    if (cfg.DedupEnabled || blockedIds.length) {
        var attempts = 0;
        while (attempts < pageLength
               && ((cfg.DedupEnabled && state.seenIds.indexOf(String(wallpapers[index].id)) !== -1)
                   || isBlocked(wallpapers[index].id, blockedIds))) {
            if (cfg.LocalSortings === "random") {
                var nextIndex = pickRandomIndex(wallpapers, usedIndices, state.seenIds, false, blockedIds);
                if (nextIndex < 0) {
                    return { wallpaper: null, exhausted: true };
                }
                if (usedIndices.indexOf(nextIndex) === -1) {
                    usedIndices.push(nextIndex);
                }
                index = nextIndex;
            } else if (cfg.LocalSortings === "descending") {
                index--;
                if (index < 0) {
                    return { wallpaper: null, exhausted: true };
                }
            } else {
                index++;
                if (index >= pageLength) {
                    return { wallpaper: null, exhausted: true };
                }
            }
            attempts++;
        }
        if (attempts >= pageLength) {
            return { wallpaper: null, exhausted: true };
        }
    }

    state.index = index;
    state.usedIndices = usedIndices;
    return { wallpaper: wallpapers[index] || null, exhausted: false };
}

function pickNextWallpaper(cfg, state, wallpapers) {
    return findNextWallpaper(cfg, state, wallpapers);
}

function pickWallpaper(cfg, state, wallpapers, preferRandom) {
    var pageLength = wallpapers.length;
    if (!pageLength) {
        return null;
    }

    var blockedIds = state.blockedIds || [];
    var index = 0;
    if (preferRandom || cfg.LocalSortings === "random") {
        index = pickRandomIndex(wallpapers, [], state.seenIds, cfg.DedupEnabled, blockedIds);
    }

    if (cfg.DedupEnabled || blockedIds.length) {
        var attempts = 0;
        while (attempts < pageLength
               && ((cfg.DedupEnabled && state.seenIds.indexOf(String(wallpapers[index].id)) !== -1)
                   || isBlocked(wallpapers[index].id, blockedIds))) {
            if (preferRandom || cfg.LocalSortings === "random") {
                index = pickRandomIndex(wallpapers, [], state.seenIds, false, blockedIds);
            } else {
                index = (index + 1) % pageLength;
            }
            attempts++;
        }
        if (attempts >= pageLength) {
            return null;
        }
    }

    state.index = index;
    state.usedIndices = (preferRandom || cfg.LocalSortings === "random") ? [index] : [];
    return wallpapers[index] || null;
}

function peekNextWallpaper(cfg, state, wallpapers) {
    var preview = {
        page: state.page,
        index: state.index,
        seed: state.seed,
        lastPage: state.lastPage,
        total: state.total,
        totalShown: state.totalShown,
        usedIndices: state.usedIndices.slice(),
        seenIds: state.seenIds.slice(),
        blockedIds: (state.blockedIds || []).slice(),
        screenWidth: state.screenWidth,
        screenHeight: state.screenHeight,
        searchQuery: state.searchQuery,
        favoritesUser: state.favoritesUser,
        favoritesId: state.favoritesId,
    };
    var result = findNextWallpaper(cfg, preview, wallpapers);
    return result.wallpaper;
}

function advanceIndex(cfg, state, wallpapers, dryRun) {
    if (dryRun) {
        return peekNextWallpaper(cfg, state, wallpapers);
    }
    return pickNextWallpaper(cfg, state, wallpapers).wallpaper;
}

function updatePageState(cfg, state, pageLength) {
    pageLength = pageLength || WALLPAPERS_PER_PAGE;
    var positionOnPage;
    switch (cfg.LocalSortings) {
    case "random":
        positionOnPage = state.usedIndices.length;
        break;
    case "descending":
        positionOnPage = pageLength - state.index;
        break;
    case "ascending":
    default:
        positionOnPage = state.index + 1;
        break;
    }

    var reachedEnd = state.lastPage > 0
        && state.page >= state.lastPage
        && (state.page - 1) * pageLength + positionOnPage >= state.total;

    if (reachedEnd) {
        state.usedIndices = [];
        state.page = 1;
        state.index = 0;
        state.needsNewSeed = true;
        state.needsSeenClear = true;
        return;
    }

    if (cfg.LocalSortings !== "random" || positionOnPage < pageLength) {
        return;
    }

    state.usedIndices = [];
    state.page++;
    if (state.lastPage > 0 && state.page > state.lastPage) {
        state.page = 1;
        state.needsNewSeed = true;
        state.needsSeenClear = true;
    }
    state.index = 0;
}

function allWallpapersSeen(wallpapers, seenIds) {
    if (!wallpapers || !wallpapers.length || !seenIds || !seenIds.length) {
        return false;
    }
    for (var i = 0; i < wallpapers.length; i++) {
        if (seenIds.indexOf(String(wallpapers[i].id)) === -1) {
            return false;
        }
    }
    return true;
}
