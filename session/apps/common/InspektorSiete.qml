// InspektorSiete — inšpektor siete LatteOS podľa ESET Network Inspector (predloha od používateľa 26. 9.):
// polkruhový radar, dole v strede tento počítač nad routerom, na vnútornom oblúku zariadenia pripojené teraz,
// na vonkajšom pripojené v minulosti; nerozpoznané zariadenie je „?“ v prerušovanom rámčeku. Každé zariadenie sa dá
// identifikovať: premenovať a zmeniť mu druh (ikonu a účel). Prepínač Radar / Zoznam, „Moja sieť“ (iba v nej sa
// hlásia nové zariadenia). Pravý klik = ponuka. Backend: latte-inspektor. Používa ho Správca zariadení › Siete
// (okno L, samostatné okno, Nastavenia › Sieť) a aplikácia Inšpektor siete.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: ins
    required property var theme
    property bool compact: true
    property bool active: true
    property bool fill: false                   // radar vyplní zadanú výšku (samostatné okno); inak pevná výška
    property string view: "radar"               // radar | zoznam
    property var net: ({ ok: false, devices: [], audio: [], me: null })
    property string selKey: ""
    property string status: ""
    signal openWindow(var args)
    readonly property var t: theme
    readonly property var sel: (net.devices || []).find(d => d.key === selKey) || null
    readonly property var gw: (net.devices || []).find(d => d.gateway) || null
    readonly property var now: (net.devices || []).filter(d => d.online && !d.gateway)
    readonly property var past: (net.devices || []).filter(d => !d.online)
    implicitHeight: head.height + 10 + (view === "radar" ? (fill ? 420 : radar.height) : list.implicitHeight) + (status ? 22 : 0)

    readonly property var kinds: [["pc", "Počítač", "device-desktop"], ["phone", "Telefón / tablet", "device-mobile"], ["tv", "Televízor", "device-tv"],
                                  ["audio", "Zvuk / receiver", "device-speaker"], ["printer", "Tlačiareň", "printer"], ["nas", "Úložisko / NAS", "server"],
                                  ["iot", "Inteligentná domácnosť", "bulb"], ["console", "Herná konzola", "device-gamepad"], ["camera", "Kamera", "camera"],
                                  ["router", "Router / Wi-Fi", "router"], ["device", "Iné zariadenie", "devices"]]
    function kindGlyph(k) { const x = kinds.find(z => z[0] === k); return x ? x[2] : "devices"; }
    function kindName(k) { const x = kinds.find(z => z[0] === k); return x ? x[1] : "Zariadenie"; }
    function label(d) { const v = d.vendor && d.vendor.indexOf("súkromná") < 0 ? d.vendor : "";
                        return d.name || v || (d.gateway ? "Router" : (d.kind !== "device" ? kindName(d.kind) : d.ip)); }
    function ago(ts) { if (!ts) return ""; const s = Date.now() / 1000 - ts; if (s < 600) return "teraz"; if (s < 3600) return "pred " + Math.round(s / 60) + " min";
                       if (s < 86400) return "pred " + Math.round(s / 3600) + " h"; const d = Math.round(s / 86400); return d === 1 ? "včera" : "pred " + d + " dňami"; }
    function hasSvc(d, t) { return (d.services || []).some(x => x.type === t); }
    function human(n) { n = +n || 0; for (const u of ["B", "kB", "MB", "GB", "TB"]) { if (n < 1024) return (n >= 10 || u === "B" ? Math.round(n) : n.toFixed(1)) + " " + u; n /= 1024; } return n.toFixed(1) + " PB"; }
    readonly property var svcName: ({ "_airplay._tcp": "AirPlay", "_raop._tcp": "AirPlay", "_googlecast._tcp": "Chromecast", "_spotify-connect._tcp": "Spotify Connect",
                                      "_ipp._tcp": "tlač", "_ipps._tcp": "tlač", "_printer._tcp": "tlač", "_smb._tcp": "zdieľané súbory", "_ssh._tcp": "SSH",
                                      "_http._tcp": "web", "_https._tcp": "web", "_sftp-ssh._tcp": "SFTP", "_snapcast._tcp": "Snapcast", "_hap._tcp": "HomeKit",
                                      "_rtsp._tcp": "video (RTSP)", "_home-assistant._tcp": "Home Assistant" })
    function services(d) { const n = []; for (const x of d.services || []) { const v = svcName[x.type]; if (v && n.indexOf(v) < 0) n.push(v); }
                           if (((d.upnp || {}).types || []).some(t => t.indexOf("MediaRenderer") >= 0)) n.push("DLNA"); return n; }

    // ── dáta ──
    component Q: Process {
        id: q
        property var done: null
        stdout: StdioCollector { onStreamFinished: { try { q.done(JSON.parse(this.text)); } catch (e) {} } }
    }
    Q { id: qLast; command: ["latte-inspektor", "posledny"]; done: (d) => { ins.net = d; if (!d.ok && !qScan.running) qScan.running = true; } }
    Q { id: qScan; command: ["latte-inspektor", "sken"]; done: (d) => { ins.net = d; ins.status = d.ok ? "Hotovo: " + d.devices.filter(x => x.online).length + " zariadení je teraz v sieti" : (d.error || ""); } }
    Process { id: runner; onExited: qLast.running = true }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) status = msg; }
    function scan() { if (!qScan.running) { qScan.running = true; status = "Prehľadávam sieť… (asi 5 s)"; } }
    function identify(d, name, kind) { run(["latte-inspektor", "oznac", d.key, name, kind], "Uložené: " + (name || label(d))); }
    onActiveChanged: if (active && !qLast.running) qLast.running = true
    Component.onCompleted: qLast.running = true
    Timer { running: ins.status !== "" && !qScan.running; interval: 3500; onTriggered: ins.status = "" }

    component Chip: Rectangle {
        id: ch
        property string label; property string glyph: ""; property bool on: false; property bool primary: false
        signal clicked()
        width: cl.implicitWidth + (glyph ? 40 : 22); height: 30; radius: 9
        color: primary ? ins.t.primary : (on ? Qt.rgba(ins.t.primary.r, ins.t.primary.g, ins.t.primary.b, 0.2) : (cm.containsMouse ? ins.t.hover : ins.t.field))
        border { width: on ? 1 : 0; color: ins.t.primary }
        Glyph { visible: ch.glyph !== ""; x: 11; anchors.verticalCenter: parent.verticalCenter; name: ch.glyph || "x"; size: 14; color: ch.primary ? ins.t.fgOnPrimary : ins.t.primary }
        Text { id: cl; x: ch.glyph ? 31 : 11; anchors.verticalCenter: parent.verticalCenter; text: ch.label; color: ch.primary ? ins.t.fgOnPrimary : ins.t.fg
               font { family: ins.t.fontUi; pixelSize: 12; weight: Font.DemiBold } }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }

    // ── hlavička: sieť, Moja sieť, pohľad, prehľadať ──
    Item {
        id: head
        width: ins.width; height: 46
        Glyph { id: hg; anchors.verticalCenter: parent.verticalCenter; name: ins.net.me && ins.net.me.wifi ? "wifi" : "network"; size: 26; color: ins.t.primary }
        Column {
            anchors { left: hg.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            Text { text: "Sieť"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10 } }
            Text { text: ins.net.me ? (ins.net.me.netname || ins.net.subnet) : "…"; color: ins.t.fg; font { family: ins.t.fontUi; pixelSize: 15; weight: Font.Bold } }
            Text { text: ins.net.mine ? "★ Moja sieť" : "☆ Označiť ako Moja sieť"; color: ins.net.mine ? ins.t.primary : ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11 }
                   MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                               onClicked: ins.run(["latte-inspektor", "moja-siet", ins.net.mine ? "nie" : "ano"], ins.net.mine ? "Už nie je Moja sieť" : "Moja sieť: nové zariadenia sa budú hlásiť") } }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Chip { glyph: "radar"; label: ins.compact ? "" : "Radar"; on: ins.view === "radar"; onClicked: ins.view = "radar" }
            Chip { glyph: "list"; label: ins.compact ? "" : "Zoznam"; on: ins.view === "zoznam"; onClicked: ins.view = "zoznam" }
            Chip { glyph: "refresh"; label: qScan.running ? "Prehľadávam…" : "Prehľadať sieť"; primary: true; onClicked: ins.scan() }
        }
    }

    // ── radar ──
    Item {
        id: radar
        visible: ins.view === "radar"
        anchors { top: head.bottom; topMargin: 10 }
        width: ins.width; height: ins.compact ? 330 : (ins.fill ? Math.max(420, ins.height - head.height - 16) : 420)
        // otvorený detail v širokom okne: radar sa posunie doľava, aby nič nezakrýval
        property real cx: (width - (det.visible && !ins.compact ? det.width + 12 : 0)) / 2
        Behavior on cx { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        readonly property real cy: height - 58
        readonly property real rad: Math.min(cx - 36, cy - 30)
        readonly property real rNow: rad * 0.52
        readonly property real rPast: rad * 0.9
        // rozloženie po oblúkoch: teraz na vnútornom (pri veľa zariadeniach aj na strednom), minulosť na vonkajšom
        function arc(list, r) {
            const a0 = Math.PI + 0.2, a1 = 2 * Math.PI - 0.2, n = list.length;
            return list.map((d, i) => { const a = a0 + (i + 0.5) * (a1 - a0) / Math.max(1, n); return { d: d, x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) }; });
        }
        readonly property int capNow: Math.max(3, Math.floor(rNow * (Math.PI - 0.4) / 82))
        readonly property var spots: arc(ins.now.slice(0, capNow), rNow)
                                     .concat(arc(ins.now.slice(capNow, capNow + Math.floor(rad * 0.72 * (Math.PI - 0.4) / 82)), rad * 0.72))
                                     .concat(arc(ins.past.slice(0, Math.floor(rPast * (Math.PI - 0.4) / 82)), rPast))
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
            Connections { target: radar; function onCxChanged() { radarBg.requestPaint(); } }
            id: radarBg
            onPaint: {
                const c = getContext("2d"); c.reset();
                const p = ins.t.primary, cx = radar.cx, cy = radar.cy;
                // pásy: minulosť (vonku), teraz (vnútri), tento počítač (stred)
                for (const [r, a] of [[radar.rad + 26, 0.05], [radar.rad * 0.72 + 30, 0.07], [radar.rNow * 0.55, 0.12]]) {
                    if (!(r > 0)) continue;                  // ešte bez rozmeru (skrytá stránka)
                    c.beginPath(); c.moveTo(cx - r, cy); c.arc(cx, cy, r, Math.PI, 2 * Math.PI); c.closePath();
                    c.fillStyle = Qt.rgba(p.r, p.g, p.b, a); c.fill();
                }
                c.strokeStyle = Qt.rgba(p.r, p.g, p.b, 0.25); c.lineWidth = 1;
                c.beginPath(); c.moveTo(cx - radar.rad - 34, cy + 0.5); c.lineTo(cx + radar.rad + 34, cy + 0.5); c.stroke();
            }
        }
        // popisy pásov pod ich ľavou časťou (ako v ESET)
        readonly property real bOut: rad + 26
        readonly property real bMid: rad * 0.72 + 30
        readonly property real bIn: rNow * 0.55
        Text { x: radar.cx - (radar.bOut + radar.bMid) / 2 - width / 2; y: radar.cy + 6; text: "V minulosti"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10 } }
        Text { x: radar.cx - (radar.bMid + radar.bIn) / 2 - width / 2; y: radar.cy + 6; text: "Pripojené teraz"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10 } }

        // tento počítač nad routerom
        Column {
            x: radar.cx - width / 2; y: radar.cy - 64
            spacing: 2
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 50; height: 42; radius: 11; color: ins.t.primary
                Glyph { anchors.centerIn: parent; name: "device-desktop"; size: 26; color: ins.t.fgOnPrimary }
                Rectangle { x: parent.width - 14; y: -4; width: 18; height: 18; radius: 9; color: "#3FB950"
                            Text { anchors.centerIn: parent; text: "✓"; color: "white"; font { pixelSize: 11; bold: true } } }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Tento počítač"; color: ins.t.fg; font { family: ins.t.fontUi; pixelSize: 11; weight: Font.DemiBold } }
        }
        Column {
            x: radar.cx - width / 2; y: radar.cy + 4
            visible: !!ins.gw
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40; height: 26; radius: 8; color: rgm.containsMouse || (ins.gw && ins.selKey === ins.gw.key) ? ins.t.hover : ins.t.surfaceVariant
                border { width: 1; color: ins.t.primary }
                Glyph { anchors.centerIn: parent; name: "router"; size: 18; color: ins.t.primary }
                MouseArea { id: rgm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => { if (m.button === Qt.RightButton) ins.menuFor(ins.gw, this, m); else ins.selKey = ins.gw.key; } }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: ins.gw ? ins.label(ins.gw) : ""; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10 } }
        }

        // zariadenia
        Repeater {
            model: radar.spots
            Item {
                id: dv
                required property var modelData
                readonly property var d: modelData.d
                readonly property bool picked: ins.selKey === d.key
                width: 84; height: 64
                x: modelData.x - width / 2; y: modelData.y - 24
                opacity: d.online ? 1 : 0.62
                Rectangle {
                    id: tile
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 46; height: 38; radius: 10
                    color: dv.picked ? Qt.rgba(ins.t.primary.r, ins.t.primary.g, ins.t.primary.b, 0.25) : (dm2.containsMouse ? ins.t.hover : ins.t.surfaceVariant)
                    border { width: dv.picked ? 2 : (dv.d.unknown ? 0 : 1); color: dv.picked ? ins.t.primary : ins.t.outline }
                    scale: dm2.containsMouse ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 110 } }
                    // nerozpoznané: prerušovaný rámček a otáznik (ako v ESET)
                    Canvas {
                        visible: dv.d.unknown && !dv.picked
                        anchors.fill: parent
                        onPaint: { const c = getContext("2d"); c.reset(); c.setLineDash([4, 3]); c.strokeStyle = ins.t.fgDim; c.lineWidth = 1.5;
                                   c.beginPath(); c.roundedRect(1, 1, width - 2, height - 2, 9, 9); c.stroke(); }
                    }
                    Text { visible: dv.d.unknown; anchors.centerIn: parent; text: "?"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 22; weight: Font.Bold } }
                    Glyph { visible: !dv.d.unknown; anchors.centerIn: parent; name: ins.kindGlyph(dv.d.kind); size: 22; color: dv.d.online ? ins.t.primary : ins.t.fgDim }
                    Rectangle { visible: !!dv.d.new; x: parent.width - 10; y: -4; width: 14; height: 14; radius: 7; color: ins.t.error
                                Text { anchors.centerIn: parent; text: "!"; color: "white"; font { pixelSize: 10; bold: true } } }
                }
                Text { anchors { top: tile.bottom; topMargin: 3; horizontalCenter: parent.horizontalCenter } width: parent.width
                       horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: ins.label(dv.d); color: ins.t.fg
                       font { family: ins.t.fontUi; pixelSize: 11; weight: dv.picked ? Font.Bold : Font.Normal } }
                MouseArea {
                    id: dm2
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => { if (m.button === Qt.RightButton) ins.menuFor(dv.d, this, m); else ins.selKey = dv.picked ? "" : dv.d.key; }
                }
            }
        }
        Text { visible: !!ins.net.ok && ins.now.length === 0 && ins.past.length === 0; anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 40 }
               width: parent.width * 0.7; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 12 }
               text: "Okrem routera tu nič nie je. Vo virtuálnom počítači (NAT) je to správne — doma sa ukážu telefóny, televízory, tlačiarne, receivery…" }
    }

    // ── zoznam (ako tabuľka v ESET) ──
    Column {
        id: list
        visible: ins.view === "zoznam"
        anchors { top: head.bottom; topMargin: 10 }
        width: ins.width; spacing: 3
        Repeater {
            model: [["Môj router", ins.gw ? [ins.gw] : []], ["Pripojené teraz", ins.now], ["Pripojené v minulosti", ins.past]].filter(g => g[1].length)
            Column {
                required property var modelData
                width: list.width; spacing: 3
                Text { topPadding: 6; text: modelData[0].toUpperCase(); color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.6 } }
                Repeater {
                    model: modelData[1]
                    Rectangle {
                        id: lr
                        required property var modelData
                        width: list.width; height: 40; radius: 9
                        color: ins.selKey === modelData.key ? Qt.rgba(ins.t.primary.r, ins.t.primary.g, ins.t.primary.b, 0.18) : (lm.containsMouse ? ins.t.hover : ins.t.field)
                        Glyph { x: 10; anchors.verticalCenter: parent.verticalCenter; name: lr.modelData.unknown ? "help" : ins.kindGlyph(lr.modelData.kind); size: 17
                                color: lr.modelData.online ? ins.t.primary : ins.t.fgDim }
                        Row {
                            x: 38; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                            readonly property real w: lr.width - 48
                            Column { width: parent.w * (ins.compact ? 0.5 : 0.34)
                                Text { width: parent.width; elide: Text.ElideRight; text: (lr.modelData.new ? "● " : "") + ins.label(lr.modelData); color: lr.modelData.new ? ins.t.error : ins.t.fg
                                       font { family: ins.t.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: ins.kindName(lr.modelData.kind) + (lr.modelData.identified ? " · identifikované" : "")
                                       color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10 } } }
                            Text { visible: !ins.compact; width: parent.w * 0.22; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                   text: lr.modelData.vendor + (lr.modelData.model ? " · " + lr.modelData.model : ""); color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11 } }
                            Text { width: parent.w * (ins.compact ? 0.27 : 0.2); anchors.verticalCenter: parent.verticalCenter; text: lr.modelData.ip; color: ins.t.fg
                                   font { family: ins.t.fontMono; pixelSize: 11 } }
                            Text { width: parent.w * (ins.compact ? 0.2 : 0.16); anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                   text: lr.modelData.online ? "teraz" : ins.ago(lr.modelData.last); color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11 } }
                        }
                        MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (m) => { if (m.button === Qt.RightButton) ins.menuFor(lr.modelData, this, m); else ins.selKey = ins.selKey === lr.modelData.key ? "" : lr.modelData.key; } }
                    }
                }
            }
        }
    }

    Text { visible: ins.status !== ""; anchors { bottom: ins.bottom; left: ins.left } text: ins.status; color: ins.t.primary; font { family: ins.t.fontUi; pixelSize: 12 } }

    // ── detail: identifikovať, premenovať, druh, údaje, akcie ──
    Rectangle {
        id: det
        visible: !!ins.sel
        z: 5
        anchors { top: head.bottom; topMargin: 6; right: parent.right }
        width: ins.compact ? ins.width : Math.min(340, ins.width * 0.45)
        height: Math.min(dc.implicitHeight + 28, Math.max(260, ins.height - head.height - 8))
        radius: 14; color: ins.t.surfaceVariant; border { width: 1; color: ins.t.primary }
        onVisibleChanged: if (visible && ins.sel) { nameIn.text = ins.sel.name || ""; det.kind = ins.sel.kind; }
        property string kind: "device"
        Connections { target: ins; function onSelKeyChanged() { if (ins.sel) { nameIn.text = ins.sel.name || ""; det.kind = ins.sel.kind; } } }
        Flickable {
            anchors { fill: parent; margins: 14 }
            contentHeight: dc.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: dc
                width: parent.width; spacing: 8
                Row {
                    spacing: 10; width: parent.width
                    Rectangle { width: 46; height: 40; radius: 11; color: ins.t.field
                                Glyph { anchors.centerIn: parent; name: ins.kindGlyph(det.kind); size: 24; color: ins.t.primary } }
                    Column {
                        width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter
                        Text { width: parent.width; elide: Text.ElideRight; text: ins.sel ? ins.label(ins.sel) : ""; color: ins.t.fg; font { family: ins.t.fontUi; pixelSize: 15; weight: Font.Bold } }
                        Text { text: ins.sel ? (ins.sel.online ? "v sieti teraz" : "naposledy " + ins.ago(ins.sel.last)) + (ins.sel.identified ? " · identifikované" : (ins.sel.unknown ? " · nerozpoznané" : "")) : ""
                               color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11 } }
                    }
                    Rectangle { width: 28; height: 28; radius: 8; color: xm.containsMouse ? ins.t.hover : "transparent"
                                Glyph { anchors.centerIn: parent; name: "x"; size: 14; color: ins.t.fgDim }
                                MouseArea { id: xm; anchors.fill: parent; hoverEnabled: true; onClicked: ins.selKey = "" } }
                }
                Text { text: "MENO"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10; weight: Font.Bold } }
                Rectangle {
                    width: parent.width; height: 34; radius: 9; color: ins.t.field; border { width: nameIn.activeFocus ? 1 : 0; color: ins.t.primary }
                    TextInput { id: nameIn; anchors { fill: parent; leftMargin: 10; rightMargin: 10 } verticalAlignment: TextInput.AlignVCenter; clip: true
                                color: ins.t.fg; font { family: ins.t.fontUi; pixelSize: 13 } selectByMouse: true
                                Keys.onReturnPressed: ins.identify(ins.sel, text.trim(), det.kind)
                                Text { visible: !nameIn.text && !nameIn.activeFocus; anchors.verticalCenter: parent.verticalCenter
                                       text: (ins.sel && ins.sel.auto && ins.sel.auto.name) || "napr. Televízor v detskej"; color: ins.t.fgDim; font: nameIn.font } }
                }
                Text { text: "DRUH (IKONA A ÚČEL)"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10; weight: Font.Bold } }
                Flow {
                    width: parent.width; spacing: 5
                    Repeater { model: ins.kinds
                        Chip { required property var modelData; glyph: modelData[2]; label: ins.compact && det.kind !== modelData[0] ? "" : modelData[1]
                               on: det.kind === modelData[0]; onClicked: det.kind = modelData[0] } }
                }
                Row {
                    spacing: 6
                    Chip { label: "Uložiť"; glyph: "check"; primary: true; onClicked: ins.identify(ins.sel, nameIn.text.trim(), det.kind) }
                    Chip { visible: !!ins.sel && ins.sel.identified; label: "Automaticky"; onClicked: { ins.run(["latte-inspektor", "oznac", ins.sel.key, "", ""], "Meno a druh podľa skenu"); } }
                }
                Text { text: "ÚDAJE"; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 10; weight: Font.Bold } }
                Repeater {
                    model: ins.sel ? [["IP adresa", ins.sel.ip], ["MAC", ins.sel.mac], ["Výrobca", ins.sel.vendor], ["Model", ins.sel.model],
                                      ["Služby", ins.services(ins.sel).join(", ")], ["Rozpoznané ako", ins.sel.auto ? ins.kindName(ins.sel.auto.kind) : ""],
                                      ["Prvýkrát", ins.sel.first ? new Date(ins.sel.first * 1000).toLocaleString(Qt.locale(), "d. M. yyyy HH:mm") : ""]].filter(r => r[1]) : []
                    Row { required property var modelData; spacing: 8; width: dc.width
                          Text { width: 100; text: modelData[0]; color: ins.t.fgDim; font { family: ins.t.fontUi; pixelSize: 11 } }
                          Text { width: parent.width - 108; wrapMode: Text.Wrap; text: modelData[1]; color: ins.t.fg; font { family: ins.t.fontUi; pixelSize: 11 } }
                          MouseArea { width: parent.width; height: parent.height; onDoubleClicked: Quickshell.execDetached(["wl-copy", modelData[1]]) } }
                }
                Flow {
                    width: parent.width; spacing: 5
                    Chip { visible: !!ins.sel && (ins.sel.gateway || ins.hasSvc(ins.sel, "_http._tcp") || ins.hasSvc(ins.sel, "_https._tcp")); label: "Webové rozhranie"; glyph: "world"
                           onClicked: ins.openWindow(["xdg-open", (ins.hasSvc(ins.sel, "_https._tcp") ? "https://" : "http://") + ins.sel.ip]) }
                    Chip { visible: !!ins.sel && ins.hasSvc(ins.sel, "_ssh._tcp"); label: "SSH"; glyph: "terminal"; onClicked: ins.openWindow(["foot", "-e", "ssh", ins.sel.ip]) }
                    Chip { visible: !!ins.sel && ins.hasSvc(ins.sel, "_smb._tcp"); label: "Súbory"; glyph: "folder"; onClicked: ins.openWindow(["latte-app", "subory", "smb://" + ins.sel.ip]) }
                    Chip { label: "Kopírovať IP"; glyph: "copy"; onClicked: Quickshell.execDetached(["wl-copy", ins.sel.ip]) }
                    Chip { visible: !!ins.sel && !ins.sel.online; label: "Zabudnúť"; glyph: "trash"
                           onClicked: { const k = ins.sel.key; ins.selKey = ""; ins.run(["latte-inspektor", "zabudni", k], "Zabudnuté"); } }
                }
            }
        }
    }

    // pravý klik na zariadenie
    function menuFor(d, item, m) {
        const q = item.mapToItem(ins, m.x, m.y);
        menu.open(q.x, q.y, [
            { glyph: "pencil", label: "Identifikovať / premenovať…", bold: true, action: () => { ins.selKey = d.key; } },
            { glyph: "category", label: "Druh", sub: kinds.map(k => ({ glyph: k[2], label: k[1], checked: d.kind === k[0], action: () => ins.identify(d, d.identified ? d.name : "", k[0]) })) },
            { separator: true },
            { glyph: "world", label: "Otvoriť webové rozhranie", enabled: d.gateway || hasSvc(d, "_http._tcp") || hasSvc(d, "_https._tcp"),
              action: () => ins.openWindow(["xdg-open", "http://" + d.ip]) },
            { glyph: "copy", label: "Kopírovať IP adresu", action: () => Quickshell.execDetached(["wl-copy", d.ip]) },
            { glyph: "copy", label: "Kopírovať MAC adresu", enabled: !!d.mac, action: () => Quickshell.execDetached(["wl-copy", d.mac]) },
            { glyph: "trash", label: "Zabudnúť", danger: true, enabled: !d.online, action: () => ins.run(["latte-inspektor", "zabudni", d.key], "Zabudnuté") }], label(d));
    }
    ContextMenu { id: menu; theme: ins.t }
}
