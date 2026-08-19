#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sourcePath = path.join(__dirname, "..", "contents", "code", "wallhaven.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*\n/, "");
const context = { console, Math, Date, JSON, encodeURIComponent, parseInt, Infinity };
vm.createContext(context);
vm.runInContext(source, context);
const Wallhaven = context;

function assert(condition, message) {
    if (!condition) {
        throw new Error(message);
    }
}

function testFileTypeFilter() {
    var cfg = { FileTypeFilter: "png", Sortings: "random", Order: "desc" };
    var state = { page: 1, seed: "x", searchQuery: "nature", screenWidth: 1920, screenHeight: 1080 };
    var url = Wallhaven.buildSearchUrl(cfg, state);
    assert(url.indexOf(encodeURIComponent("type:png")) !== -1, "png filter in url");
}

function testSimilarSearch() {
    assert(Wallhaven.buildSimilarSearchQuery("abc12") === "like:abc12", "similar query");
}

function testIntervalJitter() {
    var ms = Wallhaven.computeIntervalMs({ RandomInterval: 10, IntervalJitterPercent: 0 }, true);
    assert(ms === 600000, "base interval");
}

function testControlBus() {
    var cmd = Wallhaven.parseControlCommand('{"cmd":"next","ts":100,"group":"default"}');
    assert(cmd.cmd === "next" && cmd.group === "default", "control parse");
}

function testBase64() {
    var encoded = Wallhaven.base64EncodeUtf8("hello");
    assert(encoded.length > 0, "base64 encode");
}

function testTagBlocklist() {
    var tags = Wallhaven.parseTagBlocklist('["nsfw","text"]');
    assert(tags.length === 2, "tag parse");
    var query = Wallhaven.appendTagBlocklist("nature", tags);
    assert(query.indexOf("-nsfw") !== -1 && query.indexOf("-text") !== -1, "tag append");
}

function testSchedule() {
    var cfg = { ScheduleEnabled: true, WeekdaySearch: "weekday", WeekendSearch: "weekend" };
    var text = Wallhaven.getEffectiveSearchText(cfg);
    assert(text === "weekday" || text === "weekend", "schedule search");
}

function testCollectionRotation() {
    var lines = "alice/42 # fav\nbob/7";
    var entries = Wallhaven.parseCollectionRotationLines(lines);
    assert(entries.length === 2 && entries[0].user === "alice", "rotation lines");
    var pick = Wallhaven.pickCollectionRotation(entries, 1);
    assert(pick.entry.id === "7", "rotation pick");
}

function testHistory() {
    var history = Wallhaven.appendWallpaperHistory([], { id: "abc", ts: 1 }, 5);
    assert(history.length === 1 && history[0].id === "abc", "history append");
}

function testTransitionPick() {
    var mode = Wallhaven.pickTransitionMode({ TransitionMode: "crossfade" });
    assert(mode === "crossfade", "fixed transition");
}

function testPanelTint() {
    var hex = Wallhaven.dominantColorFromWallhaven(["660000", "ffffff"]);
    assert(hex === "660000", "dominant color");
}

function testPresetShare() {
    var preset = { name: "Test", SearchText: "nature" };
    var encoded = Wallhaven.encodePresetSharePayload(preset);
    var decoded = Wallhaven.decodePresetSharePayload(encoded);
    assert(decoded.name === "Test", "preset share roundtrip");
}

function testPreloadCount() {
    var online = Wallhaven.computePreloadCount({ PreloadCount: 2, AdaptivePreloadEnabled: true }, true, false);
    assert(online === 2, "online preload");
    var metered = Wallhaven.computePreloadCount({ PreloadCount: 2, AdaptivePreloadEnabled: true }, true, true);
    assert(metered === 1, "metered preload");
}

function testWotdUrl() {
    var cfg = { WallpaperOfDayEnabled: true, Sortings: "random", Order: "desc" };
    var url = Wallhaven.buildSearchUrl(cfg, { page: 1, seed: "x", searchQuery: "", screenWidth: 1920, screenHeight: 1080 });
    assert(url.indexOf("toplist") !== -1 && url.indexOf("topRange=1d") !== -1, "wotd url");
}

function testMetrics() {
    var m = Wallhaven.createMetricsState();
    m = Wallhaven.recordFetchMetrics(m, 120, false);
    assert(m.fetchCount === 1 && m.avgFetchMs === 120, "metrics");
}

function testImportPresetUrl() {
    var preset = { name: "X", SearchText: "test" };
    var url = Wallhaven.buildPresetShareUrl(preset);
    var imported = Wallhaven.importPresetFromShareUrl(url);
    assert(imported.name === "X", "preset url import");
}

