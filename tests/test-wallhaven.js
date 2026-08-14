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

function testBlockedIds() {
    var blocked = Wallhaven.addBlockedId([], "abc123");
    assert(blocked.length === 1, "block id added");
    assert(Wallhaven.isBlocked("abc123", blocked), "blocked id detected");
    var filtered = Wallhaven.filterWallpapersByBlocklist(
        [{ id: "abc123" }, { id: "xyz789" }],
        blocked,
    );
    assert(filtered.length === 1 && filtered[0].id === "xyz789", "blocked wallpaper filtered");
}

function testPresets() {
    var preset = Wallhaven.buildPresetFromConfig("Night", {
        SearchText: "dark nature",
        Sortings: "random",
        Order: "desc",
        TopRange: "1M",
        CategoryGeneral: true,
        CategoryAnime: false,
        CategoryPeople: false,
        PuritySfw: true,
        PuritySketchy: false,
        PurityNsfw: false,
        MinWidth: "",
        MinHeight: "",
        Ratio: "landscape",
        ColorFilter: "",
        ExactResolutions: "",
        UseBlacklist: false,
        TimeOfDayEnabled: false,
        DaySearch: "",
        NightSearch: "",
    });
    assert(preset.name === "Night", "preset name");
    assert(preset.SearchText === "dark nature", "preset search text");

    var exported = JSON.parse(Wallhaven.exportSettingsSnapshot({
        SearchText: "test",
        BrowseMode: "search",
        BlockedIdsJson: "[]",
    }));
    assert(exported.plugin === "org.robertsm.wallhaven", "export plugin id");
    assert(exported.settings.SearchText === "test", "export settings");
    var imported = Wallhaven.importSettingsSnapshot(JSON.stringify(exported));
    assert(imported.SearchText === "test", "import settings");
}

function testRateLimitDelay() {
    var xhr = {
        getResponseHeader: function(name) {
            return name === "Retry-After" ? "12" : "";
        },
    };
    assert(Wallhaven.parseRateLimitDelayMs(xhr, 429) === 12000, "retry-after header");
}

function testPeekAheadWallpapers() {
    var cfg = {
        LocalSortings: "ascending",
        DedupEnabled: false,
    };
    var state = {
        page: 1,
        index: 0,
        seed: "seed",
        lastPage: 1,
        total: 2,
        totalShown: 0,
        usedIndices: [],
        seenIds: [],
        blockedIds: [],
        screenWidth: 1920,
        screenHeight: 1080,
        searchQuery: "",
        favoritesUser: "",
        favoritesId: "",
    };
    var wallpapers = [{ id: "one" }, { id: "two" }];
    var ahead = Wallhaven.peekAheadWallpapers(cfg, state, wallpapers, 2);
    assert(ahead.length === 2, "peek ahead returns two wallpapers");
}

[
    testBlockedIds,
    testPresets,
    testRateLimitDelay,
    testPeekAheadWallpapers,
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
