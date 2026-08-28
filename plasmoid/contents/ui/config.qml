import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_syncGroup: syncGroupField.text

    QtControls2.TextField {
        id: syncGroupField
        Kirigami.FormData.label: i18n("Default sync group:")
        placeholderText: i18n("Used when no monitor is selected")
    }

    QtControls2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: i18n("Match wallpaper Advanced → Sync group. With multiple monitors, the plasmoid lists each screen and routes next/prev to that group.")
    }

    function saveConfig() {}
}
