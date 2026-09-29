// Monitor › Senzory — ako HWiNFO Sensor Status: skupiny (procesor, čipy hwmon, pamäť, disky, sieť, grafika,
// batéria), stĺpce Aktuálne / Minimum / Maximum / Priemer od otvorenia alebo vynulovania, grafy vybraných
// senzorov dole, záznam do CSV. Pravý klik: Zobraziť graf, Pridať na lištu, Premenovať, Skryť, Kopírovať.
// Voľby: ~/.config/latteos/senzory.json { hidden: [id], names: { id: názov }, tray: [id], graphs: [id] }.
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Item {
    id: sv
    required property var theme
    property var groups: []                  // snap.sensors
    signal openMenu(var items, real x, real y, string title)
    signal status(string text)

    readonly property string cfgFile: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos/senzory.json"
    property var prefs: ({ hidden: [], names: {}, tray: [], graphs: [] })
    property var stats: ({})                 // id → { min, max, sum, n }
    property var hist: ({})                  // id → posledných 120 hodnôt
    property var collapsed: ({})
    property bool showHidden: false
    property int samples: 0
    property bool logging: false
    property string logPath: ""

    FileView {
        id: pf
        path: sv.cfgFile; printErrors: false; atomicWrites: true
        onLoaded: { try { const p = JSON.parse(text()); sv.prefs = Object.assign({ hidden: [], names: {}, tray: [], graphs: [] }, p); } catch (e) {} }
    }
    Process { id: mk; running: true; command: ["mkdir", "-p", sv.cfgFile.replace(/\/[^/]*$/, "")] }
    function savePrefs(p) { prefs = p; pf.setText(JSON.stringify(p)); }
    function toggleIn(key, id) {
        const p = JSON.parse(JSON.stringify(prefs)), a = p[key] || [];
        p[key] = a.indexOf(id) >= 0 ? a.filter(x => x !== id) : a.concat([id]);
        savePrefs(p);
    }
    function rename(id, name) { const p = JSON.parse(JSON.stringify(prefs)); if (name) p.names[id] = name; else delete p.names[id]; savePrefs(p); }
    function label(it) { return prefs.names[it.id] || it.label; }
    function fmt(v, unit) {
        if (v === undefined || v === null || isNaN(v)) return "—";
        const d = unit === "V" ? 3 : (Math.abs(v) >= 100 || unit === "MHz" || unit === "MB" || unit === "ot/min" ? 0 : 1);
        return v.toFixed(d).replace(".", ",") + (unit ? " " + unit : "");
    }
    function reset() { stats = {}; samples = 0; status("Hodnoty vynulované"); }

    // nové snímky → štatistiky, história, CSV
    onGroupsChanged: {
        const st = stats, hs = hist, row = [];
        for (const g of groups) for (const it of g.items) {
            const s = st[it.id] || { min: it.value, max: it.value, sum: 0, n: 0 };
            s.min = Math.min(s.min, it.value); s.max = Math.max(s.max, it.value); s.sum += it.value; s.n++;
            st[it.id] = s;
            const h = hs[it.id] || [];
            h.push(it.value); if (h.length > 120) h.shift();
            hs[it.id] = h;
            row.push(it.value);
        }
        stats = st; hist = hs; samples++;
        if (logging) {
            if (!logHeaderDone) {
                const hdr = ["čas"];
                for (const g of groups) for (const it of g.items) hdr.push('"' + g.name + " · " + label(it) + (it.unit ? " [" + it.unit + "]" : "") + '"');
                logger.write(hdr.join(";") + "\n"); logHeaderDone = true;
            }
            logger.write([Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")].concat(row.map(v => String(v).replace(".", ","))).join(";") + "\n");
        }
    }
    property bool logHeaderDone: false
    Process { id: logger; stdinEnabled: true }
    function toggleLog() {
        if (logging) { logging = false; logger.stdinEnabled = false; status("Záznam uložený: " + logPath); return; }
        const dir = (Quickshell.env("HOME") || "") + "/Dokumenty";
        logPath = dir + "/Senzory " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm") + ".csv";
        logger.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")"; cat >> "$1"', "sh", logPath];
        logger.stdinEnabled = true; logger.running = true; logHeaderDone = false; logging = true;
        status("Zaznamenávam do " + logPath);
    }

    function itemMenu(g, it, x, y) {
        const p = prefs;
        openMenu([
            { glyph: "activity", label: p.graphs.indexOf(it.id) >= 0 ? "Skryť graf" : "Zobraziť graf", action: () => toggleIn("graphs", it.id) },
            { glyph: "layout-bottombar", label: p.tray.indexOf(it.id) >= 0 ? "Odobrať z lišty" : "Pridať na lištu", hint: p.tray.indexOf(it.id) >= 0 ? "" : "po prihlásení",
              action: () => { toggleIn("tray", it.id); status(prefs.tray.indexOf(it.id) >= 0 ? "Na lište: " + label(it) + " (zobrazí sa po ďalšom prihlásení)" : "Odobraté z lišty"); } },
            { separator: true },
            { glyph: "pencil", label: "Premenovať…", action: () => Qt.callLater(() => openMenu([{ input: label(it), label: "Nový názov (prázdne = pôvodný)", action: (t) => rename(it.id, t.trim()) }], x, y, it.label)) },
            { glyph: p.hidden.indexOf(it.id) >= 0 ? "eye" : "eye-off", label: p.hidden.indexOf(it.id) >= 0 ? "Zobraziť" : "Skryť", action: () => toggleIn("hidden", it.id) },
            { glyph: "clipboard", label: "Kopírovať hodnotu", action: () => { copier.command = ["wl-copy", "--", label(it) + ": " + fmt(it.value, it.unit)]; copier.running = true; } },
            { glyph: "refresh", label: "Vynulovať min/max", action: () => { const st = stats; delete st[it.id]; stats = st; } }
        ], x, y, g.name + " · " + label(it));
    }
    Process { id: copier }

    readonly property var rows: {
        const out = [];
        for (const g of groups) {
            const vis = g.items.filter(it => showHidden || prefs.hidden.indexOf(it.id) < 0);
            if (!vis.length) continue;
            out.push({ header: true, g: g });
            if (!collapsed[g.name]) for (const it of vis) out.push({ header: false, g: g, it: it });
        }
        return out;
    }

    // ── hlavička stĺpcov ────────────────────────────────────────────────────────────────
    Row {
        id: head
        width: parent.width; height: 26
        readonly property real nameW: width - 4 * 110 - 14
        Repeater {
            model: [["Senzor", head.nameW], ["Aktuálne", 110], ["Minimum", 110], ["Maximum", 110], ["Priemer", 110]]
            Text { required property var modelData; width: modelData[1]; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter
                   text: modelData[0]; color: sv.theme.fgDim; font { family: sv.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        }
    }
    ListView {
        id: list
        anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: graphArea.top; bottomMargin: 8 }
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: sv.rows
        ScrollHint { flick: list; colors: sv.theme }
        delegate: Rectangle {
            id: r
            required property var modelData
            readonly property var st: modelData.it ? sv.stats[modelData.it.id] : null
            readonly property bool hiddenItem: !!modelData.it && sv.prefs.hidden.indexOf(modelData.it.id) >= 0
            width: list.width - 12; height: modelData.header ? 30 : 26; radius: 6
            color: modelData.header ? Qt.rgba(sv.theme.primary.r, sv.theme.primary.g, sv.theme.primary.b, 0.08) : (rm.containsMouse ? sv.theme.hover : "transparent")
            opacity: hiddenItem ? 0.5 : 1
            Row {
                anchors.verticalCenter: parent.verticalCenter
                Item {
                    width: head.nameW; height: 26
                    Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 14; visible: r.modelData.header
                            name: sv.collapsed[r.modelData.g.name] ? "chevron-right" : "chevron-up"; color: sv.theme.primary }
                    Text {
                        x: r.modelData.header ? 28 : 24; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: r.modelData.header ? r.modelData.g.name : sv.label(r.modelData.it)
                              + (sv.prefs.tray.indexOf(r.modelData.it.id) >= 0 ? "  · na lište" : "") + (sv.prefs.graphs.indexOf(r.modelData.it.id) >= 0 ? "  · graf" : "")
                        color: r.modelData.header ? sv.theme.primary : sv.theme.fg
                        font { family: sv.theme.fontUi; pixelSize: r.modelData.header ? 12 : 12; weight: r.modelData.header ? Font.Bold : Font.Normal }
                    }
                }
                Repeater {
                    model: r.modelData.header ? [] : [r.modelData.it.value, r.st ? r.st.min : undefined, r.st ? r.st.max : undefined, r.st && r.st.n ? r.st.sum / r.st.n : undefined]
                    Text {
                        required property var modelData
                        required property int index
                        width: 110; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter
                        readonly property bool hot: index === 0 && !!r.modelData.it.crit && r.modelData.it.value >= r.modelData.it.crit - 5
                        text: sv.fmt(modelData, r.modelData.it.unit)
                        color: hot ? sv.theme.error : (index === 0 ? sv.theme.fg : sv.theme.fgDim)
                        font { family: sv.theme.fontMono; pixelSize: 12; weight: index === 0 ? Font.DemiBold : Font.Normal }
                    }
                }
            }
            MouseArea {
                id: rm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    const q = mapToItem(null, m.x, m.y);
                    if (r.modelData.header) {
                        if (m.button === Qt.RightButton) {
                            sv.openMenu([{ glyph: "chevron-up", label: sv.collapsed[r.modelData.g.name] ? "Rozbaliť" : "Zbaliť", action: () => { const c = Object.assign({}, sv.collapsed); c[r.modelData.g.name] = !c[r.modelData.g.name]; sv.collapsed = c; } },
                                         { glyph: "eye-off", label: "Skryť celú skupinu", action: () => { const p = JSON.parse(JSON.stringify(sv.prefs)); for (const it of r.modelData.g.items) if (p.hidden.indexOf(it.id) < 0) p.hidden.push(it.id); sv.savePrefs(p); } }],
                                        q.x, q.y, r.modelData.g.name);
                            return;
                        }
                        const c = Object.assign({}, sv.collapsed); c[r.modelData.g.name] = !c[r.modelData.g.name]; sv.collapsed = c;
                        return;
                    }
                    if (m.button === Qt.RightButton) sv.itemMenu(r.modelData.g, r.modelData.it, q.x, q.y);
                    else sv.toggleIn("graphs", r.modelData.it.id);
                }
                onDoubleClicked: if (!r.modelData.header) sv.toggleIn("graphs", r.modelData.it.id)
            }
        }
    }
    Text {
        visible: sv.groups.length === 0
        anchors.centerIn: list; text: "Čakám na prvé meranie…"; color: sv.theme.fgDim; font { family: sv.theme.fontUi; pixelSize: 13 }
    }

    // ── grafy vybraných senzorov (ako panely HWiNFO) ────────────────────────────────────────
    readonly property var graphItems: {
        const out = [];
        for (const g of groups) for (const it of g.items) if (prefs.graphs.indexOf(it.id) >= 0) out.push({ g: g, it: it });
        return out;
    }
    Flow {
        id: graphArea
        anchors { left: parent.left; right: parent.right; bottom: foot.top; bottomMargin: 8 }
        height: sv.graphItems.length ? Math.min(2, Math.ceil(sv.graphItems.length / 3)) * 118 : 0
        spacing: 8; clip: true
        Repeater {
            model: sv.graphItems
            Rectangle {
                id: gr
                required property var modelData
                readonly property var h: sv.hist[modelData.it.id] || []
                readonly property var st: sv.stats[modelData.it.id]
                width: (graphArea.width - 16) / 3; height: 110; radius: 10; color: sv.theme.field; border { color: sv.theme.line; width: 1 }
                Text { x: 10; y: 6; width: parent.width - 40; elide: Text.ElideRight; text: sv.label(gr.modelData.it); color: sv.theme.fg; font { family: sv.theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                Text { anchors { right: parent.right; rightMargin: 26; top: parent.top; topMargin: 6 } text: sv.fmt(gr.modelData.it.value, gr.modelData.it.unit)
                       color: sv.theme.primary; font { family: sv.theme.fontMono; pixelSize: 11; weight: Font.Bold } }
                Glyph { anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 6 } name: "x"; size: 13; color: sv.theme.fgDim
                        MouseArea { anchors { fill: parent; margins: -4 } onClicked: sv.toggleIn("graphs", gr.modelData.it.id) } }
                Canvas {
                    id: cv
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; margins: 10; topMargin: 26 }
                    readonly property var data: gr.h
                    onDataChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        const d = data; if (d.length < 2) return;
                        let lo = Math.min.apply(null, d), hi = Math.max.apply(null, d);
                        if (gr.modelData.it.unit === "%") { lo = 0; hi = Math.max(100, hi); }
                        if (hi - lo < 1e-6) { hi = lo + 1; }
                        const w = width, hh = height, step = w / 119;
                        c.beginPath();
                        for (let i = 0; i < d.length; i++) {
                            const x = w - (d.length - 1 - i) * step, y = hh - (d[i] - lo) / (hi - lo) * hh;
                            if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
                        }
                        c.strokeStyle = sv.theme.primary; c.lineWidth = 1.5; c.stroke();
                        c.lineTo(w, hh); c.lineTo(w - (d.length - 1) * step, hh); c.closePath();
                        c.fillStyle = Qt.rgba(sv.theme.primary.r, sv.theme.primary.g, sv.theme.primary.b, 0.15); c.fill();
                        c.fillStyle = sv.theme.fgDim; c.font = "9px sans-serif";
                        c.fillText(sv.fmt(hi, ""), 2, 9); c.fillText(sv.fmt(lo, ""), 2, hh - 2);
                    }
                }
            }
        }
    }

    // ── spodok: vynulovať, skryté, CSV ───────────────────────────────────────────────────────
    Row {
        id: foot
        anchors { left: parent.left; bottom: parent.bottom }
        height: 34; spacing: 8
        component Btn: Rectangle {
            id: btn
            property string label; property bool on: false
            signal clicked()
            width: bl.implicitWidth + 24; height: 34; radius: 10
            color: on ? Qt.rgba(sv.theme.primary.r, sv.theme.primary.g, sv.theme.primary.b, 0.2) : (bm.containsMouse ? sv.theme.hover : sv.theme.field)
            border { color: on ? sv.theme.primary : "transparent"; width: 1 }
            Text { id: bl; anchors.centerIn: parent; text: btn.label; color: sv.theme.fg; font { family: sv.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
        }
        Btn { label: "Vynulovať min/max"; onClicked: sv.reset() }
        Btn { label: sv.showHidden ? "Skryť skryté" : "Ukázať skryté (" + sv.prefs.hidden.length + ")"; on: sv.showHidden; onClicked: sv.showHidden = !sv.showHidden }
        Btn { label: sv.logging ? "● Zastaviť záznam" : "Záznam do CSV"; on: sv.logging; onClicked: sv.toggleLog() }
        Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; color: sv.theme.fgDim; font { family: sv.theme.fontUi; pixelSize: 11 }
               text: sv.samples + " meraní · klik = graf · pravý klik = ponuka" }
    }
}
