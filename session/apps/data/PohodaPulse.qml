// Monitor › Čas v aplikáciách — stránky podľa Pulse (Microsoft Store, inšpirácia; kód vlastný):
//   prehlad    „Dobré popoludnie“: dnešný čas s kruhom (cieľ), rozdelenie na aplikácie, týždeň, najviac dnes,
//              Sústredenie, denný cieľ, sluch, kategórie
//   obrazovka  čas pred obrazovkou: časová os dňa, sedenia, najdlhší úsek, prestávky
//   sustredenie  sedenie 15–90 min, rozptýlenia upozorniť / odsunúť, história, kategórie aplikácií
//   sluch      hlasné počúvanie v slúchadlách (odhad podľa hlasitosti), os dňa, prah, odporúčanie WHO
//   prehlady   týždeň: priemer, spolu vs minulý týždeň, práca vs zábava, top aplikácie, sedenia sústredenia
// Dáta: latte-sysmon pohoda-den DNES (pole pulse), stav sústredenia $XDG_RUNTIME_DIR/latteos/fokus.json.
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Item {
    id: pp
    required property var theme
    property string page: "prehlad"
    signal openApps()
    signal status(string text)

    readonly property bool anim: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos"
    property var d: null
    readonly property var p: d ? d.pulse : null
    property var focusState: ({ active: false })
    property string nowApp: ""
    property int nowTick: 0
    property int focusMins: 25
    property string focusMode: "upozornit"
    property var catOver: ({})
    readonly property var palette: [theme.primary, "#8E7CC3", "#6FB3A6", "#E0875F", "#C9A227", "#7FA7D9"]
    readonly property var catName: ({ praca: "Práca", zabava: "Zábava", neutral: "Neutrálne" })
    readonly property var catColor: ({ praca: "#6FB3A6", zabava: "#E0875F", neutral: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.35) })

    function fmt(s) { s = Math.round(s || 0); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h > 0 ? h + " h " + m + " min" : (m > 0 ? m + " min" : (s > 0 ? "< 1 min" : "0 min")); }
    function fmtShort(s) { s = Math.round(s || 0); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h > 0 ? h + "h " + m + "m" : m + "m"; }
    function greeting() { const h = new Date().getHours(); return h < 5 ? "Dobrú noc" : (h < 10 ? "Dobré ráno" : (h < 12 ? "Dobré dopoludnie" : (h < 18 ? "Dobré popoludnie" : "Dobrý večer"))); }

    // ── dáta ─────────────────────────────────────────────────────────────────────────────
    Process {
        id: dayProc
        command: ["latte-sysmon", "pohoda-den", Qt.formatDate(new Date(), "yyyy-MM-dd")]
        stdout: StdioCollector { onStreamFinished: { try { pp.d = JSON.parse(this.text); } catch (e) {} } }
    }
    function refresh() { dayProc.command = ["latte-sysmon", "pohoda-den", Qt.formatDate(new Date(), "yyyy-MM-dd")]; if (!dayProc.running) dayProc.running = true; }
    Timer { interval: 30000; repeat: true; running: true; triggeredOnStart: true; onTriggered: pp.refresh() }
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos/fokus.json"; printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { pp.focusState = JSON.parse(text()); } catch (e) { pp.focusState = { active: false }; } pp.refresh(); }
    }
    FileView { id: catFile; path: pp.cfg + "/pohoda-kategorie.json"; printErrors: false; atomicWrites: true
               onLoaded: { try { pp.catOver = JSON.parse(text()) || {}; } catch (e) {} } }
    Process { id: winProc; command: ["hyprctl", "-j", "activewindow"]
              stdout: StdioCollector { onStreamFinished: { try { const w = JSON.parse(this.text); pp.nowApp = w.title ? (w["class"] === "org.quickshell" ? w.title.replace(/ — LatteOS$/, "") : w.title) : ""; } catch (e) { pp.nowApp = ""; } } } }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { pp.nowTick++; if (pp.nowTick % 5 === 0 && !winProc.running) winProc.running = true; } }
    Process { id: runner }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) status(msg); }
    function ipc(args) { run(["sh", "-c", 'p=$(pgrep -f "[q]s -n -p /usr/share/latteos/apps/pohoda.qml" | head -1); [ -n "$p" ] || { setsid latte-app pohoda >/dev/null 2>&1 & sleep 3; p=$(pgrep -f "[q]s -n -p /usr/share/latteos/apps/pohoda.qml" | head -1); }; qs ipc --pid "$p" call pohoda "$@"', "sh"].concat(args)); }
    function startFocus() { ipc(["fokusStart", String(focusMins), focusMode]); status("Sústredenie na " + focusMins + " min"); }
    function stopFocus() { ipc(["fokusStop"]); }
    function setGoal(mins) { run(["sh", "-c", 'mkdir -p "$(dirname "$1")"; if [ "$2" = 0 ]; then rm -f "$1"; else printf %s "$2" > "$1"; fi', "sh", cfg + "/pohoda-ciel", String(mins)], mins ? "Denný cieľ: " + fmt(mins * 60) : "Denný cieľ zrušený"); Qt.callLater(refresh); }
    function setLoud(pct) { run(["sh", "-c", 'mkdir -p "$(dirname "$1")"; printf %s "$2" > "$1"', "sh", cfg + "/pohoda-sluch", String(pct)], "Hlasné počúvanie od " + pct + " % hlasitosti"); }
    function setCat(cls, c) { const o = Object.assign({}, catOver); if (c) o[cls] = c; else delete o[cls]; catOver = o; run(["mkdir", "-p", cfg]); catFile.setText(JSON.stringify(o)); Qt.callLater(refresh); }
    readonly property int focusLeft: focusState.active ? Math.max(0, Math.round((focusState.start + focusState.planned * 60000 - Date.now() + nowTick * 0) / 1000)) : 0

    // ── spoločné prvky ───────────────────────────────────────────────────────────────────
    component Card: Rectangle {
        radius: 16; color: Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.045); border { color: Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.08); width: 1 }
    }
    component Cap: Text { color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.8 } }
    component Big: Text { color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 30; weight: Font.DemiBold } }
    component Chip: Rectangle {
        id: ch
        property string label; property bool on: false
        signal clicked()
        width: cl.implicitWidth + 22; height: 30; radius: 15
        color: on ? pp.theme.primary : (cm.containsMouse ? pp.theme.hover : Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.06))
        Text { id: cl; anchors.centerIn: parent; text: ch.label; color: ch.on ? pp.theme.fgOnPrimary : pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: ch.clicked() }
    }
    component Ring: Canvas {
        id: rg
        property real value: 0; property color col: pp.theme.primary; property real thick: 12
        property real shown: value
        Behavior on shown { enabled: pp.anim; NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        onShownChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const r = Math.min(width, height) / 2 - thick / 2;
            c.lineWidth = thick; c.lineCap = "round";
            c.strokeStyle = Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.10);
            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke();
            c.strokeStyle = col;
            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.001, Math.min(1, shown))); c.stroke();
        }
    }
    // časová os 24 h: hodnoty 48 polhodín alebo úseky [od, do]
    component Timeline: Item {
        id: tl
        property var halves: []; property var spans: []; property color col: pp.theme.primary
        Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.05) }
        Repeater {
            model: tl.spans
            Rectangle { required property var modelData
                        x: tl.width * modelData[0] / 86400; width: Math.max(2, tl.width * (modelData[1] - modelData[0]) / 86400)
                        y: 8; height: tl.height - 26; radius: 2; color: tl.col }
        }
        Repeater {
            model: tl.halves
            Rectangle { required property var modelData; required property int index
                        readonly property real mx: Math.max(1, Math.max.apply(null, tl.halves))
                        x: tl.width * index / 48 + 1; width: tl.width / 48 - 2; radius: 2; color: tl.col
                        height: modelData > 0 ? Math.max(3, (tl.height - 26) * modelData / mx) : 0; y: tl.height - 18 - height }
        }
        Repeater {
            model: [0, 4, 8, 12, 16, 20]
            Text { required property int modelData; x: tl.width * modelData / 24; y: tl.height - 15; text: String(modelData).padStart(2, "0") + ":00"
                   color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 9 } }
        }
        Rectangle { visible: true; readonly property real nowX: tl.width * (new Date().getHours() * 3600 + new Date().getMinutes() * 60) / 86400
                    x: nowX; width: 1; y: 4; height: tl.height - 20; color: pp.theme.error; opacity: 0.6 }
    }
    component WeekBars: Item {
        id: wb
        property var week: []; property bool highlight: true
        readonly property real mx: Math.max(1, Math.max.apply(null, (week || []).map(w => w.total)))
        Row {
            anchors.fill: parent; spacing: 8
            Repeater {
                model: wb.week || []
                Item {
                    required property var modelData
                    width: (wb.width - 6 * 8) / 7; height: wb.height
                    Rectangle {
                        anchors { bottom: dl.top; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                        width: parent.width * 0.7; radius: 6
                        height: Math.max(modelData.total > 0 ? 4 : 0, (parent.height - 22) * modelData.total / wb.mx)
                        color: modelData.isTarget && wb.highlight ? pp.theme.primary : Qt.rgba(pp.theme.primary.r, pp.theme.primary.g, pp.theme.primary.b, 0.35)
                        Behavior on height { enabled: pp.anim; NumberAnimation { duration: 700; easing.type: Easing.OutQuart } }
                    }
                    Text { id: dl; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter } text: modelData.day
                           color: modelData.isTarget ? pp.theme.fg : pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11; weight: modelData.isTarget ? Font.Bold : Font.Normal } }
                }
            }
        }
    }
    component Stat: Card {
        property string value; property string label
        height: 76
        Column { anchors.centerIn: parent; spacing: 2
                 Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.value; color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
                 Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.label; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
    }

    Text { visible: !pp.p; anchors.centerIn: parent; text: "Načítavam…"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 13 } }

    Flickable {
        id: fl
        visible: !!pp.p
        anchors.fill: parent
        contentHeight: pageLoader.item ? pageLoader.item.implicitHeight + 10 : 0; clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollHint { flick: fl; colors: pp.theme }
        Loader {
            id: pageLoader
            active: !!pp.p
            width: fl.width - 12
            sourceComponent: ({ prehlad: cPrehlad, obrazovka: cObrazovka, sustredenie: cSustredenie, sluch: cSluch, prehlady: cPrehlady })[pp.page] || cPrehlad
        }
    }

    // ═════════ Prehľad ═════════
    Component {
        id: cPrehlad
        Column {
            id: pre
            spacing: 12
            readonly property real ww: width
            readonly property var topApps: pp.d ? pp.d.apps.slice(0, 3) : []
            Column { spacing: 2
                Text { text: pp.greeting(); color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 24; weight: Font.DemiBold } }
                Text { text: new Date().toLocaleDateString(Qt.locale("sk_SK"), "dddd, d. MMMM") + " · tvoj deň na jeden pohľad · iba v tomto počítači"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } } }
            Row {
                spacing: 12
                Card {
                    width: parent.parent.ww * 0.66 - 6; height: 190
                    Ring { id: todayRing; x: 18; y: 18; width: 154; height: 154
                           value: pp.p.goal ? pp.d.total / (pp.p.goal * 60) : (pp.d.average ? pp.d.total / Math.max(1, pp.d.average * 1.5) : 0)
                           col: pp.p.goal && pp.d.total > pp.p.goal * 60 ? pp.theme.error : pp.theme.primary }
                    Column { anchors.centerIn: todayRing; spacing: 0
                             Text { anchors.horizontalCenter: parent.horizontalCenter; text: pp.fmtShort(pp.d.total); color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 26; weight: Font.DemiBold } }
                             Text { anchors.horizontalCenter: parent.horizontalCenter; text: pp.p.goal ? "z cieľa " + pp.fmtShort(pp.p.goal * 60) : "bez cieľa"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
                    Column {
                        x: 196; y: 22; width: parent.width - 214; spacing: 8
                        Cap { text: "DNES · ČAS V APLIKÁCIÁCH" }
                        Row { spacing: 14
                            Text { readonly property real diff: pp.d.total - pp.d.yesterday
                                   text: (diff >= 0 ? "↗ +" : "↘ −") + pp.fmt(Math.abs(diff)) + " oproti včerajšku"; color: diff > 0 ? "#E0875F" : "#7FB77E"; font { family: pp.theme.fontUi; pixelSize: 12 } }
                            Text { text: "priemer " + pp.fmt(pp.d.average); color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } } }
                        Cap { text: "ROZDELENIE MEDZI APLIKÁCIE"; topPadding: 6 }
                        Row {
                            width: parent.width; height: 10; spacing: 3
                            Repeater { model: pre.topApps
                                Rectangle { required property var modelData; required property int index
                                            width: Math.max(4, (parent.width - 6) * modelData.seconds / Math.max(1, pp.d.total)); height: 10; radius: 5; color: pp.palette[index] } }
                        }
                        Flow { width: parent.width; spacing: 14
                            Repeater { model: pre.topApps
                                Row { required property var modelData; required property int index; spacing: 5
                                      Rectangle { width: 8; height: 8; radius: 4; color: pp.palette[index]; anchors.verticalCenter: parent.verticalCenter }
                                      Text { text: modelData.name + "  " + pp.fmtShort(modelData.seconds); color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 } } } } }
                        Text { visible: pp.nowApp !== ""; topPadding: 6; width: parent.width; elide: Text.ElideRight
                               text: "Práve používaš: " + pp.nowApp; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } }
                    }
                }
                Card {
                    width: parent.parent.ww * 0.34 - 6; height: 190
                    readonly property var best: pp.d.apps[0]
                    Column { x: 16; y: 16; width: parent.width - 32; spacing: 6
                        Cap { text: "NAJVIAC DNES" }
                        Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.best ? parent.parent.best.name : "zatiaľ nič"; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 16; weight: Font.Bold } }
                        Text { text: parent.parent.best ? pp.fmt(parent.parent.best.seconds) : ""; color: pp.theme.primary; font { family: pp.theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
                    }
                    Timeline { x: 12; width: parent.width - 24; y: 104; height: 74; halves: pp.d.hourly; col: Qt.rgba(pp.theme.primary.r, pp.theme.primary.g, pp.theme.primary.b, 0.75) }
                    MouseArea { anchors.fill: parent; onClicked: pp.openApps() }
                }
            }
            Row {
                spacing: 12
                Card {
                    width: parent.parent.ww * 0.66 - 6; height: 200
                    Column { x: 16; y: 14; spacing: 2
                             Cap { text: "TENTO TÝŽDEŇ · " + pp.d.weekRange }
                             Row { spacing: 10
                                   Text { text: pp.fmt(pp.p.weekTotal); color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                                   Text { anchors.baseline: parent.children[0].baseline; text: "∅ " + pp.fmt(pp.d.average) + " denne"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } } } }
                    WeekBars { x: 16; y: 74; width: parent.width - 32; height: 112; week: pp.d.week }
                    MouseArea { anchors.fill: parent; onClicked: pp.page = "prehlady" }
                }
                Column {
                    spacing: 12; width: parent.parent.ww * 0.34 - 6
                    Card {
                        width: parent.width; height: 100; color: pp.focusState.active ? Qt.rgba(pp.theme.primary.r, pp.theme.primary.g, pp.theme.primary.b, 0.18) : Qt.rgba(0.88, 0.53, 0.37, 0.12)
                        Column { x: 16; y: 12; width: parent.width - 32; spacing: 4
                            Text { text: pp.focusState.active ? "Sústredenie beží" : "Sústredenie"; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                            Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 }
                                   text: pp.focusState.active ? "zostáva " + Math.ceil(pp.focusLeft / 60) + " min · rozptýlenia " + pp.focusState.distractions : "Stíš rozptyľujúce aplikácie a chráň si blok práce." }
                            Chip { label: pp.focusState.active ? "Ukončiť" : "Začať sedenie →"; on: !pp.focusState.active; onClicked: pp.focusState.active ? pp.stopFocus() : (pp.page = "sustredenie") }
                        }
                    }
                    Card {
                        width: parent.width; height: 88
                        Column { x: 16; y: 12; width: parent.width - 32; spacing: 6
                            Cap { text: "DENNÝ CIEĽ" + (pp.p.goal ? " · " + pp.fmtShort(pp.p.goal * 60) : "") }
                            Rectangle { width: parent.width; height: 8; radius: 4; color: Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.1)
                                        Rectangle { height: 8; radius: 4; width: pp.p.goal ? parent.width * Math.min(1, pp.d.total / (pp.p.goal * 60)) : 0
                                                    color: pp.p.goal && pp.d.total > pp.p.goal * 60 ? pp.theme.error : "#6FB3A6" } }
                            Row { spacing: 4
                                Repeater { model: [[0, "bez"], [120, "2 h"], [240, "4 h"], [360, "6 h"], [480, "8 h"]]
                                    Chip { required property var modelData; height: 24; label: modelData[1]; on: (pp.p.goal || 0) === modelData[0]; onClicked: pp.setGoal(modelData[0]) } } }
                        }
                    }
                }
            }
            Row {
                spacing: 12
                Card {
                    width: parent.parent.ww * 0.34 - 6; height: 120; color: Qt.rgba(0.44, 0.7, 0.65, 0.10)
                    Ring { id: hr; x: 16; y: 22; width: 76; height: 76; thick: 7; col: "#6FB3A6"
                           value: pp.p.hearing.listen ? pp.p.hearing.loud / Math.max(1, pp.p.hearing.listen) : 0 }
                    Column { anchors { left: hr.right; leftMargin: 14; verticalCenter: hr.verticalCenter } spacing: 3
                             Cap { text: "SLUCH" }
                             Text { text: pp.fmt(pp.p.hearing.loud); color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                             Text { text: "hlasno · počúvanie " + pp.fmtShort(pp.p.hearing.listen); color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
                    MouseArea { anchors.fill: parent; onClicked: pp.page = "sluch" }
                }
                Card {
                    width: parent.parent.ww * 0.66 - 6; height: 120
                    Column { x: 16; y: 14; width: parent.width - 32; spacing: 8
                        Cap { text: "KATEGÓRIE · DNES" }
                        Repeater {
                            model: ["praca", "zabava", "neutral"]
                            Row { required property string modelData; spacing: 10
                                  Text { width: 80; text: pp.catName[modelData]; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 } }
                                  Rectangle { width: parent.parent.width - 170; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.08)
                                              Rectangle { height: 8; radius: 4; color: pp.catColor[parent.parent.modelData]
                                                          width: parent.width * pp.p.categories[parent.parent.modelData] / Math.max(1, pp.d.total) } }
                                  Text { text: pp.fmtShort(pp.p.categories[modelData]); color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
                        }
                    }
                }
            }
        }
    }

    // ═════════ Čas obrazovky ═════════
    Component {
        id: cObrazovka
        Column {
            spacing: 12
            Card {
                width: parent.width; height: 230
                Column { x: 18; y: 16; spacing: 2
                    Cap { text: "AKTÍVNY ČAS PRED OBRAZOVKOU · DNES" }
                    Big { text: pp.fmt(pp.p.screenTotal) }
                    Text { readonly property real diff: pp.d.total - pp.d.yesterday
                           text: (diff >= 0 ? "↑ o " : "↓ o ") + pp.fmt(Math.abs(diff)) + (diff >= 0 ? " viac" : " menej") + " v aplikáciách ako včera"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } } }
                Timeline { x: 18; y: 110; width: parent.width - 36; height: 104; spans: pp.p.screen; col: "#46B4C8" }
            }
            Row {
                spacing: 12
                readonly property real w: (parent.width - 24) / 3
                Stat { width: parent.w; value: String(pp.p.sessions); label: "sedení (prestávka ≥ 5 min ich delí)" }
                Stat { width: parent.w; value: pp.fmtShort(pp.p.longestSession); label: "najdlhší úsek bez prestávky" }
                Stat { width: parent.w; value: String(pp.p.breaks); label: "prestávok" }
            }
            Row {
                spacing: 12
                readonly property real w: (parent.width - 24) / 3
                Stat { width: parent.w; value: String(pp.p.switches); label: "prepnutí medzi aplikáciami" }
                Stat { width: parent.w; value: pp.fmtShort(pp.p.stretchAvg); label: "priemerné sústredenie v jednej aplikácii" }
                Stat { width: parent.w; value: pp.fmtShort(pp.p.stretchLongest); label: "najdlhšie sústredenie" }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 }
                   text: "Čas sa ráta, iba keď pracuješ (5 min bez pohybu = nečinnosť; prehrávané video sa ráta). Úsek sústredenia = aspoň 1 min v jednej aplikácii bez prepnutia." }
        }
    }

    // ═════════ Sústredenie ═════════
    Component {
        id: cSustredenie
        Column {
            spacing: 12
            Card {
                width: parent.width; height: pp.focusState.active ? 170 : 250
                color: pp.focusState.active ? Qt.rgba(pp.theme.primary.r, pp.theme.primary.g, pp.theme.primary.b, 0.14) : Qt.rgba(pp.theme.fg.r, pp.theme.fg.g, pp.theme.fg.b, 0.045)
                Column {
                    visible: !pp.focusState.active
                    x: 18; y: 16; width: parent.width - 36; spacing: 10
                    Text { text: "Začni sedenie sústredenia"; color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 }
                           text: "Vyber dĺžku. Rozptyľujúce aplikácie (kategória Zábava) počas sedenia LatteOS upozorní alebo odsunie medzi minimalizované okná." }
                    Row { spacing: 6
                        Repeater { model: [15, 25, 45, 60, 90]
                            Chip { required property int modelData; label: modelData + " min"; on: pp.focusMins === modelData; onClicked: pp.focusMins = modelData } } }
                    Cap { text: "AKO RIEŠIŤ ROZPTÝLENIA"; topPadding: 4 }
                    Row { spacing: 6
                        Chip { label: "🔔 Upozorniť"; on: pp.focusMode === "upozornit"; onClicked: pp.focusMode = "upozornit" }
                        Chip { label: "⊘ Odsunúť (minimalizovať)"; on: pp.focusMode === "odsunut"; onClicked: pp.focusMode = "odsunut" } }
                    Chip { label: "▶ Začať sedenie"; on: true; onClicked: pp.startFocus() }
                }
                Row {
                    visible: pp.focusState.active
                    x: 18; y: 16; spacing: 22
                    Item { width: 138; height: 138
                        Ring { anchors.fill: parent; thick: 10; value: pp.focusState.active ? 1 - pp.focusLeft / (pp.focusState.planned * 60) : 0 }
                        Text { anchors.centerIn: parent; text: Math.floor(pp.focusLeft / 60) + ":" + String(pp.focusLeft % 60).padStart(2, "0")
                               color: pp.theme.fg; font { family: pp.theme.fontMono; pixelSize: 24; weight: Font.Bold } } }
                    Column { spacing: 8; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Sústredenie beží · " + (pp.focusState.planned || 0) + " min"; color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                        Text { text: (pp.focusState.mode === "odsunut" ? "rozptýlenia sa odsúvajú" : "pri rozptýlení upozorním") + " · rozptýlenia: " + (pp.focusState.distractions || 0)
                               color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } }
                        Chip { label: "■ Ukončiť"; onClicked: pp.stopFocus() } }
                }
            }
            Row {
                spacing: 12
                Card {
                    width: (parent.parent.width - 12) * 0.5; height: Math.max(160, hcol.implicitHeight + 30)
                    Column { id: hcol; x: 16; y: 14; width: parent.width - 32; spacing: 6
                        Cap { text: "SEDENIA TOHTO TÝŽDŇA · " + pp.p.weekFocus.length }
                        Text { visible: pp.p.weekFocus.length === 0; text: "Zatiaľ žiadne."; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } }
                        Repeater { model: pp.p.weekFocus.slice().reverse().slice(0, 10)
                            Row { required property var modelData; spacing: 10; width: hcol.width
                                  Text { text: modelData.done ? "✓" : "✗"; color: modelData.done ? "#7FB77E" : pp.theme.error; font { family: pp.theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                  Column { width: parent.width - 150
                                           Text { text: pp.fmt(modelData.secs); color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                                           Text { text: modelData.date.slice(8, 10) + ". " + modelData.date.slice(5, 7) + ". o " + modelData.start; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 10 } } }
                                  Text { text: modelData.distractions === 0 ? "bez rozptýlení" : modelData.distractions + " rozptýl."; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } } }
                    }
                }
                Card {
                    width: (parent.parent.width - 12) * 0.5; height: Math.max(160, ccol.implicitHeight + 30)
                    Column { id: ccol; x: 16; y: 14; width: parent.width - 32; spacing: 6
                        Cap { text: "KATEGÓRIE APLIKÁCIÍ (čo je rozptýlenie)" }
                        Repeater { model: pp.d.weekApps.slice(0, 10)
                            Row { required property var modelData; spacing: 6; width: ccol.width
                                  Text { width: parent.width - 3 * 76; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 } }
                                  Repeater { model: [["praca", "P"], ["zabava", "Z"], ["neutral", "N"]]
                                      Chip { required property var modelData; width: 70; height: 24; label: pp.catName[modelData[0]]
                                             on: (pp.catOver[parent.modelData.class] || parent.modelData.category) === modelData[0]
                                             onClicked: pp.setCat(parent.modelData.class, modelData[0]) } } } }
                    }
                }
            }
        }
    }

    // ═════════ Sluch ═════════
    Component {
        id: cSluch
        Column {
            spacing: 12
            Card {
                width: parent.width; height: 230
                Column { x: 18; y: 16; spacing: 2
                    Cap { text: "HLASNÉ POČÚVANIE · DNES" }
                    Big { text: pp.fmt(pp.p.hearing.loud) }
                    Text { text: "z " + pp.fmt(pp.p.hearing.listen) + " počúvania"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 12 } } }
                Rectangle { anchors { right: parent.right; top: parent.top; margins: 16 } width: sl.implicitWidth + 20; height: 24; radius: 12
                            color: pp.p.hearing.loud > 3600 ? Qt.rgba(0.88, 0.48, 0.37, 0.2) : Qt.rgba(0.44, 0.7, 0.65, 0.2)
                            Text { id: sl; anchors.centerIn: parent; text: pp.p.hearing.loud > 3600 ? "⚠ dnes veľa hlasného počúvania" : "✓ bezpečné úrovne"
                                   color: pp.p.hearing.loud > 3600 ? "#E0875F" : "#6FB3A6"; font { family: pp.theme.fontUi; pixelSize: 11; weight: Font.Bold } } }
                Timeline { x: 18; y: 110; width: parent.width - 36; height: 104; halves: pp.p.hearing.loudHalves; col: "#E07A5F" }
            }
            Row {
                spacing: 12
                Card {
                    width: (parent.parent.width - 12) / 2; height: 120
                    Column { x: 16; y: 14; width: parent.width - 32; spacing: 8
                        Cap { text: "ČO JE HLASNO" }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 }
                               text: "Prehrávanie v slúchadlách s hlasitosťou aspoň:" }
                        Row { spacing: 6
                            Repeater { model: [60, 70, 80, 90]
                                Chip { required property int modelData; label: modelData + " %"; on: (pp.loudPct || 70) === modelData; onClicked: { pp.loudPct = modelData; pp.setLoud(modelData); } } } }
                    }
                }
                Card {
                    width: (parent.parent.width - 12) / 2; height: 120
                    Column { x: 16; y: 14; width: parent.width - 32; spacing: 6
                        Cap { text: "ODPORÚČANIE WHO" }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 }
                               text: "Pod 80 dB najviac 40 h týždenne, pri 85 dB najviac ~12 h. Rob prestávky a stíš, keď nepočuješ okolie." }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 10 }
                               text: "Odhad podľa hlasitosti systému, nie meranie decibelov (to závisí od slúchadiel)." }
                    }
                }
            }
        }
    }
    property int loudPct: 70
    FileView { path: pp.cfg + "/pohoda-sluch"; printErrors: false; onLoaded: pp.loudPct = parseInt(text()) || 70 }

    // ═════════ Prehľady ═════════
    Component {
        id: cPrehlady
        Column {
            spacing: 12
            Row {
                spacing: 12
                Card {
                    width: (parent.parent.width - 12) * 0.62; height: 230
                    Column { x: 18; y: 16; spacing: 2
                        Cap { text: "DENNÝ PRIEMER · " + pp.d.weekRange }
                        Big { text: pp.fmt(pp.d.average) } }
                    WeekBars { x: 18; y: 96; width: parent.width - 36; height: 120; week: pp.d.week; highlight: false }
                }
                Column {
                    spacing: 12; width: (parent.parent.width - 12) * 0.38
                    Card {
                        width: parent.width; height: 100
                        Column { x: 16; y: 14; spacing: 2
                            Cap { text: "SPOLU TENTO TÝŽDEŇ" }
                            Text { text: pp.fmt(pp.p.weekTotal); color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
                            Text { readonly property real prev: pp.p.prevWeekTotal
                                   text: prev ? ((pp.p.weekTotal >= prev ? "+" : "−") + Math.round(Math.abs(pp.p.weekTotal - prev) / prev * 100) + " % oproti minulému týždňu") : "minulý týždeň bez záznamu"
                                   color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
                    }
                    Card {
                        id: catCard
                        width: parent.width; height: 118
                        readonly property var wc: pp.p.weekCategories
                        readonly property real tot: Math.max(1, wc.praca + wc.zabava + wc.neutral)
                        Column { x: 16; y: 14; width: parent.width - 32; spacing: 8
                            Cap { text: "PRÁCA VS ZÁBAVA" }
                            Row { width: parent.width; height: 8; spacing: 2
                                  Repeater { model: ["praca", "zabava", "neutral"]
                                      Rectangle { required property string modelData; height: 8; radius: 4; color: pp.catColor[modelData]
                                                  width: Math.max(0, (parent.width - 4) * catCard.wc[modelData] / catCard.tot) } } }
                            Repeater { model: ["praca", "zabava", "neutral"]
                                Row { required property string modelData; spacing: 6; width: parent.width
                                      Rectangle { width: 7; height: 7; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: pp.catColor[modelData] }
                                      Text { width: parent.width - 80; text: pp.catName[modelData]; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 11 } }
                                      Text { text: pp.fmtShort(catCard.wc[modelData]); color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } } }
                        }
                    }
                }
            }
            Card {
                width: parent.width; height: tcol.implicitHeight + 30
                Column { id: tcol; x: 18; y: 14; width: parent.width - 36; spacing: 10
                    Cap { text: "TOP APLIKÁCIE TOHTO TÝŽDŇA" }
                    Grid { columns: 2; columnSpacing: 24; rowSpacing: 10; width: parent.width
                        Repeater { model: pp.d.weekApps.slice(0, 8)
                            Column { required property var modelData; required property int index; width: (tcol.width - 24) / 2; spacing: 4
                                     Row { width: parent.width
                                           Text { width: parent.width - 70; elide: Text.ElideRight; text: modelData.name; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 12 } }
                                           Text { width: 70; horizontalAlignment: Text.AlignRight; text: pp.fmtShort(modelData.seconds); color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } }
                                     Rectangle { height: 4; radius: 2; color: pp.palette[index % pp.palette.length]
                                                 width: parent.width * modelData.seconds / Math.max(1, pp.d.weekApps[0].seconds) } } } }
                }
            }
            Card {
                width: parent.width; height: 60
                Row { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter } spacing: 12
                      Glyph { name: "clock"; size: 18; color: pp.theme.primary; anchors.verticalCenter: parent.verticalCenter }
                      Column { Text { text: "Sedenia sústredenia"; color: pp.theme.fg; font { family: pp.theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                               Text { text: "dokončené tento týždeň"; color: pp.theme.fgDim; font { family: pp.theme.fontUi; pixelSize: 11 } } } }
                Text { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } text: String(pp.p.weekFocus.filter(f => f.done).length)
                       color: pp.theme.fg; font { family: pp.theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
            }
        }
    }
}
