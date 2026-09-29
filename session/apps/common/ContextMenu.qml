// ContextMenu — kontextové menu (pravý klik) pre aplikácie LatteOS. Vkladá sa ako posledné dieťa
// položky cez celé okno; open(x, y, items) ho ukáže na mieste kurzora (súradnice okna).
// items: [{ glyph, label, hint?, danger?, enabled?, bold?, action: function }, { separator: true },   ← bold = predvolená voľba (ako Windows)
//         { colors: [{ key, color, label }], current, action: function(key) }  ← riadok farebných štítkov
//         { input: "text", label, action: function(text) }                       ← textové pole (premenovanie)
//         { glyph, label, sub: [ … ] }                                            ← vnorená ponuka (› ako vo Windows)
//         { label, checked: true|false, action }                                  ← voľba s bodkou (Zoradiť podľa)]
import QtQuick

Item {
    id: menu
    required property var theme
    property var items: []
    property string title: ""
    anchors.fill: parent
    visible: false
    z: 1000

    function open(x, y, list, heading) {
        items = list; title = heading || ""; subItems = [];
        visible = true;
        box.x = Math.max(6, Math.min(x, width - box.width - 6));
        box.y = Math.max(6, Math.min(y, height - box.implicitHeight - 6));
        box.forceActiveFocus();
    }
    // ponuka nad bodom (spodný okraj v bottomY), napr. nad ostrovom lišty ako Win+X nad tlačidlom Štart
    function openAbove(x, bottomY, list, heading) {
        open(x, 0, list, heading);
        box.y = Math.max(6, Math.min(bottomY - box.implicitHeight, height - box.implicitHeight - 6));
    }
    // vymení obsah na tom istom mieste (napr. „Premenovať…“ → textové pole)
    // (pri textovom poli si fokus vezme pole — kurzor je hneď v ňom a názov je označený)
    function replace(list, heading) { items = list; title = heading || ""; visible = true; if (!list.some(i => i.input !== undefined)) box.forceActiveFocus(); }
    function close() { visible = false; activeField = null; subItems = []; }
    property var subItems: []                  // otvorená vnorená ponuka
    property real subY: 0      // položky sa nahradia pri ďalšom open()
    property var activeField: null             // otvorené textové pole: klik mimo menu text uloží (ako vo Windows)

    MouseArea {    // klik mimo menu ho zavrie; rozpísaný názov sa uloží
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: { const f = menu.activeField; if (f) f.commit(); else menu.close(); }
    }

    Rectangle {
        id: box
        width: 272
        implicitHeight: col.implicitHeight + 12
        height: implicitHeight
        radius: 12
        color: menu.theme.surfaceVariant
        border { color: menu.theme.line; width: 1 }
        focus: true
        Keys.onEscapePressed: menu.close()

        // tieň (lacný: posunutý obdĺžnik, bez efektov — beží aj pri softvérovom kreslení)
        Rectangle { z: -1; x: 3; y: 5; width: parent.width; height: parent.height; radius: parent.radius; color: Qt.rgba(0, 0, 0, 0.28) }

        Column {
            id: col
            x: 6; y: 6; width: parent.width - 12
            spacing: 1

            Text {
                visible: menu.title !== ""
                width: parent.width; leftPadding: 10; topPadding: 4; bottomPadding: 6; elide: Text.ElideMiddle
                text: menu.title; color: menu.theme.fgDim
                font { family: menu.theme.fontUi; pixelSize: 11; weight: Font.Bold }
            }

            Repeater {
                model: menu.items
                Loader {
                    id: ld
                    required property var modelData
                    width: col.width
                    sourceComponent: modelData.separator ? sep : (modelData.colors ? swatches : (modelData.input !== undefined ? field : entry))
                    property var it: modelData
                }
            }
        }
    }

    // vnorená ponuka vedľa hlavnej (vľavo, ak by vpravo pretiekla)
    Rectangle {
        id: subBox
        visible: menu.subItems.length > 0
        width: 232
        height: subCol.implicitHeight + 12
        x: box.x + box.width + width - 4 > menu.width ? box.x - width + 4 : box.x + box.width - 4
        y: Math.max(6, Math.min(menu.subY, menu.height - height - 6))
        radius: 12
        color: menu.theme.surfaceVariant
        border { color: menu.theme.line; width: 1 }
        Rectangle { z: -1; x: 3; y: 5; width: parent.width; height: parent.height; radius: parent.radius; color: Qt.rgba(0, 0, 0, 0.28) }
        MouseArea { anchors.fill: parent }        // klik do ponuky ju nezavrie
        Column {
            id: subCol
            x: 6; y: 6; width: parent.width - 12
            spacing: 1
            Repeater {
                model: menu.subItems
                Loader {
                    required property var modelData
                    width: subCol.width
                    sourceComponent: modelData.separator ? sep : entry
                    property var it: Object.assign({ inSub: true }, modelData)
                }
            }
        }
    }

    Component {
        id: sep
        Item { height: 9; Rectangle { y: 4; x: 8; width: parent.width - 16; height: 1; color: menu.theme.line } }
    }
    Component {
        id: entry
        Rectangle {
            readonly property var it: parent.it
            readonly property bool on: it.enabled !== false
            height: 34; radius: 8
            color: em.containsMouse && on ? (it.danger ? Qt.rgba(menu.theme.error.r, menu.theme.error.g, menu.theme.error.b, 0.18) : menu.theme.hover) : "transparent"
            opacity: on ? 1 : 0.45
            Glyph { x: 10; anchors.verticalCenter: parent.verticalCenter; visible: parent.it.checked === undefined
                    name: parent.it.glyph || "point"; size: 16; color: parent.it.danger ? menu.theme.error : menu.theme.fg }
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; visible: parent.it.checked === true; text: "●"; color: menu.theme.primary
                   font { family: menu.theme.fontUi; pixelSize: 9 } }
            Text {
                x: 36; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 36 - hint.width - 12; elide: Text.ElideRight
                text: parent.it.label; color: parent.it.danger ? menu.theme.error : menu.theme.fg
                font { family: menu.theme.fontUi; pixelSize: 13; weight: parent.it.bold ? Font.Bold : Font.Medium }
            }
            Text {
                id: hint
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: parent.it.sub ? "›" : (parent.it.hint || ""); color: menu.theme.fgDim
                font { family: menu.theme.fontUi; pixelSize: 11 }
            }
            MouseArea {
                id: em; anchors.fill: parent; hoverEnabled: true
                // vnorená ponuka sa otvorí pod kurzorom (ako vo Windows); iná položka hlavnej ponuky ju zavrie
                onEntered: if (parent.it.sub) { const q = mapToItem(menu, 0, 0); menu.subY = q.y - 6; menu.subItems = parent.it.sub; }
                           else if (!parent.it.inSub) menu.subItems = []
                onClicked: {
                    if (!parent.on) return;
                    if (parent.it.sub) { const q = mapToItem(menu, 0, 0); menu.subY = q.y - 6; menu.subItems = parent.it.sub; return; }
                    const a = parent.it.action;
                    if (parent.it.keepOpen) Qt.callLater(a);       // mení obsah menu: až po dokončení kliku
                    else { menu.close(); if (a) a(); }
                }
            }
        }
    }
    Component {
        id: swatches
        Item {
            id: sw
            readonly property var it: parent.it
            height: 40
            Text {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                text: sw.it.label || "Farba"; color: menu.theme.fgDim
                font { family: menu.theme.fontUi; pixelSize: 12 }
            }
            Row {
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 5
                Repeater {
                    model: sw.it.colors
                    Rectangle {
                        required property var modelData
                        readonly property bool picked: sw.it.current === modelData.key
                        width: 20; height: 20; radius: 10
                        color: modelData.color || "transparent"
                        border { color: picked ? menu.theme.fg : (modelData.color ? Qt.darker(modelData.color, 1.3) : menu.theme.fgDim); width: picked ? 2 : 1 }
                        Glyph { anchors.centerIn: parent; visible: !parent.modelData.color; name: "x"; size: 12; color: menu.theme.fgDim }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: { const a = sw.it.action, k = parent.modelData.key; menu.close(); a(k); }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: field
        Rectangle {
            readonly property var it: parent.it
            height: 38; radius: 8; color: menu.theme.field
            border { color: menu.theme.primary; width: 1 }
            TextInput {
                id: ti
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter; clip: true
                text: parent.it.input; color: menu.theme.fg; selectionColor: menu.theme.primary
                font { family: menu.theme.fontUi; pixelSize: 13 }
                function commit() { const a = parent.it.action, t = text; menu.close(); if (t.trim() !== "" && t !== parent.it.input) a(t); }
                Component.onCompleted: {
                    menu.activeField = ti;
                    // názov bez prípony označený (ako vo Windows/Linuxe); celý, ak ide o priečinok alebo wholeName
                    Qt.callLater(() => { ti.forceActiveFocus(); const dot = ti.text.lastIndexOf("."); ti.select(0, dot > 0 && !ti.parent.it.wholeName ? dot : ti.text.length); });
                }
                // Enter nesmie prepadnúť do panela pod menu (inak by sa otvoril premenovaný priečinok)
                Keys.onReturnPressed: (ev) => { ev.accepted = true; commit(); }
                Keys.onEnterPressed: (ev) => { ev.accepted = true; commit(); }
                Keys.onEscapePressed: (ev) => { ev.accepted = true; menu.close(); }
            }
        }
    }
}
