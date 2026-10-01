import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Wallhaven API health and the soft-offline state machine: what the last
// request returned, the shared 429 cooldown latch (all monitors honour it
// through wallhaven-ratelimit.json), outage entry/exit and the quiet probe
// that ends a non-429 outage. While soft-offline the engine shows cache only.
Item {
    id: apiState

    required property var host     // wallpaper root (main.qml)
    required property var dbus     // DBusHelper
    required property var engine   // slideshow engine (main.qml)
    readonly property var cfg: host.cfg

    // Hard cooldown that survives attribution/detail 200s clearing soft-offline.
    // Search /api/v1 must not run until this timestamp.
    property double _rateLimitUntilMs: 0
    property double _outageProbeAtMs: 0
    property int _outageProbeFailCount: 0
    property int _apiLastStatus: 0
    property string _apiLastError: ""
    property int _apiRateLimitCount: 0
    property string _apiLastRateLimitAt: ""
    property string _apiLastSuccessAt: ""
    // Temporary soft-offline while Wallhaven is unreachable; clears on API recovery.
    property bool _apiOutageOffline: false

    readonly property var apiHealth: Wallhaven.buildApiHealthSnapshot({
        lastStatus: _apiLastStatus,
        lastError: _apiLastError,
        rateLimitCount: _apiRateLimitCount,
        lastRateLimitAt: _apiLastRateLimitAt,
        lastSuccessAt: _apiLastSuccessAt,
        outageOffline: apiState._apiOutageOffline,
        apiKey: host.effectiveApiKey,
        walletStatus: host.walletStatus,
    })

    readonly property string apiHealthSummary: {
        if (apiState._apiOutageOffline) {
            return i18n("API down — using cache (%1)", host.diskCacheEntryCount);
        }
        if (_apiLastStatus === 401 || _apiLastStatus === 403) {
            var tail = Wallhaven.apiKeyLastFour(host.effectiveApiKey);
            return tail
                ? i18n("Invalid API key (…%1) — clear or re-enter", tail)
                : i18n("API unauthorized (401/403) — check or clear API key");
        }
        if (_apiRateLimitCount > 0 && _apiLastStatus === 429) {
            return i18n("Rate limited (429) — %1 time(s)", _apiRateLimitCount);
        }
        if (_apiLastStatus >= 400) {
            return i18n("Last API error: HTTP %1", _apiLastStatus);
        }
        if (_apiLastSuccessAt) {
            var keyTail = Wallhaven.apiKeyLastFour(host.effectiveApiKey);
            return keyTail ? i18n("API OK (key …%1)", keyTail) : i18n("API OK");
        }
        return i18n("API idle");
    }

    function isRateLimitedNow() {
        return apiState._rateLimitUntilMs > 0 && Date.now() < apiState._rateLimitUntilMs;
    }

    function enterApiOutageOffline(statusCode, cooldownMs) {
        apiState._apiOutageOffline = true;
        engine.stopRetries();
        var msg;
        if (statusCode === 429) {
            var cool = Wallhaven.rateLimitCooldownMs(cooldownMs);
            apiState._rateLimitUntilMs = Math.max(apiState._rateLimitUntilMs, Date.now() + cool);
            msg = i18n("Rate limited by Wallhaven. Using cache until it recovers.");
            apiState.publishRateLimitLatch(cool, statusCode);
        } else if (statusCode) {
            msg = i18n("Wallhaven unreachable (%1). Using cache until it recovers.", statusCode);
        } else {
            msg = i18n("Using cache until Wallhaven recovers.");
        }
        if (!engine.tryOfflineFallback(msg)) {
            engine.showStatus(msg, "error");
        }
        host.publishStatus();
    }

    function clearApiOutageOffline(resumeFetch, force) {
        // Never clear while the hard rate-limit cooldown is still active —
        // wallpaper detail /api/v1/w/{id} 200s used to clear soft-offline and
        // immediately re-open search fetches. Explicit resumeonline may force.
        if (!force && apiState.isRateLimitedNow()) {
            return;
        }
        if (force) {
            apiState._rateLimitUntilMs = 0;
            clearRateLimitLatch();
        }
        if (!apiState._apiOutageOffline) {
            return;
        }
        apiState._apiOutageOffline = false;
        apiState._outageProbeFailCount = 0;
        apiState._outageProbeAtMs = 0;
        host.publishStatus();
        // Never auto-resetSlideshow here. Favicon/connectivity used to clear the
        // latch and immediately re-fetch, which caused wallpaper jumping + fresh
        // 429 storms. Resume on the normal interval / explicit user action only.
        if (resumeFetch && !cfg.OfflineOnlyMode && cfg.BrowseMode !== "playlist" && cfg.BrowseMode !== "local") {
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
        }
    }

    // Quiet API probe while soft-offline from a non-429 outage. Favicon must never
    // clear outage; only a real /api/v1 200 may. Backs off on repeated failures.
    function maybeProbeApiOutageClear() {
        if (!apiState._apiOutageOffline) {
            return;
        }
        if (apiState.isRateLimitedNow()) {
            return;
        }
        // A non-quiet 200 can land while the 429 latch still blocked clear —
        // once the latch is gone, trust that success and leave soft-offline.
        if (apiState._apiLastStatus === 200) {
            clearApiOutageOffline(false);
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
            return;
        }
        if (apiState._apiLastStatus === 429) {
            return;
        }
        if (!host.configuration || cfg.OfflineOnlyMode
                || cfg.BrowseMode === "playlist" || cfg.BrowseMode === "local") {
            return;
        }
        var fails = apiState._outageProbeFailCount || 0;
        var gapMs = Math.min(300000, 30000 * Math.pow(2, Math.min(fails, 3)));
        var now = Date.now();
        if (apiState._outageProbeAtMs > 0 && (now - apiState._outageProbeAtMs) < gapMs) {
            return;
        }
        apiState._outageProbeAtMs = now;
        var url = "https://wallhaven.cc/api/v1/search?categories=100&purity=100&page=1&sorting=date_added&order=desc";
        var key = Wallhaven.sanitizeApiKey(host.effectiveApiKey);
        if (key) {
            url += "&apikey=" + encodeURIComponent(key);
        }
        engine.requestJson(url, function(json) {
            if (!apiState._apiOutageOffline) {
                return;
            }
            if (apiState.isRateLimitedNow()) {
                return;
            }
            if (!json || typeof json !== "object") {
                apiState._outageProbeFailCount = fails + 1;
                return;
            }
            apiState._outageProbeFailCount = 0;
            // Quiet XHR success does not call noteApiResult — clear explicitly.
            apiState._apiLastStatus = 200;
            apiState._apiLastSuccessAt = new Date().toISOString();
            apiState._apiLastError = "";
            clearApiOutageOffline(false);
            engine.showStatus(i18n("Wallhaven is back — resuming on the next change."), "info");
            host.publishStatus();
        }, function() {
            apiState._outageProbeFailCount = (apiState._outageProbeFailCount || 0) + 1;
        }, { quiet: true });
    }

    function publishRateLimitLatch(cooldownMs, statusCode) {
        var cool = Wallhaven.rateLimitCooldownMs(cooldownMs);
        apiState._rateLimitUntilMs = Math.max(apiState._rateLimitUntilMs, Date.now() + cool);
        var untilMs = apiState._rateLimitUntilMs;
        var payload = Wallhaven.buildRateLimitLatch(untilMs, statusCode || 429);
        dbus.writeFile(host.rateLimitBusFile, payload, function() {});
    }

    function clearRateLimitLatch() {
        if (apiState.isRateLimitedNow()) {
            return;
        }
        apiState._rateLimitUntilMs = 0;
        dbus.writeFile(host.rateLimitBusFile, "{\"untilMs\":0}", function() {});
    }

    function pollSharedRateLimit() {
        dbus.readFile(host.rateLimitBusFile, function(text) {
            var latch = Wallhaven.parseRateLimitLatch(text);
            var now = Date.now();
            if (Wallhaven.rateLimitLatchActive(latch, now)) {
                apiState._rateLimitUntilMs = Math.max(apiState._rateLimitUntilMs, latch.untilMs);
                if (!apiState._apiOutageOffline) {
                    apiState._apiOutageOffline = true;
                    engine.stopRetries();
                    if (!engine.tryOfflineFallback(
                            i18n("Rate limited by Wallhaven. Using cache until it recovers."))) {
                        engine.showStatus(
                            i18n("Rate limited by Wallhaven. Using cache until it recovers."),
                            "error",
                        );
                    }
                    host.publishStatus();
                }
                return;
            }
            // Latch expired — allow online again without forcing a new fetch.
            if (apiState._rateLimitUntilMs && now >= apiState._rateLimitUntilMs) {
                apiState._rateLimitUntilMs = 0;
            }
            // A detail/search 200 can arrive while the latch still blocked
            // clearApiOutageOffline — once the latch is gone, leave soft-offline
            // for both prior-429 and already-healthy (200) states.
            if (Wallhaven.shouldClearSoftOutage(
                    apiState._apiOutageOffline, apiState._apiLastStatus, apiState.isRateLimitedNow())) {
                clearApiOutageOffline(false);
            }
        });
    }

    function noteApiResult(status, errorText) {
        apiState._apiLastStatus = status || 0;
        apiState._apiLastError = String(errorText || "");
        if (status === 429) {
            apiState._apiRateLimitCount = (apiState._apiRateLimitCount || 0) + 1;
            apiState._apiLastRateLimitAt = new Date().toISOString();
            host._metrics = Wallhaven.recordRateLimitMetrics(host._metrics);
        } else if (status === 200) {
            apiState._apiLastSuccessAt = new Date().toISOString();
            apiState._apiLastError = "";
            if (host.configuration) {
                host.configuration.ApiKeyValid = !!Wallhaven.sanitizeApiKey(host.effectiveApiKey);
            }
            // Clear soft-offline without forcing a new slideshow reset/fetch.
            clearApiOutageOffline(false);
            clearRateLimitLatch();
        } else if (status === 401 || status === 403) {
            if (host.configuration) {
                host.configuration.ApiKeyValid = false;
            }
            // Auth errors are not outages — keep online path so user can clear the key.
            var keyHint = Wallhaven.apiKeyLastFour(host.effectiveApiKey);
            engine.showStatus(
                keyHint
                    ? i18n("Wallhaven rejected API key (…%1). Clear or re-enter it.", keyHint)
                    : i18n("Wallhaven unauthorized (%1). Check API key / NSFW settings.", status),
                "error",
            );
            // Still paint something when the current frame is missing/broken.
            if (!host.wallpaperIsVisible()) {
                if (!engine.tryOfflineFallback(i18n("Using cached wallpaper while API key is fixed."))) {
                    host.bootstrapWallpaperFromCache();
                }
            }
        }
        host.publishStatus();
    }

    // Faster probe cadence while non-429 soft-offline so recovery is not stuck
    // waiting on the 45s favicon timer alone.
    Timer {
        id: outageProbeTimer
        interval: 30000
        running: host._configured && apiState._apiOutageOffline && apiState._apiLastStatus !== 429
        repeat: true
        onTriggered: apiState.maybeProbeApiOutageClear()
    }
}
