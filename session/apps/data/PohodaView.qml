// SPDX-License-Identifier: AGPL-3.0-or-later
// LatteOS — Monitor › Čas v aplikáciách (Digitálna pohoda).
// Vzhľad a správanie prevzaté a upravené z projektu serpantinum (ilyamiro, https://github.com/ilyamiro/serpantinum,
// src/quickshell/guide/wellbeing/DigitalWellbeingTab.qml, AGPL-3.0). Tento súbor je preto pod AGPL-3.0-or-later;
// zvyšok LatteOS ním nie je dotknutý (samostatný súbor, použitý cez Loader). Zmeny: téma a písma LatteOS,
// slovenčina, dáta z latte-sysmon pohoda-den (meranie pohoda.qml), denné limity, animácie iba s GPU.
//
// Deň:    ← / → (aj klávesy) mení deň · priemer | dnešný súčet | oproti včerajšku · týždeň (klik = deň) · mesiac
//         ako teplotná mapa (klik = deň) · aplikácie (klik = jej deň po polhodinách, pravý klik = limit)
// Týždeň: mapa 7 dní × 24 hodín · denný priemer · najčastejšie hodiny · aplikácie týždňa
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Item {
    id: pv
    required property var theme
    signal limitMenu(var entry, real x, real y)       // pravý klik na aplikáciu (Monitor ukáže ponuku limitov)
    property var limits: ({})

    readonly property bool anim: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    function dur(ms) { return anim ? ms : 0; }

    property var day: new Date()
    property string appClass: ""
    property string appName: ""
    property string appIcon: ""
    property bool weekView: false
    property var d: null
    readonly property bool isToday: iso(day) === iso(new Date())

    readonly property color accent: theme.primary
    readonly property color accent2: Qt.lighter(theme.primary, 1.35)
    readonly property color up: "#E0875F"
    readonly property color down: "#7FB77E"
    readonly property color cardColor: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.045)
    readonly property color cardBorder: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.08)
    readonly property color track: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.10)

    function iso(x) { const z = x.getTimezoneOffset() * 60000; return new Date(x - z).toISOString().slice(0, 10); }
    function fmtLarge(s) { s = Math.round(s); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h > 0 ? h + " h " + m + " min" : m + " min"; }
    function fmtList(s) { s = Math.round(s); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h > 0 ? h + " h " + String(m).padStart(2, "0") + " min" : (m > 0 ? m + " min" : (s > 0 ? "< 1 min" : "0 min")); }
    function fancyDate(x) {
        if (iso(x) === iso(new Date())) return "Dnes";
        const y = new Date(); y.setDate(y.getDate() - 1);
        if (iso(x) === iso(y)) return "Včera";
        return Qt.locale("sk_SK").toString(x, "dddd d. MMMM");
    }
    function iconSrc(ic) { if (!ic) return ""; if (ic.startsWith("/")) return "file://" + ic; return Quickshell.iconPath(ic, true); }

    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: { try { pv.d = JSON.parse(this.text); } catch (e) {} } }
    }
    function refresh() {
        proc.command = ["latte-sysmon", "pohoda-den", iso(day)].concat(appClass !== "" ? [appClass] : []);
        if (!proc.running) proc.running = true;
    }
    function changeDay(n) { const x = new Date(day); x.setDate(x.getDate() + n); if (x > new Date()) return; day = x; refresh(); }
    function toDate(s) { if (!s) return; day = new Date(s + "T12:00:00"); weekView = false; refresh(); }
    Timer { interval: 15000; repeat: true; running: pv.visible && pv.isToday; onTriggered: pv.refresh() }

    // nábeh ako v serpantinum: hlavička → karty → stred → zoznam (s GPU; bez neho hneď)
    property real inHead: 1; property real inStats: 1; property real inMid: 1; property real inBottom: 1; property real inBars: 1
    property real animTotal: d ? d.total : 0
    Behavior on animTotal { enabled: pv.anim; NumberAnimation { duration: 850; easing.type: Easing.OutQuint } }
    ParallelAnimation {
        id: intro
        SequentialAnimation { PauseAnimation { duration: 100 } NumberAnimation { target: pv; property: "inHead"; from: 0; to: 1; duration: 800; easing.type: Easing.OutBack } }
        SequentialAnimation { PauseAnimation { duration: 250 } NumberAnimation { target: pv; property: "inStats"; from: 0; to: 1; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        SequentialAnimation { PauseAnimation { duration: 350 } NumberAnimation { target: pv; property: "inMid"; from: 0; to: 1; duration: 850; easing.type: Easing.OutQuart } }
        SequentialAnimation { PauseAnimation { duration: 300 } NumberAnimation { target: pv; property: "inBars"; from: 0; to: 1; duration: 1300; easing.type: Easing.OutQuart } }
        SequentialAnimation { PauseAnimation { duration: 550 } NumberAnimation { target: pv; property: "inBottom"; from: 0; to: 1; duration: 1000; easing.type: Easing.OutExpo } }
    }
    property real weekFocus: weekView ? 1 : 0
    Behavior on weekFocus { NumberAnimation { duration: pv.dur(550); easing.type: Easing.OutExpo } }
    property real appFocus: appClass !== "" && !weekView ? 1 : 0
    Behavior on appFocus { NumberAnimation { duration: pv.dur(550); easing.type: Easing.OutExpo } }
    Component.onCompleted: { refresh(); if (anim) intro.restart(); }

    Shortcut { sequence: "Left"; enabled: pv.visible; onActivated: pv.changeDay(pv.weekView ? -7 : -1) }
    Shortcut { sequence: "Right"; enabled: pv.visible; onActivated: pv.changeDay(pv.weekView ? 7 : 1) }

    component RoundBtn: Rectangle {
        id: rb
        property string glyph; property string label: ""; property bool shown: true
        signal clicked()
        width: label === "" ? 34 : lt.implicitWidth + 44; height: 34; radius: 10
        color: bm.containsMouse ? Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.10) : pv.cardColor
        opacity: shown ? 1 : 0; visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: pv.dur(350); easing.type: Easing.OutQuint } }
        Row { anchors.centerIn: parent; spacing: 6
              Glyph { name: rb.glyph; size: 15; color: bm.containsMouse ? pv.theme.fg : pv.theme.fgDim; anchors.verticalCenter: parent.verticalCenter }
              Text { id: lt; visible: rb.label !== ""; text: rb.label; color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                  anchors.verticalCenter: parent.verticalCenter } }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    component Card: Rectangle { radius: 16; color: pv.cardColor; border { color: pv.cardBorder; width: 1 } }

    // ── hlavička ─────────────────────────────────────────────────────────────
    Item {
        id: head
        width: parent.width; height: 40
        opacity: pv.inHead; transform: Translate { y: -20 * (1 - pv.inHead) }
        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter } spacing: 6
            RoundBtn { glyph: "chevron-left"; label: "Späť"; shown: pv.appClass !== "" || pv.weekView
                       onClicked: { if (pv.appClass !== "") { pv.appClass = ""; pv.refresh(); } else pv.weekView = false; } }
            RoundBtn { glyph: "calendar"; label: "Týždeň"; shown: pv.appClass === "" && !pv.weekView; onClicked: pv.weekView = true }
            RoundBtn { glyph: "chevron-left"; onClicked: pv.changeDay(pv.weekView ? -7 : -1) }
        }
        Row {
            anchors.centerIn: parent; spacing: 8
            Image { visible: pv.appClass !== "" && !pv.weekView; width: 22; height: 22; source: pv.iconSrc(pv.appIcon); sourceSize { width: 44; height: 44 } anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pv.weekView ? "Týždeň " + (pv.d ? pv.d.weekRange : "") : (pv.appClass !== "" ? pv.appName + " · " + pv.fancyDate(pv.day) : pv.fancyDate(pv.day))
                color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
            }
        }
        RoundBtn { anchors { right: parent.right; verticalCenter: parent.verticalCenter } glyph: "chevron-right"; shown: !pv.isToday; onClicked: pv.changeDay(pv.weekView ? 7 : 1) }
    }

    // ── deň ──────────────────────────────────────────────────────────────────
    Item {
        id: dayView
        anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        opacity: 1 - pv.weekFocus; visible: opacity > 0
        transform: Translate { x: -40 * pv.weekFocus }
        scale: 0.95 + 0.05 * (1 - pv.weekFocus)

        // karty: priemer · súčet · oproti včerajšku
        Row {
            id: stats
            width: parent.width; height: 70; spacing: 8
            opacity: pv.inStats; transform: Translate { y: 30 * (1 - pv.inStats) }
            readonly property real wSide: (width - 16) * 0.3
            Card {
                width: stats.wSide; height: parent.height
                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } spacing: 12
                    Rectangle { width: 38; height: 38; radius: 11; color: pv.cardColor; anchors.verticalCenter: parent.verticalCenter
                                Glyph { anchors.centerIn: parent; name: "clock"; size: 19; color: pv.theme.fg } }
                    Column { anchors.verticalCenter: parent.verticalCenter
                        Text { text: pv.fmtList(pv.d ? pv.d.average : 0); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 19; weight: Font.Bold } }
                        Text { text: "denný priemer · " + (pv.d ? pv.d.weekRange : ""); color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold } } }
                }
            }
            Card {
                width: stats.width - 2 * stats.wSide - 16; height: parent.height
                color: Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.06)
                Text { anchors.centerIn: parent; text: pv.fmtLarge(pv.animTotal); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 30; weight: Font.Black } }
            }
            Card {
                width: stats.wSide; height: parent.height
                readonly property real diff: pv.d ? pv.d.total - pv.d.yesterday : 0
                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } spacing: 12
                    Rectangle { width: 38; height: 38; radius: 11; color: pv.cardColor; anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: parent.parent.parent.diff > 0 ? "▲" : "▼"; color: parent.parent.parent.diff > 0 ? pv.up : pv.down; font.pixelSize: 16 } }
                    Column { anchors.verticalCenter: parent.verticalCenter
                        Text { visible: !!pv.d && (pv.d.total > 0 || pv.d.yesterday > 0) && parent.parent.parent.diff !== 0
                               text: pv.fmtList(Math.abs(parent.parent.parent.diff)); color: parent.parent.parent.diff > 0 ? pv.up : pv.down; font { family: pv.theme.fontUi; pixelSize: 19; weight: Font.Bold } }
                        Text { text: !pv.d || (pv.d.total === 0 && pv.d.yesterday === 0) ? "bez údajov" : (parent.parent.parent.diff === 0 ? "rovnako ako včera" : (parent.parent.parent.diff > 0 ? "viac ako včera" : "menej ako včera"))
                               color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold } } }
                }
            }
        }

        // stred: týždeň (stĺpce) + mesiac (teplotná mapa)
        Row {
            id: mid
            anchors { top: stats.bottom; topMargin: 8 } width: parent.width; height: 160; spacing: 8
            Card {
                width: parent.width - 268; height: parent.height
                opacity: pv.inMid; transform: Translate { x: -30 * (1 - pv.inMid) }
                Row {
                    id: wk
                    anchors { fill: parent; margins: 12 } spacing: 8
                    readonly property real mx: pv.d ? Math.max(1, ...pv.d.week.map(w => w.total)) : 1
                    Repeater {
                        model: pv.d ? pv.d.week : []
                        Item {
                            required property var modelData
                            width: (wk.width - 6 * 8) / 7; height: wk.height
                            MouseArea { id: wm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pv.toDate(modelData.date) }
                            Rectangle {
                                anchors { bottom: dl.top; bottomMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
                                height: Math.max(4, (parent.height - 24) * modelData.total / wk.mx * pv.inBars); radius: 4
                                opacity: wm.containsMouse ? 0.75 : 1
                                color: modelData.isTarget ? "transparent" : Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.16)
                                gradient: modelData.isTarget ? grad : null
                                Behavior on height { enabled: pv.anim && pv.inBars === 1; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                            }
                            Text { id: dl; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter } text: modelData.day
                                   color: modelData.isTarget ? pv.theme.fg : pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                            Rectangle { visible: wm.containsMouse && modelData.total > 0; anchors { bottom: dl.top; bottomMargin: 2; horizontalCenter: parent.horizontalCenter }
                                        width: wt.implicitWidth + 12; height: 20; radius: 6; color: pv.theme.surface; z: 3
                                        Text { id: wt; anchors.centerIn: parent; text: pv.fmtList(modelData.total); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 10 } } }
                        }
                    }
                }
            }
            Card {
                width: 260; height: parent.height
                opacity: pv.inMid; transform: Translate { x: 30 * (1 - pv.inMid) }
                Column {
                    anchors { fill: parent; margins: 10 } spacing: 6
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                          Glyph { name: "calendar"; size: 13; color: pv.accent; anchors.verticalCenter: parent.verticalCenter }
                          Text { text: pv.d ? pv.d.monthName : ""; color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 13; weight: Font.DemiBold } } }
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter; columns: 7; spacing: 5
                        readonly property real mx: pv.d ? Math.max(1, ...pv.d.month.map(m => m.total)) : 1
                        Repeater {
                            model: pv.d ? pv.d.month : []
                            Rectangle {
                                required property var modelData
                                width: 16; height: 16; radius: 3
                                visible: modelData.total !== -1
                                color: modelData.total <= 0 ? Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.10)
                                                           : Qt.rgba(pv.accent.r, pv.accent.g, pv.accent.b, 0.25 + 0.75 * modelData.total / parent.mx)
                                border { color: modelData.isTarget ? pv.theme.fg : "transparent"; width: modelData.isTarget ? 1 : 0 }
                                scale: 0.7 + 0.3 * pv.inMid
                                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pv.toDate(modelData.date) }
                            }
                        }
                    }
                }
            }
        }
        Gradient { id: grad; GradientStop { position: 0; color: pv.accent2 } GradientStop { position: 1; color: pv.accent } }

        // dole: aplikácie dňa / deň vybranej aplikácie po polhodinách
        Item {
            anchors { top: mid.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
            opacity: pv.inBottom; transform: Translate { y: 30 * (1 - pv.inBottom) }
            ListView {
                id: appList
                anchors.fill: parent; spacing: 6; clip: true
                opacity: 1 - pv.appFocus; visible: opacity > 0
                transform: Translate { x: -30 * pv.appFocus }
                model: pv.d ? pv.d.apps : []
                ScrollHint { flick: appList; colors: pv.theme }
                Text { visible: appList.count === 0 && !!pv.d; anchors.centerIn: parent; text: "Pre tento deň nie sú záznamy."; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 13 } }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var lim: pv.limits[modelData["class"]]
                    width: appList.width - 10; height: 54; radius: 14
                    color: rm.containsMouse ? Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.09) : pv.cardColor
                    border { color: pv.cardBorder; width: 1 }
                    transform: Translate { y: row.index * 12 * (1 - pv.inBottom) }
                    Rectangle {
                        id: ib; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; radius: 10; color: pv.cardColor; clip: true
                        Image { id: im; anchors { fill: parent; margins: 4 } source: pv.iconSrc(row.modelData.icon); sourceSize { width: 64; height: 64 } fillMode: Image.PreserveAspectFit; asynchronous: true; mipmap: true }
                        Text { anchors.centerIn: parent; visible: im.status !== Image.Ready; text: row.modelData.name.charAt(0).toUpperCase(); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                    }
                    Column {
                        anchors { left: ib.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } spacing: 3
                        Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.name + (row.lim ? "   ·   limit " + row.lim + " min" : "")
                               color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                        Row {
                            width: parent.width; spacing: 8
                            Item {
                                width: parent.width - chip.width - 8; height: 10; anchors.verticalCenter: parent.verticalCenter
                                Rectangle { anchors.fill: parent; radius: 5; color: pv.track }
                                Rectangle { height: parent.height; radius: 5; color: pv.accent
                                            width: Math.max(10, parent.width * row.modelData.percent / 100 * pv.inBars)
                                            Behavior on width { enabled: pv.anim && pv.inBars === 1; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } } }
                            }
                            Rectangle { id: chip; width: ct.implicitWidth + 16; height: 24; radius: 6; color: Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.10)
                                        Text { id: ct; anchors.centerIn: parent; text: pv.fmtList(row.modelData.seconds)
                                               color: row.lim && row.modelData.seconds >= row.lim * 60 ? pv.theme.error : pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 12; weight: Font.DemiBold } } }
                        }
                    }
                    MouseArea {
                        id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); pv.limitMenu(row.modelData, q.x, q.y); return; }
                            pv.appClass = row.modelData["class"]; pv.appName = row.modelData.name; pv.appIcon = row.modelData.icon; pv.refresh();
                        }
                    }
                }
            }
            // deň aplikácie po polhodinách
            Card {
                anchors.fill: parent
                opacity: pv.appFocus; visible: opacity > 0
                transform: Translate { x: 30 * (1 - pv.appFocus) }
                Row { id: ah; anchors { top: parent.top; topMargin: 12; horizontalCenter: parent.horizontalCenter } spacing: 6
                      Glyph { name: "activity"; size: 14; color: pv.accent; anchors.verticalCenter: parent.verticalCenter }
                      Text { text: "Používanie počas dňa · spolu " + pv.fmtList(pv.d ? pv.d.total : 0); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 13; weight: Font.DemiBold } } }
                Row {
                    id: halves
                    anchors { left: parent.left; right: parent.right; top: ah.bottom; bottom: hl.top; margins: 14 } spacing: 3
                    readonly property real mx: pv.d ? Math.max(1, ...pv.d.hourly) : 1
                    Repeater {
                        model: 48
                        Item {
                            required property int index
                            readonly property real v: pv.d ? pv.d.hourly[index] : 0
                            width: (halves.width - 47 * 3) / 48; height: halves.height
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; radius: 2
                                height: Math.max(4, parent.height * parent.v / halves.mx * pv.inBars)
                                color: parent.v > 0 ? pv.accent : pv.track; opacity: hm.containsMouse ? 0.7 : 1
                                Behavior on height { enabled: pv.anim; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                            }
                            MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true }
                            Rectangle { visible: hm.containsMouse && parent.v > 0; z: 4; y: -26; x: -20; width: htt.implicitWidth + 12; height: 22; radius: 6; color: pv.theme.surface
                                        Text { id: htt; anchors.centerIn: parent; text: Math.floor(index / 2) + ":" + (index % 2 ? "30" : "00") + " · " + pv.fmtList(parent.parent.v); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 10 } } }
                        }
                    }
                }
                Row {
                    id: hl
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                    Repeater {
                        model: ["00:00", "06:00", "12:00", "18:00", "24:00"]
                        Text { required property string modelData; required property int index
                               width: index < 4 ? (hl.width - 30) / 4 : 30; text: modelData; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 10 } }
                    }
                }
            }
        }
    }

    // ── týždeň ───────────────────────────────────────────────────────────────
    Item {
        anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        opacity: pv.weekFocus; visible: opacity > 0
        transform: Translate { x: 40 * (1 - pv.weekFocus) }
        Card {
            id: heat
            width: parent.width; height: 230
            readonly property real mx: pv.d ? Math.max(1, ...pv.d.weekHeatmap.map(r => Math.max(...r))) : 1
            Column {
                id: hc
                anchors { fill: parent; margins: 14 } spacing: 4
                Repeater {
                    model: 7
                    Row {
                        required property int index
                        spacing: 4
                        Text { width: 26; text: ["po", "ut", "st", "št", "pi", "so", "ne"][index]; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                            anchors.verticalCenter: parent.verticalCenter }
                        Repeater {
                            model: 24
                            Rectangle {
                                required property int index
                                readonly property real v: pv.d ? pv.d.weekHeatmap[parent.index][index] : 0
                                width: (hc.width - 30 - 23 * 4) / 24; height: 22; radius: 4
                                color: v <= 0 ? Qt.rgba(pv.theme.fg.r, pv.theme.fg.g, pv.theme.fg.b, 0.07) : Qt.rgba(pv.accent.r, pv.accent.g, pv.accent.b, 0.25 + 0.75 * v / heat.mx)
                                scale: 0.7 + 0.3 * pv.weekFocus
                            }
                        }
                    }
                }
                Row {
                    x: 30
                    Repeater {
                        model: ["0", "6", "12", "18", "23"]
                        Text { required property string modelData; required property int index
                               width: index < 4 ? (hc.width - 30) / 4 : 20; text: modelData + " h"; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 10 } }
                    }
                }
            }
        }
        Row {
            id: wstats
            anchors { top: heat.bottom; topMargin: 8 } width: parent.width; height: 64; spacing: 8
            Card { width: (parent.width - 8) / 2; height: parent.height
                   Column { anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "denný priemer"; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: pv.fmtList(pv.d ? pv.d.average : 0); color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 19; weight: Font.Bold } } } }
            Card { width: (parent.width - 8) / 2; height: parent.height
                   Column { anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "najčastejšie"; color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: pv.d && pv.d.peak ? pv.d.peak : "—"; color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 19; weight: Font.Bold } } } }
        }
        ListView {
            id: wlist
            anchors { top: wstats.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 6; clip: true
            model: pv.d ? pv.d.weekApps : []
            ScrollHint { flick: wlist; colors: pv.theme }
            delegate: Rectangle {
                id: wr
                required property var modelData
                width: wlist.width - 10; height: 46; radius: 12; color: pv.cardColor; border { color: pv.cardBorder; width: 1 }
                Image { id: wim; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 26; height: 26; source: pv.iconSrc(wr.modelData.icon); sourceSize { width: 52; height: 52 } }
                Text { anchors { left: wim.right; leftMargin: 10; verticalCenter: parent.verticalCenter } width: 170; elide: Text.ElideRight; text: wr.modelData.name
                       color: pv.theme.fg; font { family: pv.theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                Item {
                    anchors { left: wim.right; leftMargin: 190; right: wct.left; rightMargin: 10; verticalCenter: parent.verticalCenter } height: 8
                    Rectangle { anchors.fill: parent; radius: 4; color: pv.track }
                    Rectangle { height: parent.height; radius: 4; color: pv.accent; width: Math.max(8, parent.width * wr.modelData.percent / 100) }
                }
                Text { id: wct; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: pv.fmtList(wr.modelData.seconds)
                       color: pv.theme.fgDim; font { family: pv.theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
            }
        }
    }
}
