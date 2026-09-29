// IconButton — tlačidlo s ikonou pre hlavičky a panely aplikácií LatteOS.
import QtQuick

Rectangle {
    id: ib
    required property var theme
    property string glyph: "x"
    property bool enabledState: true
    property bool checked: false
    property string tip: ""
    signal clicked()
    width: 34; height: 34; radius: 9
    color: checked ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18)
                   : (ibm.containsMouse && enabledState ? theme.hover : "transparent")
    opacity: enabledState ? 1 : 0.35
    Glyph { anchors.centerIn: parent; name: ib.glyph; size: 18; color: ib.checked ? ib.theme.primary : ib.theme.fg }
    MouseArea { id: ibm; anchors.fill: parent; hoverEnabled: true; enabled: ib.enabledState; onClicked: ib.clicked() }
}
