import QtQuick
import org.kde.plasma.workspace.dbus as PDBus
import "../code/wallhaven.js" as Wallhaven

// D-Bus signal subscriptions that replace file/IPC polling. main.qml loads this
// through a Loader: SignalWatcher only exists from Plasma 6.4 (the rest of the
// D-Bus QML module from 6.2), so on 6.2/6.3 this file fails to load and the
// wallpaper keeps its timers at the old polling cadence instead.
Item {
    id: signals

    // wallhaven-control.json was rewritten (payload = its JSON text).
    signal controlChanged(string payload)
    // wallhaven-sync-<group>.json was rewritten.
    signal syncAdvanced(string group, string payload)
    signal screenLockChanged(bool locked)

    // Whether wallhaven-dbus.py currently owns its bus name.
    readonly property bool serviceRegistered: serviceWatcher.registered

    PDBus.SignalWatcher {
        busType: PDBus.BusType.Session
        service: "org.robertsm.Wallhaven"
        path: "/Wallhaven"
        iface: "org.robertsm.Wallhaven"

        function dbusControlChanged(payload) {
            signals.controlChanged(Wallhaven.dbusReplyAsString(payload));
        }

        function dbusSyncAdvanced(group, payload) {
            signals.syncAdvanced(Wallhaven.dbusReplyAsString(group), Wallhaven.dbusReplyAsString(payload));
        }

        // Only the plasmoid follows status snapshots. SignalWatcher logs a
        // warning for every signal that has no handler, hence the no-op.
        function dbusStatusChanged(cacheNamespace, payload) {
        }
    }

    PDBus.DBusServiceWatcher {
        id: serviceWatcher
        busType: PDBus.BusType.Session
        watchedService: "org.robertsm.Wallhaven"
    }

    // kscreenlocker exports the interface on both paths and may emit on either
    // (or both); main.qml only reacts to actual state changes.
    PDBus.SignalWatcher {
        busType: PDBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/org/freedesktop/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"

        function dbusActiveChanged(active) {
            signals.screenLockChanged(Wallhaven.dbusReplyIsTrue(active));
        }
    }

    PDBus.SignalWatcher {
        busType: PDBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"

        function dbusActiveChanged(active) {
            signals.screenLockChanged(Wallhaven.dbusReplyIsTrue(active));
        }
    }
}
