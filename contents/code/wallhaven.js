.pragma library

var WALLPAPERS_PER_PAGE = 24;

function createRandomSeed() {
    return Math.random().toString(36).slice(2, 10);
}

function dbusReplyIsTrue(value) {
    if (value === true || value === 1 || value === "1" || value === "true") {
        return true;
    }
    if (value === false || value === 0 || value === "0" || value === "false" || value == null) {
        return false;
    }
    if (Array.isArray(value) && value.length) {
        return dbusReplyIsTrue(value[0]);
    }
    if (typeof value === "object") {
        if (Object.prototype.hasOwnProperty.call(value, "value")) {
            return dbusReplyIsTrue(value.value);
        }
        if (typeof value.length === "number" && value.length > 0) {
            return dbusReplyIsTrue(value[0]);
        }
    }
    return false;
}

function dbusReplyAsString(value) {
    if (value === undefined || value === null) {
        return "";
    }
    if (typeof value === "string") {
        return value;
    }
    if (Array.isArray(value) && value.length) {
        return dbusReplyAsString(value[0]);
    }
    if (typeof value === "object") {
        if (Object.prototype.hasOwnProperty.call(value, "value")) {
            return dbusReplyAsString(value.value);
        }
        if (typeof value.length === "number" && value.length > 0) {
            return dbusReplyAsString(value[0]);
        }
    }
    return String(value);
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
    // Wallhaven only serves the full-resolution wallpaper at `path`. thumbs.small/
    // large/original are all *thumbnails* (progressively bigger previews, never the
    // full file), so "small" quality must prefer thumbs.small first or the
    // low-bandwidth setting silently downloads the larger thumbs.large instead.
    if (quality === "small") {
        return (thumbs && thumbs.small)
            || wallpaper.thumb
            || (thumbs && thumbs.large)
            || (thumbs && thumbs.original)
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
    return JSON.stringify(ids.slice(-2000));
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
    "OfflineOnlyMode", "OfflinePlaylistPinnedOnly", "TimeOfDayEnabled", "DaySearch", "NightSearch",
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
    "MusicReactiveEnabled", "MusicReactiveIntensity", "WeatherReactiveEnabled",
    "WeatherLocation", "TimeCapsulesJson", "SystemThemeSyncEnabled", "AchievementsEnabled",
    "PreferSharpMatches", "ImageEnhanceEnabled", "EnhanceBrightness", "EnhanceContrast",
    "EnhanceSaturation", "UpscaleEnabled", "CacheDownloadOriginal",
    "PauseOnIdleEnabled", "IdlePauseMinutes", "SyncProfilesEnabled", "SyncProfilesJson",
    "PanelBlurStrength", "SettingsFilterHint",
    "SettingsUiMode", "LocalFolderPath", "ReducedMotion",
    "ScrubSecretsOnExport", "SmartOfflineEnabled", "SmartOfflineDayAware",
    "LocalFolderMaxDepth", "LocalFolderExclude",
];

// Fields captured when saving/applying search presets or sync-group profiles.
var PRESET_SNAPSHOT_KEYS = [
    "SearchText", "BrowseMode", "CollectionUser", "CollectionId",
    "Sortings", "LocalSortings", "Order", "TopRange",
    "CategoryGeneral", "CategoryAnime", "CategoryPeople",
    "PuritySfw", "PuritySketchy", "PurityNsfw",
    "MinWidth", "MinHeight", "Ratio", "ColorFilter", "ExactResolutions",
    "UseBlacklist", "DedupEnabled", "PreferSharpMatches", "FileTypeFilter",
    "TagBlocklistJson", "TagFavoritesJson",
    "TimeOfDayEnabled", "DaySearch", "NightSearch",
    "ScheduleEnabled", "WeekdaySearch", "WeekendSearch",
    "WallpaperOfDayEnabled",
];

function buildPresetSnapshotFromCfg(cfg) {
    var out = {};
    if (!cfg) {
        return out;
    }
    for (var i = 0; i < PRESET_SNAPSHOT_KEYS.length; i++) {
        var key = PRESET_SNAPSHOT_KEYS[i];
        if (cfg[key] !== undefined) {
            out[key] = cfg[key];
        }
    }
    return out;
}

function parseSyncProfiles(raw) {
    if (!raw) {
        return {};
    }
    try {
        var parsed = JSON.parse(raw);
        return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
    } catch (e) {
        return {};
    }
}

function serializeSyncProfiles(profiles) {
    if (!profiles || typeof profiles !== "object") {
        return "{}";
    }
    return JSON.stringify(profiles);
}

function applySyncProfile(profile, configuration) {
    if (!profile || !configuration) {
        return false;
    }
    var keys = Object.keys(profile);
    for (var i = 0; i < keys.length; i++) {
        if (keys[i] !== "name") {
            configuration[keys[i]] = profile[keys[i]];
        }
    }
    return true;
}

function exportSettingsSnapshot(cfg, options) {
    options = options || {};
    var scrub = options.scrubSecrets !== undefined
        ? !!options.scrubSecrets
        : (cfg && cfg.ScrubSecretsOnExport !== false);
    var snapshot = {
        version: 6,
        schemaVersion: 3,
        plugin: "org.robertsm.wallhaven",
        exportedAt: new Date().toISOString(),
        settings: {},
    };
    for (var i = 0; i < EXPORTABLE_SETTINGS_KEYS.length; i++) {
        var key = EXPORTABLE_SETTINGS_KEYS[i];
        if (cfg && cfg[key] !== undefined) {
            if (scrub && (key === "ApiKey" || key === "PreviewAttribution")) {
                continue;
            }
            snapshot.settings[key] = cfg[key];
        }
    }
    if (scrub) {
        snapshot.secretsScrubbed = true;
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

function migrateConfigurationToV3(configuration) {
    if (!configuration) {
        return { migrated: false, from: 0, to: 3 };
    }
    var from = parseInt(configuration.ConfigSchemaVersion, 10) || 0;
    if (from >= 3) {
        return { migrated: false, from: from, to: 3 };
    }
    // v3 defaults: prefer KWallet, scrub exports, settings UI simple, smart offline on.
    if (configuration.UseKWalletForApiKey === undefined || configuration.UseKWalletForApiKey === false) {
        // Only force-enable wallet load when an API key is already present in config
        // or wallet was never considered; keep false if user explicitly cleared key+wallet.
        if (String(configuration.ApiKey || "").trim() !== "") {
            configuration.UseKWalletForApiKey = true;
        }
    }
    if (configuration.ScrubSecretsOnExport === undefined) {
        configuration.ScrubSecretsOnExport = true;
    }
    if (!configuration.SettingsUiMode) {
        configuration.SettingsUiMode = "simple";
    }
    if (configuration.SmartOfflineEnabled === undefined) {
        configuration.SmartOfflineEnabled = true;
    }
    if (configuration.SmartOfflineDayAware === undefined) {
        configuration.SmartOfflineDayAware = true;
    }
    if (from < 2 && configuration.PauseWhenInactive === true && configuration.PauseOnIdleEnabled === false) {
        // Historical rename hint: keep lock-pause semantics; idle stays separate.
    }
    configuration.ConfigSchemaVersion = 3;
    return { migrated: true, from: from, to: 3 };
}

function isLocalBrowseMode(cfg) {
    return cfg && cfg.BrowseMode === "local";
}

function listLocalImagePaths(entries, excludeRaw) {
    entries = entries || [];
    var excludes = String(excludeRaw || "").split(/[,;\n]/).map(function(part) {
        return String(part || "").trim().toLowerCase();
    }).filter(function(part) { return part.length > 0; });
    var out = [];
    for (var i = 0; i < entries.length; i++) {
        var path = String(entries[i] || "").trim();
        if (!path) {
            continue;
        }
        var lower = path.toLowerCase();
        var excluded = false;
        for (var e = 0; e < excludes.length; e++) {
            if (lower.indexOf(excludes[e]) !== -1) {
                excluded = true;
                break;
            }
        }
        if (excluded) {
            continue;
        }
        if (lower.indexOf(".jpg") > 0 || lower.indexOf(".jpeg") > 0
                || lower.indexOf(".png") > 0 || lower.indexOf(".webp") > 0
                || lower.indexOf(".bmp") > 0) {
            out.push(path);
        }
    }
    return out;
}

function orderLocalImagePaths(paths, localSortings) {
    paths = (paths || []).slice();
    var mode = String(localSortings || "ascending");
    if (mode === "random") {
        for (var i = paths.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var tmp = paths[i];
            paths[i] = paths[j];
            paths[j] = tmp;
        }
        return paths;
    }
    paths.sort(function(a, b) {
        var left = String(a).toLowerCase();
        var right = String(b).toLowerCase();
        if (left < right) {
            return mode === "descending" ? 1 : -1;
        }
        if (left > right) {
            return mode === "descending" ? -1 : 1;
        }
        return 0;
    });
    return paths;
}

function presetAccentColor(preset) {
    if (preset && preset.ColorFilter) {
        var hex = String(preset.ColorFilter).replace("#", "").trim();
        if (/^[0-9a-fA-F]{6}$/.test(hex)) {
            return "#" + hex.toLowerCase();
        }
    }
    var name = String((preset && preset.name) || "preset");
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
        hash = ((hash << 5) - hash) + name.charCodeAt(i);
        hash |= 0;
    }
    var hue = Math.abs(hash) % 360;
    return "hsl(" + hue + ", 45%, 42%)";
}

function presetPreviewThumbUrl(preset) {
    if (!preset) {
        return "";
    }
    var sample = String(preset.SampleWallpaperId || preset.sampleId || "").trim();
    if (sample) {
        return thumbUrlForId(sample);
    }
    return "";
}

function pickSmartCachedId(index, cfg, cursor) {
    var ids = listCachedIds(index, cfg);
    if (cfg && cfg.BrowseMode === "playlist" && cfg.OfflinePlaylistPinnedOnly) {
        var pinned = parsePinnedCacheIds(cfg.PinnedCacheIdsJson);
        ids = ids.filter(function(id) {
            return pinned.indexOf(id) !== -1;
        });
    }
    if (!ids.length) {
        return { id: "", cursor: cursor || 0 };
    }
    if (!(cfg && cfg.SmartOfflineEnabled)) {
        var next = ((cursor || 0) + 1) % ids.length;
        return { id: ids[next], cursor: next };
    }
    // Prefer higher-resolution / pinned entries when available; else rotate.
    var pinnedAll = parsePinnedCacheIds(cfg && cfg.PinnedCacheIdsJson);
    var dayAware = !!(cfg && cfg.SmartOfflineDayAware);
    var preferDay = dayAware && isDayPeriod();
    var periodNeedle = "";
    if (dayAware) {
        periodNeedle = String(preferDay
            ? (cfg.DaySearch || cfg.SearchText || "")
            : (cfg.NightSearch || cfg.SearchText || "")).toLowerCase();
    }
    var scored = ids.map(function(id, idx) {
        var dims = diskCacheDimensionsForId(index, id);
        var area = dims ? (dims.dimension_x * dims.dimension_y) : 0;
        var pinBoost = pinnedAll.indexOf(id) !== -1 ? 1e12 : 0;
        var dayBoost = 0;
        if (dayAware) {
            var cat = index.categories ? String(index.categories[id] || "").toLowerCase() : "";
            // Soft preference: daytime leans general; night leans anime/people when no query.
            if (periodNeedle) {
                if (periodNeedle.indexOf(cat) !== -1 || (cat && periodNeedle.indexOf(cat) >= 0)) {
                    dayBoost = 5e9;
                }
                // Match category tokens from day/night query loosely.
                if (preferDay && cat.indexOf("general") !== -1) {
                    dayBoost += 1e9;
                }
                if (!preferDay && (cat.indexOf("anime") !== -1 || cat.indexOf("people") !== -1)) {
                    dayBoost += 1e9;
                }
            } else if (preferDay && cat === "general") {
                dayBoost = 2e9;
            } else if (!preferDay && (cat === "anime" || cat === "people")) {
                dayBoost = 2e9;
            }
        }
        return { id: id, idx: idx, score: pinBoost + dayBoost + area };
    });
    scored.sort(function(a, b) {
        return b.score - a.score;
    });
    // Walk from last cursor through smart order for variety.
    var start = Math.max(0, (cursor || 0) + 1) % scored.length;
    var pick = scored[start % scored.length];
    return { id: pick.id, cursor: start };
}

function pluginVersion() {
    return "3.1.0";
}

function buildPresetFromConfig(name, cfg) {
    var out = buildPresetSnapshotFromCfg(cfg);
    out.name = String(name || "").trim();
    return out;
}

function applyPresetToConfig(preset, configuration) {
    if (!preset || !configuration) {
        return false;
    }
    var normalized = normalizeSearchPreset(preset);
    var keys = Object.keys(normalized);
    for (var i = 0; i < keys.length; i++) {
        configuration[keys[i]] = normalized[keys[i]];
    }
    return true;
}

function normalizeSearchPreset(preset) {
    if (!preset) {
        return {};
    }
    var out = {};
    var keys = Object.keys(preset);
    var i;
    for (i = 0; i < keys.length; i++) {
        if (keys[i] === "name") {
            continue;
        }
        out[keys[i]] = preset[keys[i]];
    }
    var catKeys = ["CategoryGeneral", "CategoryAnime", "CategoryPeople"];
    var hasCat = false;
    for (i = 0; i < catKeys.length; i++) {
        if (Object.prototype.hasOwnProperty.call(preset, catKeys[i])) {
            hasCat = true;
        }
    }
    if (hasCat) {
        for (i = 0; i < catKeys.length; i++) {
            out[catKeys[i]] = !!preset[catKeys[i]];
        }
    }
    var purKeys = ["PuritySfw", "PuritySketchy", "PurityNsfw"];
    var hasPur = false;
    for (i = 0; i < purKeys.length; i++) {
        if (Object.prototype.hasOwnProperty.call(preset, purKeys[i])) {
            hasPur = true;
        }
    }
    if (hasPur) {
        for (i = 0; i < purKeys.length; i++) {
            out[purKeys[i]] = !!preset[purKeys[i]];
        }
    }
    return out;
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
    var empty = { ids: [], next: 0, categories: {}, purities: {}, dimensions: {}, usedAt: {} };
    if (!raw) {
        return empty;
    }
    try {
        var parsed = JSON.parse(raw);
        var categories = {};
        var purities = {};
        var dimensions = {};
        var usedAt = {};
        if (parsed && parsed.categories && typeof parsed.categories === "object") {
            categories = parsed.categories;
        }
        if (parsed && parsed.purities && typeof parsed.purities === "object") {
            purities = parsed.purities;
        }
        if (parsed && parsed.dimensions && typeof parsed.dimensions === "object") {
            dimensions = parsed.dimensions;
        }
        if (parsed && parsed.usedAt && typeof parsed.usedAt === "object") {
            usedAt = parsed.usedAt;
        }
        if (!parsed || !parsed.ids || !parsed.ids.length) {
            return {
                ids: [],
                next: Math.max(0, parseInt(parsed && parsed.next, 10) || 0),
                categories: categories,
                purities: purities,
                dimensions: dimensions,
                usedAt: usedAt,
            };
        }
        return {
            ids: parsed.ids.map(function(id) { return id === null || id === undefined ? "" : String(id); }),
            next: Math.max(0, parseInt(parsed.next, 10) || 0),
            categories: categories,
            purities: purities,
            dimensions: dimensions,
            usedAt: usedAt,
        };
    } catch (e) {
        return empty;
    }
}

function serializeDiskCacheIndex(index) {
    if (!index) {
        return "{\"ids\":[],\"next\":0,\"categories\":{},\"purities\":{},\"dimensions\":{}}";
    }
    return JSON.stringify({
        ids: index.ids || [],
        next: index.next || 0,
        categories: index.categories || {},
        purities: index.purities || {},
        dimensions: index.dimensions || {},
        usedAt: index.usedAt || {},
    });
}

function diskCacheSlotForId(index, id) {
    if (!index || !index.ids || !id) {
        return -1;
    }
    return index.ids.indexOf(String(id));
}

function setDiskCacheCategory(index, id, category, purity) {
    if (!index || !id) {
        return;
    }
    if (!index.categories) {
        index.categories = {};
    }
    if (!index.purities) {
        index.purities = {};
    }
    var cat = String(category || "").trim().toLowerCase();
    if (cat && cat !== "cached") {
        index.categories[String(id)] = cat;
    }
    var pur = String(purity || "").trim().toLowerCase();
    if (pur && pur !== "cached") {
        index.purities[String(id)] = pur;
    }
}

// Records the wallpaper's native resolution alongside its disk-cache entry,
// captured once at cache-write time from the API listing (the cached file
// itself is grabToImage'd at a target render size, not the original source
// resolution, so it can't answer "did this need upscaling" on its own).
// Lets a later "re-upscale cached wallpapers" pass decide which already-cached
// entries qualify without re-querying the Wallhaven API for each one.
function setDiskCacheDimensions(index, id, dimensionX, dimensionY) {
    if (!index || !id) {
        return;
    }
    if (!index.dimensions) {
        index.dimensions = {};
    }
    var w = Number(dimensionX);
    var h = Number(dimensionY);
    if (w > 0 && h > 0) {
        index.dimensions[String(id)] = [w, h];
    }
}

// Returns { dimension_x, dimension_y } for a cached entry, or null when
// unknown (e.g. it was cached before this tracking existed).
function diskCacheDimensionsForId(index, id) {
    if (!index || !index.dimensions) {
        return null;
    }
    var entry = index.dimensions[String(id)];
    if (!entry || entry.length !== 2 || !entry[0] || !entry[1]) {
        return null;
    }
    return { dimension_x: entry[0], dimension_y: entry[1] };
}

function touchDiskCacheId(index, id, atMs) {
    if (!index || !id) {
        return;
    }
    if (!index.usedAt) {
        index.usedAt = {};
    }
    var ts = Number(atMs);
    index.usedAt[String(id)] = ts > 0 ? ts : Date.now();
}

function evictDiskCacheOccupant(index, occupant) {
    occupant = String(occupant || "");
    if (!occupant || !index) {
        return;
    }
    if (index.categories) {
        delete index.categories[occupant];
    }
    if (index.purities) {
        delete index.purities[occupant];
    }
    if (index.dimensions) {
        delete index.dimensions[occupant];
    }
    if (index.usedAt) {
        delete index.usedAt[occupant];
    }
}

function diskCacheUsedAt(index, id) {
    if (!index || !index.usedAt || !id) {
        return 0;
    }
    return Number(index.usedAt[String(id)]) || 0;
}

function allocateDiskCacheSlot(index, id, maxSlots, pinnedIds, category, purity) {
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
        setDiskCacheCategory(index, id, category, purity);
        touchDiskCacheId(index, id);
        return existing;
    }
    while (index.ids.length < maxSlots) {
        index.ids.push("");
    }
    var slot = -1;
    var i;
    var start = (index.next || 0) % maxSlots;
    for (i = 0; i < maxSlots; i++) {
        var emptySlot = (start + i) % maxSlots;
        if (!String(index.ids[emptySlot] || "")) {
            slot = emptySlot;
            break;
        }
    }
    if (slot < 0) {
        var oldestTime = Infinity;
        for (i = 0; i < maxSlots; i++) {
            var occupantId = String(index.ids[i] || "");
            if (!occupantId || pinnedIds.indexOf(occupantId) !== -1) {
                continue;
            }
            var used = diskCacheUsedAt(index, occupantId);
            if (used < oldestTime) {
                oldestTime = used;
                slot = i;
            }
        }
    }
    if (slot < 0) {
        // Every slot is pinned (or DiskCacheMaxSlots <= the pinned count) — refuse to
        // evict a pinned wallpaper rather than silently unpinning it by overwriting
        // its slot.
        return -1;
    }
    evictDiskCacheOccupant(index, index.ids[slot]);
    index.ids[slot] = id;
    setDiskCacheCategory(index, id, category, purity);
    touchDiskCacheId(index, id);
    index.next = (slot + 1) % maxSlots;
    return slot;
}

function sanitizeCacheNamespace(raw) {
    var ns = String(raw || "").replace(/[^a-zA-Z0-9._-]/g, "_");
    ns = ns.replace(/_+/g, "_").replace(/^_+|_+$/g, "");
    if (ns.length > 64) {
        ns = ns.substring(0, 64);
    }
    return ns;
}

function diskCacheFileName(slot, namespace) {
    var n = Math.max(0, parseInt(slot, 10) || 0);
    var padded = n < 10 ? ("0" + n) : String(n);
    var ns = sanitizeCacheNamespace(namespace);
    if (ns) {
        return "wallhaven-cache-" + ns + "-" + padded + ".jpg";
    }
    return "wallhaven-cache-" + padded + ".jpg";
}

function wallpaperMatchesCategories(wallpaper, cfg) {
    if (!wallpaper || !cfg) {
        return true;
    }
    var cat = String(wallpaper.category || "").toLowerCase();
    if (!cat || cat === "cached") {
        return true;
    }
    if (cat === "people") {
        return !!cfg.CategoryPeople;
    }
    if (cat === "anime") {
        return !!cfg.CategoryAnime;
    }
    if (cat === "general") {
        return !!cfg.CategoryGeneral;
    }
    return true;
}

function shouldFilterByCategories(cfg) {
    if (!cfg) {
        return false;
    }
    var mode = cfg.BrowseMode || "search";
    return mode !== "collection" && mode !== "favorites" && mode !== "playlist";
}

function wallpaperMatchesPurity(wallpaper, cfg) {
    if (!wallpaper || !cfg) {
        return true;
    }
    var purity = String(wallpaper.purity || "").toLowerCase();
    if (!purity || purity === "cached") {
        return true;
    }
    if (purity === "sfw") {
        return !!cfg.PuritySfw;
    }
    if (purity === "sketchy") {
        return !!cfg.PuritySketchy;
    }
    if (purity === "nsfw") {
        return !!cfg.PurityNsfw && !!cfg.ApiKey;
    }
    return true;
}

function filterWallpapersByCategories(wallpapers, cfg) {
    if (!wallpapers || !wallpapers.length || !shouldFilterByCategories(cfg)) {
        return wallpapers || [];
    }
    return wallpapers.filter(function(wallpaper) {
        return wallpaperMatchesCategories(wallpaper, cfg) && wallpaperMatchesPurity(wallpaper, cfg);
    });
}

function cachedIdMatchesCategories(index, id, cfg) {
    if (!shouldFilterByCategories(cfg) || !index || !id) {
        return true;
    }
    var cat = index.categories ? String(index.categories[id] || "") : "";
    var purity = index.purities ? String(index.purities[id] || "") : "";
    return wallpaperMatchesCategories({ category: cat }, cfg)
        && wallpaperMatchesPurity({ purity: purity }, cfg);
}

function listCachedIds(index, cfg) {
    if (!index || !index.ids) {
        return [];
    }
    var ids = [];
    for (var i = 0; i < index.ids.length; i++) {
        var id = String(index.ids[i] || "").trim();
        if (id && ids.indexOf(id) === -1 && cachedIdMatchesCategories(index, id, cfg)) {
            ids.push(id);
        }
    }
    return ids;
}

function pickRandomCachedId(index, cfg, pinnedOnly) {
    var ids = listCachedIds(index, cfg);
    if (pinnedOnly) {
        var pinned = parsePinnedCacheIds(cfg && cfg.PinnedCacheIdsJson);
        ids = ids.filter(function(id) {
            return pinned.indexOf(id) !== -1;
        });
    }
    if (!ids.length) {
        return "";
    }
    return ids[(Math.random() * ids.length) | 0];
}

function parseCollectionShareUrl(raw) {
    var text = String(raw || "").trim();
    if (!text) {
        return null;
    }
    // https://wallhaven.cc/collections/username/12345
    var m = text.match(/wallhaven\.cc\/collections\/([^\/\s?#]+)\/(\d+)/i);
    if (m) {
        return { username: m[1], id: m[2] };
    }
    // username/12345 or username:12345
    m = text.match(/^([A-Za-z0-9_-]+)[\/:](\d+)$/);
    if (m) {
        return { username: m[1], id: m[2] };
    }
    return null;
}

function filterCollectionsByQuery(entries, query) {
    entries = entries || [];
    query = String(query || "").trim().toLowerCase();
    if (!query) {
        return entries;
    }
    return entries.filter(function(entry) {
        if (!entry) {
            return false;
        }
        var hay = [
            entry.username || "",
            entry.id || "",
            entry.label || "",
            entry.display || "",
        ].join(" ").toLowerCase();
        return hay.indexOf(query) !== -1;
    });
}

function buildApiHealthSnapshot(state) {
    state = state || {};
    return {
        lastStatus: parseInt(state.lastStatus, 10) || 0,
        lastError: String(state.lastError || ""),
        rateLimitCount: parseInt(state.rateLimitCount, 10) || 0,
        lastRateLimitAt: String(state.lastRateLimitAt || ""),
        lastSuccessAt: String(state.lastSuccessAt || ""),
        healthy: state.lastStatus === 200 || state.lastStatus === 0 && !state.lastError,
    };
}

function parallaxStrengthNorm(strength) {
    return Math.max(0, Math.min(100, strength || 50)) / 100;
}

function parallaxScaleForStrength(enabled, strength) {
    if (!enabled) {
        return 1;
    }
    return 1.06 + parallaxStrengthNorm(strength) * 0.10;
}

function parallaxOffsetX(enabled, strength, width, phase, screenPhase) {
    if (!enabled) {
        return 0;
    }
    var t = (Number(phase) || 0) + (Number(screenPhase) || 0);
    return Math.sin(t * Math.PI * 2) * (width || 1920) * 0.07 * parallaxStrengthNorm(strength);
}

function parallaxOffsetY(enabled, strength, height, phase, screenPhase) {
    if (!enabled) {
        return 0;
    }
    var t = (Number(phase) || 0) + (Number(screenPhase) || 0);
    return Math.cos(t * Math.PI * 2 * 0.65) * (height || 1080) * 0.05 * parallaxStrengthNorm(strength);
}

function parallaxCycleMs(strength) {
    var s = Math.max(1, Math.min(100, strength || 50));
    return Math.round(80000 - ((s - 1) / 99) * 40000);
}

function parallaxScreenPhase(virtualX) {
    return (Math.max(0, Number(virtualX) || 0) / 3840) % 1;
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
    if (cfg.BrowseMode === "similar") {
        base = buildSimilarSearchQuery(cfg.SimilarSourceId || "");
    } else if (cfg.TimeOfDayEnabled) {
        var hour = new Date().getHours();
        var isDay = hour >= 6 && hour < 20;
        base = isDay ? (cfg.DaySearch || "") : (cfg.NightSearch || "");
    } else if (cfg.ScheduleEnabled) {
        base = isWeekend() ? (cfg.WeekendSearch || "") : (cfg.WeekdaySearch || "");
    } else {
        base = cfg.SearchText || "";
    }
    base = appendTagFavorites(base, parseTagFavorites(cfg.TagFavoritesJson));
    if (cfg.WeatherReactiveEnabled && cfg.WeatherTagCache) {
        base = appendWeatherModifier(base, cfg.WeatherTagCache);
    }
    return base;
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
        localThumbUrl: data.localThumbUrl || "",
        pageUrl: data.pageUrl || "",
        tags: data.tags || "",
        details: data.details || "",
        resolution: data.resolution || "",
        purity: data.purity || "",
        category: data.category || "",
        paused: !!data.paused,
        slideshowActive: !!data.slideshowActive,
        nextChangeMs: Math.max(0, parseInt(data.nextChangeMs, 10) || 0),
        attribution: data.attribution || "",
        varietyWatchEnabled: !!data.varietyWatchEnabled,
        syncGroup: data.syncGroup || "default",
        browseMode: data.browseMode || "",
        screenName: data.screenName || "",
        cacheNamespace: data.cacheNamespace || "",
        lockScreenSyncAt: data.lockScreenSyncAt || "",
        lockScreenSyncPath: data.lockScreenSyncPath || "",
        lockScreenSyncOk: !!data.lockScreenSyncOk,
        metrics: data.metrics || null,
        apiHealth: data.apiHealth || null,
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

function buildPanelTintMetadata(hexColor, wallpaperId, blurStrength) {
    var blur = Math.max(0, Math.min(100, parseInt(blurStrength, 10) || 0));
    return JSON.stringify({
        wallpaperId: wallpaperId ? String(wallpaperId) : "",
        color: hexColor || "",
        blurStrength: blur,
        updatedAt: new Date().toISOString(),
    }, null, 2);
}

function varietySymlinkName() {
    return "wallhaven-current.jpg";
}

function lockScreenImageFileName() {
    return "wallhaven-lockscreen.jpg";
}

function lockScreenImageUrl(path) {
    var dest = String(path || "");
    if (!dest) {
        return "";
    }
    if (dest.indexOf("file://") === 0) {
        return dest;
    }
    return "file://" + dest;
}

function shellSingleQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'";
}

function buildLockScreenSyncCommand(sourcePath, destPath) {
    var source = String(sourcePath || "");
    var dest = String(destPath || "");
    if (!source || !dest) {
        return "";
    }
    var url = lockScreenImageUrl(dest);
    var parts = [];
    if (source !== dest) {
        parts.push("cp -f " + shellSingleQuote(source) + " " + shellSingleQuote(dest));
    }
    parts.push("kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image");
    parts.push("kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image " + shellSingleQuote(url));
    parts.push("kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage " + shellSingleQuote(url));
    parts.push("kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key FillMode 2");
    return parts.join(" && ");
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

var BUNDLED_CURATED_PRESETS = [
    {
        name: "Nature landscapes",
        SearchText: "nature landscape mountains",
        Sortings: "random",
        Ratio: "landscape",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
    },
    {
        name: "Anime night city",
        SearchText: "anime city night rain",
        Sortings: "random",
        CategoryAnime: true,
        CategoryGeneral: false,
        CategoryPeople: false,
    },
    {
        name: "Minimal dark",
        SearchText: "minimal dark abstract",
        Sortings: "toplist",
        TopRange: "1M",
        ColorFilter: "000000",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
        SampleWallpaperId: "85k258",
    },
    {
        name: "Cyberpunk",
        SearchText: "cyberpunk neon",
        Sortings: "random",
        CategoryGeneral: true,
        CategoryAnime: true,
        CategoryPeople: false,
        SampleWallpaperId: "6k3oox",
    },
    {
        name: "Space",
        SearchText: "space nebula stars",
        Sortings: "random",
        Ratio: "landscape",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
        SampleWallpaperId: "28jdg9",
    },
];

var BUNDLED_COMMUNITY_PRESETS = [
    {
        name: "Community — Cozy cabin",
        SearchText: "cabin cozy winter snow",
        Sortings: "random",
        Ratio: "landscape",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
    },
    {
        name: "Community — Retro synth",
        SearchText: "retrowave synthwave 80s",
        Sortings: "toplist",
        TopRange: "1M",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
    },
    {
        name: "Community — Ocean calm",
        SearchText: "ocean waves beach sunset",
        Sortings: "random",
        ColorFilter: "0066cc",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
    },
];

function cloneBundledPresets(presets) {
    return parseCuratedPresets(JSON.stringify(presets || []));
}

function bundledCuratedPresets() {
    return cloneBundledPresets(BUNDLED_CURATED_PRESETS);
}

function bundledCommunityPresets() {
    return cloneBundledPresets(BUNDLED_COMMUNITY_PRESETS);
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
        settings: exportSettingsSnapshot(cfg, { scrubSecrets: true }),
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
        exportSettingsSnapshot(cfg, { scrubSecrets: true }),
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
        var dims = diskCacheDimensionsForId(index, id);
        entries.push({
            id: id,
            slot: i,
            pinned: pinnedIds.indexOf(id) !== -1,
            thumbUrl: thumbUrlForId(id),
            dimensionX: dims ? dims.dimension_x : 0,
            dimensionY: dims ? dims.dimension_y : 0,
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

// KConfig serializes QColor entries (like kdeglobals' [General] AccentColor) as
// "r,g,b" decimal, not a "#RRGGBB" string. Writing a raw hex string there fails to
// parse as a QColor, so Plasma silently falls back to its default accent color.
function hexToKdeAccentColor(hex) {
    var color = parseHexColor(hex);
    if (!color) {
        return "";
    }
    return color.r + "," + color.g + "," + color.b;
}

// GNOME's org.gnome.desktop.interface accent-color is a fixed 9-value enum, not a
// free-form color — gsettings rejects anything else. Map the wallpaper's accent to
// the closest named option so the write actually takes effect.
var GNOME_ACCENT_COLORS = [
    { name: "blue", hex: "3584e4" },
    { name: "teal", hex: "2190a4" },
    { name: "green", hex: "3a944a" },
    { name: "yellow", hex: "c88800" },
    { name: "orange", hex: "ed5b00" },
    { name: "red", hex: "e62d42" },
    { name: "pink", hex: "d56199" },
    { name: "purple", hex: "9141ac" },
    { name: "slate", hex: "6f8396" },
];

function nearestGnomeAccentColor(hex) {
    var color = parseHexColor(hex);
    if (!color) {
        return "";
    }
    var best = "";
    var bestDist = Infinity;
    for (var i = 0; i < GNOME_ACCENT_COLORS.length; i++) {
        var candidate = parseHexColor(GNOME_ACCENT_COLORS[i].hex);
        var dr = color.r - candidate.r;
        var dg = color.g - candidate.g;
        var db = color.b - candidate.b;
        var dist = dr * dr + dg * dg + db * db;
        if (dist < bestDist) {
            bestDist = dist;
            best = GNOME_ACCENT_COLORS[i].name;
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

function buildCollectionsUrlForUser(username, apiKey) {
    var user = String(username || "").trim();
    if (!user) {
        return "";
    }
    var url = "https://wallhaven.cc/api/v1/collections/" + encodeURIComponent(user);
    if (apiKey) {
        url += "?apikey=" + encodeURIComponent(String(apiKey).trim());
    }
    return url;
}

function isHttpPresetUrl(url) {
    var raw = String(url || "").trim().toLowerCase();
    return raw.indexOf("https://") === 0 || raw.indexOf("http://") === 0;
}

function parseRemotePresetPayload(raw) {
    var text = String(raw || "").trim();
    if (!text) {
        throw new Error("empty preset");
    }
    if (text.charAt(0) === "{" || text.charAt(0) === "[") {
        var parsed = JSON.parse(text);
        if (parsed && parsed.settings && typeof parsed.settings === "object") {
            return parsed.settings;
        }
        if (parsed && parsed.name) {
            return parsed;
        }
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            return parsed;
        }
        throw new Error("invalid preset json");
    }
    return importPresetFromShareUrl(text);
}

function laptopModeSettings() {
    return {
        MeteredCacheOnly: true,
        OfflineCacheFallback: true,
        PauseOnBatteryLow: true,
        BatteryLowThreshold: 20,
        PauseOnIdleEnabled: true,
        IdlePauseMinutes: 10,
        ImageQuality: "large",
        PreloadCount: 1,
        AdaptivePreloadEnabled: false,
        KenBurnsEnabled: false,
        MusicReactiveEnabled: false,
        ParallaxEnabled: false,
        UpscaleEnabled: false,
        CacheDownloadOriginal: false,
        NotifyOnRefresh: false,
    };
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

// Whether a wallpaper's native resolution genuinely falls short of the given
// screen size, i.e. a PreserveAspectCrop fit would need to stretch it upward
// by more than a small margin (minCoverScale, default 15%). Used to gate the
// external-upscaler hook so it only fires on real low-res matches rather than
// every wallpaper that's a few pixels shy of an exact fit.
function needsUpscale(wallpaper, screenWidth, screenHeight, minCoverScale) {
    var dimX = wallpaper && Number(wallpaper.dimension_x);
    var dimY = wallpaper && Number(wallpaper.dimension_y);
    var sw = Number(screenWidth);
    var sh = Number(screenHeight);
    if (!dimX || !dimY || dimX <= 0 || dimY <= 0 || !sw || !sh || sw <= 0 || sh <= 0) {
        return false;
    }
    var coverScale = Math.max(sw / dimX, sh / dimY);
    var threshold = (minCoverScale && minCoverScale > 1) ? minCoverScale : 1.15;
    return coverScale > threshold;
}

// How much the image would need to be upscaled to cover the given screen size
// (PreserveAspectCrop semantics: the more-constrained dimension wins), and how
// closely its aspect ratio matches the screen's. Combined into a single weight
// so "prefer sharp matches" mode can bias random selection toward wallpapers
// that won't need heavy upscaling or an aggressive crop, without ever fully
// excluding the rest (a match's weight never drops to exactly 0).
function wallpaperResolutionScore(wallpaper, screenWidth, screenHeight) {
    var dimX = wallpaper && Number(wallpaper.dimension_x);
    var dimY = wallpaper && Number(wallpaper.dimension_y);
    var sw = Number(screenWidth);
    var sh = Number(screenHeight);
    if (!dimX || !dimY || dimX <= 0 || dimY <= 0 || !sw || !sh || sw <= 0 || sh <= 0) {
        return 1;
    }
    var coverScale = Math.max(sw / dimX, sh / dimY);
    var upscalePenalty = coverScale > 1 ? (1 / coverScale) : 1;

    var imageAspect = dimX / dimY;
    var screenAspect = sw / sh;
    var aspectRatioOfRatios = imageAspect > screenAspect ? (imageAspect / screenAspect) : (screenAspect / imageAspect);
    var aspectScore = 1 / aspectRatioOfRatios;

    return Math.max(0.05, upscalePenalty * aspectScore);
}

// Weighted counterpart to a plain uniform pick among `available` indices. Falls
// back to a uniform pick if every candidate weighs zero so a bad/empty weightFn
// can never strand the slideshow.
function pickWeightedIndex(available, wallpapers, weightFn) {
    var weights = [];
    var total = 0;
    for (var i = 0; i < available.length; i++) {
        var w = Math.max(0, weightFn(wallpapers[available[i]]) || 0);
        weights.push(w);
        total += w;
    }
    if (total <= 0) {
        return available[(Math.random() * available.length) | 0];
    }
    var target = Math.random() * total;
    var cumulative = 0;
    for (var j = 0; j < available.length; j++) {
        cumulative += weights[j];
        if (target < cumulative) {
            return available[j];
        }
    }
    return available[available.length - 1];
}

function pickRandomIndex(wallpapers, usedIndices, seenIds, dedupEnabled, blockedIds, weightFn) {
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

    if (weightFn) {
        return pickWeightedIndex(available, wallpapers, weightFn);
    }

    return available[(Math.random() * available.length) | 0];
}

// Builds the optional weight function for pickRandomIndex from the
// PreferSharpMatches setting. Returns undefined (plain uniform random) unless
// the setting is enabled and the state carries known screen dimensions.
function resolutionWeightFn(cfg, state) {
    if (!cfg || !cfg.PreferSharpMatches) {
        return undefined;
    }
    return function (wallpaper) {
        return wallpaperResolutionScore(wallpaper, state.screenWidth, state.screenHeight);
    };
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
            resolutionWeightFn(cfg, state),
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
                var nextIndex = pickRandomIndex(wallpapers, usedIndices, state.seenIds, false, blockedIds, resolutionWeightFn(cfg, state));
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
        index = pickRandomIndex(wallpapers, [], state.seenIds, cfg.DedupEnabled, blockedIds, resolutionWeightFn(cfg, state));
    }

    if (cfg.DedupEnabled || blockedIds.length) {
        var attempts = 0;
        while (attempts < pageLength
               && ((cfg.DedupEnabled && state.seenIds.indexOf(String(wallpapers[index].id)) !== -1)
                   || isBlocked(wallpapers[index].id, blockedIds))) {
            if (preferRandom || cfg.LocalSortings === "random") {
                index = pickRandomIndex(wallpapers, [], state.seenIds, false, blockedIds, resolutionWeightFn(cfg, state));
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

// ---------------------------------------------------------------------
// v2.5.0 additions: swipe-to-rate, music/weather reactivity, time
// capsules, milestone toasts.
// ---------------------------------------------------------------------

function tagsStringToBlocklistTags(tagsString, maxTags) {
    maxTags = maxTags || 5;
    if (!tagsString) {
        return [];
    }
    return String(tagsString).split(",").map(function(tag) {
        return tag.trim().replace(/\s+/g, "_");
    }).filter(function(tag) {
        return tag.length > 0;
    }).slice(0, maxTags);
}

function addTagsToJsonList(raw, tagsToAdd, maxEntries) {
    maxEntries = maxEntries || 30;
    var list = parseTagBlocklist(raw);
    for (var i = 0; i < tagsToAdd.length; i++) {
        if (list.indexOf(tagsToAdd[i]) === -1) {
            list.push(tagsToAdd[i]);
        }
    }
    if (list.length > maxEntries) {
        list = list.slice(list.length - maxEntries);
    }
    return serializeTagBlocklist(list);
}

function removeTagsFromJsonList(raw, tagsToRemove) {
    var list = parseTagBlocklist(raw);
    if (!tagsToRemove || !tagsToRemove.length) {
        return serializeTagBlocklist(list);
    }
    list = list.filter(function(tag) {
        return tagsToRemove.indexOf(tag) === -1;
    });
    return serializeTagBlocklist(list);
}

function musicReactiveSpeedMultiplier(intensityPercent, isPlaying) {
    if (!isPlaying) {
        return 1;
    }
    var pct = Math.max(0, Math.min(100, intensityPercent || 0));
    return 1 + (pct / 100) * 0.6;
}

function mapWeatherCodeToTag(code) {
    code = parseInt(code, 10);
    if (isNaN(code)) {
        return "";
    }
    if (code === 0) {
        return "clear sky";
    }
    if (code >= 1 && code <= 3) {
        return "clouds";
    }
    if (code === 45 || code === 48) {
        return "fog";
    }
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
        return "rain";
    }
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
        return "snow";
    }
    if (code >= 95 && code <= 99) {
        return "storm";
    }
    return "";
}

function appendWeatherModifier(query, tag) {
    query = String(query || "").trim();
    tag = String(tag || "").trim();
    if (!tag) {
        return query;
    }
    return (query ? query + " " : "") + tag;
}

function parseLatLon(text) {
    var match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ""));
    if (!match) {
        return null;
    }
    return { lat: parseFloat(match[1]), lon: parseFloat(match[2]) };
}

function parseGeocodeResponse(json) {
    try {
        var data = typeof json === "string" ? JSON.parse(json) : json;
        var results = data && data.results;
        if (!results || !results.length) {
            return null;
        }
        var first = results[0];
        return { lat: first.latitude, lon: first.longitude, name: first.name || "" };
    } catch (e) {
        return null;
    }
}

function parseCurrentWeatherResponse(json) {
    try {
        var data = typeof json === "string" ? JSON.parse(json) : json;
        var current = data && data.current_weather;
        if (!current) {
            return null;
        }
        return { code: current.weathercode, temperature: current.temperature };
    } catch (e) {
        return null;
    }
}

function pad2(value) {
    value = parseInt(value, 10) || 0;
    return value < 10 ? "0" + value : String(value);
}

function isoDateFromParts(year, month, day) {
    return year + "-" + pad2(month) + "-" + pad2(day);
}

function monthDayFromParts(month, day) {
    return pad2(month) + "-" + pad2(day);
}

function parseTimeCapsuleLines(text) {
    if (!text) {
        return [];
    }
    var lines = String(text).split("\n");
    var entries = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || line.charAt(0) === "#") {
            continue;
        }
        var parts = line.split("|");
        var date = (parts[0] || "").trim();
        var query = (parts[1] || "").trim();
        var label = (parts[2] || "").trim();
        if (!/^\d{2}-\d{2}$/.test(date) && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
            continue;
        }
        if (!query) {
            continue;
        }
        entries.push({ date: date, query: query, label: label });
    }
    return entries;
}

function formatTimeCapsuleLines(entries) {
    if (!entries || !entries.length) {
        return "";
    }
    return entries.map(function(entry) {
        var line = entry.date + "|" + entry.query;
        if (entry.label) {
            line += "|" + entry.label;
        }
        return line;
    }).join("\n");
}

function parseTimeCapsules(raw) {
    if (!raw) {
        return [];
    }
    try {
        var parsed = JSON.parse(raw);
        if (!parsed || !parsed.length) {
            return [];
        }
        return parsed.filter(function(entry) {
            return entry && entry.date && entry.query;
        });
    } catch (e) {
        return [];
    }
}

function serializeTimeCapsules(entries) {
    return JSON.stringify(entries || []);
}

function findDueTimeCapsule(entries, todayFull, todayMonthDay) {
    if (!entries || !entries.length) {
        return null;
    }
    for (var i = 0; i < entries.length; i++) {
        var date = entries[i].date;
        if (date === todayFull || date === todayMonthDay) {
            return entries[i];
        }
    }
    return null;
}

function computeStreak(lastDateStr, todayStr, currentStreak) {
    if (!lastDateStr) {
        return 1;
    }
    if (lastDateStr === todayStr) {
        return currentStreak || 1;
    }
    var last = new Date(lastDateStr + "T00:00:00");
    var today = new Date(todayStr + "T00:00:00");
    var diffDays = Math.round((today.getTime() - last.getTime()) / 86400000);
    if (diffDays === 1) {
        return (currentStreak || 0) + 1;
    }
    return 1;
}

function findNewMilestone(previousCount, newCount, milestones) {
    for (var i = 0; i < milestones.length; i++) {
        if (previousCount < milestones[i] && newCount >= milestones[i]) {
            return milestones[i];
        }
    }
    return 0;
}
