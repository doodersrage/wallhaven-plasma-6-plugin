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
        localThumbUrl: "",
        pageUrl: "",
        tags: "",
        paused: false,
        slideshowActive: false,
        nextChangeMs: 0,
    })
    property bool dbusOffline: false
    property int countdownMs: 0
    property real swipeOffset: 0
    property bool swiping: false
    readonly property string historyFile: cacheDir + "/wallhaven-history.json"
    property var historyEntries: []

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

    function sendHistoryCommand(id) {
        var group = Plasmoid.configuration.syncGroup || "default";
        var msg = new PDBus.dbusMessage({
            service: "org.robertsm.Wallhaven",
            path: "/Wallhaven",
            iface: "org.robertsm.Wallhaven",
            member: "CommandWithQuery",
            signature: "sss",
            arguments: ["history", id, group],
        });
        PDBus.SessionBus.asyncCall(msg, function() {}, function(err) {
            console.warn("Wallhaven plasmoid D-Bus call failed:", err);
        });
    }

    function loadHistory() {
        var msg = new PDBus.dbusMessage({
            service: "org.robertsm.Wallhaven",
            path: "/Wallhaven",
            iface: "org.robertsm.Wallhaven",
            member: "ReadTextFile",
            signature: "s",
            arguments: [historyFile],
        });
        PDBus.SessionBus.asyncCall(msg, function(text) {
            if (!text) {
                historyEntries = [];
                return;
            }
            try {
                var parsed = JSON.parse(text);
                historyEntries = (parsed || []).slice().reverse();
            } catch (e) {
                historyEntries = [];
            }
        }, function() {});
    }

    function loadStatus() {
        var msg = new PDBus.dbusMessage({
            service: "org.robertsm.Wallhaven",
            path: "/Wallhaven",
            iface: "org.robertsm.Wallhaven",
            member: "ReadTextFile",
            signature: "s",
            arguments: [statusFile],
        });
        PDBus.SessionBus.asyncCall(msg, function(text) {
            root.dbusOffline = false;
            if (!text) {
                return;
            }
            try {
                var parsed = JSON.parse(text);
                if (!parsed) {
                    return;
                }
                statusData = {
                    id: parsed.id || "",
                    thumbUrl: parsed.thumbUrl || "",
                    localThumbUrl: parsed.localThumbUrl || "",
                    pageUrl: parsed.pageUrl || "",
                    tags: parsed.tags || "",
                    paused: !!parsed.paused,
                    slideshowActive: !!parsed.slideshowActive,
                    nextChangeMs: Math.max(0, parseInt(parsed.nextChangeMs, 10) || 0),
                };
                countdownMs = statusData.nextChangeMs;
            } catch (e) {
            }
        }, function(err) {
            root.dbusOffline = true;
            console.warn("Wallhaven plasmoid status read failed:", err);
        });
    }

    function plasmoidThumbSource() {
        if (statusData.localThumbUrl) {
            return statusData.localThumbUrl;
        }
        return statusData.thumbUrl;
    }

    function openCurrentPage() {
        if (statusData.pageUrl) {
            Qt.openUrlExternally(statusData.pageUrl);
        } else if (statusData.id) {
            Qt.openUrlExternally("https://wallhaven.cc/w/" + statusData.id);
        } else {
            root.sendCommand("open");
        }
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

    Timer {
        interval: 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.loadHistory()
    }

    Component.onCompleted: {
        loadStatus();
        loadHistory();
    }

    preferredRepresentation: fullRepresentation

    fullRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Item {
            id: thumbFrame
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
            clip: false

            Item {
                id: swipeContent
                anchors.fill: parent
                x: root.swipeOffset
                rotation: root.swipeOffset / 8

                Behavior on x {
                    enabled: !root.swiping
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                }
                Behavior on rotation {
                    enabled: !root.swiping
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                }

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: root.plasmoidThumbSource() !== ""
                    source: root.plasmoidThumbSource()
                }

                PlasmaCore.IconItem {
                    anchors.centerIn: parent
                    visible: root.plasmoidThumbSource() === ""
                    source: root.dbusOffline ? "network-disconnect" : "preferences-desktop-wallpaper"
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.swipeOffset > 0 ? "#2ecc71" : "#e74c3c"
                    opacity: Math.min(0.55, Math.abs(root.swipeOffset) / 90)
                }

                PlasmaCore.IconItem {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    opacity: Math.min(1, Math.abs(root.swipeOffset) / 40)
                    source: root.swipeOffset > 0 ? "emblem-favorite" : "emblem-remove"
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

            MouseArea {
                id: swipeArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                property real pressX: 0
                property bool dragged: false

                ToolTip.visible: containsMouse && !root.swiping
                ToolTip.text: i18n("Click to open · drag right to like, left to mute tags")

                onPressed: function(mouse) {
                    pressX = mouse.x;
                    dragged = false;
                    root.swiping = true;
                }
                onPositionChanged: function(mouse) {
                    if (!pressed || !(mouse.buttons & Qt.LeftButton)) {
                        return;
                    }
                    var delta = mouse.x - pressX;
                    if (Math.abs(delta) > 6) {
                        dragged = true;
                    }
                    root.swipeOffset = Math.max(-70, Math.min(70, delta));
                }
                onReleased: function(mouse) {
                    root.swiping = false;
                    var offset = root.swipeOffset;
                    root.swipeOffset = 0;
                    if (mouse.button === Qt.RightButton) {
                        plasmoidMenu.open();
                        return;
                    }
                    if (dragged && Math.abs(offset) > 40 && !root.dbusOffline) {
                        root.sendCommand(offset > 0 ? "like" : "dislike");
                        dragged = false;
                        return;
                    }
                    dragged = false;
                    if (mouse.button === Qt.LeftButton) {
                        root.openCurrentPage();
                    }
                }
                onCanceled: {
                    root.swiping = false;
                    root.swipeOffset = 0;
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
                text: root.dbusOffline ? i18n("D-Bus offline") : (statusData.paused ? i18n("Slideshow paused") : i18n("Wallhaven"))
            }
        }

        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "go-previous"
            ToolTip.text: i18n("Previous wallpaper")
            enabled: !root.dbusOffline
            onClicked: root.sendCommand("prev")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "go-next"
            ToolTip.text: i18n("Next wallpaper")
            enabled: !root.dbusOffline
            onClicked: root.sendCommand("next")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: statusData.paused ? "media-playback-start" : "media-playback-pause"
            ToolTip.text: statusData.paused ? i18n("Resume slideshow") : i18n("Pause slideshow")
            enabled: !root.dbusOffline
            onClicked: root.sendCommand(statusData.paused ? "resume" : "pause")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "view-refresh"
            ToolTip.text: i18n("Reload wallpaper")
            enabled: !root.dbusOffline
            onClicked: root.sendCommand("reload")
        }
        QtControls2.ToolButton {
            id: historyButton
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "view-history"
            ToolTip.text: i18n("Recent wallpapers")
            enabled: !root.dbusOffline && root.historyEntries.length > 0
            onClicked: {
                root.loadHistory();
                historyPopup.open();
            }
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "open-menu-symbolic"
            ToolTip.text: i18n("More actions")
            onClicked: plasmoidMenu.open()
        }
    }

    QtControls2.Popup {
        id: historyPopup
        x: Math.max(0, historyButton.x - width + historyButton.width)
        y: historyButton.height
        width: Math.min(420, Math.max(220, historyRow.implicitWidth + 24))
        height: 96
        padding: 8
        modal: false
        focus: true
        closePolicy: QtControls2.Popup.CloseOnEscape | QtControls2.Popup.CloseOnPressOutsideParent

        QtControls2.ScrollView {
            anchors.fill: parent
            contentHeight: height
            QtControls2.ScrollBar.vertical.policy: QtControls2.ScrollBar.AlwaysOff

            RowLayout {
                id: historyRow
                spacing: Kirigami.Units.smallSpacing
                height: parent.height

                Repeater {
                    model: root.historyEntries
                    delegate: QtControls2.AbstractButton {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        ToolTip.visible: hovered
                        ToolTip.text: i18n("Show wallpaper #%1", modelData.id)
                        onClicked: {
                            root.sendHistoryCommand(String(modelData.id));
                            historyPopup.close();
                        }

                        contentItem: Image {
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            source: modelData.thumbUrl || ""
                        }
                    }
                }

                QtControls2.Label {
                    visible: root.historyEntries.length === 0
                    text: i18n("No history yet.")
                    opacity: 0.7
                }
            }
        }
    }

    QtControls2.Menu {
        id: plasmoidMenu
        QtControls2.MenuItem {
            text: i18n("Open wallpaper page")
            enabled: statusData.pageUrl !== "" || statusData.id !== ""
            onTriggered: root.openCurrentPage()
        }
        QtControls2.MenuItem {
            text: i18n("Similar wallpapers")
            enabled: statusData.id !== "" && !root.dbusOffline
            onTriggered: root.sendCommand("similar")
        }
        QtControls2.MenuSeparator {}
        QtControls2.MenuItem {
            icon.name: "emblem-favorite"
            text: i18n("Like (boost these tags)")
            enabled: statusData.tags !== "" && !root.dbusOffline
            onTriggered: root.sendCommand("like")
        }
        QtControls2.MenuItem {
            icon.name: "emblem-remove"
            text: i18n("Dislike (mute these tags)")
            enabled: statusData.tags !== "" && !root.dbusOffline
            onTriggered: root.sendCommand("dislike")
        }
        QtControls2.MenuSeparator {}
        QtControls2.MenuItem {
            text: i18n("Copy tags")
            enabled: statusData.id !== "" && !root.dbusOffline
            onTriggered: root.sendCommand("copytags")
        }
        QtControls2.MenuItem {
            text: i18n("Block wallpaper")
            enabled: statusData.id !== "" && !root.dbusOffline
            onTriggered: root.sendCommand("block")
        }
        QtControls2.MenuSeparator {
            visible: root.dbusOffline
        }
        QtControls2.MenuItem {
            visible: root.dbusOffline
            text: i18n("Start D-Bus service")
            onTriggered: Qt.openUrlExternally("https://github.com/doodersrage/wallhaven-plasma-6-plugin#quick-start")
        }
    }
}
