import QtQuick
import QtQuick.Controls as QQC2

// Modal-style overlay with the full wallpaper details (Wallpaper Info action).
Rectangle {
    id: sheet

    property bool open: false
    property string detailsText: ""
    signal closeRequested()

    z: 120
    anchors.fill: parent
    color: "#99000000"
    visible: open
    enabled: visible

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.closeRequested()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 480)
        height: Math.min(detailsLabel.implicitHeight + 72, parent.height - 48)
        radius: 10
        color: "#e6101014"

        MouseArea {
            anchors.fill: parent
            onClicked: { /* keep open */ }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            QQC2.Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "white"
                font.bold: true
                text: i18n("Wallpaper details")
            }

            QQC2.ScrollView {
                width: parent.width
                height: parent.height - 56
                clip: true
                QQC2.Label {
                    id: detailsLabel
                    width: sheet.width - 80
                    wrapMode: Text.WordWrap
                    color: "#f0f0f0"
                    text: sheet.detailsText || i18n("No details yet.")
                }
            }

            QQC2.Button {
                text: i18n("Close")
                onClicked: sheet.closeRequested()
            }
        }
    }
}