function testVarietyParse() {
    var ini = "[preferences]\nimage_fetch_search = nature landscape\n";
    assert(Wallhaven.parseVarietySearch(ini) === "nature landscape", "variety parse");
}

function testStatusSnapshotLocalThumb() {
    var snap = JSON.parse(Wallhaven.buildStatusSnapshot({
        id: "abc12",
        thumbUrl: "https://th.wallhaven.cc/small/abc/abc12.jpg",
        localThumbUrl: "file:///home/user/.cache/wallhaven/abc12.jpg",
        varietyWatchEnabled: true,
    }));
    assert(snap.localThumbUrl.indexOf("file://") === 0, "local thumb in status bus");
    assert(snap.varietyWatchEnabled === true, "variety watch flag in status bus");
}

function testPluginVersion() {
    assert(/^\d+\.\d+\.\d+$/.test(Wallhaven.pluginVersion()), "plugin version semver");
}

function testAppendDebugLogLine() {
    var text = Wallhaven.appendDebugLogLine("a\nb\n", "c", 2);
    assert(text === "b\nc\n", "debug log rotation");
}

function testBundledPresetsMatchJson() {
    var curatedJson = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "contents", "presets", "curated.json"), "utf8"));
    var communityJson = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "contents", "presets", "community.json"), "utf8"));
    assert(JSON.stringify(Wallhaven.bundledCuratedPresets()) === JSON.stringify(curatedJson), "curated pack matches json");
    assert(JSON.stringify(Wallhaven.bundledCommunityPresets()) === JSON.stringify(communityJson), "community pack matches json");
    var merged = Wallhaven.mergePresetLists([{ name: "Nature landscapes" }], Wallhaven.bundledCuratedPresets());
    assert(merged.length === curatedJson.length, "merge skips duplicate curated names");
}

function testParallaxMotion() {
    var off = Wallhaven.parallaxOffsetX(false, 50, 1920, 0.25, 0);
    assert(off === 0, "parallax disabled is zero");
    var mid = Wallhaven.parallaxOffsetX(true, 100, 1920, 0.25, 0);
    assert(Math.abs(mid) > 50, "parallax pan is visible");
    assert(Wallhaven.parallaxScaleForStrength(true, 100) > 1.1, "parallax zooms to hide edges");
    assert(Wallhaven.parallaxScaleForStrength(false, 100) === 1, "disabled parallax scale");
    assert(Wallhaven.parallaxCycleMs(50) > 40000, "slow cycle");
    var left = Wallhaven.parallaxOffsetX(true, 80, 1920, 0, 0);
    var right = Wallhaven.parallaxOffsetX(true, 80, 1920, 0, 0.25);
    assert(Math.abs(left - right) > 1, "screens phase differently");
}

function testLockScreenSyncCommand() {
    var cmd = Wallhaven.buildLockScreenSyncCommand("/tmp/src.jpg", "/tmp/lock.jpg");
    assert(cmd.indexOf("cp -f") !== -1, "copies to stable lockscreen file");
    assert(cmd.indexOf("--group Wallpaper") !== -1, "nested wallpaper group");
    assert(cmd.indexOf("--group org.kde.image") !== -1, "image plugin group");
    assert(cmd.indexOf("--key Image ") !== -1, "Image key");
    assert(cmd.indexOf("file:///tmp/lock.jpg") !== -1, "file url");
    assert(cmd.indexOf("--key Wallpaper ") === -1, "does not write bogus Greeter Wallpaper key");
    var same = Wallhaven.buildLockScreenSyncCommand("/tmp/lock.jpg", "/tmp/lock.jpg");
    assert(same.indexOf("cp -f") === -1, "skips copy when already at dest");
}

