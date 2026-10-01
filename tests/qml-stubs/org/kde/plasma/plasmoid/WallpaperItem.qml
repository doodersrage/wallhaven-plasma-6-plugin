import QtQuick

// Test stand-in for Plasma's WallpaperItem (only plasmashell can create the
// real one). tests/qml-host.py provides "wallhavenTestConfig", a real
// QQmlPropertyMap filled from contents/config/main.xml.
//
// i18n lives here so every file loaded beneath the wallpaper resolves it the
// way KLocalizedContext provides it in Plasma.
Item {
    property var configuration: wallhavenTestConfig
    property bool loading: false
    property list<QtObject> contextualActions

    function i18n(text) {
        var out = String(text);
        for (var i = 1; i < arguments.length; i++) {
            out = out.split("%" + i).join(String(arguments[i]));
        }
        return out;
    }
}
