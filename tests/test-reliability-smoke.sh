#!/usr/bin/env bash
# Smoke checks for 3.5.x blank-monitor / control / storm reliability guards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN="${ROOT}/contents/ui/main.qml"
JS="${ROOT}/contents/code/wallhaven.js"
DBUS="${ROOT}/tools/wallhaven-dbus.py"

echo "==> Reliability symbol smoke"

required_qml=(
    "function reloadCurrentImage"
    "function bootstrapWallpaperFromCache"
    "function wallpaperIsVisible"
    "function wallpaperLooksStuckBlank"
    "function recoverBlankFrame"
    "function recoverAfterWake"
    "function clearWallpaperImageSources"
    "function resetWallpaperLayerVisibility"
    "function tryStartPendingTransition"
    "function abortPendingTransitionKeepVisible"
    "function setSlideshowPaused"
    "function maybeProbeApiOutageClear"
    "transitionReadyTimer"
    "startupVisibilityTimer"
    "outageProbeTimer"
    "_pendingSyncAdvance"
    "_pendingControlCmd"
    "_outageProbeAtMs"
)

for needle in "${required_qml[@]}"; do
    rg -q --fixed-strings "${needle}" "${MAIN}" || {
        echo "Missing in main.qml: ${needle}" >&2
        exit 1
    }
done

rg -q 'function isNavControlCommand' "${JS}"
rg -q 'function shouldClearSoftOutage' "${JS}"
rg -q --fixed-strings 'clearApiOutageOffline(true, true)' "${MAIN}"
rg -q 'shouldClearSoftOutage' "${MAIN}"
rg -q 'function isLockSyncPrimaryWinner' "${JS}"
rg -q 'function releaseDiskCacheId' "${JS}"
rg -q 'cmdGroup === "default" && isNavControlCommand' "${JS}"
rg -q --fixed-strings 'return "ok" if code == 0 else f"fail:{code}"' "${DBUS}"
rg -q '"curl"' "${DBUS}"
rg -q 'def validate_run_argv' "${DBUS}"
rg -q 'CURL_HOST_RE' "${DBUS}"
rg -q 'BASH_SCRIPT_ALLOWLIST' "${DBUS}"
rg -q 'fadeBlackOut.stop()' "${MAIN}"
rg -q 'wallpaperIsVisible()' "${MAIN}"

# Offline fallback must require a visible frame before keeping currentUrl.
rg -q -U 'currentSrc && root\.wallpaperIsVisible\(\)' "${MAIN}" || {
    echo "tryOfflineFallback must keep current when wallpaperIsVisible()" >&2
    exit 1
}

# Sync-advance must queue while busy rather than stamping-and-skipping.
rg -q '_pendingSyncAdvance = true' "${MAIN}"
rg -q --fixed-strings 'skipForward(true)' "${MAIN}"
rg -q --fixed-strings 'Wallhaven.shouldBroadcastSyncAdvance(fromSync)' "${MAIN}"

# Nav controls must queue while busy and flush in endBusy.
rg -q '_pendingControlCmd = \{ cmd: cmd.cmd' "${MAIN}" || rg -q '_pendingControlCmd =' "${MAIN}"
rg -q 'root\._pendingControlCmd' "${MAIN}"

# Cache-advance throttle returns false (not a successful advance).
rg -q 'Not a successful advance' "${MAIN}"

# Quiet outage probe clears only via API path (never favicon).
rg -q 'maybeProbeApiOutageClear' "${MAIN}"
rg -q 'Do NOT clear API outage' "${MAIN}" || rg -q 'must never clear outage' "${MAIN}" || true
rg -q --fixed-strings 'quiet: true' "${MAIN}"

# Warm/original curl must require RunArgv ok + non-empty file.
rg -q 'releaseDiskCacheId' "${MAIN}"
rg -q --fixed-strings '"test", "-s"' "${MAIN}" || rg -q --fixed-strings "['test', '-s'" "${MAIN}" || rg -q '"test", "-s"' "${MAIN}"

# Lock sync: same-id retry budget (flock serializes multi-monitor writers).
rg -q 'attempts:' "${MAIN}" || rg -q --fixed-strings 'attempts:' "${MAIN}"
rg -q 'function isLockSyncPrimaryWinner' "${JS}"

# Cache throttle must not look like a successful advance.
rg -q 'function shouldThrottleCacheAdvance' "${JS}"
rg -q --fixed-strings 'statusOverride === undefined' "${JS}"
rg -q -U 'shouldThrottleCacheAdvance\([\s\S]*?return false;' "${MAIN}" || rg -q 'Not a successful advance' "${MAIN}"

# Pause/resume must be idempotent setters, not toggle both.
rg -q --fixed-strings 'case "pause":' "${MAIN}"
rg -q --fixed-strings 'setSlideshowPaused(true)' "${MAIN}"
rg -q --fixed-strings 'setSlideshowPaused(false)' "${MAIN}"

# Offline / 429 cache-storm guards
rg -q '_lastCacheAdvanceMs' "${MAIN}"
rg -q 'never fall back to a remote thumb' "${MAIN}" || rg -q 'Soft-offline / rate-limit: never fall back' "${MAIN}"
rg -q 'Soft-offline must never open a network image URL' "${MAIN}"
rg -q 'never advance the' "${MAIN}" || rg -q 'never advance the offline cursor' "${MAIN}"
rg -q 'do not require paintedWidth' "${MAIN}"
rg -q 'Only reload the current frame' "${MAIN}" || rg -q 'Only reload the current frame. Advancing cache' "${MAIN}"

rg -q 'function isFreshBusTimestamp' "${JS}"
rg -q 'function shouldThrottleCacheAdvance' "${JS}"
rg -q --fixed-strings 'property double _lastControlTs' "${MAIN}"
rg -q --fixed-strings 'property double _lastSyncAdvanceTs' "${MAIN}"
rg -q --fixed-strings 'property double _nextSlideshowAt' "${MAIN}"
rg -q 'isFreshBusTimestamp' "${MAIN}"
rg -q 'shouldThrottleCacheAdvance' "${MAIN}"
rg -q --fixed-strings 'statusOverride === undefined' "${JS}"

echo "==> Reliability symbol smoke OK"
