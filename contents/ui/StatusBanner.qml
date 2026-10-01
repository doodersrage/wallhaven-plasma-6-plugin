import QtQuick
import QtQuick.Controls as QQC2

// Transient status line across the top of the desktop.
Rectangle {
    id: banner

    property string message: ""
    property string type: "info"   // info | warn | error
    property bool shown: false

    z: 100
    anchors.top: parent.top
    anchors.topMargin: 16
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    height: shown ? statusLabel.implicitHeight + 16 : 0
    visible: shown
    radius: 8
    color: type === "error" ? "#cc1e1e"
         : type === "warn" ? "#785014"
         : "#1e3c64"
    opacity: 0.9

    QQC2.Label {
        id: statusLabel
        anchors.centerIn: parent
        width: parent.width - 32
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: "white"
        text: banner.message
    }
}
