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

[
    testFileTypeFilter,
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
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
