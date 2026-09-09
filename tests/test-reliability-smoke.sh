#!/usr/bin/env bash
# Smoke checks for 3.5.x blank-monitor / control / storm reliability guards.
# Uses grep so GitHub Actions (no ripgrep) still works; prefers rg when present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN="${ROOT}/contents/ui/main.qml"
JS="${ROOT}/contents/code/wallhaven.js"
DBUS="${ROOT}/tools/wallhaven-dbus.py"

# match_q [--fixed-strings] PATTERN FILE
match_q() {
    local fixed=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fixed-strings) fixed=1; shift ;;
            -U) shift ;; # multiline ignored; callers use line-local needles / fallbacks
            *) break ;;
        esac
    done
    local pat="$1"
    local file="$2"
    if command -v rg >/dev/null 2>&1; then
        if [[ ${fixed} -eq 1 ]]; then
            rg -q --fixed-strings -- "${pat}" "${file}"
        else
            rg -q -- "${pat}" "${file}"
        fi
    elif [[ ${fixed} -eq 1 ]]; then
        grep -Fq -- "${pat}" "${file}"
    else
        grep -Eq -- "${pat}" "${file}"
    fi
}

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
    match_q --fixed-strings "${needle}" "${MAIN}" || {
        echo "Missing in main.qml: ${needle}" >&2
        exit 1
    }
done

match_q 'function isNavControlCommand' "${JS}"
match_q 'function shouldClearSoftOutage' "${JS}"
match_q --fixed-strings 'clearApiOutageOffline(true, true)' "${MAIN}"
match_q 'shouldClearSoftOutage' "${MAIN}"
match_q 'function isLockSyncPrimaryWinner' "${JS}"
match_q 'function releaseDiskCacheId' "${JS}"
match_q 'cmdGroup === "default" && isNavControlCommand' "${JS}"
match_q --fixed-strings 'return "ok" if code == 0 else f"fail:{code}"' "${DBUS}"
match_q '"curl"' "${DBUS}"
match_q 'def validate_run_argv' "${DBUS}"
match_q 'CURL_HOST_RE' "${DBUS}"
match_q 'BASH_SCRIPT_ALLOWLIST' "${DBUS}"
match_q 'fadeBlackOut.stop()' "${MAIN}"
match_q 'wallpaperIsVisible()' "${MAIN}"

# Offline fallback must require a visible frame before keeping currentUrl.
match_q 'currentSrc && root\.wallpaperIsVisible\(\)' "${MAIN}" || {
    echo "tryOfflineFallback must keep current when wallpaperIsVisible()" >&2
    exit 1
}

# Sync-advance must queue while busy rather than stamping-and-skipping.
match_q '_pendingSyncAdvance = true' "${MAIN}"
match_q --fixed-strings 'skipForward(true)' "${MAIN}"
match_q --fixed-strings 'Wallhaven.shouldBroadcastSyncAdvance(fromSync)' "${MAIN}"

# Nav controls must queue while busy and flush in endBusy.
match_q '_pendingControlCmd =' "${MAIN}"
match_q 'root\._pendingControlCmd' "${MAIN}"

# Cache-advance throttle returns false (not a successful advance).
match_q 'Not a successful advance' "${MAIN}"

# Quiet outage probe clears only via API path (never favicon).
match_q 'maybeProbeApiOutageClear' "${MAIN}"
match_q 'Do NOT clear API outage' "${MAIN}" || match_q 'must never clear outage' "${MAIN}" || true
match_q --fixed-strings 'quiet: true' "${MAIN}"

# Warm/original curl must require RunArgv ok + non-empty file.
match_q 'releaseDiskCacheId' "${MAIN}"
match_q --fixed-strings '"test", "-s"' "${MAIN}" || match_q --fixed-strings "['test', '-s'" "${MAIN}" || match_q '"test", "-s"' "${MAIN}"

# Lock sync: same-id retry budget (flock serializes multi-monitor writers).
match_q 'attempts:' "${MAIN}"
match_q 'function isLockSyncPrimaryWinner' "${JS}"
match_q 'function ensureLockScreenImage' "${MAIN}"
match_q 'function buildLockScreenEnsureCommand' "${JS}"
match_q 'function lockScreenCurrentFileName' "${JS}"
match_q --fixed-strings 'wallhaven-lockscreen-current.jpg' "${JS}"
match_q --fixed-strings 'ensureLockScreenImage("startup")' "${MAIN}"
match_q --fixed-strings 'ensureLockScreenImage("wake:' "${MAIN}"
match_q --fixed-strings 'ensureLockScreenImage("sync-failed")' "${MAIN}"

# Cache throttle must not look like a successful advance.
match_q 'function shouldThrottleCacheAdvance' "${JS}"
match_q --fixed-strings 'statusOverride === undefined' "${JS}"
match_q 'Not a successful advance' "${MAIN}"

# Pause/resume must be idempotent setters, not toggle both.
match_q --fixed-strings 'case "pause":' "${MAIN}"
match_q --fixed-strings 'setSlideshowPaused(true)' "${MAIN}"
match_q --fixed-strings 'setSlideshowPaused(false)' "${MAIN}"

# Offline / 429 cache-storm guards
match_q '_lastCacheAdvanceMs' "${MAIN}"
match_q 'never fall back to a remote thumb' "${MAIN}" || match_q 'Soft-offline / rate-limit: never fall back' "${MAIN}"
match_q 'Soft-offline must never open a network image URL' "${MAIN}"
match_q 'never advance the' "${MAIN}" || match_q 'never advance the offline cursor' "${MAIN}"
match_q 'do not require paintedWidth' "${MAIN}"
match_q 'Only reload the current frame' "${MAIN}" || match_q 'Only reload the current frame. Advancing cache' "${MAIN}"

match_q 'function isFreshBusTimestamp' "${JS}"
match_q 'function shouldThrottleCacheAdvance' "${JS}"
match_q --fixed-strings 'property double _lastControlTs' "${MAIN}"
match_q --fixed-strings 'property double _lastSyncAdvanceTs' "${MAIN}"
match_q --fixed-strings 'property double _nextSlideshowAt' "${MAIN}"
match_q 'isFreshBusTimestamp' "${MAIN}"
match_q 'shouldThrottleCacheAdvance' "${MAIN}"
match_q --fixed-strings 'statusOverride === undefined' "${JS}"

echo "==> Reliability symbol smoke OK"
