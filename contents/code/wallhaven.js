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

function wallpaperUrl(wallpaper, quality) {
    if (!wallpaper) {
        return "";
    }
    if (quality === "original") {
        return wallpaper.path || wallpaper.large || wallpaper.thumb || "";
    }
    if (quality === "small") {
        return wallpaper.thumb || wallpaper.large || wallpaper.path || "";
    }
    return wallpaper.large || wallpaper.path || wallpaper.thumb || "";
}

function getEffectiveSearchText(cfg) {
    if (cfg.TimeOfDayEnabled) {
        var hour = new Date().getHours();
        var isDay = hour >= 6 && hour < 20;
        return isDay ? cfg.DaySearch : cfg.NightSearch;
    }
    return cfg.SearchText || "";
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
    if (cfg.ColorFilter) {
        params.push("colors=" + encodeURIComponent(cfg.ColorFilter));
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

function pickRandomIndex(wallpapers, usedIndices, seenIds, dedupEnabled) {
    var available = [];
    for (var i = 0; i < wallpapers.length; i++) {
        if (usedIndices.indexOf(i) !== -1) {
            continue;
        }
        if (dedupEnabled && seenIds.indexOf(String(wallpapers[i].id)) !== -1) {
            continue;
        }
        available.push(i);
    }

    if (!available.length) {
        for (var j = 0; j < wallpapers.length; j++) {
            if (usedIndices.indexOf(j) === -1) {
                available.push(j);
            }
        }
    }

    if (!available.length) {
        return 0;
    }

    return available[(Math.random() * available.length) | 0];
}

function advanceIndex(cfg, state, wallpapers, dryRun) {
    var snapshot = dryRun ? JSON.parse(JSON.stringify(state)) : null;
    var pageLength = wallpapers.length;
    var index = state.index;

    switch (cfg.LocalSortings) {
    case "random":
        index = pickRandomIndex(
            wallpapers,
            state.usedIndices,
            state.seenIds,
            cfg.DedupEnabled,
        );
        if (!dryRun) {
            state.usedIndices.push(index);
        }
        break;
    case "descending":
        index--;
        if (index < 0) {
            index = state.lastPage === state.page
                ? state.total - (state.lastPage - 1) * WALLPAPERS_PER_PAGE
                : WALLPAPERS_PER_PAGE;
        }
        break;
    case "ascending":
    default:
        if (state.totalShown > 0) {
            index++;
        }
        if (index > WALLPAPERS_PER_PAGE) {
            index = 0;
        }
        break;
    }

    if (cfg.DedupEnabled && !dryRun) {
        var attempts = 0;
        while (attempts < pageLength && state.seenIds.indexOf(String(wallpapers[index].id)) !== -1) {
            if (cfg.LocalSortings === "random") {
                index = pickRandomIndex(wallpapers, state.usedIndices, state.seenIds, true);
                state.usedIndices.push(index);
            } else {
                index = (index + 1) % pageLength;
            }
            attempts++;
        }
    }

    if (dryRun && snapshot) {
        return wallpapers[index] || wallpapers[0];
    }

    state.index = index;
    return wallpapers[index] || wallpapers[0];
}

function updatePageState(cfg, state) {
    var positionOnPage;
    switch (cfg.LocalSortings) {
    case "random":
        positionOnPage = state.usedIndices.length;
        break;
    case "descending":
        positionOnPage = WALLPAPERS_PER_PAGE - state.index;
        break;
    case "ascending":
    default:
        positionOnPage = state.index;
        break;
    }

    var reachedEnd = state.lastPage === state.page
        && (state.page - 1) * WALLPAPERS_PER_PAGE + positionOnPage >= state.total;

    if (reachedEnd) {
        state.usedIndices = [];
        state.page = 1;
    } else if (positionOnPage >= WALLPAPERS_PER_PAGE) {
        state.usedIndices = [];
        state.page++;
    }
}