function testDiskCacheNamespaceAndCategories() {
    assert(Wallhaven.sanitizeCacheNamespace("DP-1") === "DP-1", "sanitize screen name");
    assert(Wallhaven.diskCacheFileName(0, "DP-1") === "wallhaven-cache-DP-1-00.jpg", "namespaced slot file");
    assert(Wallhaven.diskCacheFileName(0) === "wallhaven-cache-00.jpg", "legacy slot file");
    assert(Wallhaven.diskCacheFileName(0, "HDMI-A-1") !== Wallhaven.diskCacheFileName(0, "DP-1"), "monitors do not share files");

    var cfg = { BrowseMode: "search", CategoryGeneral: true, CategoryAnime: true, CategoryPeople: false };
    var page = [
        { id: "aaa", category: "general" },
        { id: "bbb", category: "people" },
        { id: "ccc", category: "anime" },
    ];
    var filtered = Wallhaven.filterWallpapersByCategories(page, cfg);
    assert(filtered.length === 2 && filtered[0].id === "aaa" && filtered[1].id === "ccc", "drop people category");
    assert(Wallhaven.filterWallpapersByCategories(page, { BrowseMode: "collection", CategoryPeople: false }).length === 3, "collections skip category filter");

    var index = { ids: [], next: 0, categories: {} };
    Wallhaven.allocateDiskCacheSlot(index, "bbb", 5, [], "people");
    Wallhaven.allocateDiskCacheSlot(index, "aaa", 5, [], "general");
    var allIds = Wallhaven.listCachedIds(index);
    assert(allIds.length === 2, "unfiltered cache ids");
    var matching = Wallhaven.listCachedIds(index, cfg);
    assert(matching.length === 1 && matching[0] === "aaa", "offline cache skips people");
    Wallhaven.allocateDiskCacheSlot(index, "ddd", 5, [], "general", "nsfw");
    assert(Wallhaven.listCachedIds(index, cfg).indexOf("ddd") === -1, "offline cache skips nsfw");
    var sfwOnly = { BrowseMode: "search", CategoryGeneral: true, CategoryPeople: true, PuritySfw: true, PuritySketchy: false, PurityNsfw: false };
    var mixed = [
        { id: "s", category: "general", purity: "sfw" },
        { id: "k", category: "general", purity: "sketchy" },
        { id: "n", category: "general", purity: "nsfw" },
    ];
    var kept = Wallhaven.filterWallpapersByCategories(mixed, sfwOnly);
    assert(kept.length === 1 && kept[0].id === "s", "drop sketchy and nsfw");
    var roundtrip = Wallhaven.parseDiskCacheIndex(Wallhaven.serializeDiskCacheIndex(index));
    assert(roundtrip.categories.bbb === "people", "cache index stores category");
    assert(roundtrip.purities.ddd === "nsfw", "cache index stores purity");
}

function testNormalizeSearchPreset() {
    var cfg = {};
    Wallhaven.applyPresetToConfig({
        name: "Cyberpunk",
        SearchText: "cyberpunk neon",
        CategoryGeneral: true,
        CategoryAnime: true,
    }, cfg);
    assert(cfg.SearchText === "cyberpunk neon", "preset search text");
    assert(cfg.CategoryPeople === false, "omitted people category becomes false");
    assert(cfg.CategoryAnime === true, "explicit anime stays on");
    var space = Wallhaven.bundledCuratedPresets().filter(function(p) { return p.name === "Space"; })[0];
    assert(space.CategoryPeople === false, "space pack disables people");
}

function testExportIncludesV250Settings() {
    var newKeys = [
        "MusicReactiveEnabled", "MusicReactiveIntensity", "WeatherReactiveEnabled",
        "WeatherLocation", "TimeCapsulesJson", "SystemThemeSyncEnabled", "AchievementsEnabled",
    ];
    var cfg = {};
    newKeys.forEach(function(key) { cfg[key] = key === "MusicReactiveIntensity" ? 55 : "test-value"; });
    cfg.MusicReactiveEnabled = true;
    var snapshot = JSON.parse(Wallhaven.exportSettingsSnapshot(cfg));
    newKeys.forEach(function(key) {
        assert(snapshot.settings[key] !== undefined, "v2.5.0 setting exported: " + key);
    });
    var imported = Wallhaven.importSettingsSnapshot(Wallhaven.exportSettingsSnapshot(cfg));
    assert(imported.WeatherLocation === "test-value", "v2.5.0 setting roundtrips through import");
}

function testSwipeToRate() {
    var tags = Wallhaven.tagsStringToBlocklistTags("sky, city lights, sunset", 5);
    assert(tags.length === 3 && tags[1] === "city_lights", "tags normalized for lists");
    var boosted = Wallhaven.addTagsToJsonList("[]", tags, 30);
    assert(JSON.parse(boosted).length === 3, "boost adds tags");
    var removed = Wallhaven.removeTagsFromJsonList(boosted, ["sky"]);
    assert(JSON.parse(removed).indexOf("sky") === -1, "dislike/like removes contradicting tag");
}

function testMusicReactiveSpeed() {
    assert(Wallhaven.musicReactiveSpeedMultiplier(50, false) === 1, "no boost when not playing");
    assert(Wallhaven.musicReactiveSpeedMultiplier(100, true) === 1.6, "max boost at 100%");
    assert(Wallhaven.musicReactiveSpeedMultiplier(0, true) === 1, "no boost at 0% intensity");
}

