// CardStack — vrstvené karty oblastí (old/main_setting_v2.md §6–9, stará verzia latte_settings/app.py AreaCard):
// Softvér · Dáta · Hardvér · Účet · Prostredie · Systém. Otvorená karta má výšku podľa svojich stránok (ako Gtk.Revealer
// v starej verzii) a iba keď sa nezmestí, posúva sa zoznam v nej; hlavné karty sa nikdy neposúvajú (§7).
// Ostatné sú zmenšené „chrbty“ s názvom, súhrnom a stavom. Klik na chrbát otvorí oblasť, ďalší klik ju zbalí.
// Pohyb je krátky a pokojný (200 ms, aj pri softvérovom kreslení; vypne ho iba „bez animácií“): karta sa rozbalí,
// stránky sa odkryjú spolu s ňou a zvýraznenie aktívnej stránky sa presunie, neskáče.
// Klávesnica: ↑/↓ stránky, PgUp/PgDn alebo Ctrl+↑/↓ oblasti, Enter/Medzera rozbalí/zbalí, Home = Domov.
// Stav nikdy nenesie iba farba: symbol ● hotové · ◐ časť · ○ plán + text (§55).
// areas: [{ key, title, glyph, summary, pages: [{ key, label, glyph, status: "ready"|"partial"|"planned" }] }]
import QtQuick

