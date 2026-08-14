import QtQuick
import QtQuick.Controls as QtControls2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_syncGroup: syncGroupField.text

    QtControls2.TextField {
        id: syncGroupField
        Kirigami.FormData.label: i18n("Sync group:")
        placeholderText: i18n("Must match wallpaper Advanced → Sync group")
    }

    function saveConfig() {}
}
