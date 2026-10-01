import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Mirrors the wallpaper onto the lock screen. The copy + kscreenlockerrc
// update itself runs in wallhaven-dbus.py (SyncLockScreen / EnsureLockScreen),
// which serializes concurrent monitors with a flock; this side only decides
// when to sync, tracks the last result and retries once.
Item {
    id: lockSync

    required property var host   // wallpaper root (main.qml)
    required property var dbus   // DBusHelper
    readonly property var cfg: host.cfg

    property string lastSyncAt: ""
    property string lastSyncPath: ""
    property bool lastSyncOk: false
    property int _seq: 0
    property var _retry: null

    function lockScreenImagePath(wallpaperId) {
        return host.diskCacheDir + "/" + Wallhaven.lockScreenImageFileName(
            wallpaperId || host._pendingWallpaperId || host.currentWallpaperId,
        );
    }

    function noteResult(ok, path) {
        lastSyncOk = ok;
        lastSyncAt = new Date().toISOString();
        lastSyncPath = path;
        host.publishStatus();
    }

    function syncLockScreenImage(localPath, wallpaperId) {
        if (!cfg.SyncLockScreen || !localPath) {
            return;
        }
        // The service's flock serializes multi-monitor writers.
        // Do not gate on geometric "primary" — SyncLockScreen often lives only on
        // a non-origin screen, and skipping there left the lock image stale forever.
        var source = Wallhaven.urlToLocalPath(localPath);
        if (!source) {
            noteResult(false, "");
            return;
        }
        var dest = lockScreenImagePath(wallpaperId);
        var seq = ++lockSync._seq;
        var expectedId = String(wallpaperId || host._pendingWallpaperId || host.currentWallpaperId || "");
        dbus.syncLockScreen(source, dest, function(reply) {
            // A newer sync superseded this one (rapid next / overlapping callbacks).
            if (seq !== lockSync._seq) {
                return;
            }
            var text = String(reply || "").trim();
            noteResult(text === "ok", dest);
            if (lastSyncOk) {
                lockSync._retry = null;
                host.logDebug("Lock screen synced → " + dest);
                return;
            }
            host.logDebug("Lock screen sync failed → " + dest + " reply=" + text);
            host.showStatus(i18n("Lock screen sync failed."), "warn", false, { notify: false });
            // One deferred retry for the same wallpaper id only (settling cache file).
            var priorAttempts = 0;
            if (lockSync._retry && lockSync._retry.id === expectedId) {
                priorAttempts = lockSync._retry.attempts || 0;
            }
            if (priorAttempts < 1) {
                lockSync._retry = { id: expectedId, path: source, attempts: priorAttempts + 1 };
                retryTimer.restart();
            } else {
                lockSync._retry = null;
                // Last resort: repair from current mirror / any leftover file.
                lockSync.ensureLockScreenImage("sync-failed");
            }
        });
    }

    // Any monitor can repair a blank lock Image. Screens without SyncLockScreen
    // mirror whatever the syncing monitor last published (current.jpg / leftovers).
    // The service leaves a lock wallpaper the user chose themselves alone.
    function ensureLockScreenImage(reason) {
        host.logDebug("ensureLockScreenImage(" + reason + ")");
        dbus.ensureLockScreen(function(reply) {
            var text = String(reply || "").trim();
            if (text === "ok") {
                noteResult(true, host.diskCacheDir + "/" + Wallhaven.lockScreenCurrentFileName());
                host.logDebug("Lock screen ensure OK (" + reason + ")");
            } else {
                host.logDebug("Lock screen ensure not applied (" + reason + ") reply=" + text);
            }
        });
    }

    Timer {
        id: retryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            var retry = lockSync._retry;
            if (!retry || !retry.path || !lockSync.cfg.SyncLockScreen) {
                lockSync._retry = null;
                return;
            }
            if (retry.id && String(lockSync.host.currentWallpaperId || "") !== String(retry.id)
                    && String(lockSync.host._pendingWallpaperId || "") !== String(retry.id)) {
                lockSync._retry = null;
                return;
            }
            // Keep _retry so a second failure sees attempts and stops.
            lockSync.syncLockScreenImage(retry.path, retry.id);
        }
    }
}
