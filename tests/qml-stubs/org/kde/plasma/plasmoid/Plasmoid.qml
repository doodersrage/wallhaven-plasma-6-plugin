pragma Singleton
import QtQuick

// Test stand-in for the Plasmoid attached object.
QtObject {
    property QtObject configuration: QtObject {
        property string syncGroup: "default"
    }
    // The settings dialog reaches the running wallpaper through this.
    property var wallpaperGraphicsObject: null
    property string icon: ""
    property string title: "Wallhaven Control"
    property int status: 0
    property bool busy: false
    property list<QtObject> contextualActions
    property int formFactor: 0
    property int location: 0
}
