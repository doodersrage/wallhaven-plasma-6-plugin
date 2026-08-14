import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as PDBus

PlasmoidItem {
    id: root

    readonly property string cacheDir: StandardPaths.writableLocation(StandardPaths.CacheLocation)
    readonly property string controlFile: cacheDir + "/wallhaven-control.json"
    readonly property string statusFile: cacheDir + "/wallhaven-status.json"

    property var statusData: ({
        id: "",
        thumbUrl: "",
        pageUrl: "",
        paused: false,
        slideshowActive: false,
        nextChangeMs: 0,
    })
    property int countdownMs: 0

    function sendCommand(cmd, query) {
        var group = Plasmoid.configuration.syncGroup || "default";
        var msg;
        if (query) {
            msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: "Search",
                signature: "ss",
                arguments: [query, group],
            });
        } else {
            msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: "CommandInGroup",
                signature: "ss",
                arguments: [cmd, group],
            });
        }
        PDBus.SessionBus.asyncCall(msg, function() {}, function(err) {
            console.warn("Wallhaven plasmoid D-Bus call failed:", err);
        });
    }

    function loadStatus() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + statusFile);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            if (xhr.status !== 0 && xhr.status !== 200) {
                return;
            }
            try {
                var parsed = JSON.parse(xhr.responseText);
                if (!parsed) {
                    return;
                }
                statusData = {
                    id: parsed.id || "",
                    thumbUrl: parsed.thumbUrl || "",
                    pageUrl: parsed.pageUrl || "",
                    paused: !!parsed.paused,
                    slideshowActive: !!parsed.slideshowActive,
                    nextChangeMs: Math.max(0, parseInt(parsed.nextChangeMs, 10) || 0),
                };
                countdownMs = statusData.nextChangeMs;
            } catch (e) {
            }
        };
        xhr.send();
    }

    function formatCountdown(ms) {
        if (ms <= 0 || statusData.paused || !statusData.slideshowActive) {
            return statusData.paused ? i18n("Paused") : i18n("Manual");
        }
        var totalSec = Math.ceil(ms / 1000);
        var min = Math.floor(totalSec / 60);
        var sec = totalSec % 60;
        return min + ":" + (sec < 10 ? "0" : "") + sec;
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.loadStatus();
            if (countdownMs > 0 && !statusData.paused) {
                countdownMs = Math.max(0, countdownMs - 1000);
            }
        }
    }

    Component.onCompleted: loadStatus()

    preferredRepresentation: fullRepresentation

    fullRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        plasmoidMenu.open();
                    }
                }
            }

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: statusData.thumbUrl !== ""
                source: statusData.thumbUrl
            }

            PlasmaCore.IconItem {
                anchors.centerIn: parent
                visible: statusData.thumbUrl === ""
                source: "preferences-desktop-wallpaper"
                width: Kirigami.Units.iconSizes.medium
                height: width
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                radius: 3
                color: "#000000"
                opacity: 0.65
                visible: statusData.id !== ""
                width: idLabel.implicitWidth + 6
                height: idLabel.implicitHeight + 2

                QtControls2.Label {
                    id: idLabel
                    anchors.centerIn: parent
                    color: "#ffffff"
                    font.pointSize: 7
                    text: statusData.id ? ("#" + statusData.id) : ""
                }
            }
        }

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            QtControls2.Label {
                font.pointSize: 8
                opacity: 0.8
                text: root.formatCountdown(root.countdownMs)
            }

            QtControls2.Label {
                font.pointSize: 7
                opacity: 0.65
                text: statusData.paused ? i18n("Slideshow paused") : i18n("Wallhaven")
            }
        }

        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "go-previous"
            ToolTip.text: i18n("Previous wallpaper")
            onClicked: root.sendCommand("prev")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "go-next"
            ToolTip.text: i18n("Next wallpaper")
            onClicked: root.sendCommand("next")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: statusData.paused ? "media-playback-start" : "media-playback-pause"
            ToolTip.text: statusData.paused ? i18n("Resume slideshow") : i18n("Pause slideshow")
            onClicked: root.sendCommand(statusData.paused ? "resume" : "pause")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "view-refresh"
            ToolTip.text: i18n("Reload wallpaper")
            onClicked: root.sendCommand("reload")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "open-menu-symbolic"
            ToolTip.text: i18n("More actions")
            onClicked: plasmoidMenu.open()
        }
    }

    QtControls2.Menu {
        id: plasmoidMenu
        QtControls2.MenuItem {
            text: i18n("Open in browser")
            enabled: statusData.pageUrl !== "" || statusData.id !== ""
            onTriggered: {
                if (statusData.pageUrl) {
                    Qt.openUrlExternally(statusData.pageUrl);
                } else if (statusData.id) {
                    Qt.openUrlExternally("https://wallhaven.cc/w/" + statusData.id);
                } else {
                    root.sendCommand("open");
                }
            }
        }
        QtControls2.MenuItem {
            text: i18n("Copy tags")
            enabled: statusData.id !== ""
            onTriggered: root.sendCommand("copytags")
        }
        QtControls2.MenuItem {
            text: i18n("Block wallpaper")
            enabled: statusData.id !== ""
            onTriggered: root.sendCommand("block")
        }
    }
}