Rectangle {
    id: stack
    required property var theme
    property var areas: []
    property string openArea: areas.length ? areas[0].key : ""
    property string current: ""          // kľúč stránky
    property string heading: "Nastavenia"
    property string headingGlyph: "settings"
    property bool homeActive: current === "domov"
    property int animMs: 200
    signal activated(string area, string page)
    signal homeRequested()
    signal contextRequested(string area, string page, string label, real x, real y)   // pravý klik na stránku

    readonly property int spineH: 50
    readonly property int overlap: 8
    readonly property int rowH: 36

    width: 262
    // sklo (GPU): polopriehľadný panel, Hyprland pod ním rozmaže tapetu; bez GPU plné pozadie
    color: theme.glass ? Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, theme.mode === "dark" ? 0.55 : 0.62)
                       : Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.18 : 0.04)
    activeFocusOnTab: true

    function statusMark(s) { return s === "ready" ? "●" : (s === "partial" ? "◐" : "○"); }
    function statusText(s) { return s === "ready" ? "hotové" : (s === "partial" ? "čiastočne" : "plánované"); }
    function openAreaObj() { return areas.find(a => a.key === openArea); }
    function firstPage(a) { return (a.pages || []).find(p => p.status !== "planned") || (a.pages || [])[0]; }
    function openAt(i) {
        if (i < 0 || i >= areas.length) return;
        const a = areas[i];
        openArea = a.key;
        const p = firstPage(a);
        if (p) activated(a.key, p.key);
    }
    function toggle(a) {
        if (openArea === a.key) { openArea = ""; return; }                 // zbaliť (obsah vpravo ostane)
        openArea = a.key;
        if (!(a.pages || []).some(p => p.key === current)) { const p = firstPage(a); if (p) activated(a.key, p.key); }
    }
    function stepPage(d) {
        const a = openAreaObj(); if (!a) { openAt(0); return; }
        const ps = a.pages || [];
        let i = ps.findIndex(p => p.key === current);
        i = i < 0 ? (d > 0 ? 0 : ps.length - 1) : i + d;
        if (i >= 0 && i < ps.length) { activated(a.key, ps[i].key); return; }
        const ai = areas.findIndex(x => x.key === a.key) + d;             // na konci oblasti prejde do ďalšej
        if (ai < 0 || ai >= areas.length) return;
        const na = areas[ai], nps = na.pages || [];
        if (!nps.length) return;
        openArea = na.key;
        activated(na.key, (d > 0 ? nps[0] : nps[nps.length - 1]).key);
    }
    Keys.onPressed: (ev) => {
        const ctrl = ev.modifiers & Qt.ControlModifier, ai = areas.findIndex(a => a.key === openArea);
        if ((ev.key === Qt.Key_Down && ctrl) || ev.key === Qt.Key_PageDown) openAt(Math.min(areas.length - 1, ai + 1));
        else if ((ev.key === Qt.Key_Up && ctrl) || ev.key === Qt.Key_PageUp) openAt(Math.max(0, ai - 1));
        else if (ev.key === Qt.Key_Down) stepPage(1);
        else if (ev.key === Qt.Key_Up) stepPage(-1);
        else if (ev.key === Qt.Key_Home) homeRequested();
        else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) && ai >= 0) toggle(areas[ai]);
        else { ev.accepted = false; return; }
        ev.accepted = true;
    }

    Column {
        id: top
        x: 0; y: 14; width: parent.width
        spacing: 6
        Row {
            x: 16; spacing: 10; height: 40
            Glyph { name: stack.headingGlyph; size: 22; color: stack.theme.primary; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: stack.heading; color: stack.theme.fg; anchors.verticalCenter: parent.verticalCenter
                font { family: stack.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold }
            }
        }
        Rectangle {   // Domov = stavový prehľad, nie ďalšia kategória (§5)
            x: 10; width: parent.width - 20; height: 40; radius: 10
            color: stack.homeActive ? Qt.rgba(stack.theme.primary.r, stack.theme.primary.g, stack.theme.primary.b, 0.16)
                                    : (hm.containsMouse ? stack.theme.hover : "transparent")
            Behavior on color { ColorAnimation { duration: stack.animMs * 0.6 } }
            Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "home"; size: 18; color: stack.homeActive ? stack.theme.primary : stack.theme.fg }
            Text {
                x: 42; anchors.verticalCenter: parent.verticalCenter; text: "Domov · stav systému"; color: stack.theme.fg
                font { family: stack.theme.fontUi; pixelSize: 13; weight: stack.homeActive ? Font.Bold : Font.Medium }
            }
            MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; onClicked: { stack.forceActiveFocus(); stack.homeRequested(); } }
        }
    }

    // karty
    Item {
        id: deck
        anchors { left: parent.left; right: parent.right; top: top.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 12 }
        readonly property int openIndex: stack.areas.findIndex(a => a.key === stack.openArea)
        readonly property real step: stack.spineH - stack.overlap
        // najväčšia výška otvorenej karty: zvyšok po chrbtoch všetkých ostatných (tie sa neposúvajú)
        readonly property real maxOpen: Math.max(stack.spineH + stack.rowH * 2, height - (stack.areas.length - 1) * step)

        // karty sa skladajú pod seba s prekrytím; výšky sa animujú, takže nasledujúce karty sa posúvajú spolu s nimi
        Column {
        width: parent.width
        spacing: -stack.overlap
        Repeater {
            id: cards
            model: stack.areas
            Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property bool open: stack.openArea === modelData.key
                readonly property var pages: modelData.pages || []
                readonly property int readyCount: pages.filter(p => p.status === "ready").length
                readonly property string areaStatus: readyCount === pages.length ? "ready" : (readyCount > 0 || pages.some(p => p.status === "partial") ? "partial" : "planned")
                readonly property real openH: Math.min(deck.maxOpen, stack.spineH + pages.length * stack.rowH + 12)
                readonly property real extra: open ? openH - stack.spineH : 0     // o koľko je vyššia ako chrbát

                property real grow: extra
                Behavior on grow { NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }

                x: 10; width: deck.width - 20
                height: stack.spineH + grow
                z: open ? 100 : stack.areas.length - index        // vyššie karty ležia na nižších (chrbty)
                radius: 14
                readonly property color base: open ? stack.theme.surface : Qt.tint(stack.theme.surface, Qt.rgba(stack.theme.fg.r, stack.theme.fg.g, stack.theme.fg.b, card.hovered ? 0.07 : 0.035))
                color: stack.theme.glass ? Qt.rgba(base.r, base.g, base.b, open ? 0.92 : 0.78) : base
                // tieň na kartu pod ňou (karty sú naskladané ako fyzické), lacný prechod — aj bez GPU
                Rectangle {
                    z: -1
                    x: 6; width: parent.width - 12; y: parent.height - 4; height: card.open ? 14 : 10
                    radius: 6
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, stack.theme.mode === "dark" ? 0.32 : 0.14) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Behavior on color { ColorAnimation { duration: stack.animMs * 0.6 } }
                border { color: open ? Qt.rgba(stack.theme.primary.r, stack.theme.primary.g, stack.theme.primary.b, 0.55) : stack.theme.line; width: 1 }
                property bool hovered: spineMouse.containsMouse

                // chrbát karty: ikona · NÁZOV · súhrn · stav · šípka
                Item {
                    id: spine
                    width: parent.width; height: stack.spineH
                    readonly property real dy: card.index > 0 ? stack.overlap / 2 : 0
                    Glyph {
                        x: 14; y: (stack.spineH - height) / 2 + spine.dy
                        name: card.modelData.glyph; size: 18; color: card.open ? stack.theme.primary : stack.theme.fg
                    }
                    Column {
                        x: 44; width: parent.width - 96
                        y: (stack.spineH - height) / 2 + spine.dy
                        Text {
                            text: card.modelData.title.toUpperCase(); color: stack.theme.fg
                            font { family: stack.theme.fontUi; pixelSize: 12; weight: Font.ExtraBold; letterSpacing: 0.9 }
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: card.modelData.summary || ""; color: stack.theme.fgDim
                            font { family: stack.theme.fontUi; pixelSize: 11 }
                        }
                    }
                    Text {
                        anchors { right: chev.left; rightMargin: 6 }
                        y: (stack.spineH - height) / 2 + spine.dy
                        text: stack.statusMark(card.areaStatus)
                        color: card.areaStatus === "planned" ? stack.theme.fgDim : stack.theme.primary
                        font { family: stack.theme.fontUi; pixelSize: 13 }
                    }
                    Glyph {
                        id: chev
                        anchors { right: parent.right; rightMargin: 12 }
                        y: (stack.spineH - height) / 2 + spine.dy
                        name: "chevron-right"; size: 14; color: stack.theme.fgDim
                        rotation: card.open ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: spineMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: { stack.forceActiveFocus(); stack.toggle(card.modelData); }
                    }
                }

                // stránky: sú tam stále, karta ich pri rozbaľovaní odkrýva (clip), preto neblikajú
                Flickable {
                    id: fl
                    anchors { left: parent.left; right: parent.right; top: spine.bottom }
                    height: Math.max(0, card.height - stack.spineH - 6)
                    opacity: Math.min(1, card.grow / Math.max(1, card.openH - stack.spineH) * 1.4)
                    visible: card.grow > 0.5
                    contentHeight: pagesCol.height
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    Behavior on contentY { enabled: !fl.moving; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
                    // aktívna stránka musí byť vidieť (aj po skoku z vyhľadávania alebo klávesnicou)
                    function reveal() {
                        const i = card.pages.findIndex(p => p.key === stack.current); if (i < 0) return;
                        const y0 = i * stack.rowH, y1 = y0 + stack.rowH;
                        if (y0 < contentY) contentY = y0; else if (y1 > contentY + height) contentY = y1 - height;
                    }
                    Connections { target: stack; function onCurrentChanged() { fl.reveal(); } }
                    onHeightChanged: reveal()
                    ScrollHint { flick: fl; colors: stack.theme }

                    Item {
                        id: pagesCol
                        width: fl.width; height: card.pages.length * stack.rowH
                        readonly property int activeIdx: card.pages.findIndex(p => p.key === stack.current)
                        // posuvné zvýraznenie aktívnej stránky
                        Rectangle {
                            x: 6; width: parent.width - 12; height: stack.rowH - 2; radius: 9
                            visible: pagesCol.activeIdx >= 0
                            y: Math.max(0, pagesCol.activeIdx) * stack.rowH + 1
                            color: Qt.rgba(stack.theme.primary.r, stack.theme.primary.g, stack.theme.primary.b, 0.16)
                            Behavior on y { NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
                            Rectangle { x: 0; width: 3; height: parent.height - 14; anchors.verticalCenter: parent.verticalCenter; radius: 2; color: stack.theme.primary }
                        }
                        Repeater {
                            model: card.pages
                            Item {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool active: stack.current === modelData.key
                                x: 6; y: index * stack.rowH; width: pagesCol.width - 12; height: stack.rowH
                                Rectangle {
                                    anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                    radius: 9; color: rm.containsMouse && !row.active ? stack.theme.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: stack.animMs * 0.5 } }
                                }
                                opacity: modelData.status === "planned" ? 0.6 : 1
                                Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; name: row.modelData.glyph || "point"; size: 16; color: row.active ? stack.theme.primary : stack.theme.fg }
                                Text {
                                    x: 38; width: parent.width - 64; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                    text: row.modelData.label; color: stack.theme.fg
                                    font { family: stack.theme.fontUi; pixelSize: 13; weight: row.active ? Font.Bold : Font.Medium }
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: stack.statusMark(row.modelData.status); color: row.modelData.status === "planned" ? stack.theme.fgDim : stack.theme.primary
                                    font { family: stack.theme.fontUi; pixelSize: 11 }
                                }
                                MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: (m) => { stack.forceActiveFocus();
                                                                if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); stack.contextRequested(card.modelData.key, row.modelData.key, row.modelData.label, q.x, q.y); }
                                                                else stack.activated(card.modelData.key, row.modelData.key); } }
                            }
                        }
                    }
                }
                // fokus klávesnice na otvorenej karte (nie iba farba, §8)
                Rectangle { anchors.fill: parent; radius: 14; color: "transparent"; visible: stack.activeFocus && card.open
                            border { color: stack.theme.primary; width: 2 } }
            }
        }
        }
    }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: stack.theme.line }
}
