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
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
