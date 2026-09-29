// LatteOS — Porovnanie súborov podľa obsahu (ako „Compare by content“ v Total Commanderi).
//   Text: dva stĺpce vedľa seba so spoločným posúvaním; zmenené riadky žlté, pridané zelené, zmazané červené,
//   v zmenenom riadku zvýraznené rozdielne znaky. Alt+↓ / Alt+↑ (alebo N / P) ďalší / predošlý rozdiel,
//   D = iba rozdiely, W zalamovanie, F5 znova načítať (súbor sa medzitým zmenil). Binárne: zoznam rozdielnych bajtov.
//   Dáta: latte-tc diff A B. Spúšťa sa: latte-app porovnaj A B (cesty z LATTE_APP_ARGV, aj s medzerami)
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }
    readonly property var args: (Quickshell.env("LATTE_APP_ARGV") || "").split("\n").filter(s => s !== "")
    property string fileA: args[0] || ""
    property string fileB: args[1] || ""
    property var data: null
    property bool onlyDiff: false
    property bool wrap: false
    readonly property var rows: !data || data.binary ? [] : (onlyDiff ? data.rows.filter(r => r[0] !== "=") : data.rows)
    readonly property var diffIdx: { const out = []; for (let i = 0; i < rows.length; i++) if (rows[i][0] !== "=" && (i === 0 || rows[i - 1][0] === "=")) out.push(i); return out; }
    property int curDiff: -1

    Process {
        id: load
        command: ["latte-tc", "diff", app.fileA, app.fileB]
        running: app.fileA !== "" && app.fileB !== ""
        stdout: StdioCollector { onStreamFinished: { try { app.data = JSON.parse(this.text); } catch (e) { app.data = { error: true }; } app.curDiff = -1; } }
    }
    function jump(d) {
        if (!diffIdx.length) return;
        let k = curDiff + d;
        if (k < 0) k = diffIdx.length - 1; else if (k >= diffIdx.length) k = 0;
        curDiff = k; view.positionViewAtIndex(diffIdx[k], ListView.Center);
    }
    // rozdielny úsek v zmenenom riadku (spoločný začiatok a koniec ostanú bez zvýraznenia)
    function span(a, b) { let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
                          let j = 0; while (j < a.length - i && j < b.length - i && a[a.length - 1 - j] === b[b.length - 1 - j]) j++; return [i, j]; }
    function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;").replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;"); }
    function marked(t, other, kind) {
        if (kind !== "~") return esc(t);
        const s = span(t, other), mid = t.slice(s[0], t.length - s[1]);
        return esc(t.slice(0, s[0])) + (mid ? "<span style='background-color:" + Qt.rgba(0.95, 0.7, 0.2, 0.45) + "'>" + esc(mid) + "</span>" : "") + esc(t.slice(t.length - s[1]));
    }
    function bg(kind, side) {
        if (kind === "~") return Qt.rgba(0.9, 0.7, 0.2, 0.13);
        if (kind === "+") return side === 1 ? Qt.rgba(0.3, 0.75, 0.4, 0.16) : Qt.rgba(0, 0, 0, 0.12);
        if (kind === "-") return side === 0 ? Qt.rgba(0.9, 0.35, 0.3, 0.16) : Qt.rgba(0, 0, 0, 0.12);
        return "transparent";
    }
    function hex(n, w) { let s = n.toString(16).toUpperCase(); while (s.length < w) s = "0" + s; return s; }
    function human(b) { const u = ["B", "KB", "MB", "GB"]; let v = b || 0, i = 0; while (v >= 1024 && i < 3) { v /= 1024; i++; } return v.toFixed(i ? 1 : 0).replace(".", ",") + " " + u[i]; }

    FloatingWindow {
        onClosed: Qt.quit()
        title: "Porovnanie — " + app.fileA.split("/").pop() + " ↔ " + app.fileB.split("/").pop()
        implicitWidth: 1280; implicitHeight: 780
        color: theme.surface
        Item {
            id: root
            anchors.fill: parent; focus: true
            Keys.onPressed: (ev) => {
                const alt = ev.modifiers & Qt.AltModifier; ev.accepted = true;
                if (ev.key === Qt.Key_Escape) Qt.quit();
                else if ((ev.key === Qt.Key_Down && alt) || ev.key === Qt.Key_N) app.jump(1);
                else if ((ev.key === Qt.Key_Up && alt) || ev.key === Qt.Key_P) app.jump(-1);
                else if (ev.key === Qt.Key_D) app.onlyDiff = !app.onlyDiff;
                else if (ev.key === Qt.Key_W) app.wrap = !app.wrap;
                else if (ev.key === Qt.Key_F5) load.running = true;
                else if (ev.key === Qt.Key_Down) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + 22);
                else if (ev.key === Qt.Key_Up) view.contentY = Math.max(0, view.contentY - 22);
                else if (ev.key === Qt.Key_PageDown) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + view.height - 40);
                else if (ev.key === Qt.Key_PageUp) view.contentY = Math.max(0, view.contentY - view.height + 40);
                else if (ev.key === Qt.Key_Home) view.positionViewAtBeginning();
                else if (ev.key === Qt.Key_End) view.positionViewAtEnd();
                else ev.accepted = false;
            }
            HeaderBar {
                id: header
                theme: theme; appId: "latteos-subory"; netVisible: false
                anchors { left: parent.left; right: parent.right; top: parent.top }
                title: "Porovnanie podľa obsahu"
                onCloseRequested: Qt.quit()
            }
            component Chip: Rectangle {
                id: c
                property string label; property bool on: false
                signal clicked()
                width: cl.implicitWidth + 20; height: 28; radius: 8
                color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.22) : (cm.containsMouse ? theme.hover : theme.field)
                Text { id: cl; anchors.centerIn: parent; text: c.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: c.on ? Font.Bold : Font.Normal } }
                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: { c.clicked(); root.forceActiveFocus(); } }
            }
            Row {
                id: bar
                anchors { left: parent.left; top: header.bottom; margins: 10 }
                spacing: 6
                Chip { label: "▲ Predošlý rozdiel"; onClicked: app.jump(-1) }
                Chip { label: "▼ Ďalší rozdiel"; onClicked: app.jump(1) }
                Chip { label: "D Iba rozdiely"; on: app.onlyDiff; onClicked: app.onlyDiff = !app.onlyDiff }
                Chip { label: "W Zalamovať"; on: app.wrap; onClicked: app.wrap = !app.wrap }
                Chip { label: "F5 Znova načítať"; onClicked: load.running = true }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; leftPadding: 8
                    color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                    text: !app.data ? "Porovnávam…" : app.data.error ? "Súbory sa nedajú prečítať" : app.data.binary
                          ? (app.data.different ? app.data.different + " rozdielnych bajtov · prvý na 0x" + app.hex(Math.max(0, app.data.first), 8) : "Súbory sú zhodné ✓")
                          : (app.diffIdx.length ? app.diffIdx.length + " rozdielov · zmenené " + app.data.stats.change + " · pridané " + app.data.stats.add + " · zmazané " + app.data.stats.del
                                                    + (app.curDiff >= 0 ? " · " + (app.curDiff + 1) + "/" + app.diffIdx.length : "")
                                                : "Súbory sú zhodné ✓")
                }
            }
            // hlavičky stĺpcov
            Row {
                id: heads
                anchors { left: parent.left; right: parent.right; top: bar.bottom; topMargin: 8; leftMargin: 10; rightMargin: 10 }
                Repeater { model: [app.fileA, app.fileB]
                    Rectangle { required property string modelData; width: heads.width / 2; height: 26; color: theme.field
                        Text { x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle; text: modelData
                               color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.DemiBold } } } }
            }
            ListView {
                id: view
                visible: !!app.data && !app.data.binary
                anchors { left: parent.left; right: parent.right; top: heads.bottom; bottom: parent.bottom; margins: 10; topMargin: 0 }
                clip: true; model: app.rows; boundsBehavior: Flickable.StopAtBounds
                ScrollHint { flick: view; colors: theme }
                delegate: Row {
                    id: dr
                    required property var modelData
                    required property int index
                    readonly property bool curHit: app.curDiff >= 0 && app.diffIdx[app.curDiff] === index
                    width: view.width
                    Repeater { model: 2
                        Rectangle {
                            required property int index
                            readonly property int side: index
                            width: dr.width / 2; height: Math.max(20, tx.implicitHeight + 2)
                            color: app.bg(dr.modelData[0], side)
                            border { color: dr.curHit ? theme.primary : "transparent"; width: dr.curHit ? 1 : 0 }
                            Text { width: 48; anchors.top: parent.top; anchors.topMargin: 1; horizontalAlignment: Text.AlignRight
                                   text: dr.modelData[side === 0 ? 1 : 3] || ""; color: theme.fgDim; font { family: theme.fontMono; pixelSize: 11 } }
                            Text {
                                id: tx
                                x: 58; width: parent.width - 64; anchors.top: parent.top; anchors.topMargin: 1
                                textFormat: Text.StyledText; wrapMode: app.wrap ? Text.WrapAnywhere : Text.NoWrap; elide: app.wrap ? Text.ElideNone : Text.ElideRight
                                text: app.marked(dr.modelData[side === 0 ? 2 : 4], dr.modelData[side === 0 ? 4 : 2], dr.modelData[0])
                                color: theme.fg; font { family: theme.fontMono; pixelSize: 12 }
                            }
                        }
                    }
                }
            }
            // binárne súbory: rozdielne bajty
            ListView {
                id: bview
                visible: !!app.data && !!app.data.binary
                anchors { left: parent.left; right: parent.right; top: heads.bottom; bottom: parent.bottom; margins: 10; topMargin: 6 }
                clip: true; model: app.data && app.data.binary ? app.data.bytes : []
                header: Text { bottomPadding: 6; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                               text: app.data && app.data.binary ? "Veľkosť: " + app.human(app.data.sizeA) + " ↔ " + app.human(app.data.sizeB)
                                                                   + (app.data.bytes.length >= 200 ? " · ukázaných prvých 200 rozdielov" : "") : "" }
                delegate: Row {
                    required property var modelData
                    spacing: 24
                    Text { text: "0x" + app.hex(modelData[0], 8); color: theme.fgDim; font { family: theme.fontMono; pixelSize: 12 } }
                    Text { text: app.hex(modelData[1], 2) + "  '" + (modelData[1] >= 32 && modelData[1] < 127 ? String.fromCharCode(modelData[1]) : ".") + "'"; color: "#E07A5F"; font { family: theme.fontMono; pixelSize: 12 } }
                    Text { text: "→"; color: theme.fgDim; font { family: theme.fontMono; pixelSize: 12 } }
                    Text { text: app.hex(modelData[2], 2) + "  '" + (modelData[2] >= 32 && modelData[2] < 127 ? String.fromCharCode(modelData[2]) : ".") + "'"; color: "#46A758"; font { family: theme.fontMono; pixelSize: 12 } }
                }
            }
        }
    }
}
