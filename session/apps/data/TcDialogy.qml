// Súbory › Total Commander: nástroje v dialógoch (backend latte-tc).
//   premenuj  Ctrl+M  hromadné premenovanie: masky [N] [E] [C] [C:3] [Y][M][D] [h][m][s] [P] [N2-5], hľadať/nahradiť (aj regex),
//                     veľkosť písmen, počítadlo, živý náhľad, „Späť“ vráti posledné premenovanie
//   hladaj    Alt+F7  maska, priečinok, text v obsahu (aj regex), veľkosť, vek, priečinky, v archívoch; výsledky priebežne
//   sync              synchronizácia ľavého a pravého panela (→ ← ↔, podľa obsahu), plán pred vykonaním
//   archiv    Enter   archív (zip, 7z, rar, tar.*, iso) ako priečinok: prechádzanie, rozbaliť označené/všetko, test
//   atributy  Alt+Enter  vlastnosti, práva (osmičkovo aj rwx), dátum zmeny, rekurzívne
//   zbal      Alt+F5  zip / 7z / tar.gz / tar.xz / tar.zst do druhého panela
//   rozdel            rozdelenie súboru na časti (.001 …) + .crc, spojenie cez „Spojiť“
//   strom     Alt+F10 strom priečinkov (Ctrl+F8): rozbaľovanie šípkami, Enter prejde, písaním hľadá
//   Archív s heslom (7z/zip AES, 7z aj so skrytými menami), viac zväzkov (.7z.001), mazanie v archíve (F8)
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Item {
    id: tc
    required property var theme
    property string tool: ""               // prázdne = zavreté
    property var items: []                 // položky (entries) z aktívneho panela
    property string dirA: ""               // aktívny panel
    property string dirB: ""               // druhý panel
    signal done(string msg)
    signal goTo(string dir, string name)
    signal feed(var list)                  // výsledky hľadania do panela
    anchors.fill: parent
    visible: tool !== ""
    z: 70
    function open(t, list, a, b) { items = list || []; dirA = a; dirB = b; tool = t; }
    function close() { tool = ""; }
    function human(b) { const u = ["B", "KB", "MB", "GB", "TB"]; let v = b || 0, i = 0; while (v >= 1024 && i < 4) { v /= 1024; i++; } return v.toFixed(i ? 1 : 0).replace(".", ",") + " " + u[i]; }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4); MouseArea { anchors.fill: parent; onClicked: tc.close() } }

    component Field: Rectangle {
        id: fld
        property alias text: fin.text
        property alias input: fin
        property bool secret: false
        property string hint
        signal accepted()
        width: parent ? parent.width : 200; height: 34; radius: 9; color: tc.theme.field; border { color: fin.activeFocus ? tc.theme.primary : "transparent"; width: 1 }
        TextInput { id: fin; anchors { fill: parent; leftMargin: 10; rightMargin: 10 } verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
                    echoMode: fld.secret ? TextInput.Password : TextInput.Normal
                    color: tc.theme.fg; font { family: tc.theme.fontMono; pixelSize: 12 }
                    Keys.onReturnPressed: (ev) => { ev.accepted = true; fld.accepted(); }
                    Keys.onEscapePressed: (ev) => { ev.accepted = true; tc.close(); } }
        Text { visible: fin.text === "" && fld.hint !== ""; x: 10; anchors.verticalCenter: parent.verticalCenter; text: fld.hint; color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } }
    }
    component Btn: Rectangle {
        id: bt
        property string label; property bool primary: false; property bool on: false
        signal clicked()
        width: btl.implicitWidth + 22; height: 30; radius: 9
        color: primary ? tc.theme.primary : (on ? Qt.rgba(tc.theme.primary.r, tc.theme.primary.g, tc.theme.primary.b, 0.22) : (btm.containsMouse ? tc.theme.hover : tc.theme.field))
        border { color: on ? tc.theme.primary : "transparent"; width: 1 }
        Text { id: btl; anchors.centerIn: parent; text: bt.label; color: bt.primary ? tc.theme.fgOnPrimary : tc.theme.fg; font { family: tc.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        MouseArea { id: btm; anchors.fill: parent; hoverEnabled: true; onClicked: bt.clicked() }
    }
    component Lbl: Text { color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.5 } }
    component Card: Rectangle {
        default property alias content: cc.data
        property string title
        property real w: 760
        property real h: 560
        anchors.centerIn: parent; width: Math.min(w, tc.width - 40); height: Math.min(h, tc.height - 40); radius: 16
        color: tc.theme.surface; border { color: tc.theme.outline; width: 1 }
        MouseArea { anchors.fill: parent }
        Text { x: 18; y: 14; text: parent.title; color: tc.theme.fg; font { family: tc.theme.fontDisplay; pixelSize: 18; weight: Font.DemiBold } }
        Glyph { anchors { right: parent.right; top: parent.top; margins: 16 } name: "x"; size: 16; color: tc.theme.fgDim
                MouseArea { anchors { fill: parent; margins: -6 } onClicked: tc.close() } }
        Item { id: cc; x: 18; y: 48; width: parent.width - 36; height: parent.height - 64 }
    }
    // Process, ktorý ohlási výsledok až keď je hotový výstup aj kód ukončenia (onExited býva skôr než text)
    component Tool: Process {
        id: tp
        signal result(int code, string out)
        property int code: 0
        property string txt: ""
        property int got: 0
        property string input: ""              // heslo a pod. na stdin (nie v argumentoch príkazu)
        stdinEnabled: input !== ""
        onStarted: if (input !== "") write(input + "\n")
        onRunningChanged: if (running) got = 0
        onExited: (c) => { tp.code = c; if (++tp.got === 2) tp.result(tp.code, tp.txt); }
        stdout: StdioCollector { onStreamFinished: { tp.txt = this.text; if (++tp.got === 2) tp.result(tp.code, tp.txt); } }
    }

    // ═══ hromadné premenovanie ═══════════════════════════════════════════════════════════
    Card {
        visible: tc.tool === "premenuj"
        title: "Hromadné premenovanie (Ctrl+M) · " + tc.items.length + " položiek"
        w: 900; h: 620
        property var preview: []
        property string pismena: ""
        property bool rx: false
        id: ren
        function args() {
            return ["--vzor", rVzor.text || "[N]", "--pripona", rExt.text, "--hladaj", rFind.text, "--nahrad", rRepl.text]
                   .concat(ren.rx ? ["--regex"] : []).concat(ren.pismena ? ["--pismena", ren.pismena] : [])
                   .concat(["--start", rStart.text || "1", "--krok", rStep.text || "1", "--cifry", rDig.text || "1", "--"]).concat(tc.items.map(e => e.path));
        }
        function refresh() { if (tc.tool !== "premenuj") return; renProc.command = ["latte-tc", "premenuj"].concat(args()); renProc.running = true; }
        Timer { id: renT; interval: 250; onTriggered: ren.refresh() }
        Tool { id: renProc; onResult: (c, out) => { try { ren.preview = JSON.parse(out); } catch (e) { ren.preview = []; } } }
        Tool { id: renRun; onResult: (c, out) => { tc.done(c === 0 ? "Premenované: " + tc.items.length + " (Späť v Ctrl+M)" : "Premenovanie zlyhalo (duplicitné alebo existujúce mená)"); if (c === 0) tc.close(); } }
        Tool { id: renUndo; onResult: (c, out) => tc.done("Vrátené posledné premenovanie") }
        onVisibleChanged: if (visible) { rVzor.text = "[N]"; rExt.text = "[E]"; rFind.text = ""; rRepl.text = ""; ren.pismena = ""; ren.rx = false; rStart.text = "1"; rStep.text = "1"; rDig.text = "1"; refresh(); rVzor.input.forceActiveFocus(); }
        Column {
            id: renCol
            width: parent.width; spacing: 6
            Row { spacing: 10; width: parent.width
                  Column { width: (parent.width - 10) * 0.6; spacing: 3; Lbl { text: "MASKA MENA" } Field { id: rVzor; input.onTextChanged: renT.restart() } }
                  Column { width: (parent.width - 10) * 0.4; spacing: 3; Lbl { text: "PRÍPONA" } Field { id: rExt; input.onTextChanged: renT.restart() } } }
            Flow { width: parent.width; spacing: 4
                   Repeater { model: [["[N]", "meno"], ["[N1-3]", "znaky 1–3"], ["[E]", "prípona"], ["[C]", "počítadlo"], ["[C:3]", "001"], ["[Y]-[M]-[D]", "dátum"], ["[h][m][s]", "čas"], ["[P]", "priečinok"]]
                              Btn { required property var modelData; label: modelData[0] + " " + modelData[1]; onClicked: { rVzor.input.insert(rVzor.input.cursorPosition, modelData[0]); rVzor.input.forceActiveFocus(); } } } }
            Row { spacing: 10; width: parent.width
                  Column { width: (parent.width - 30) * 0.3; spacing: 3; Lbl { text: "HĽADAŤ" } Field { id: rFind; input.onTextChanged: renT.restart() } }
                  Column { width: (parent.width - 30) * 0.3; spacing: 3; Lbl { text: "NAHRADIŤ" } Field { id: rRepl; input.onTextChanged: renT.restart() } }
                  Column { spacing: 3; Lbl { text: "POČÍTADLO od · krok · cifry" }
                           Row { spacing: 4; Field { id: rStart; width: 60; input.onTextChanged: renT.restart() } Field { id: rStep; width: 50; input.onTextChanged: renT.restart() } Field { id: rDig; width: 50; input.onTextChanged: renT.restart() } } } }
            Row { spacing: 4
                  Btn { label: "Regex"; on: ren.rx; onClicked: { ren.rx = !ren.rx; ren.refresh(); } }
                  Item { width: 10; height: 1 }
                  Repeater { model: [["", "bez zmeny"], ["lower", "malé"], ["upper", "VEĽKÉ"], ["prve", "Prvé veľké"]]
                             Btn { required property var modelData; label: modelData[1]; on: ren.pismena === modelData[0]; onClicked: { ren.pismena = modelData[0]; ren.refresh(); } } } }
            Lbl { text: "NÁHĽAD"; topPadding: 4 }
        }
        ListView {
            id: renList
            anchors { top: renCol.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: renBtns.top; bottomMargin: 8 }
            clip: true; model: ren.preview
            ScrollHint { flick: renList; colors: tc.theme }
            delegate: Row {
                required property var modelData
                width: renList.width; height: 22; spacing: 8
                Text { width: (parent.width - 110) / 2; elide: Text.ElideMiddle; text: modelData[0]; color: tc.theme.fgDim; font { family: tc.theme.fontMono; pixelSize: 11 } }
                Text { text: "→"; color: tc.theme.primary; font.pixelSize: 11 }
                Text { width: (parent.width - 110) / 2; elide: Text.ElideMiddle; text: modelData[1]; color: modelData[2] ? tc.theme.error : (modelData[0] === modelData[1] ? tc.theme.fgDim : tc.theme.fg)
                       font { family: tc.theme.fontMono; pixelSize: 11; weight: Font.DemiBold } }
                Text { text: modelData[2]; color: tc.theme.error; font { family: tc.theme.fontUi; pixelSize: 10 } }
            }
        }
        Row { id: renBtns; anchors { left: parent.left; bottom: parent.bottom } spacing: 8
              Btn { label: "Spustiť"; primary: true; onClicked: { renRun.command = ["latte-tc", "premenuj"].concat(ren.args()).concat(["--vykonaj"]); renRun.running = true; } }
              Btn { label: "Späť posledné"; onClicked: { renUndo.command = ["latte-tc", "spat"]; renUndo.running = true; } }
              Btn { label: "Zavrieť"; onClicked: tc.close() }
              Text { anchors.verticalCenter: parent.verticalCenter; text: ren.preview.filter(p => p[2]).length ? "⚠ " + ren.preview.filter(p => p[2]).length + " kolízií" : ""; color: tc.theme.error; font { family: tc.theme.fontUi; pixelSize: 12 } } }
    }

    // ═══ hľadanie (Alt+F7) ══════════════════════════════════════════════════════════════
    Card {
        id: fs
        visible: tc.tool === "hladaj"
        title: "Hľadať súbory (Alt+F7)"
        w: 900; h: 640
        property var results: []
        property bool running: findProc.running
        property bool rx: false
        property bool dirs: false
        property bool arch: false
        Process {
            id: findProc
            stdout: SplitParser { onRead: (l) => { const f = l.split("\t"); if (fs.results.length < 5000) fs.results = fs.results.concat([{ k: f[0], path: f[1], inner: f[2] || "" }]); } }
        }
        function start() {
            results = [];
            const kb = (t) => t.trim() === "" ? "-1" : String(Math.round(parseFloat(t.replace(",", ".")) * 1024));
            findProc.command = ["latte-tc", "hladaj", fDir.text, "--maska", fMask.text || "*"].concat(fText.text ? ["--text", fText.text] : []).concat(rx ? ["--regex"] : [])
                               .concat(["--velkost-od", kb(fMin.text), "--velkost-do", kb(fMax.text), "--dni", fDays.text.trim() || "-1"]).concat(dirs ? ["--priecinky"] : []).concat(arch ? ["--archivy"] : []);
            findProc.running = true;
        }
        onVisibleChanged: if (visible) { fDir.text = tc.dirA; if (!fMask.text) fMask.text = "*"; fMask.input.forceActiveFocus(); fMask.input.selectAll(); }
        Column {
            id: fsCol
            width: parent.width; spacing: 6
            Row { spacing: 10; width: parent.width
                  Column { width: (parent.width - 10) * 0.4; spacing: 3; Lbl { text: "HĽADAŤ SÚBORY (maska, ; oddeľuje)" } Field { id: fMask; onAccepted: fs.start() } }
                  Column { width: (parent.width - 10) * 0.6; spacing: 3; Lbl { text: "V PRIEČINKU (a podpriečinkoch)" } Field { id: fDir; onAccepted: fs.start() } } }
            Row { spacing: 10; width: parent.width
                  Column { width: (parent.width - 30) * 0.45; spacing: 3; Lbl { text: "TEXT V OBSAHU" } Field { id: fText; hint: "nepovinné"; onAccepted: fs.start() } }
                  Column { spacing: 3; Lbl { text: "VEĽKOSŤ KB od – do" } Row { spacing: 4; Field { id: fMin; width: 80; onAccepted: fs.start() } Field { id: fMax; width: 80; onAccepted: fs.start() } } }
                  Column { spacing: 3; Lbl { text: "ZMENENÉ ZA DNÍ" } Field { id: fDays; width: 80; onAccepted: fs.start() } } }
            Row { spacing: 4
                  Btn { label: "Regex"; on: fs.rx; onClicked: fs.rx = !fs.rx }
                  Btn { label: "Aj priečinky"; on: fs.dirs; onClicked: fs.dirs = !fs.dirs }
                  Btn { label: "V archívoch"; on: fs.arch; onClicked: fs.arch = !fs.arch }
                  Item { width: 20; height: 1 }
                  Btn { label: fs.running ? "Zastaviť" : "Hľadať (Enter)"; primary: !fs.running; onClicked: fs.running ? findProc.signal(15) : fs.start() }
                  Btn { label: "Do panela (" + fs.results.length + ")"; onClicked: { tc.feed(fs.results.filter(r => r.k !== "A").map(r => ({ dir: r.k === "D", path: r.path }))); tc.close(); } } }
            Lbl { text: (fs.running ? "HĽADÁM… " : "NÁJDENÉ: ") + fs.results.length + " · dvojklik = prejsť na súbor"; topPadding: 4 }
        }
        ListView {
            id: fList
            anchors { top: fsCol.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true; model: fs.results
            ScrollHint { flick: fList; colors: tc.theme }
            delegate: Rectangle {
                required property var modelData
                width: fList.width; height: 24; radius: 6; color: fm.containsMouse ? tc.theme.hover : "transparent"
                Glyph { x: 6; anchors.verticalCenter: parent.verticalCenter; name: modelData.k === "D" ? "folder" : (modelData.k === "A" ? "file-zip" : "file"); size: 14
                        color: modelData.k === "D" ? tc.theme.primary : tc.theme.fgDim }
                Text { x: 28; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle
                       text: modelData.path + (modelData.inner ? "  ›  " + modelData.inner : ""); color: tc.theme.fg; font { family: tc.theme.fontMono; pixelSize: 11 } }
                MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true
                            onDoubleClicked: { const p = modelData.path, d = p.substring(0, p.lastIndexOf("/")) || "/"; tc.goTo(modelData.k === "D" ? p : d, modelData.k === "D" ? "" : p.split("/").pop()); tc.close(); } }
            }
        }
    }

    // ═══ synchronizácia priečinkov ═══════════════════════════════════════════════════════
    Card {
        id: sy
        visible: tc.tool === "sync"
        title: "Synchronizovať priečinky"
        w: 860; h: 600
        property string smer: "lr"
        property bool obsah: false
        property var plan: []
        property int pct: -1
        Tool { id: syPlan; onResult: (c, out) => { try { sy.plan = JSON.parse(out); } catch (e) { sy.plan = []; } } }
        Process { id: syRun
                  stdout: SplitParser { onRead: (l) => { const f = l.split(" "); if (f[0] === "P") sy.pct = parseInt(f[1]); } }
                  onExited: (c) => { sy.pct = -1; tc.done(c === 0 ? "Synchronizované: " + sy.plan.length + " súborov" : "Synchronizácia zlyhala"); sy.compare(); } }
        function compare() { syPlan.command = ["latte-tc", "synchronizuj", tc.dirA, tc.dirB, "--smer", smer].concat(obsah ? ["--obsah"] : []); syPlan.running = true; }
        onVisibleChanged: if (visible) { plan = []; compare(); }
        Column {
            id: syCol
            width: parent.width; spacing: 6
            Text { width: parent.width; elide: Text.ElideMiddle; text: "Vľavo: " + tc.dirA; color: tc.theme.fg; font { family: tc.theme.fontMono; pixelSize: 12 } }
            Text { width: parent.width; elide: Text.ElideMiddle; text: "Vpravo: " + tc.dirB; color: tc.theme.fg; font { family: tc.theme.fontMono; pixelSize: 12 } }
            Row { spacing: 4
                  Repeater { model: [["lr", "→ zľava doprava"], ["rl", "← sprava doľava"], ["obe", "↔ oboma smermi"]]
                             Btn { required property var modelData; label: modelData[1]; on: sy.smer === modelData[0]; onClicked: { sy.smer = modelData[0]; sy.compare(); } } }
                  Item { width: 10; height: 1 }
                  Btn { label: "Podľa obsahu"; on: sy.obsah; onClicked: { sy.obsah = !sy.obsah; sy.compare(); } }
                  Btn { label: "Porovnať"; onClicked: sy.compare() } }
            Lbl { text: syPlan.running ? "POROVNÁVAM…" : (sy.plan.length ? "PLÁN: " + sy.plan.length + " súborov · " + tc.human(sy.plan.reduce((a, x) => a + x.velkost, 0)) : "PRIEČINKY SÚ ROVNAKÉ") }
        }
        ListView {
            id: syList
            anchors { top: syCol.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: syBtns.top; bottomMargin: 8 }
            clip: true; model: sy.plan
            ScrollHint { flick: syList; colors: tc.theme }
            delegate: Row {
                required property var modelData
                width: syList.width; height: 22; spacing: 10
                Text { width: 24; text: modelData.akcia; color: tc.theme.primary; font { pixelSize: 14; bold: true } }
                Text { width: syList.width - 130; elide: Text.ElideMiddle; text: modelData.subor; color: tc.theme.fg; font { family: tc.theme.fontMono; pixelSize: 11 } }
                Text { text: tc.human(modelData.velkost); color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } }
            }
        }
        Row { id: syBtns; anchors { left: parent.left; bottom: parent.bottom } spacing: 8
              Btn { label: sy.pct >= 0 ? "Synchronizujem " + sy.pct + " %" : "Synchronizovať"; primary: sy.pct < 0 && sy.plan.length > 0
                    onClicked: if (sy.pct < 0 && sy.plan.length) { sy.pct = 0; syRun.command = ["latte-tc", "synchronizuj", tc.dirA, tc.dirB, "--smer", sy.smer].concat(sy.obsah ? ["--obsah"] : []).concat(["--vykonaj"]); syRun.running = true; } }
              Btn { label: "Zavrieť"; onClicked: tc.close() } }
    }

    // ═══ archív ako priečinok ═══════════════════════════════════════════════════════════
    Card {
        id: ar
        visible: tc.tool === "archiv"
        title: "Archív · " + (tc.items[0] ? tc.items[0].name : "") + (ar.prefix ? " › " + ar.prefix : "")
        w: 860; h: 620
        property var all: []
        property string prefix: ""
        property var sel: ({})
        property string err: ""
        property bool needPw: false
        property string pw: ""
        function pwArgs() { return ar.pw !== "" ? ["--heslo"] : []; }
        function load() { arList.input = ar.pw; arList.command = ["latte-tc", "archiv", "zoznam", tc.items[0].path].concat(pwArgs()); arList.running = true; }
        function delMarked() {
            const l = Object.keys(ar.sel); if (!l.length) return;
            arDel.input = ar.pw; arDel.command = ["latte-tc", "archiv", "smaz", tc.items[0].path].concat(l).concat(pwArgs()); arDel.running = true;
        }
        Keys.onPressed: (ev) => { if (ev.key === Qt.Key_F8 || ev.key === Qt.Key_Delete) { ar.delMarked(); ev.accepted = true; } }
        readonly property var shown: {
            const out = [], seen = {};
            for (const it of all) {
                if (prefix && !it.name.startsWith(prefix + "/")) continue;
                const rest = prefix ? it.name.slice(prefix.length + 1) : it.name;
                if (!rest) continue;
                const top = rest.split("/")[0], isDir = rest.includes("/") || it.dir;
                if (seen[top]) continue; seen[top] = true;
                out.push({ name: top, full: (prefix ? prefix + "/" : "") + top, dir: isDir, size: isDir ? 0 : it.size, date: it.date });
            }
            return out.sort((a, b) => (b.dir - a.dir) || a.name.localeCompare(b.name));
        }
        Tool { id: arList; onResult: (c, out) => { try { const j = JSON.parse(out); ar.all = j.items; ar.err = j.error; ar.needPw = !!j.needPassword;
                                                         if (ar.needPw) arPw.input.forceActiveFocus(); } catch (e) { ar.all = []; ar.err = "archív sa nedá prečítať"; } } }
        Tool { id: arOut; onResult: (c, out) => tc.done(c === 0 ? "Rozbalené do " + tc.dirB : (c === 3 ? "Zlé alebo chýbajúce heslo" : "Rozbaľovanie zlyhalo")) }
        Tool { id: arTest; onResult: (c, out) => tc.done(c === 0 ? "Archív je v poriadku ✓" : (c === 3 ? "Zlé alebo chýbajúce heslo" : "Archív je poškodený: " + out)) }
        Tool { id: arDel; onResult: (c, out) => { if (c === 0) { ar.sel = {}; ar.load(); } else tc.done(c === 3 ? "Zlé heslo" : "Mazanie v archíve zlyhalo (rar a iso sa meniť nedajú)"); } }
        onVisibleChanged: if (visible) { all = []; prefix = ""; sel = {}; err = ""; needPw = false; pw = ""; load(); forceActiveFocus(); }
        Row { id: arBar; spacing: 8
              Btn { label: "↑ .."; onClicked: { const p = ar.prefix; ar.prefix = p.includes("/") ? p.substring(0, p.lastIndexOf("/")) : ""; } }
              Btn { label: "Rozbaliť označené (F5)"; primary: Object.keys(ar.sel).length > 0; onClicked: { const l = Object.keys(ar.sel); if (!l.length) return; arOut.input = ar.pw; arOut.command = ["latte-tc", "archiv", "rozbal", tc.items[0].path, tc.dirB].concat(l).concat(ar.pwArgs()); arOut.running = true; } }
              Btn { label: "Rozbaliť všetko (Alt+F9)"; onClicked: { arOut.input = ar.pw; arOut.command = ["latte-tc", "archiv", "rozbal", tc.items[0].path, tc.dirB].concat(ar.pwArgs()); arOut.running = true; } }
              Btn { label: "Test"; onClicked: { arTest.input = ar.pw; arTest.command = ["latte-tc", "archiv", "test", tc.items[0].path].concat(ar.pwArgs()); arTest.running = true; } }
              Btn { label: "Zmazať označené (F8)"; visible: Object.keys(ar.sel).length > 0; onClicked: ar.delMarked() }
              Text { anchors.verticalCenter: parent.verticalCenter; text: ar.all.length + " položiek · cieľ: " + tc.dirB.split("/").pop(); color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } } }
        Text { visible: ar.err !== "" && !ar.needPw; y: 40; width: parent.width; wrapMode: Text.WordWrap; text: ar.err; color: tc.theme.error; font { family: tc.theme.fontUi; pixelSize: 12 } }
        Column {
            visible: ar.needPw; y: 44; z: 2; width: 380; spacing: 6
            Lbl { text: ar.err.toUpperCase() }
            Row { spacing: 6
                  Field { id: arPw; width: 260; secret: true; hint: "heslo archívu"; onAccepted: { ar.pw = arPw.text; ar.load(); } }
                  Btn { label: "Otvoriť"; primary: true; onClicked: { ar.pw = arPw.text; ar.load(); } } }
        }
        ListView {
            id: arView
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: arBar.bottom; topMargin: 10 }
            clip: true; model: ar.shown
            ScrollHint { flick: arView; colors: tc.theme }
            delegate: Rectangle {
                required property var modelData
                readonly property bool marked: ar.sel[modelData.full] !== undefined
                width: arView.width; height: 26; radius: 6; color: am.containsMouse ? tc.theme.hover : "transparent"
                Glyph { x: 6; anchors.verticalCenter: parent.verticalCenter; name: modelData.dir ? "folder" : "file"; size: 14; color: modelData.dir ? tc.theme.primary : tc.theme.fgDim }
                Text { x: 28; width: parent.width - 220; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: modelData.name
                       color: parent.marked ? tc.theme.error : tc.theme.fg; font { family: tc.theme.fontUi; pixelSize: 12; weight: parent.marked || modelData.dir ? Font.DemiBold : Font.Normal } }
                Text { x: parent.width - 190; width: 80; anchors.verticalCenter: parent.verticalCenter; text: modelData.dir ? "<DIR>" : tc.human(modelData.size); color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } }
                Text { x: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; text: modelData.date; color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } }
                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true
                            onClicked: { const s = Object.assign({}, ar.sel); if (s[modelData.full] !== undefined) delete s[modelData.full]; else s[modelData.full] = true; ar.sel = s; }
                            onDoubleClicked: if (modelData.dir) { ar.prefix = modelData.full; ar.sel = {}; } }
            }
        }
    }

    // ═══ vlastnosti a atribúty ═══════════════════════════════════════════════════════════
    Card {
        id: at
        visible: tc.tool === "atributy"
        title: "Vlastnosti a atribúty · " + (tc.items.length === 1 ? tc.items[0].name : tc.items.length + " položiek")
        w: 640; h: 600
        property var info: null
        property bool rek: false
        Process { id: chownRun }
        Tool { id: atInfo; onResult: (c, out) => { try { at.info = JSON.parse(out); aMode.text = at.info.mode; aDate.text = at.info.modified; aOwner.text = at.info.owner + ":" + at.info.group; } catch (e) {} } }
        Tool { id: atSet; onResult: (c, out) => { tc.done(c === 0 ? "Atribúty zmenené" : "Zmena atribútov zlyhala (práva?)"); if (c === 0) tc.close(); } }
        onVisibleChanged: if (visible) { info = null; rek = false; atInfo.command = ["latte-tc", "vlastnosti", tc.items[0].path]; atInfo.running = true; }
        Column {
            width: parent.width; spacing: 6
            Repeater {
                model: at.info ? [["Cesta", at.info.path], ["Typ", at.info.mime + (at.info.link ? " · odkaz na " + at.info.link : "")], ["Veľkosť", tc.human(at.info.size) + " (" + at.info.size + " B)"],
                                  ["Vlastník", at.info.owner + " : " + at.info.group], ["Práva", at.info.rwx + " (" + at.info.mode + ")"],
                                  ["Zmenené", at.info.modified], ["Otvorené", at.info.accessed], ["Inode · odkazy", at.info.inode + " · " + at.info.links]] : []
                Row { required property var modelData; spacing: 10; width: parent.width
                      Text { width: 110; text: modelData[0]; color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 12 } }
                      Text { width: parent.width - 120; elide: Text.ElideMiddle; text: modelData[1]; color: tc.theme.fg; font { family: tc.theme.fontUi; pixelSize: 12 } } }
            }
            Lbl { text: "PRÁVA (osmičkovo, napr. 644 = rw-r--r--, 755 = rwxr-xr-x)"; topPadding: 8 }
            Row { spacing: 6
                  Field { id: aMode; width: 90 }
                  Repeater { model: [["644", "súbor"], ["600", "súkromný"], ["755", "program / priečinok"], ["700", "súkromný priečinok"]]
                             Btn { required property var modelData; label: modelData[0] + " " + modelData[1]; onClicked: aMode.text = modelData[0] } } }
            Lbl { text: "DÁTUM ZMENY (RRRR-MM-DD HH:MM)" }
            Row { spacing: 6; Field { id: aDate; width: 200 } Btn { label: "Teraz"; onClicked: aDate.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm") } }
            Lbl { text: "VLASTNÍK : SKUPINA (zmena so správcom, v termináli sa opýta na heslo)" }
            Row { spacing: 6
                  Field { id: aOwner; width: 200 }
                  Btn { label: "Zmeniť vlastníka"
                        onClicked: {
                            const own = aOwner.text.trim();
                            if (!/^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$/.test(own)) { tc.done("Vlastník: meno alebo meno:skupina"); return; }
                            chownRun.command = ["foot", "-T", "Zmena vlastníka", "sh", "-c",
                                'o="$1"; r="$2"; shift 2; echo "sudo chown $r $o …"; sudo chown $r -- "$o" "$@" && echo "Hotovo." || echo "Zlyhalo."; printf "Enter zavrie okno"; read x',
                                "sh", own, at.rek ? "-R" : ""].concat(tc.items.map(e => e.path));
                            chownRun.startDetached(); tc.close();
                        } } }
            Btn { label: (at.rek ? "☑" : "☐") + " Aj obsah priečinkov"; onClicked: at.rek = !at.rek }
            Row { spacing: 8; topPadding: 6
                  Btn { label: "Uložiť"; primary: true
                        onClicked: { atSet.command = ["latte-tc", "atributy"].concat(aMode.text !== (at.info ? at.info.mode : "") ? ["--prava", aMode.text] : [])
                                                     .concat(aDate.text !== (at.info ? at.info.modified : "") ? ["--datum", aDate.text] : []).concat(at.rek ? ["--rekurzivne"] : []).concat(["--"]).concat(tc.items.map(e => e.path));
                                     atSet.running = true; } }
                  Btn { label: "Zavrieť"; onClicked: tc.close() } }
        }
    }

    // ═══ zbaliť (Alt+F5) ═════════════════════════════════════════════════════════════════
    Card {
        id: zb
        visible: tc.tool === "zbal"
        title: "Zbaliť (Alt+F5) · " + (tc.items.length === 1 ? tc.items[0].name : tc.items.length + " položiek")
        w: 620; h: 380
        property string fmt: "zip"
        readonly property bool pwOk: fmt === "zip" || fmt === "7z"
        Tool { id: zbRun; onResult: (c, out) => tc.done(c === 0 ? "Zbalené: " + zName.text.split("/").pop() : "Balenie zlyhalo") }
        function base() { return tc.items.length === 1 ? tc.items[0].name.replace(/\.[^./]+$/, "") : (tc.dirA.split("/").pop() || "archiv"); }
        onVisibleChanged: if (visible) { fmt = "zip"; zName.text = tc.dirB + "/" + base() + ".zip"; zPw.text = ""; zVol.text = ""; zName.input.forceActiveFocus(); }
        onFmtChanged: zName.text = zName.text.replace(/\.(zip|7z|tar\.gz|tar\.xz|tar\.zst)$/, "") + "." + fmt
        Column {
            width: parent.width; spacing: 8
            Lbl { text: "ARCHÍV" }
            Field { id: zName; onAccepted: zbGo.clicked() }
            Row { spacing: 4; Repeater { model: ["zip", "7z", "tar.gz", "tar.xz", "tar.zst"]
                                         Btn { required property string modelData; label: modelData; on: zb.fmt === modelData; onClicked: zb.fmt = modelData } } }
            Row { spacing: 8; visible: zb.pwOk
                  Column { spacing: 4; Lbl { text: "HESLO (AES-256" + (zb.fmt === "7z" ? ", skryje aj mená" : "") + ")" }
                           Field { id: zPw; width: 250; secret: true; hint: "bez hesla"; onAccepted: zbGo.clicked() } }
                  Column { spacing: 4; Lbl { text: "ZVÄZKY (napr. 700M, 4G)" }
                           Field { id: zVol; width: 150; hint: "jeden súbor"; onAccepted: zbGo.clicked() } } }
            Row { spacing: 8
                  Btn { id: zbGo; label: "Zbaliť"; primary: true
                        onClicked: { const pw = zb.pwOk ? zPw.text : "", vol = zb.pwOk ? zVol.text.trim() : "";
                                     zbRun.input = pw;
                                     zbRun.command = ["latte-tc", "archiv", "zbal", zName.text].concat(tc.items.map(e => e.path)).concat(pw ? ["--heslo"] : []).concat(vol ? ["--casti", vol] : []);
                                     zbRun.running = true; tc.close(); } }
                  Btn { label: "Zrušiť"; onClicked: tc.close() } }
        }
    }

    // ═══ rozdeliť súbor ══════════════════════════════════════════════════════════════════
    Card {
        id: rz
        visible: tc.tool === "rozdel"
        title: "Rozdeliť súbor · " + (tc.items[0] ? tc.items[0].name + " (" + tc.human(tc.items[0].size) + ")" : "")
        w: 620; h: 300
        Tool { id: rzRun; onResult: (c, out) => tc.done(c === 0 ? "Rozdelené do " + tc.dirB + " (spojíš „Spojiť“ na .001)" : "Rozdelenie zlyhalo") }
        onVisibleChanged: if (visible) { rzSize.text = "100M"; rzSize.input.forceActiveFocus(); }
        Column {
            width: parent.width; spacing: 8
            Lbl { text: "VEĽKOSŤ ČASTI" }
            Row { spacing: 4
                  Field { id: rzSize; width: 110; onAccepted: rzGo.clicked() }
                  Repeater { model: ["100M", "700M", "1G", "4G"]; Btn { required property string modelData; label: modelData; onClicked: rzSize.text = modelData } } }
            Text { text: "Cieľ: " + tc.dirB; color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 12 } }
            Row { spacing: 8
                  Btn { id: rzGo; label: "Rozdeliť"; primary: true; onClicked: { rzRun.command = ["latte-tc", "rozdel", tc.items[0].path, rzSize.text, tc.dirB]; rzRun.running = true; tc.close(); } }
                  Btn { label: "Zrušiť"; onClicked: tc.close() } }
        }
    }

    // ═══ strom priečinkov (Alt+F10 / Ctrl+F8) ═══════════════════════════════════════════
    Card {
        id: tr
        visible: tc.tool === "strom"
        title: "Strom priečinkov (Alt+F10) · " + tr.rootDir.replace(Quickshell.env("HOME") || "~", "~")
        w: 620; h: 640
        property string rootDir: "/"
        property var rows: []              // [{ name, path, depth, more, open }]
        property int cur: 0
        property string find: ""
        property bool hidden: false
        property var pending: ({})         // path → index čakajúci na podpriečinky
        function start() {
            rootDir = (Quickshell.env("HOME") || "/");
            rows = [{ name: "/", path: "/", depth: 0, more: true, open: false }];
            cur = 0; find = ""; expand(0, tc.dirA);
        }
        // rozbalí riadok i; ak je `toward` pod ním, rozbaľuje ďalej až k nemu (strom sa otvorí na aktívnom priečinku)
        property string toward: ""
        function expand(i, towardPath) {
            const r = rows[i]; if (!r || r.open) return;
            toward = towardPath || "";
            const q = trProc.createObject(tr, { row: i, parentPath: r.path });
            q.command = ["latte-tc", "strom", r.path]; q.running = true;
        }
        function collapse(i) {
            const r = rows[i]; if (!r || !r.open) return;
            let j = i + 1; while (j < rows.length && rows[j].depth > r.depth) j++;
            const n = rows.slice(); n.splice(i + 1, j - i - 1); n[i] = Object.assign({}, r, { open: false }); rows = n;
        }
        function inserted(i, parentPath, list) {
            if (!rows[i] || rows[i].path !== parentPath) return;
            const r = rows[i], kids = list.filter(k => tr.hidden || !k.hidden).map(k => ({ name: k.name, path: k.path, depth: r.depth + 1, more: k.more, open: false }));
            const n = rows.slice(); n[i] = Object.assign({}, r, { open: true, more: kids.length > 0 }); n.splice.apply(n, [i + 1, 0].concat(kids)); rows = n;
            if (toward && toward !== parentPath) {
                const k = n.findIndex((x, idx) => idx > i && (toward === x.path || toward.startsWith(x.path === "/" ? "/" : x.path + "/")));
                if (k >= 0) { if (toward === n[k].path) { cur = k; toward = ""; trView.positionViewAtIndex(k, ListView.Center); } else expand(k, toward); }
            }
        }
        Component { id: trProc; Tool { property int row: 0; property string parentPath: ""
                                         onResult: (c, out) => { let l = []; try { l = JSON.parse(out); } catch (e) {} tr.inserted(row, parentPath, l); destroy(); } } }
        function go(i) { const r = rows[i]; if (r) { tc.goTo(r.path, ""); tc.close(); } }
        onVisibleChanged: if (visible) { start(); forceActiveFocus(); }
        Keys.onPressed: (ev) => {
            ev.accepted = true;
            if (ev.key === Qt.Key_Down) cur = Math.min(rows.length - 1, cur + 1);
            else if (ev.key === Qt.Key_Up) cur = Math.max(0, cur - 1);
            else if (ev.key === Qt.Key_PageDown) cur = Math.min(rows.length - 1, cur + 15);
            else if (ev.key === Qt.Key_PageUp) cur = Math.max(0, cur - 15);
            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Plus) { if (rows[cur] && rows[cur].open) cur = Math.min(rows.length - 1, cur + 1); else expand(cur); }
            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Minus) {
                if (rows[cur] && rows[cur].open) collapse(cur);
                else { let j = cur - 1; while (j >= 0 && rows[j].depth >= rows[cur].depth) j--; if (j >= 0) cur = j; }
            }
            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) go(cur);
            else if (ev.key === Qt.Key_Escape) { if (find) find = ""; else tc.close(); }
            else if (ev.key === Qt.Key_Backspace) find = find.slice(0, -1);
            else if (ev.text && ev.text.length === 1 && ev.text > " ") {
                find += ev.text;
                const f = find.toLowerCase();
                for (let k = 0; k < rows.length; k++) { const j = (cur + k) % rows.length; if (rows[j].name.toLowerCase().startsWith(f)) { cur = j; break; } }
            }
            else ev.accepted = false;
            trView.positionViewAtIndex(cur, ListView.Contain);
        }
        Row { id: trBar; spacing: 8
              Btn { label: "Domov"; onClicked: { const h = Quickshell.env("HOME") || "/"; tr.start(); tr.toward = h; } }
              Btn { label: (tr.hidden ? "☑" : "☐") + " Skryté"; onClicked: { tr.hidden = !tr.hidden; tr.start(); } }
              Text { anchors.verticalCenter: parent.verticalCenter; text: tr.find ? "Hľadám: " + tr.find : "→ rozbaliť · ← zbaliť · Enter prejsť · písaním hľadať"
                     color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 11 } } }
        ListView {
            id: trView
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: trBar.bottom; topMargin: 10 }
            clip: true; model: tr.rows
            ScrollHint { flick: trView; colors: tc.theme }
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: trView.width; height: 26; radius: 6
                color: index === tr.cur ? Qt.rgba(tc.theme.primary.r, tc.theme.primary.g, tc.theme.primary.b, 0.2) : (tm.containsMouse ? tc.theme.hover : "transparent")
                Text { x: 6 + modelData.depth * 16; width: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.more ? (modelData.open ? "▾" : "▸") : ""
                       color: tc.theme.fgDim; font { family: tc.theme.fontUi; pixelSize: 12 }
                       MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: { tr.cur = index; if (modelData.open) tr.collapse(index); else tr.expand(index); } } }
                Glyph { x: 22 + modelData.depth * 16; anchors.verticalCenter: parent.verticalCenter; name: modelData.open ? "folder-open" : "folder"; size: 14; color: tc.theme.primary }
                Text { x: 42 + modelData.depth * 16; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: modelData.name
                       color: tc.theme.fg; font { family: tc.theme.fontUi; pixelSize: 12; weight: modelData.path === tc.dirA ? Font.Bold : Font.Normal } }
                MouseArea { id: tm; anchors.fill: parent; anchors.leftMargin: 22 + modelData.depth * 16; hoverEnabled: true
                            onClicked: tr.cur = index; onDoubleClicked: tr.go(index) }
            }
        }
    }
}
