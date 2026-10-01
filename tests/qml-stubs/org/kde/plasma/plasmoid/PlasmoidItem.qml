import QtQuick

// Test stand-in for Plasma's PlasmoidItem.
Item {
    property Component fullRepresentation
    property Component compactRepresentation
    property var preferredRepresentation
    property bool expanded: false
    property real switchWidth: 0
    property real switchHeight: 0
    property string toolTipMainText
    property string toolTipSubText
    property bool hideOnWindowDeactivate: true
    property bool activationTogglesExpanded: true

    function i18n(text) {
        var out = String(text);
        for (var i = 1; i < arguments.length; i++) {
            out = out.split("%" + i).join(String(arguments[i]));
        }
        return out;
    }
}
