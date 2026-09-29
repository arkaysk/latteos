// SpravcaZariadeni — jadro Správcu zariadení LatteOS (zadanie 26. 9., podľa starej verzie old/docs/nastavenia.md):
// jedna implementácia pre okno v tvare L z pravého rohu lišty (rychle.qml), samostatné okno (zariadenia.qml) a stránky
// Nastavení (only = jedna kategória). Dve karty hore: Zariadenia a Siete.
//   Zariadenia  dlaždice kategórií zoradené podľa dôležitosti (nie podľa používania): Obrazovky, Grafika, Zvuk, Sieť,
//               Bluetooth, Napájanie, Disky, Vstup, Kamery, Tlačiarne, USB, Počítač, Ostatné. Klik = zariadenia kategórie
//               ako vo Windows (stav, ovládač, oprava, vlastnosti, pravý klik) a k tomu to, čo ponúka softvér ovládača:
//               zvuk (výstup, vstup, konektory = priradenie jackov, konfigurácia reproduktorov, hlasitosť aplikácií),
//               obrazovka (rozlíšenie, mierka s potvrdením do 15 s, jas), sieť (Wi-Fi), Bluetooth (párovanie), disky…
//   Siete       pripojenia, Wi-Fi v okolí, VPN a tunely, SSH server, firewall (zóny, služby, porty, presmerovania), adresy.
// Backend: latte-devices (list, siete, audio, audio karty, bt, bezpecnost, firewall); root operácie v termináli so sudo.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: dm
    required property var theme
    property bool compact: true                 // okno L (užšie) · false = samostatné okno
    property string tab: "zariadenia"           // zariadenia | siete
    property string group: ""                   // "" = dlaždice kategórií
    property string only: ""                    // iba jedna kategória (Nastavenia)
    property bool embedded: false               // vložený do rolovanej stránky: bez vlastného rolovania, výška = obsah
    readonly property real naturalHeight: tabs.height + (tabs.visible ? 10 : 0) + body.implicitHeight + 12
    property var sel: null                      // { group, item }
    property string wantItem: ""                // vybrať toto zariadenie hneď po načítaní (hostiteľ otvára konkrétne zariadenie)
    property bool active: true                  // načítavať (okno otvorené)
    property string status: ""
    signal openWindow(var args)                 // otvoriť iné okno (hostiteľ zavrie popup)
    readonly property var t: theme

    readonly property var order: ["obrazovky", "grafika", "zvuk", "siet", "bluetooth", "napajanie", "disky", "vstup", "kamery", "tlac", "usb", "pocitac", "ostatne"]
    property var groups: []
    property var faults: []
    property string summary: ""
    property int total: 0
    property var problems: []
    readonly property var ordered: order.map(k => groups.find(g => g.key === k)).filter(g => !!g).concat(groups.filter(g => order.indexOf(g.key) < 0))
    readonly property var curGroup: groups.find(g => g.key === (only || group)) || null
    function count(n) { return n + (n === 1 ? " zariadenie" : (n >= 2 && n <= 4 ? " zariadenia" : " zariadení")); }

    // ── dáta ─────────────────────────────────────────────────────────────────────────
    component Q: Process {
        id: q
        property var done: null
        stdout: StdioCollector { onStreamFinished: { if (q.done) { try { q.done(JSON.parse(this.text)); } catch (e) {} } } }
    }
    Q { id: qList; command: ["latte-devices", "list"]
        done: (d) => { dm.groups = d.groups; dm.faults = d.faults || []; dm.summary = d.summary || ""; dm.total = d.total || 0; dm.problems = d.problems || []; dm.refreshSel();
                      if (dm.wantItem) { const g = dm.groups.find(x => x.key === (dm.only || dm.group)), it = g ? g.items.find(i => i.name === dm.wantItem) : null;
                                         dm.wantItem = ""; if (it) dm.pick(g, it); } } }
    property var audio: ({ sinks: [], sources: [], apps: [] })
    Q { id: qAudio; command: ["latte-devices", "audio"]; done: (d) => dm.audio = d }
    property var cards: ({ cards: [], active: {} })
    Q { id: qCards; command: ["latte-devices", "audio", "karty"]; done: (d) => dm.cards = d }
    property var bt: ({ available: false, powered: false, devices: [] })
    Q { id: qBt; command: ["latte-devices", "bt"]; done: (d) => dm.bt = d }
    Q { id: qBtScan; command: ["latte-devices", "bt", "hladaj"]; done: (d) => { dm.bt = d; dm.status = "Hľadanie skončilo"; } }
    property var nets: ({ connections: [], wifi: [], addresses: [] })
    Q { id: qNets; command: ["latte-devices", "siete"]; done: (d) => dm.nets = d }
    property var sec: ({ ssh: {}, firewall: { zones: [] }, tunnels: [] })
    Q { id: qSec; command: ["latte-devices", "bezpecnost"]; done: (d) => dm.sec = d }
    property var fwFull: null
    // inšpektor siete: údaje má komponent InspektorSiete (záložka Siete); tu iba ciele zvuku
    readonly property var insp: inspView.net
    function netSinkFor(name) { return (audio.sinks || []).find(x => x.net && x.desc.toLowerCase().indexOf((name || "").toLowerCase()) >= 0) || null; }
    Q { id: qFw; command: ["latte-devices", "firewall"]; done: (d) => { dm.fwFull = d; dm.status = d.ok ? "" : "Pravidlá sa nedajú zobraziť bez potvrdenia (polkit)"; } }
    // režim napájania (Windows 11: Úspora / Vyvážený / Najlepší výkon) + herný režim LatteOS
    property var power: ({ cur: "", list: [], game: false })
    Q { id: qPower; command: ["latte-devices", "napajanie"]; done: (d) => dm.power = d }
    readonly property var powerNames: ({ "power-saver": "Úsporný", balanced: "Vyvážený", performance: "Výkon" })
    property var live: []
    Q { id: qLive; command: ["latte-sysmon", "senzory"]
        done: (g) => {
            const pre = dm.sel && dm.sel.item.sensorPrefix ? dm.sel.item.sensorPrefix : "", out = [];
            for (const grp of g) for (const it of grp.items) if (pre && it.id.startsWith(pre)) out.push(it);
            if (dm.sel && dm.sel.group === "pocitac") for (const grp of g) if (grp.name.startsWith("Procesor")) for (const it of grp.items.slice(0, 6)) out.push(it);
            dm.live = out;
        } }
    property var uses: []
    Process { id: qUse; command: ["latte-sukromie"]
              stdout: StdioCollector { onStreamFinished: dm.uses = this.text.split("\n").filter(l => l).map(l => l.split("\t")) } }

    function need(p) { if (!p.running) p.running = true; }
    function refresh() {
        need(qList);
        const g = only || group;
        if (tab === "siete") { need(qNets); need(qSec); need(qAudio); return; }
        if (g === "zvuk") { need(qAudio); need(qCards); }
        if (g === "bluetooth") need(qBt);
        if (g === "siet") need(qNets);
        if (g === "napajanie") need(qPower);
        if (sel && (sel.item.sensorPrefix || sel.group === "pocitac")) need(qLive);
        if (g === "kamery" || g === "zvuk") need(qUse);
    }
    onActiveChanged: if (active) refresh(); else revert()
    onTabChanged: refresh()
    onGroupChanged: { sel = null; refresh(); if (curGroup && curGroup.items.length === 1) pick(curGroup, curGroup.items[0]); }
    Component.onCompleted: { if (only) group = only; refresh(); }
    Timer { interval: 4000; repeat: true; running: dm.active && dm.visible && dm.countdown === 0; onTriggered: dm.refresh() }

    Process { id: runner; onExited: later.restart() }
    Timer { id: later; interval: 400; onTriggered: dm.refresh() }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) status = msg; }
    // operácie so správcom: v termináli so sudo (ako Nastavenia › Používatelia)
    function sudo(script, title) {
        run(["foot", "-T", title, "sh", "-c", script + '; echo; printf "Enter zavrie okno"; read x'], title);
    }
    function refreshSel() {
        if (!sel) return;
        const g = groups.find(x => x.key === sel.group), it = g ? g.items.find(i => i.name === sel.item.name) : null;
        if (it) sel = { group: sel.group, item: it };
    }
    function pick(g, it) {
        sel = { group: g.key, item: it };
        if (g.key === "obrazovky" && it.mode) { pickMode = it.mode; pickScale = it.scale; }
        live = []; refresh();
    }
    function fix(f) {
        if (f.packages && f.packages.length && !f.repo) run(["latte-app", "instalator", "--nazov=Ovládač_" + f.name.replace(/[^\w]+/g, "_").slice(0, 30), "install"].concat(f.packages), "App Manager inštaluje " + f.packages.join(", "));
        else openWindow(["latte-app", "aplikacie", "aktualizacie"]);
    }

    // obrazovka: 15 s na potvrdenie, potom návrat (aj pri zatvorení)
    property string pickMode: ""
    property real pickScale: 1
    property int countdown: 0
    property var trial: null
    function tryDisplay() {
        const it = sel.item;
        trial = { connector: it.connector, mode: pickMode, scale: pickScale, before: it.mode, beforeScale: it.scale };
        run(["latte-devices", "display", "try", it.connector, pickMode, String(pickScale)], "Skúšam " + pickMode + " · mierka " + pickScale);
        countdown = 15; tick.start();
    }
    function keep() { if (!trial) return; tick.stop(); countdown = 0; run(["latte-devices", "display", "keep", trial.connector, trial.mode, String(trial.scale)], "Uložené"); trial = null; }
    function revert() { if (!trial) return; tick.stop(); countdown = 0; run(["latte-devices", "display", "try", trial.connector, trial.before, String(trial.beforeScale)], "Vrátené"); trial = null; }
    // odchod zo stránky počas skúšky = návrat (proces komponentu by zanikol s ním)
    Component.onDestruction: if (trial) Quickshell.execDetached(["latte-devices", "display", "try", trial.connector, trial.before, String(trial.beforeScale)])
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: { dm.countdown--; if (dm.countdown <= 0) dm.revert(); } }

    // Wi-Fi s heslom
    property string wifiSsid: ""
    property bool wifiSecure: false
    Process { id: wifiProc; stdinEnabled: true; onExited: (c) => { dm.status = c === 0 ? "Pripojené: " + dm.wifiSsid : "Pripojenie zlyhalo (heslo?)"; dm.wifiSsid = ""; later.restart(); } }
    function wifiConnect(pw) { wifiProc.stdinEnabled = true; wifiProc.command = ["latte-devices", "wifi", wifiSsid]; wifiProc.running = true; wifiProc.write(pw + "\n"); wifiProc.stdinEnabled = false; status = "Pripájam " + wifiSsid + "…"; }
    function pickWifi(w) { wifiSsid = w.ssid; wifiSecure = !!w.security; if (!wifiSecure) wifiConnect(""); }

    // pravý klik na zariadenie (ako vo Windows: vlastnosti, ovládač, akcie podľa druhu)
    function deviceMenu(g, it, x, y) {
        const det = it.details || {}, items = [{ glyph: "info-circle", label: "Vlastnosti", action: () => pick(g, it) }];
        const dev = det["zariadenie"] || "";
        if ((g.key === "disky" || g.key === "usb") && dev) {
            items.push({ glyph: "folder", label: "Otvoriť v Súboroch", action: () => run(["sh", "-c", 'm=$(lsblk -nro MOUNTPOINT "$1" | grep -m1 .); [ -n "$m" ] && exec latte-app subory "$m"; udisksctl mount -b "$1" >/dev/null 2>&1; m=$(lsblk -nro MOUNTPOINT "$1" | grep -m1 .); [ -n "$m" ] && exec latte-app subory "$m"', "sh", dev]) });
            if (g.key === "usb" || /usb/i.test(det["pripojenie"] || ""))
                items.push({ glyph: "usb", label: "Bezpečne odobrať", action: () => safeRemove(dev, it.name) });
        }
        if (g.key === "siet") {
            const ifc = (it.name.match(/·\s*(\S+)$/) || [])[1] || "", on = (det["stav"] || "") === "connected";
            if (ifc) items.push({ glyph: on ? "world-off" : "world", label: on ? "Odpojiť" : "Pripojiť", action: () => run(["nmcli", "device", on ? "disconnect" : "connect", ifc]) });
        }
        if (it.state && it.state !== "ok" && it.state !== "off") items.push({ glyph: "download", label: "Opraviť ovládač", action: () => fix(it) });
        items.push({ glyph: "download", label: "Aktualizovať ovládač (App Manager)", action: () => openWindow(["latte-app", "aplikacie", "aktualizacie"]) });
        items.push({ separator: true });
        const info = it.name + "\n" + it.sub + Object.keys(det).map(k => "\n" + k + ": " + det[k]).join("");
        items.push({ glyph: "clipboard", label: "Kopírovať informácie", action: () => run(["wl-copy", "--", info], "Skopírované") });
        menu.open(x, y, items, it.name);
    }
    function safeRemove(dev, name) {
        run(["sh", "-c", 'for p in $(lsblk -nro PATH "$1" | tail -n +2) "$1"; do udisksctl unmount -b "$p" 2>/dev/null; done; udisksctl power-off -b "$1" && notify-send -a LatteOS "Môžeš odpojiť" "$2"', "sh", dev, name], "Odoberám " + name);
    }

    // ── spoločné prvky ─────────────────────────────────────────────────────────────
    component H: Text { color: dm.t.fgDim; topPadding: 6; font { family: dm.t.fontUi; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.6 } }
    component Note: Text { width: parent ? parent.width : 200; wrapMode: Text.WordWrap; color: dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 12 } }
    component Btn: Rectangle {
        id: bn
        property string label; property string glyph: ""; property bool primary: false; property bool on: false; property bool enabled: true
        signal clicked()
        width: bl.implicitWidth + (glyph ? 44 : 24); height: 32; radius: 9; opacity: enabled ? 1 : 0.45
        color: primary ? dm.t.primary : (on ? Qt.rgba(dm.t.primary.r, dm.t.primary.g, dm.t.primary.b, 0.2) : (bm.containsMouse && enabled ? dm.t.hover : dm.t.field))
        border { color: on ? dm.t.primary : "transparent"; width: 1 }
        Glyph { visible: bn.glyph !== ""; x: 11; anchors.verticalCenter: parent.verticalCenter; name: bn.glyph || "x"; size: 15; color: bn.primary ? dm.t.fgOnPrimary : dm.t.primary }
        Text { id: bl; x: bn.glyph ? 33 : 12; anchors.verticalCenter: parent.verticalCenter; text: bn.label; color: bn.primary ? dm.t.fgOnPrimary : dm.t.fg
               font { family: dm.t.fontUi; pixelSize: 12; weight: Font.DemiBold } }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; enabled: bn.enabled; onClicked: bn.clicked() }
    }
    component Slider: Item {
        id: sl
        property real from: 0; property real to: 100; property real value: 0; property bool enabled: true
        signal moved(real v)
        height: 24; opacity: enabled ? 1 : 0.45
        readonly property real frac: Math.max(0, Math.min(1, ((sm.pressed ? sm.v : value) - from) / (to - from)))
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: dm.t.field }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.max(6, parent.width * sl.frac); height: 6; radius: 3; color: dm.t.primary }
        Rectangle { x: (parent.width - 16) * sl.frac; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: dm.t.fg; border { color: dm.t.primary; width: 2 } }
        MouseArea { id: sm; anchors.fill: parent; enabled: sl.enabled; property real v: 0
                    function at(x) { return Math.round(sl.from + Math.max(0, Math.min(1, x / width)) * (sl.to - sl.from)); }
                    onPressed: (m) => v = at(m.x); onPositionChanged: (m) => v = at(m.x); onReleased: sl.moved(v)
                    onWheel: (w) => sl.moved(Math.max(sl.from, Math.min(sl.to, sl.value + (w.angleDelta.y > 0 ? 5 : -5)))) }
    }
    component Row2: Row {                        // riadok „názov · hodnota“ s ovládaním vpravo
        id: r2
        property string label; property string sub: ""; property string glyph: ""; property bool picked: false
        default property alias tools: tl.data
        signal clicked()
        width: parent ? parent.width : 300; spacing: 8
        Rectangle {
            width: r2.width - tl.width - (tl.width ? 8 : 0); height: 36; radius: 9
            color: r2.picked ? Qt.rgba(dm.t.primary.r, dm.t.primary.g, dm.t.primary.b, 0.18) : (rm.containsMouse ? dm.t.hover : dm.t.field)
            border { color: r2.picked ? dm.t.primary : "transparent"; width: 1 }
            Glyph { visible: r2.glyph !== ""; x: 10; anchors.verticalCenter: parent.verticalCenter; name: r2.glyph || "x"; size: 15; color: r2.picked ? dm.t.primary : dm.t.fgDim }
            Column { x: r2.glyph ? 32 : 10; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter
                     Text { width: parent.width; elide: Text.ElideRight; text: r2.label; color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 12; weight: r2.picked ? Font.Bold : Font.Normal } }
                     Text { visible: r2.sub !== ""; width: parent.width; elide: Text.ElideRight; text: r2.sub; color: dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 10 } } }
            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; onClicked: r2.clicked() }
        }
        Row { id: tl; spacing: 4; anchors.verticalCenter: parent.verticalCenter }
    }

    // ── hlavička: karty ─────────────────────────────────────────────────────────────
    Row {
        id: tabs
        visible: dm.only === ""
        x: 0; y: 0; spacing: 6; height: visible ? 34 : 0
        Repeater {
            model: [["zariadenia", "Zariadenia", "cpu"], ["siete", "Siete", "network"]]
            Btn { required property var modelData; label: modelData[1]; glyph: modelData[2]; on: dm.tab === modelData[0]
                  onClicked: { dm.tab = modelData[0]; if (modelData[0] === "zariadenia") dm.group = ""; } }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; width: dm.width - 260; elide: Text.ElideRight
               text: dm.tab === "zariadenia" ? (dm.faults.length ? "⚠ " + dm.summary : dm.summary) : (dm.nets.addresses.join(" · ") || "")
               color: dm.faults.length && dm.tab === "zariadenia" ? dm.t.error : dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 12 } }
    }

    Flickable {
        id: fl
        anchors { left: parent.left; right: parent.right; top: tabs.bottom; topMargin: tabs.visible ? 10 : 0; bottom: parent.bottom }
        contentHeight: body.implicitHeight + 12; clip: true; boundsBehavior: Flickable.StopAtBounds; interactive: !dm.embedded
        ScrollHint { flick: fl; colors: dm.t }
        Column {
            id: body
            width: fl.width - 8; spacing: 10

            // ═══ Zariadenia · dlaždice kategórií ═══════════════════════════════════
            Grid {
                visible: dm.tab === "zariadenia" && dm.group === "" && dm.only === ""
                columns: dm.compact ? 3 : 4; spacing: 8; width: body.width
                Repeater {
                    model: dm.ordered
                    Rectangle {
                        id: ct
                        required property var modelData
                        readonly property bool empty: modelData.items.length === 0
                        readonly property var bad: modelData.items.filter(i => i.state && i.state !== "ok" && i.state !== "off")
                        width: (body.width - (dm.compact ? 16 : 24)) / (dm.compact ? 3 : 4); height: 70; radius: 14
                        color: cm.containsMouse ? dm.t.hover : dm.t.field; opacity: empty ? 0.5 : 1
                        border { color: bad.length ? dm.t.error : "transparent"; width: 1.5 }
                        Rectangle { id: ci; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44; radius: 12
                                    color: Qt.rgba(dm.t.primary.r, dm.t.primary.g, dm.t.primary.b, 0.14)
                                    Glyph { anchors.centerIn: parent; name: ct.modelData.glyph; size: 22; color: dm.t.primary } }
                        Column { anchors { left: ci.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } spacing: 2
                                 Text { width: parent.width; elide: Text.ElideRight; text: ct.modelData.title; color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 13; weight: Font.Bold } }
                                 Text { width: parent.width; elide: Text.ElideRight
                                        text: ct.bad.length ? "⚠ " + ct.bad[0].stateTitle : (ct.empty ? "nič nepripojené" : (ct.modelData.items.length === 1 ? ct.modelData.items[0].name : dm.count(ct.modelData.items.length)))
                                        color: ct.bad.length ? dm.t.error : dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 11 } } }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: dm.group = ct.modelData.key }
                    }
                }
            }
            Repeater {                                   // problémy s tlačidlom Doinštalovať
                model: dm.tab === "zariadenia" && dm.group === "" ? dm.faults : []
                Row2 { required property var modelData; glyph: "alert-triangle"; label: modelData.name + " · " + modelData.stateTitle; sub: modelData.reason
                       Btn { label: modelData.packages.length && !modelData.repo ? "Doinštalovať" : "App Manager"; primary: true; onClicked: dm.fix(modelData) } }
            }

            // ═══ Zariadenia · kategória ════════════════════════════════════════════
            Row {
                visible: dm.tab === "zariadenia" && dm.group !== "" && dm.only === "" && dm.compact
                spacing: 8
                Btn { label: "Všetky zariadenia"; glyph: "arrow-left"; onClicked: dm.group = "" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: dm.curGroup ? dm.curGroup.title : ""; color: dm.t.fg
                       font { family: dm.t.fontDisplay; pixelSize: 18; weight: Font.DemiBold } }
            }
            Column {
                visible: dm.tab === "zariadenia" && dm.group !== ""
                width: body.width; spacing: 6
                Note { visible: !!dm.curGroup && dm.curGroup.items.length === 0; text: "Nič nepripojené." }
                Repeater {
                    model: dm.curGroup ? dm.curGroup.items : []
                    Rectangle {
                        id: dv
                        required property var modelData
                        readonly property bool picked: !!dm.sel && dm.sel.item.name === modelData.name
                        readonly property bool bad: !!modelData.state && modelData.state !== "ok" && modelData.state !== "off"
                        width: parent.width; height: 48; radius: 11
                        color: picked ? Qt.rgba(dm.t.primary.r, dm.t.primary.g, dm.t.primary.b, 0.16) : (dvm.containsMouse ? dm.t.hover : dm.t.field)
                        border { color: picked ? dm.t.primary : (bad ? dm.t.error : "transparent"); width: 1.2 }
                        Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; name: dm.curGroup ? dm.curGroup.glyph : "cpu"; size: 20; color: dv.bad ? dm.t.error : dm.t.primary }
                        Column { x: 44; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter
                                 Text { width: parent.width; elide: Text.ElideRight; text: dv.modelData.name; color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 13; weight: Font.Bold } }
                                 Text { width: parent.width; elide: Text.ElideRight; color: dv.bad ? dm.t.error : dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 11 }
                                        text: (dv.bad ? "⚠ " + dv.modelData.stateTitle + " · " : ({ ok: "● ", warn: "! ", off: "○ " })[dv.modelData.status] || "") + dv.modelData.sub } }
                        MouseArea { id: dvm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (m) => { dm.pick(dm.curGroup, dv.modelData); if (m.button === Qt.RightButton) { const q = mapToItem(dm, m.x, m.y); dm.deviceMenu(dm.curGroup, dv.modelData, q.x, q.y); } } }
                    }
                }

                // ── vybrané zariadenie: stav, oprava, vlastnosti ──
                Column {
                    id: dd
                    visible: !!dm.sel
                    width: parent.width; spacing: 6; topPadding: 4
                    readonly property var it: dm.sel ? dm.sel.item : null
                    readonly property bool bad: !!it && !!it.state && it.state !== "ok" && it.state !== "off"
                    Row2 { visible: dd.bad; glyph: "alert-triangle"; label: dd.it ? dd.it.stateTitle : ""; sub: dd.it ? dd.it.reason : ""
                           Btn { label: dd.it && dd.it.packages && dd.it.packages.length && !dd.it.repo ? "Doinštalovať" : "App Manager"; primary: true; onClicked: dm.fix(dd.it) } }
                    Text { visible: (dm.group === "kamery" || dm.group === "zvuk") && dm.uses.length > 0; width: parent.width; wrapMode: Text.WordWrap
                           color: dm.t.error; font { family: dm.t.fontUi; pixelSize: 12; weight: Font.Bold }
                           text: dm.uses.filter(u => (dm.group === "kamery") === (u[0] === "camera")).map(u => "Práve používa: " + u[1]).join("\n") }
                    Flow {                               // živé hodnoty z Monitora
                        visible: dm.live.length > 0; width: parent.width; spacing: 6
                        Repeater { model: dm.live.slice(0, 8)
                            Rectangle { required property var modelData; width: lvt.implicitWidth + 16; height: 26; radius: 8; color: dm.t.field
                                        Text { id: lvt; anchors.centerIn: parent; text: modelData.label + "  " + String(modelData.value).replace(".", ",") + " " + modelData.unit
                                               color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 11 } } } }
                    }
                    Grid {                               // vlastnosti (ako karta Všeobecné vo Windows)
                        columns: 2; columnSpacing: 10; rowSpacing: 2; width: parent.width
                        Repeater {
                            model: dd.it ? Object.keys(dd.it.details || {}).reduce((a, k) => a.concat([k, String(dd.it.details[k])]), []) : []
                            Text { required property string modelData; required property int index
                                   width: index % 2 ? dd.width - 130 : 120; elide: index % 2 ? Text.ElideMiddle : Text.ElideRight; text: modelData
                                   color: index % 2 ? dm.t.fg : dm.t.fgDim; font { family: dm.t.fontUi; pixelSize: 11 } }
                        }
                    }
                }

                // ── softvér ovládača: ZVUK ──
                Column {
                    visible: dm.group === "zvuk"
                    width: parent.width; spacing: 5
                    H { text: "VÝSTUP (klik = predvolený)" }
                    Repeater { model: dm.audio.sinks
                        Row2 { required property var modelData; glyph: "volume"; label: modelData.desc; sub: modelData.mute ? "stlmené" : modelData.volume + " %"; picked: modelData.default
                               onClicked: dm.run(["latte-devices", "audio", "default", "sink", modelData.name])
                               Slider { width: 110; anchors.verticalCenter: parent.verticalCenter; to: 150; value: modelData.volume
                                        onMoved: (v) => dm.run(["latte-devices", "audio", "volume", "sink", modelData.name, String(v)]) }
                               Btn { glyph: modelData.mute ? "volume-off" : "volume"; label: modelData.mute ? "Zapnúť" : "Stlmiť"; onClicked: dm.run(["latte-devices", "audio", "mute", "sink", modelData.name]) } } }
                    H { text: "VSTUP (mikrofón)" }
                    Repeater { model: dm.audio.sources
                        Row2 { required property var modelData; glyph: "microphone"; label: modelData.desc; sub: modelData.mute ? "stlmené" : modelData.volume + " %"; picked: modelData.default
                               onClicked: dm.run(["latte-devices", "audio", "default", "source", modelData.name])
                               Btn { label: modelData.mute ? "Zapnúť" : "Stlmiť"; onClicked: dm.run(["latte-devices", "audio", "mute", "source", modelData.name]) } } }
                    // konektory a konfigurácia reproduktorov každej karty (softvér zvukovky: priradenie jackov a kanálov)
                    Repeater {
                        model: dm.cards.cards
                        Column {
                            id: card
                            required property var modelData
                            width: parent.width; spacing: 4
                            readonly property var sinkName: Object.keys(dm.cards.active).find(k => dm.cards.active[k].kind === "sink" && k.indexOf(modelData.name.replace("alsa_card.", "")) >= 0) || ""
                            readonly property var srcName: Object.keys(dm.cards.active).find(k => dm.cards.active[k].kind === "source" && !k.endsWith(".monitor") && k.indexOf(modelData.name.replace("alsa_card.", "")) >= 0) || ""
                            H { text: "KONEKTORY · " + card.modelData.desc.toUpperCase() }
                            Flow { width: parent.width; spacing: 5
                                Repeater { model: card.modelData.ports
                                    Btn { required property var modelData
                                          readonly property string dev: modelData.dir === "out" ? card.sinkName : card.srcName
                                          glyph: modelData.dir === "out" ? "volume" : "microphone"
                                          label: modelData.desc + (modelData.plugged ? "" : " (nepripojené)")
                                          on: dev !== "" && dm.cards.active[dev] && dm.cards.active[dev].port === modelData.name
                                          enabled: dev !== ""
                                          onClicked: dm.run(["latte-devices", "audio", "port", modelData.dir === "out" ? "sink" : "source", dev, modelData.name], "Konektor: " + modelData.desc) } } }
                            H { text: "KONFIGURÁCIA (kanály)" }
                            Flow { width: parent.width; spacing: 5
                                Repeater { model: card.modelData.profiles.filter(p => p.available)
                                    Btn { required property var modelData; label: modelData.desc; on: card.modelData.active === modelData.name
                                          onClicked: dm.run(["latte-devices", "audio", "profil", card.modelData.name, modelData.name], "Profil: " + modelData.desc) } } }
                        }
                    }
                    H { text: "APLIKÁCIE" }
                    Note { visible: dm.audio.apps.length === 0; text: "Žiadna aplikácia teraz nehrá." }
                    Repeater { model: dm.audio.apps
                        Row2 { required property var modelData; glyph: "player-play"; label: modelData.name; sub: modelData.media
                               Slider { width: 110; anchors.verticalCenter: parent.verticalCenter; to: 150; value: modelData.volume
                                        onMoved: (v) => dm.run(["latte-devices", "audio", "volume", "app", modelData.id, String(v)]) }
                               Btn { glyph: modelData.mute ? "volume-off" : "volume"; label: ""; onClicked: dm.run(["latte-devices", "audio", "mute", "app", modelData.id]) }
                               // prehrávať na inom výstupe (napr. Spotify na AirPlay receiveri v obývačke)
                               Btn { glyph: "cast"; label: ""; onClicked: { const q = mapToItem(dm, 0, height), a = modelData;
                                     menu.open(q.x, q.y, dm.audio.sinks.map(k => ({ glyph: k.net ? "cast" : "device-speaker", label: k.desc, checked: k.id === a.sink,
                                                                               action: () => dm.run(["latte-devices", "audio", "presun", a.id, k.name], a.name + " → " + k.desc) }))
                                                         .concat([{ separator: true }, { glyph: "radar", label: "Nájsť výstupy v sieti…", action: () => { dm.tab = "siete"; } }]),
                                               "Prehrávať " + a.name + " na"); } } } }
                }

                // ── OBRAZOVKY: rozlíšenie, mierka, potvrdenie ──
                Column {
                    visible: dm.group === "obrazovky" && !!dd.it && !!dd.it.modes
                    width: parent.width; spacing: 6
                    H { text: "ROZLÍŠENIE" }
                    Flow { width: parent.width; spacing: 5
                        Repeater { model: dd.it && dd.it.modes ? dd.it.modes.slice(0, 12) : []
                            Btn { required property string modelData; label: modelData.replace("x", " × ").replace("@", " · ") + " Hz"; on: dm.pickMode === modelData; onClicked: dm.pickMode = modelData } } }
                    H { text: "MIERKA" }
                    Row { spacing: 5
                        Repeater {
                            model: { const r = dm.pickMode.match(/^(\d+)x(\d+)/), w = r ? parseInt(r[1]) : 0, h = r ? parseInt(r[2]) : 0;
                                     return [1, 1.25, 1.5, 1.75, 2].filter(sc => sc === 1 || (Number.isInteger(w / sc) && Number.isInteger(h / sc))); }
                            Btn { required property real modelData; label: (modelData * 100) + " %"; on: Math.abs(dm.pickScale - modelData) < 0.01; onClicked: dm.pickScale = modelData } } }
                    Row { spacing: 8; visible: dm.countdown === 0
                          Btn { label: "Použiť"; primary: !!dd.it && (dm.pickMode !== dd.it.mode || Math.abs(dm.pickScale - dd.it.scale) > 0.01); onClicked: if (primary) dm.tryDisplay() } }
                    Row2 { visible: dm.countdown > 0; glyph: "clock"; label: "Ponechať toto nastavenie? Návrat o " + dm.countdown + " s."
                           Btn { label: "Ponechať"; primary: true; onClicked: dm.keep() }
                           Btn { label: "Vrátiť"; onClicked: dm.revert() } }
                }

                // ── SIEŤ: Wi-Fi ──
                Column {
                    visible: dm.group === "siet"
                    width: parent.width; spacing: 5
                    H { text: "WI-FI V OKOLÍ" }
                    Note { visible: dm.nets.wifi.length === 0; text: "Žiadna Wi-Fi karta alebo sieť v dosahu." }
                    Repeater { model: dm.nets.wifi.slice(0, 8)
                        Row2 { required property var modelData; glyph: "wifi"; label: modelData.ssid; sub: (modelData.security ? "🔒 " : "") + modelData.signal + " %"; picked: modelData.inUse
                               onClicked: dm.pickWifi(modelData) } }
                    Btn { label: "Siete a VPN"; glyph: "network"; onClicked: dm.tab = "siete" }
                }

                // ── BLUETOOTH ──
                Column {
                    visible: dm.group === "bluetooth"
                    width: parent.width; spacing: 5
                    Note { visible: !dm.bt.available; text: "Tento počítač nemá Bluetooth adaptér (alebo je vypnutý v BIOSe)." }
                    Row { visible: dm.bt.available; spacing: 6
                          Btn { label: dm.bt.powered ? "Vypnúť Bluetooth" : "Zapnúť Bluetooth"; glyph: "bluetooth"; on: dm.bt.powered
                                onClicked: dm.run(["latte-devices", "bt", dm.bt.powered ? "vypni" : "zapni"]) }
                          Btn { label: qBtScan.running ? "Hľadám…" : "Pridať zariadenie"; glyph: "plus"; enabled: dm.bt.powered && !qBtScan.running
                                onClicked: { dm.status = "Hľadám zariadenia (8 s)…"; qBtScan.running = true; } } }
                    Repeater { model: dm.bt.devices
                        Row2 { required property var modelData; glyph: "bluetooth"; label: modelData.name
                               sub: (modelData.connected ? "pripojené" : modelData.paired ? "spárované" : "nové") + (modelData.battery !== null ? " · batéria " + modelData.battery + " %" : "")
                               picked: modelData.connected
                               Btn { label: modelData.connected ? "Odpojiť" : (modelData.paired ? "Pripojiť" : "Spárovať")
                                     onClicked: dm.run(["latte-devices", "bt", modelData.connected ? "odpoj" : (modelData.paired ? "pripoj" : "sparuj"), modelData.mac], modelData.name) }
                               Btn { visible: modelData.paired; label: "Zabudnúť"; onClicked: dm.run(["latte-devices", "bt", "zabudni", modelData.mac]) } } }
                }

                // ── napájanie: režim ──
                Column {
                    visible: dm.group === "napajanie"
                    width: parent.width; spacing: 6
                    H { text: "REŽIM NAPÁJANIA" }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater { model: dm.power.list
                            Btn { required property string modelData; label: dm.powerNames[modelData] || modelData; glyph: "bolt"
                                  on: !dm.power.game && dm.power.cur === modelData
                                  onClicked: dm.run(["powerprofilesctl", "set", modelData], "Režim: " + label) } }
                        Btn { label: "Herný režim"; glyph: "device-gamepad"; on: dm.power.game
                              onClicked: dm.run(["hyprctl", "eval", "latte.game(" + !dm.power.game + ")"], dm.power.game ? "Herný režim vypnutý" : "Herný režim zapnutý") }
                    }
                    Note { visible: dm.power.list.length === 0; text: "Profily výkonu nie sú dostupné (power-profiles-daemon)." }
                }

                // ── ostatné kategórie: nástroje ──
                Flow {
                    width: parent.width; spacing: 6
                    Btn { visible: dm.group === "napajanie"; label: "Uspávanie a vypnutie obrazovky"; glyph: "moon"; onClicked: dm.openWindow(["latte-app", "nastavenia", "uzamknutie"]) }
                    Btn { visible: dm.group === "vstup"; label: "Myš a touchpad"; glyph: "mouse"; onClicked: dm.openWindow(["latte-app", "nastavenia", "vstup"]) }
                    Btn { visible: dm.group === "vstup"; label: "Klávesnica a skratky"; glyph: "keyboard"; onClicked: dm.openWindow(["latte-app", "nastavenia", "klavesnica"]) }
                    Btn { visible: dm.group === "grafika"; label: "Stupeň výkonu"; glyph: "bolt"; onClicked: dm.openWindow(["latte-app", "nastavenia", "vykon"]) }
                    Btn { visible: dm.group === "grafika" || dm.group === "pocitac"; label: "Hardvér v Monitore"; glyph: "activity"; onClicked: dm.openWindow(["latte-app", "monitor", "hardver"]) }
                    Btn { visible: dm.group === "tlac"; label: "Tlačiarne (CUPS)"; glyph: "printer"; onClicked: dm.openWindow(["xdg-open", "http://localhost:631/printers"]) }
                    Btn { visible: (dm.group === "disky" || dm.group === "usb") && !!dd.it; label: "Otvoriť v Súboroch"; glyph: "folder"
                          onClicked: dm.openWindow(["latte-app", "subory"]) }
                    Btn { visible: (dm.group === "usb" || dm.group === "disky") && !!dd.it && !!(dd.it.details || {})["zariadenie"] && /usb/i.test(((dd.it.details || {})["pripojenie"] || "") + dm.group)
                          label: "Bezpečne odobrať"; glyph: "usb"; onClicked: dm.safeRemove(dd.it.details["zariadenie"], dd.it.name) }
                    Btn { visible: dm.group === "kamery" || dm.group === "zvuk"; label: "Kto smie mikrofón a kameru"; glyph: "shield"; onClicked: dm.openWindow(["latte-app", "aplikacie", "opravnenia"]) }
                    Btn { visible: dm.group === "grafika" || dm.group === "siet" || dm.group === "ostatne"; label: "Ovládače a firmvér"; glyph: "download"; onClicked: dm.openWindow(["latte-app", "aplikacie", "aktualizacie"]) }
                }
            }

            // ═══ Siete ═════════════════════════════════════════════════════════════
            Column {
                visible: dm.tab === "siete"
                width: body.width; spacing: 5
                H { text: "PRIPOJENIA" }
                Repeater { model: dm.nets.connections.filter(c => !c.vpn)
                    Row2 { required property var modelData; glyph: modelData.type === "Wi-Fi" ? "wifi" : "network"; label: modelData.name
                           sub: modelData.type + (modelData.device ? " · " + modelData.device : "") + (modelData.active ? " · pripojené" : "") + (modelData.auto ? " · automaticky" : "")
                           picked: modelData.active
                           Btn { label: modelData.active ? "Odpojiť" : "Pripojiť"; onClicked: dm.run(["latte-devices", "siet", modelData.active ? "odpoj" : "pripoj", modelData.name]) }
                           Btn { label: "…"; onClicked: { const q = mapToItem(dm, 0, height), c = modelData;
                                 menu.open(q.x, q.y, [{ glyph: "settings", label: "Upraviť (nmtui)", action: () => dm.run(["foot", "-e", "nmtui", "edit", c.name]) },
                                                      { glyph: "trash", label: "Zabudnúť", danger: true, action: () => dm.run(["latte-devices", "siet", "zabudni", c.name]) }], c.name); } } } }
                H { text: "WI-FI V OKOLÍ" }
                Note { visible: dm.nets.wifi.length === 0; text: "Žiadna Wi-Fi karta alebo sieť v dosahu." }
                Repeater { model: dm.nets.wifi.slice(0, 10)
                    Row2 { required property var modelData; glyph: "wifi"; label: modelData.ssid; sub: (modelData.security ? "🔒 " + modelData.security + " · " : "") + modelData.signal + " %"
                           picked: modelData.inUse; onClicked: dm.pickWifi(modelData) } }
                Rectangle {
                    visible: dm.wifiSsid !== "" && dm.wifiSecure
                    width: parent.width; height: 40; radius: 9; color: dm.t.field; border { color: dm.t.primary; width: 1 }
                    Text { id: wl; x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Heslo pre " + dm.wifiSsid + ":"; color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 12 } }
                    TextInput { id: wpw; anchors { left: wl.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                echoMode: TextInput.Password; passwordCharacter: "•"; color: dm.t.fg; font { family: dm.t.fontUi; pixelSize: 13 }
                                onVisibleChanged: if (visible) forceActiveFocus()
                                Keys.onReturnPressed: (ev) => { ev.accepted = true; dm.wifiConnect(text); text = ""; }
                                Keys.onEscapePressed: (ev) => { ev.accepted = true; dm.wifiSsid = ""; } }
                }
                // ── inšpektor siete (ako ESET Network Inspector): radar, identifikácia zariadení (common/InspektorSiete.qml) ──
                H { text: "SIEŤ OKOLO · INŠPEKTOR" }
                InspektorSiete {
                    id: inspView
                    theme: dm.t; compact: dm.compact
                    width: parent.width; height: implicitHeight
                    active: dm.active && dm.tab === "siete"
                    onOpenWindow: (a) => dm.openWindow(a)
                }

                // ── zvuk do siete: AirPlay/Snapcast priamo v PipeWire, Spotify Connect v Spotify, DLNA a Chromecast doinštalovať ──
                H { text: "ZVUK DO SIETE" }
                Row2 { glyph: "cast"; label: "Prijímače AirPlay ako zvukové výstupy"; picked: !!dm.insp.airplay
                       sub: dm.insp.airplay ? "zapnuté · receivery a Apple TV sú v zozname výstupov (Zvuk › Aplikácie › ikona vysielania)" : "vypnuté"
                       Btn { label: dm.insp.airplay ? "Vypnúť" : "Zapnúť"
                             onClicked: { dm.run(["latte-inspektor", "airplay", dm.insp.airplay ? "vypni" : "zapni"], "AirPlay " + (dm.insp.airplay ? "vypnuté" : "zapnuté"));
                                          inspView.net = Object.assign({}, inspView.net, { airplay: !dm.insp.airplay }); } } }
                Repeater { model: dm.insp.audio || []
                    Row2 { required property var modelData
                           readonly property var sink: modelData.via === "airplay" || modelData.via === "snapcast" ? dm.netSinkFor(modelData.name) : null
                           glyph: modelData.via === "spotify" ? "player-play" : "device-speaker"; label: modelData.name + " · " + modelData.ip; sub: modelData.how
                           Btn { visible: !!sink; label: "Prehrávať sem"; primary: true
                                 onClicked: dm.run(["latte-devices", "audio", "default", "sink", sink.name], "Zvuk ide do: " + modelData.name) }
                           Btn { visible: !modelData.ready; label: "App Manager"; onClicked: dm.openWindow(["latte-app", "aplikacie", "objavovat"]) } } }
                Note { visible: (dm.insp.audio || []).length === 0
                       text: "V sieti zatiaľ nie je receiver, televízor ani reproduktor, ktorý by prijímal zvuk. Spotify vie hrať na zariadenia so Spotify Connect aj sám (ikona zariadení v Spotify)." }

                H { text: "VPN A TUNELY" }
                Repeater { model: dm.nets.connections.filter(c => c.vpn)
                    Row2 { required property var modelData; glyph: "lock"; label: modelData.name; sub: modelData.type + (modelData.active ? " · pripojené" : ""); picked: modelData.active
                           Btn { label: modelData.active ? "Odpojiť" : "Pripojiť"; onClicked: dm.run(["latte-devices", "siet", modelData.active ? "odpoj" : "pripoj", modelData.name]) } } }
                Repeater { model: dm.sec.tunnels
                    Row2 { required property var modelData; glyph: "arrows-move"; label: "SSH tunel (PID " + modelData.pid + ")"; sub: modelData.cmd
                           Btn { label: "Ukončiť"; onClicked: dm.run(["kill", String(modelData.pid)], "Tunel ukončený") } } }
                Note { visible: dm.nets.connections.filter(c => c.vpn).length === 0 && dm.sec.tunnels.length === 0; text: "Žiadna VPN ani tunel." }
                Row { spacing: 6
                      Btn { label: "Pridať VPN / WireGuard"; glyph: "plus"; onClicked: dm.run(["foot", "-e", "nmtui", "connect"]) }
                      Btn { label: "Pridať SSH tunel"; glyph: "plus"; onClicked: menu.open(0, fl.y + 40, [{ input: "ssh -N -L 8080:localhost:80 meno@server", label: "Príkaz tunela",
                            action: (c) => { if (/^ssh\s/.test(c)) dm.run(["sh", "-c", c + " >/dev/null 2>&1 &"], "Tunel spustený"); } }], "SSH tunel (-L miestny, -R vzdialený, -D SOCKS)") } }
                H { text: "SSH SERVER (vzdialený prístup do tohto PC)" }
                Row2 { glyph: "terminal-2"; label: dm.sec.ssh.active ? "Beží na porte " + dm.sec.ssh.port : "Vypnutý"
                       sub: dm.sec.ssh.enabled ? "spúšťa sa pri štarte" : "nespúšťa sa pri štarte"; picked: !!dm.sec.ssh.active
                       Btn { label: dm.sec.ssh.active ? "Vypnúť" : "Zapnúť"
                             onClicked: dm.sudo(dm.sec.ssh.active ? "sudo systemctl disable --now sshd" : "sudo systemctl enable --now sshd", "SSH server") } }
                H { text: "FIREWALL" }
                Row2 { glyph: "shield"; label: dm.sec.firewall.active ? "Zapnutý · predvolená zóna " + dm.sec.firewall.default : "Vypnutý"
                       sub: dm.sec.firewall.zones.map(z => z.name + " (" + z.interfaces.join(", ") + ")").join(" · "); picked: !!dm.sec.firewall.active
                       Btn { label: dm.sec.firewall.active ? "Vypnúť" : "Zapnúť"; onClicked: dm.sudo(dm.sec.firewall.active ? "sudo systemctl disable --now firewalld" : "sudo systemctl enable --now firewalld", "Firewall") } }
                Repeater { model: dm.fwFull && dm.fwFull.ok ? [] : dm.sec.firewall.zones
                    Note { required property var modelData; text: "Povolené (predvolené pre zónu " + modelData.name + "): " + modelData.services.concat(modelData.ports).join(", ") } }
                Column {
                    visible: !!dm.fwFull && dm.fwFull.ok
                    width: parent.width; spacing: 4
                    Repeater { model: dm.fwFull && dm.fwFull.ok ? [["Služby", "services"], ["Porty", "ports"], ["Presmerovanie portov", "forward_ports"], ["Bohaté pravidlá", "rich_rules"]] : []
                        Note { required property var modelData; text: modelData[0] + ": " + ((dm.fwFull[modelData[1]] || []).join(", ") || "žiadne") } }
                }
                Row { spacing: 6
                      Btn { label: dm.fwFull && dm.fwFull.ok ? "Obnoviť pravidlá" : "Zobraziť všetky pravidlá"; glyph: "list-tree"; onClicked: { dm.status = "Firewall sa môže opýtať na heslo…"; qFw.running = true; } }
                      Btn { label: "Povoliť port…"; glyph: "plus"
                            onClicked: menu.open(0, fl.y + 60, [{ input: "8080/tcp", label: "Port/protokol",
                                action: (p) => { if (/^\d+(-\d+)?\/(tcp|udp)$/.test(p)) dm.sudo("sudo firewall-cmd --permanent --add-port=" + p + " && sudo firewall-cmd --reload", "Firewall: povoliť " + p); } }], "Povoliť prichádzajúce spojenia na port") }
                      Btn { label: "Presmerovať port…"; glyph: "arrows-move"
                            onClicked: menu.open(0, fl.y + 60, [{ input: "8080:tcp:80", label: "zdroj:protokol:cieľ",
                                action: (p) => { const m = p.match(/^(\d+):(tcp|udp):(\d+)(?::([\d.]+))?$/); if (m) dm.sudo("sudo firewall-cmd --permanent --add-forward-port=port=" + m[1] + ":proto=" + m[2] + ":toport=" + m[3] + (m[4] ? ":toaddr=" + m[4] : "") + " && sudo firewall-cmd --reload", "Firewall: presmerovanie " + p); } }],
                                "Presmerovanie: port:protokol:cieľový port[:adresa]") } }
                H { text: "ADRESY" }
                Note { text: dm.nets.addresses.join(" · ") || "žiadne" }

            }
            Note { visible: dm.status !== ""; text: dm.status; color: dm.t.primary }
            Note { visible: dm.problems.length > 0 && dm.tab === "zariadenia"; text: "! " + dm.problems.join(" · "); color: dm.t.error }
        }
    }
    ContextMenu { id: menu; theme: dm.t }
}
