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

function testParseDiskCacheIndex() {
    const empty = Wallhaven.parseDiskCacheIndex("");
    assert(empty.ids.length === 0, "empty index");

    const parsed = Wallhaven.parseDiskCacheIndex('{"ids":["abc","def"],"next":2}');
    assert(parsed.ids.length === 2 && parsed.ids[0] === "abc", "parsed ids");
    assert(parsed.next === 2, "parsed next pointer");
}

function testListCachedIds() {
    const ids = Wallhaven.listCachedIds({ ids: ["a", "", "b", "a"] });
    assert(ids.length === 2 && ids[0] === "a" && ids[1] === "b", "unique cached ids");
}

function testNormalizeCollectionEntry() {
    const entry = Wallhaven.normalizeCollectionEntry({
        id: 42,
        label: "Anime",
        username: "demo",
    });
    assert(entry.display.indexOf("demo") !== -1, "collection display includes username");
    assert(entry.id === "42", "collection id stringified");
}

function testParseCollectionsResponse() {
    const list = Wallhaven.parseCollectionsResponse({
        data: [
            { id: 1, label: "Favorites", username: "demo" },
            { id: 2, label: "Landscape", username: "demo" },
        ],
    });
    assert(list.length === 2, "collections parsed");
}

function testPeekAheadWallpapers() {
    const cfg = {
        LocalSortings: "ascending",
        DedupEnabled: false,
    };
    const state = {
        page: 1,
        index: 0,
        seed: "seed",
        lastPage: 1,
        total: 2,
        totalShown: 0,
        usedIndices: [],
        seenIds: [],
        screenWidth: 1920,
        screenHeight: 1080,
        searchQuery: "",
        favoritesUser: "",
        favoritesId: "",
    };
    const wallpapers = [
        { id: "one" },
        { id: "two" },
    ];
    const ahead = Wallhaven.peekAheadWallpapers(cfg, state, wallpapers, 2);
    assert(ahead.length === 2, "peek ahead returns two wallpapers");
    assert(ahead[0].id === "one" && ahead[1].id === "two", "peek ahead order");
}

[
    testParseDiskCacheIndex,
    testListCachedIds,
    testNormalizeCollectionEntry,
    testParseCollectionsResponse,
    testPeekAheadWallpapers,
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
