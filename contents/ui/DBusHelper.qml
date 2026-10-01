import QtQuick
import org.kde.plasma.workspace.dbus as PDBus
import "../code/wallhaven.js" as Wallhaven

// Every call the wallpaper makes to wallhaven-dbus.py (org.robertsm.Wallhaven).
// plasmashell QML cannot touch files or run processes itself, so file I/O,
// KWallet, lock-screen sync and the few allow-listed commands all go through
// here. Replies arrive wrapped (variant/array); callbacks get plain strings.
QtObject {
    id: helper

    readonly property string service: "org.robertsm.Wallhaven"
    readonly property string objectPath: "/Wallhaven"
    readonly property bool busAvailable: typeof PDBus !== "undefined" && !!PDBus.SessionBus

    function wallhavenNormalizeSignature(signature) {
        var sig = String(signature || "").trim();
        if (!sig)
            return "";
        // Plasma's D-Bus encoder expects parenthesized signatures, e.g. "(ss)".
        if (sig.charAt(0) !== "(")
            sig = "(" + sig + ")";
        return sig;
    }

    function wallhavenTypedArgs(signature, args) {
        // Prefer typed wrappers when available; fall back to plain values.
        var out = [];
        var sig = String(signature || "").replace(/[()]/g, "");
        var list = args || [];
        var ai = 0;
        var hasStringCtor = typeof PDBus.string === "function";
        var hasBoolCtor = typeof PDBus.bool === "function";
        for (var i = 0; i < sig.length && ai < list.length; i++) {
            var ch = sig.charAt(i);
            var value = list[ai++];
            if (ch === "s" && hasStringCtor)
                out.push(new PDBus.string(String(value == null ? "" : value)));
            else if (ch === "b" && hasBoolCtor)
                out.push(new PDBus.bool(!!value));
            else
                out.push(value);
        }
        while (ai < list.length)
            out.push(list[ai++]);
        return out;
    }

    // Call any session-bus method. onReply(reply) / onError(err) are optional.
    function sessionCall(service, path, iface, member, signature, args, onReply, onError) {
        if (!helper.busAvailable) {
            if (onError)
                onError(null);
            return;
        }
        var normalized = wallhavenNormalizeSignature(signature);
        var msg = new PDBus.dbusMessage({
            service: service,
            path: path,
            iface: iface,
            member: member,
            signature: normalized,
            arguments: wallhavenTypedArgs(normalized, args),
        });
        PDBus.SessionBus.asyncCall(msg, function(reply) {
            if (onReply)
                onReply(reply);
        }, function(err) {
            if (onError)
                onError(err);
        });
    }

    // callback(reply) on success, callback("") on any failure.
    function wallhavenMessage(member, signature, args, callback) {
        sessionCall(helper.service, helper.objectPath, helper.service, member, signature, args,
            callback, function(err) {
                var detail = "";
                try {
                    if (err && err.error)
                        detail = String(err.error.message || err.error.name || "");
                    else if (err && err.message)
                        detail = String(err.message);
                } catch (e) {}
                console.warn("Wallhaven D-Bus call failed:", member, detail || err);
                if (callback)
                    callback("");
            });
    }

    function stringCall(member, signature, args, callback) {
        wallhavenMessage(member, signature, args, function(reply) {
            if (callback)
                callback(Wallhaven.dbusReplyAsString(reply));
        });
    }

    function ping(onUp, onDown) {
        sessionCall(helper.service, helper.objectPath, helper.service, "Ping", "", [], onUp, onDown);
    }

    function writeFile(path, text, callback) {
        stringCall("WriteTextFile", "ss", [Wallhaven.urlToLocalPath(path), text || ""], callback);
    }

    function readFile(path, callback) {
        stringCall("ReadTextFile", "s", [Wallhaven.urlToLocalPath(path)], callback);
    }

    function appendFile(path, line, callback) {
        stringCall("AppendTextFile", "ss", [Wallhaven.urlToLocalPath(path), line || ""], callback);
    }

    // Allow-listed argv only (rm/cp/curl/test/stat/…); the service has no shell.
    function runArgv(argv, callback) {
        var cleaned = [];
        for (var i = 0; i < (argv || []).length; i++) {
            var arg = String(argv[i] == null ? "" : argv[i]);
            // Never pass file:// URLs to command-line tools.
            if (arg.indexOf("file:") === 0)
                arg = Wallhaven.urlToLocalPath(arg);
            cleaned.push(arg);
        }
        stringCall("RunArgv", "s", [JSON.stringify(cleaned)], callback);
    }

    // callback({path: bytes}) — one call instead of a `stat` process per file.
    function statCacheFiles(paths, callback) {
        stringCall("StatCacheFiles", "s", [JSON.stringify(paths || [])], function(text) {
            var sizes = {};
            try {
                sizes = JSON.parse(text || "{}") || {};
            } catch (e) {
                sizes = {};
            }
            if (callback)
                callback(sizes);
        });
    }

    function listImageFiles(folder, maxDepth, exclude, callback) {
        var options = JSON.stringify({
            maxDepth: Math.max(0, Math.min(8, parseInt(maxDepth, 10) || 3)),
            exclude: String(exclude || ""),
        });
        stringCall("ListImageFiles", "ss", [folder || "", options], callback);
    }

    // callback(binaryPath) -- "" when no upscaler is installed or the call fails.
    function checkUpscalerAvailable(callback) {
        stringCall("UpscalerAvailable", "", [], callback);
    }

    // callback(ok) -- ok is false on any failure (not installed, timed out,
    // tool errored); callers should just keep using the plain-scaled image.
    function upscale(inputPath, outputPath, callback) {
        wallhavenMessage("Upscale", "ss", [inputPath, outputPath], function(reply) {
            if (callback)
                callback(Wallhaven.dbusReplyIsTrue(reply));
        });
    }

    // callback(key) -- "" when KWallet has no key or is unavailable.
    function getApiKey(callback) {
        stringCall("GetApiKey", "", [], callback);
    }

    // callback(ok)
    function setApiKey(key, callback) {
        stringCall("SetApiKey", "s", [String(key || "")], function(text) {
            if (callback)
                callback(text.trim() === "ok");
        });
    }

    // callback("ok" | "fail:<reason>" | "")
    function syncLockScreen(sourcePath, destPath, callback) {
        stringCall("SyncLockScreen", "ss",
            [Wallhaven.urlToLocalPath(sourcePath), Wallhaven.urlToLocalPath(destPath)], callback);
    }

    // callback("ok" | "skip:<why>" | "fail:<reason>" | "")
    function ensureLockScreen(callback) {
        stringCall("EnsureLockScreen", "", [], callback);
    }

    function linkVarietyCurrent(folder, sourcePath, callback) {
        stringCall("LinkVarietyCurrent", "ss",
            [String(folder || ""), Wallhaven.urlToLocalPath(sourcePath)], callback);
    }

    function syncSystemAccent(kdeColor, gnomeAccent, callback) {
        stringCall("SyncSystemAccent", "ss", [String(kdeColor || ""), String(gnomeAccent || "")], callback);
    }

    // Pathless publish helpers; callback(ok).
    function publishStatus(statusJson, callback) {
        stringCall("PublishStatusJson", "s", [statusJson], function(text) {
            if (callback)
                callback(text !== "");
        });
    }

    function publishMonitorStatus(cacheNamespace, statusJson, callback) {
        stringCall("PublishMonitorStatusJson", "ss", [String(cacheNamespace || "default"), statusJson],
            function(text) {
                if (callback)
                    callback(text !== "");
            });
    }

    function listMonitorStatuses(callback) {
        stringCall("ListMonitorStatuses", "", [], function(text) {
            var list = [];
            try {
                list = JSON.parse(text || "[]");
            } catch (e) {
                list = [];
            }
            if (callback)
                callback(Array.isArray(list) ? list : []);
        });
    }

    function sendSearch(query, group) {
        wallhavenMessage("Search", "ss", [query, group]);
    }

    // On Wayland the unfocused desktop surface cannot set the selection, so
    // TextEdit.copy() silently does nothing. Klipper can; onUnavailable() lets
    // the caller fall back for sessions without it.
    function setClipboard(text, onUnavailable) {
        sessionCall("org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "setClipboardContents",
            "s", [String(text)], null, onUnavailable);
    }

    // onReply(names[]) / onError()
    function listBusNames(onReply, onError) {
        sessionCall("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames",
            "", [], onReply, onError);
    }

    function mprisPlaybackStatus(playerService, onReply, onError) {
        sessionCall(playerService, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get",
            "ss", ["org.mpris.MediaPlayer2.Player", "PlaybackStatus"], onReply, onError);
    }

    // org.freedesktop.ScreenSaver is the cross-desktop interface kscreenlocker
    // publishes lock state on.
    function screenSaverCall(member, onReply, onError) {
        sessionCall("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver",
            "org.freedesktop.ScreenSaver", member, "", [], onReply, onError);
    }
}
