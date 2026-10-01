import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Where the Wallhaven API key lives. With KWallet in use the key is held only
// in memory (sessionKey): it is read over D-Bus from the wallet at startup and
// never written back into the plain wallpaper config. A key typed into
// settings and not saved to the wallet stays in the config and takes priority.
QtObject {
    id: apiKeys

    required property var host   // wallpaper root (main.qml)
    required property var dbus   // DBusHelper
    readonly property var cfg: host.cfg

    property string sessionKey: ""
    // unknown | disabled | loaded | missing | failed
    property string status: "unknown"
    readonly property string effectiveKey: Wallhaven.effectiveApiKey(cfg ? cfg.ApiKey : "", sessionKey)

    function load() {
        if (!cfg.UseKWalletForApiKey) {
            sessionKey = "";
            status = "disabled";
            return;
        }
        dbus.getApiKey(function(reply) {
            if (!host.configuration || !cfg.UseKWalletForApiKey) {
                return;
            }
            var resolved = Wallhaven.resolveWalletApiKey(cfg.ApiKey, reply);
            sessionKey = resolved.sessionKey;
            status = resolved.status;
            if (resolved.scrubConfig) {
                // Builds before 3.7 copied the wallet key into the plain config.
                host.configuration.ApiKey = "";
                host.scheduleConfigWrite();
                host.logDebug("Removed the plain-text API key copy from wallpaper settings (kept in KWallet)");
            }
            host.publishStatus();
        });
    }

    // callback(ok) is optional. Saves `key`, or the key currently in use.
    function save(key, callback) {
        var clean = Wallhaven.sanitizeApiKey(key) || effectiveKey;
        if (!clean) {
            host.showStatus(i18n("Enter an API key first."), "warn");
            if (callback)
                callback(false);
            return;
        }
        dbus.setApiKey(clean, function(ok) {
            if (!ok) {
                status = "failed";
                host.showStatus(i18n("Could not save the API key to KWallet."), "error");
                if (callback)
                    callback(false);
                return;
            }
            // Session key first, so dropping the config copy does not look like
            // the key going away (which would reset the slideshow).
            sessionKey = clean;
            status = "loaded";
            if (host.configuration) {
                host.configuration.UseKWalletForApiKey = true;
                host.configuration.ApiKey = "";
                host.scheduleConfigWrite();
            }
            host.showStatus(i18n("API key saved to KWallet (folder org.robertsm.wallhaven)."), "info");
            host.publishStatus();
            if (callback)
                callback(true);
        });
    }

    function clear(keepWallet) {
        if (!host.configuration) {
            return;
        }
        host.configuration.ApiKey = "";
        host.configuration.ApiKeyValid = false;
        if (!keepWallet) {
            host.configuration.UseKWalletForApiKey = false;
            sessionKey = "";
            status = "disabled";
        }
        host.scheduleConfigWrite();
        host.showStatus(i18n("API key cleared."), "info");
        host.publishStatus();
    }
}
