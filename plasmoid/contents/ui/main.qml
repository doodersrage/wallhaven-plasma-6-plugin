import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string controlFile: StandardPaths.writableLocation(StandardPaths.CacheLocation)
        + "/wallhaven-control.json"

    function sendCommand(cmd) {
        var payload = JSON.stringify({
            cmd: cmd,
            ts: Date.now(),
            group: Plasmoid.configuration.syncGroup || "default",
        });
        var encoded = encodeURIComponent(payload);
        writeProcess.command = [
            "python3", "-c",
            "import sys, urllib.parse; open(sys.argv[1],'w',encoding='utf-8').write(urllib.parse.unquote(sys.argv[2]))",
            controlFile, encoded,
        ];
        writeProcess.start();
    }

    Process { id: writeProcess }

    preferredRepresentation: fullRepresentation

    fullRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        PlasmaCore.IconItem {
            source: "preferences-desktop-wallpaper"
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: width
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
            icon.name: "media-playback-pause"
            ToolTip.text: i18n("Toggle slideshow pause")
            onClicked: root.sendCommand("pause")
        }
        QtControls2.ToolButton {
            display: QtControls2.AbstractButton.IconOnly
            icon.name: "view-refresh"
            ToolTip.text: i18n("Reload wallpaper")
            onClicked: root.sendCommand("reload")
        }
    }
}
