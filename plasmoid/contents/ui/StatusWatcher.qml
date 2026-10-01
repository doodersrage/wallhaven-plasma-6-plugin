import QtQuick
import org.kde.plasma.workspace.dbus as PDBus

// Tells the plasmoid when the wallpaper published a new status, instead of
// re-reading it every second. Loaded through a Loader: SignalWatcher only
// exists from Plasma 6.4, so on 6.2/6.3 this file fails to load and main.qml
// keeps polling.
Item {
    id: watcher

    signal statusChanged(string cacheNamespace)

    // Whether wallhaven-dbus.py currently owns its bus name.
    readonly property bool serviceRegistered: serviceWatcher.registered

    PDBus.SignalWatcher {
        busType: PDBus.BusType.Session
        service: "org.robertsm.Wallhaven"
        path: "/Wallhaven"
        iface: "org.robertsm.Wallhaven"

        function dbusStatusChanged(cacheNamespace, payload) {
            watcher.statusChanged(String(cacheNamespace));
        }

        // Meant for the wallpaper. SignalWatcher logs a warning for every
        // signal that has no handler, hence the no-ops.
        function dbusControlChanged(payload) {
        }

        function dbusSyncAdvanced(group, payload) {
        }
    }

    PDBus.DBusServiceWatcher {
        id: serviceWatcher
        busType: PDBus.BusType.Session
        watchedService: "org.robertsm.Wallhaven"
    }
}
