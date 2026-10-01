import QtQuick
import QtQuick.Controls as QQC2

// Wallpaper credit (id, resolution, tags) in a corner; click for details.
Rectangle {
    id: banner

    required property var cfg
    property string attributionText: ""
    signal clicked()

    readonly property bool attributionVisible: cfg.ShowAttribution && attributionText !== ""
    readonly property string corner: cfg.AttributionCorner || "bottom-left"
    readonly property bool cornerCentered: corner === "top-center" || corner === "bottom-center"

    z: 100
    radius: 8
    color: "#000000"
    opacity: 0.65
    visible: attributionVisible

    width: Math.min(Math.max(attributionLabel.implicitWidth + 32, 120), parent.width - 32)
    height: attributionVisible ? attributionLabel.implicitHeight + 16 : 0

    anchors.left: !cornerCentered && corner.indexOf("left") >= 0 ? parent.left : undefined
    anchors.right: corner.indexOf("right") >= 0 ? parent.right : undefined
    anchors.top: corner.indexOf("top") >= 0 ? parent.top : undefined
    anchors.bottom: corner.indexOf("bottom") >= 0 ? parent.bottom : undefined
    anchors.horizontalCenter: cornerCentered ? parent.horizontalCenter : undefined
    anchors.margins: 16

    onAttributionVisibleChanged: {
        if (attributionVisible && cfg.AttributionAutoHideSec > 0) {
            visible = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Math.max(1, banner.cfg.AttributionAutoHideSec) * 1000
        repeat: false
        onTriggered: banner.visible = false
    }

    QQC2.Label {
        id: attributionLabel
        anchors.centerIn: parent
        width: Math.min(banner.parent.width - 64, 420)
        wrapMode: Text.WordWrap
        color: "#ffffff"
        font.pointSize: Math.max(7, Math.round(9 * (banner.cfg.AttributionFontScale || 100) / 100))
        text: banner.attributionText
    }

    MouseArea {
        anchors.fill: parent
        enabled: banner.attributionVisible
        onClicked: banner.clicked()
    }
}
