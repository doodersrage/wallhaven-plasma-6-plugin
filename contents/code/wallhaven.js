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
    "BlockedIdsJson", "SearchPresetsJson",
];

function exportSettingsSnapshot(cfg) {
    var snapshot = {
        version: 2,
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

function allocateDiskCacheSlot(index, id, maxSlots) {
    maxSlots = maxSlots || DISK_CACHE_SLOTS;
    id = String(id || "");
    if (!id) {
        return -1;
    }
    if (!index.ids) {
        index.ids = [];
    }
    var existing = index.ids.indexOf(id);
    if (existing !== -1) {
        return existing;
    }
    var slot = (index.next || 0) % maxSlots;
    while (index.ids.length < maxSlots) {
        index.ids.push("");
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
    if (cfg.TimeOfDayEnabled) {
        var hour = new Date().getHours();
        var isDay = hour >= 6 && hour < 20;
        return isDay ? cfg.DaySearch : cfg.NightSearch;
    }
    return cfg.SearchText || "";
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

    params.push("sorting=" + encodeURIComponent(cfg.Sortings || "random"));
    params.push("order=" + encodeURIComponent(cfg.Order || "desc"));
    params.push("page=" + encodeURIComponent(String(state.page)));

    if (cfg.Sortings === "random") {
        params.push("seed=" + encodeURIComponent(state.seed));
    }
    if (cfg.Sortings === "toplist" && cfg.TopRange) {
        params.push("topRange=" + encodeURIComponent(cfg.TopRange));
    }

    var query = state.searchQuery || getEffectiveSearchText(cfg);
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
