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

[
    testFileTypeFilter,
    testSimilarSearch,
    testIntervalJitter,
    testControlBus,
    testBase64,
].forEach(function(run) {
    run();
});

console.log("All wallhaven.js tests passed.");