function testWeatherMapping() {
    assert(Wallhaven.mapWeatherCodeToTag(0) === "clear sky", "clear code");
    assert(Wallhaven.mapWeatherCodeToTag(61) === "rain", "rain code");
    assert(Wallhaven.mapWeatherCodeToTag(75) === "snow", "snow code");
    assert(Wallhaven.mapWeatherCodeToTag(95) === "storm", "storm code");
    assert(Wallhaven.appendWeatherModifier("nature", "rain") === "nature rain", "weather modifier appended");
    assert(Wallhaven.appendWeatherModifier("nature", "") === "nature", "empty tag is no-op");
    var parsed = Wallhaven.parseLatLon("41.8, -87.6");
    assert(parsed && parsed.lat === 41.8 && parsed.lon === -87.6, "lat/lon parse");
    var geocode = Wallhaven.parseGeocodeResponse({ results: [{ latitude: 1, longitude: 2, name: "X" }] });
    assert(geocode.lat === 1 && geocode.lon === 2, "geocode parse");
    var weather = Wallhaven.parseCurrentWeatherResponse({ current_weather: { weathercode: 61, temperature: 12 } });
    assert(weather.code === 61, "current weather parse");
}

function testTimeCapsules() {
    var text = "12-25|christmas snow|Holiday\n2026-09-01|back to school";
    var entries = Wallhaven.parseTimeCapsuleLines(text);
    assert(entries.length === 2 && entries[0].date === "12-25" && entries[0].label === "Holiday", "capsule line parse");
    assert(entries[1].label === "", "optional label defaults empty");
    var roundtrip = Wallhaven.formatTimeCapsuleLines(entries);
    assert(roundtrip.indexOf("12-25|christmas snow|Holiday") !== -1, "capsule line format");
    var stored = Wallhaven.parseTimeCapsules(Wallhaven.serializeTimeCapsules(entries));
    assert(stored.length === 2, "capsule json roundtrip");
    var due = Wallhaven.findDueTimeCapsule(entries, "2027-12-25", "12-25");
    assert(due && due.query === "christmas snow", "recurring MM-DD capsule matches");
    var dueOnce = Wallhaven.findDueTimeCapsule(entries, "2026-09-01", "09-01");
    assert(dueOnce && dueOnce.query === "back to school", "one-off YYYY-MM-DD capsule matches");
    assert(Wallhaven.findDueTimeCapsule(entries, "2026-01-01", "01-01") === null, "no match on other days");
    assert(Wallhaven.isoDateFromParts(2026, 3, 5) === "2026-03-05", "iso date format");
    assert(Wallhaven.monthDayFromParts(3, 5) === "03-05", "month-day format");
}

function testAchievements() {
    assert(Wallhaven.computeStreak("", "2026-01-01", 0) === 1, "first ever view starts streak at 1");
    assert(Wallhaven.computeStreak("2026-01-01", "2026-01-01", 4) === 4, "same day keeps streak");
    assert(Wallhaven.computeStreak("2026-01-01", "2026-01-02", 4) === 5, "consecutive day increments streak");
    assert(Wallhaven.computeStreak("2026-01-01", "2026-01-05", 4) === 1, "gap resets streak");
    assert(Wallhaven.findNewMilestone(8, 10, [10, 50, 100]) === 10, "crossing milestone fires once");
    assert(Wallhaven.findNewMilestone(10, 10, [10, 50, 100]) === 0, "already-hit milestone does not refire");
    assert(Wallhaven.findNewMilestone(48, 60, [10, 50, 100]) === 50, "skips ahead to the crossed milestone");
}

[    testFileTypeFilter,
    testSimilarSearch,
    testIntervalJitter,
    testControlBus,
    testBase64,
    testTagBlocklist,
    testSchedule,
    testCollectionRotation,
    testHistory,
    testTransitionPick,
    testPanelTint,
    testPresetShare,
    testPreloadCount,
    testWotdUrl,
    testMetrics,
    testImportPresetUrl,
    testVarietyParse,
    testStatusSnapshotLocalThumb,
    testPluginVersion,
    testAppendDebugLogLine,
    testBundledPresetsMatchJson,
    testParallaxMotion,
    testLockScreenSyncCommand,
    testDiskCacheNamespaceAndCategories,
    testNormalizeSearchPreset,
    testExportIncludesV250Settings,
    testSwipeToRate,
    testMusicReactiveSpeed,
    testWeatherMapping,
    testTimeCapsules,
    testAchievements,
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
