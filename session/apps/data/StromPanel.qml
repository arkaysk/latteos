// StromPanel — strom priečinkov ako trvalý panel vedľa zoznamu (Súbory, ako „oddelený strom“ v Total Commanderi / navigačný
// panel Prieskumníka). Rozbaľuje sa postupne (latte-tc strom PRIEČINOK), sám sa otvorí na aktívnom priečinku (path).
//   klik = otvoriť priečinok v aktívnom paneli, ▸/▾ alebo dvojklik = rozbaliť/zbaliť, pravý klik = ponuka (contextRequested)
//   súbor pretiahnutý na priečinok v strome = ponuka Kopírovať / Presunúť (dropRequested, ako v zozname)
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Rectangle {
    id: st
    required property var theme
    property string path: "/"                  // aktívny priečinok (zvýraznený, strom sa k nemu rozbalí)
    property bool hidden: false                 // skryté priečinky
    signal openDir(string path)
    signal contextRequested(string path, real x, real y)
    signal dropRequested(var drop, string path, var area)
    property var rows: []                       // [{ name, path, depth, more, open }]
    color: Qt.rgba(theme.surfaceVariant.r, theme.surfaceVariant.g, theme.surfaceVariant.b, 0.5)
    radius: 12

    readonly property string home: Quickshell.env("HOME") || "/"
    // koreň: domov a „/“ (ako Prieskumník: Domov a Tento počítač)
    Component.onCompleted: { rows = [{ name: "Domov", path: home, depth: 0, more: true, open: false, root: true },
                                     { name: "Systém (/)", path: "/", depth: 0, more: true, open: false, root: true }];
                             reveal(path); }
    onPathChanged: reveal(path)
    property string toward: ""
    // rozbaľuje od najbližšieho koreňa smerom k cieľu
    function reveal(p) {
        if (!p || p.includes("://")) return;
        const ri = p === home || p.startsWith(home + "/") ? 0 : rows.findIndex(r => r.root && r.path === "/");
        toward = p;
        const hit = rows.findIndex(r => r.path === p);
        if (hit >= 0) { toward = ""; view.positionViewAtIndex(hit, ListView.Contain); return; }
        // najhlbší už rozbalený predok
        let best = ri;
        for (let i = 0; i < rows.length; i++) if (rows[i].open && (p.startsWith(rows[i].path === "/" ? "/" : rows[i].path + "/"))) if (rows[i].depth >= rows[best].depth) best = i;
        const b = rows[best];
        if (b && !b.open) expand(best);
        else if (b) { const k = rows.findIndex((x, idx) => idx > best && x.depth === b.depth + 1 && (p === x.path || p.startsWith(x.path + "/"))); if (k >= 0) expand(k); }
    }
    property var pending: ({})                  // cesta → načítava sa (dve rýchle reveal() by rozbalili dvakrát)
    function expand(i) {
        const r = rows[i]; if (!r || r.open || pending[r.path]) return;
        const pd = Object.assign({}, pending); pd[r.path] = true; pending = pd;
        const q = proc.createObject(st, { row: i, parentPath: r.path });
        q.command = ["latte-tc", "strom", r.path]; q.running = true;
    }
    function collapse(i) {
        const r = rows[i]; if (!r || !r.open) return;
        let j = i + 1; while (j < rows.length && rows[j].depth > r.depth) j++;
        const n = rows.slice(); n.splice(i + 1, j - i - 1); n[i] = Object.assign({}, r, { open: false }); rows = n;
    }
    function inserted(i, parentPath, list) {
        const pd = Object.assign({}, pending); delete pd[parentPath]; pending = pd;
        if (!rows[i] || rows[i].path !== parentPath) i = rows.findIndex(r => r.path === parentPath && !r.open);
        if (i < 0 || rows[i].open) return;
        const r = rows[i], kids = list.filter(k => st.hidden || !k.hidden).map(k => ({ name: k.name, path: k.path, depth: r.depth + 1, more: k.more, open: false }));
        const n = rows.slice(); n[i] = Object.assign({}, r, { open: true, more: kids.length > 0 }); n.splice.apply(n, [i + 1, 0].concat(kids)); rows = n;
        if (toward) Qt.callLater(() => reveal(toward));
    }
    Component { id: proc; Process { property int row: 0; property string parentPath: ""
                                    stdout: StdioCollector { onStreamFinished: { let l = []; try { l = JSON.parse(this.text); } catch (e) {} st.inserted(row, parentPath, l); } }
                                    onExited: destroy() } }

    ListView {
        id: view
        anchors { fill: parent; margins: 6 }
        clip: true; model: st.rows; boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: rw
            required property var modelData
            required property int index
            readonly property bool here: modelData.path === st.path
            width: view.width; height: 26; radius: 7
            color: here ? Qt.rgba(st.theme.primary.r, st.theme.primary.g, st.theme.primary.b, 0.22)
                        : (dz.containsDrag ? Qt.rgba(st.theme.primary.r, st.theme.primary.g, st.theme.primary.b, 0.30) : (rm.containsMouse ? st.theme.hover : "transparent"))
            Row {
                x: 4 + rw.modelData.depth * 14; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { width: 12; text: rw.modelData.more ? (rw.modelData.open ? "▾" : "▸") : ""; color: st.theme.fgDim; font.pixelSize: 11
                       anchors.verticalCenter: parent.verticalCenter
                       MouseArea { anchors { fill: parent; margins: -4 } onClicked: rw.modelData.open ? st.collapse(rw.index) : st.expand(rw.index) } }
                Glyph { name: rw.modelData.root ? (rw.modelData.path === "/" ? "device-desktop" : "home") : "folder"; size: 15
                        color: rw.here ? st.theme.primary : st.theme.fgDim; anchors.verticalCenter: parent.verticalCenter }
                Text { text: rw.modelData.name; color: st.theme.fg; elide: Text.ElideRight; width: view.width - 60 - rw.modelData.depth * 14
                       font { family: st.theme.fontUi; pixelSize: 12; weight: rw.here ? Font.DemiBold : Font.Normal } anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: rm; anchors { fill: parent; leftMargin: 20 + rw.modelData.depth * 14 } hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => { if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); st.contextRequested(rw.modelData.path, q.x, q.y); } else st.openDir(rw.modelData.path); }
                onDoubleClicked: rw.modelData.open ? st.collapse(rw.index) : st.expand(rw.index)
            }
            DropArea {
                id: dz; anchors.fill: parent; keys: ["latte-subory", "text/uri-list"]
                onEntered: (d) => { if (d.source && d.source.fromPane) d.source.targetDir = rw.modelData.path; springT.restart(); }
                onExited: springT.stop()
                onDropped: (d) => st.dropRequested(d, rw.modelData.path, dz)
                Timer { id: springT; interval: 900; onTriggered: if (dz.containsDrag && rw.modelData.more && !rw.modelData.open) st.expand(rw.index) }
            }
        }
        ScrollHint { flick: view; colors: st.theme }
    }
}
