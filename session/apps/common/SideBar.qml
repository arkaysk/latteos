// SideBar — bočná lišta aplikácií LatteOS (návrh V2): od vrchu až dole, rozkladacie sekcie.
// Slúži ako menu (Nastavenia), zoznam diskov a obľúbených priečinkov (Súbory) aj rýchly prístup.
// model: [{ title, items: [{ key, glyph, label, sub?, usage? (0–1), dim?, tag? (farba štítka) }] }]
import QtQuick

Rectangle {
    id: bar
    required property var theme
    property var model: []
    property string current: ""
    property string heading: ""
    property string headingGlyph: "coffee"
    signal activated(var item)
    signal contextRequested(var item, real x, real y)   // pravý klik (súradnice okna)

    property var collapsed: ({})
    width: 250
    color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.18 : 0.04)

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 16
        clip: true
        Column {
            id: col
            width: parent.width
            topPadding: 14
            spacing: 2

            Row {
                x: 16; spacing: 10; height: 40
                Glyph { name: bar.headingGlyph; size: 22; color: bar.theme.primary; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: bar.heading; color: bar.theme.fg; anchors.verticalCenter: parent.verticalCenter
                    font { family: bar.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold }
                }
            }

            Repeater {
                model: bar.model
                Column {
                    id: sec
                    required property var modelData
                    width: col.width
                    readonly property bool open: !bar.collapsed[modelData.title]

                    Item {
                        width: parent.width; height: 30
                        Text {
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            text: sec.modelData.title.toUpperCase(); color: bar.theme.fgDim
                            font { family: bar.theme.fontUi; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.8 }
                        }
                        Glyph {
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            name: sec.open ? "chevron-up" : "chevron-right"; size: 14; color: bar.theme.fgDim
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { const c = Object.assign({}, bar.collapsed); c[sec.modelData.title] = sec.open; bar.collapsed = c; }
                        }
                    }

                    Repeater {
                        model: sec.open ? sec.modelData.items : []
                        Rectangle {
                            id: row
                            required property var modelData
                            x: 8; width: col.width - 16; height: modelData.sub ? 48 : 38; radius: 10
                            readonly property bool active: bar.current === modelData.key
                            color: active ? Qt.rgba(bar.theme.primary.r, bar.theme.primary.g, bar.theme.primary.b, 0.16)
                                          : (ma.containsMouse ? bar.theme.hover : "transparent")
                            opacity: modelData.dim ? 0.5 : 1

                            Glyph {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                name: row.modelData.tag ? "folder-filled" : (row.modelData.glyph || "folder"); size: 18
                                color: row.modelData.tag || (row.active ? bar.theme.primary : bar.theme.fg)
                            }
                            Column {
                                x: 42; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: row.modelData.label; color: bar.theme.fg
                                    font { family: bar.theme.fontUi; pixelSize: 13; weight: row.active ? Font.Bold : Font.Medium }
                                }
                                Text {
                                    visible: !!row.modelData.sub; width: parent.width; elide: Text.ElideRight
                                    text: row.modelData.sub || ""; color: bar.theme.fgDim
                                    font { family: bar.theme.fontUi; pixelSize: 11 }
                                }
                                Rectangle {   // využitie disku
                                    visible: row.modelData.usage !== undefined
                                    width: parent.width; height: 3; radius: 2; color: bar.theme.line
                                    Rectangle {
                                        width: parent.width * Math.min(1, row.modelData.usage || 0); height: parent.height; radius: 2
                                        color: (row.modelData.usage || 0) > 0.9 ? bar.theme.error : bar.theme.primary
                                    }
                                }
                            }
                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => {
                                    if (m.button === Qt.RightButton) { const p = mapToItem(null, m.x, m.y); bar.contextRequested(row.modelData, p.x, p.y); }
                                    else bar.activated(row.modelData);
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                }
            }
        }
    }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: bar.theme.line }
}
