// MonitorView — jadro Monitora LatteOS (Prehľad, Procesy, Po štarte, Telemetria, Hardvér, Senzory, Čas v aplikáciách).
// Jedna implementácia pre samostatné okno (monitor.qml) aj Nastavenia › Spúšťanie a na pozadí (embedded, sekcia autorun;
// živé meranie latte-sysmon stream vtedy nebeží). Rozdelené 26. 9. podľa zásady „všetko nastavenie v Nastaveniach“.
// Pôvodný popis okna:
// LatteOS — Monitor (Process Manager / Latte System Monitor), podľa old/IDEAS.md:
// živý stav (CPU, RAM, disky, sieť, teploty), procesy (druh, vlastník, príkaz, ukončenie s varovaním),
// Po štarte (autostart, systemd, časovače, cron s pôvodom) a Výstupy telemetrie. Nie je to nastavenie
// aplikácií (App Manager) ani hardvéru (Device Manager). Spúšťa sa: latte-app monitor, Ctrl+Shift+Esc
import QtQuick
import Quickshell
import Quickshell.Io
import "../data"

Item {
    id: app
    required property var theme
    property bool embedded: false
    property string args: ""                   // sekcia zo spustenia (LATTE_APP_ARGS)
    signal closeRequested()
    readonly property bool live: !(embedded && section === "autorun")   // živé meranie iba keď ho niečo ukazuje
    readonly property var th: theme

    property string section: ({ strom: "procesy" })[args] || args || "prehlad"
    property string search: ""
    property string status: ""
    property var snap: ({ cpu: 0, cores: [], mem: { total: 1, used: 0 }, disk: {}, net: {}, load: [], temps: [], fs: [], procs: [] })
    property var cpuHist: []
    property var devHist: ({})             // Výkon: história po zariadeniach (disk:…, nic:…)
    property string vykonSel: "cpu"
    // zariadenia na stránke Výkon (ako ľavý zoznam vo Win11 Správcovi úloh › Výkon)
    readonly property var devices: {
        const out = [{ key: "cpu", title: "Procesor", glyph: "cpu", value: Math.round(snap.cpu || 0) + " %" + (snap.freq ? "  " + (snap.freq / 1000).toFixed(2).replace(".", ",") + " GHz" : ""), hist: cpuHist, max: 100 },
                     { key: "mem", title: "Pamäť", glyph: "database", value: human((snap.mem || {}).used) + " / " + human((snap.mem || {}).total) + " (" + Math.round(100 * ((snap.mem || {}).used || 0) / Math.max(1, (snap.mem || {}).total || 1)) + " %)", hist: memHist, max: 100 }];
        for (const d of (snap.disks || [])) out.push({ key: "disk:" + d.name, title: "Disk " + d.name + (d.rota ? " (HDD)" : " (SSD)"), glyph: "device-floppy", value: d.active + " %", hist: devHist["disk:" + d.name] || [], max: 100, d: d });
        for (const n of (snap.nics || [])) out.push({ key: "nic:" + n.name, title: (n.wifi ? "Wi-Fi " : "Ethernet ") + n.name, glyph: n.wifi ? "wifi" : "network",
                                                     value: "↓ " + human(n.rx) + "/s  ↑ " + human(n.tx) + "/s", hist: devHist["nic:" + n.name] || [], max: 1024 * 64, n: n });
        if (snap.gpu) out.push({ key: "gpu", title: "Grafika" + (snap.gpu.name ? " · " + snap.gpu.name : ""), glyph: "device-desktop", value: snap.gpu.busy + " %", hist: gpuHist, max: 100 });
        return out;
    }
    property var memHist: []
    property var netHist: []
    property var diskHist: []
    property var gpuHist: []
    property var hw: null
    property var hwRoot: null                   // latte-sysmon hw-root (sudo), uložené v ~/.cache/latteos/hw-root.json
    property bool rootBusy: false
    property string rootError: ""
    readonly property string rootCache: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache")) + "/latteos/hw-root.json"
    FileView { id: rootFile; path: app.rootCache; printErrors: false; atomicWrites: true
               onLoaded: { try { app.hwRoot = JSON.parse(text()); } catch (e) {} } }
    Process {
        id: rootProc
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                app.rootBusy = false;
                try { const j = JSON.parse(this.text); app.hwRoot = j; mkCache.running = true; rootFile.setText(this.text); app.rootError = ""; app.status = "Podrobnosti hardvéru načítané a uložené"; }
                catch (e) { app.rootError = "Nesprávne heslo alebo chyba nástrojov"; }
            }
        }
    }
    Process { id: mkCache; command: ["mkdir", "-p", app.rootCache.replace(/\/[^/]*$/, "")] }
    function loadRoot(pw) {
        rootBusy = true; rootError = "";
        rootProc.command = ["sudo", "-S", "-p", "", "latte-sysmon", "hw-root"];
        rootProc.running = true; rootProc.write(pw + "\n"); rootProc.stdinEnabled = false;
    }
    Process { id: reportProc }
    function saveReport(t) {
        const f = (Quickshell.env("HOME") || "") + "/Dokumenty/Hardvér " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm") + ".txt";
        reportProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\n" "$2" > "$1"', "sh", f, t];
        reportProc.running = true;
        status = "Správa uložená: " + f;
    }
    // Digitálna pohoda (pohoda.qml meria, latte-sysmon pohoda sčíta)
    property var well: null
    property var limits: ({})
    property bool wellOff: false
    readonly property var wellColors: [theme.primary, "#C75B4A", "#6FA8DC", "#8BC48A", "#B58ED8", "#E8C33B"]
    readonly property var wellTop: well ? well.apps.filter(a => a.today > 0).sort((x, y) => y.today - x.today).slice(0, 6) : []
    function wellColor(cls) { const i = wellTop.findIndex(a => a["class"] === cls); return i >= 0 ? wellColors[i] : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.25); }
    function dur(sec) {
        sec = Math.round(sec || 0);
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60);
        return h > 0 ? h + " h " + m + " min" : (m > 0 ? m + " min" : (sec > 0 ? "< 1 min" : "0 min"));
    }
    Process {
        id: wellProc
        command: ["latte-sysmon", "pohoda", "7"]
        stdout: StdioCollector { onStreamFinished: { try { app.well = JSON.parse(this.text); } catch (e) {} } }
    }
    Timer { interval: 60000; repeat: true; running: app.section === "pohoda"; onTriggered: if (!wellProc.running) wellProc.running = true }
    FileView {
        id: limitsFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos/pohoda-limity.json"
        printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { app.limits = JSON.parse(text()) || {}; } catch (e) { app.limits = {}; } }
    }
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos/pohoda"
        printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: app.wellOff = text().trim() === "off"; onLoadFailed: app.wellOff = false
    }
    function setLimit(cls, minutes) {
        const l = Object.assign({}, limits);
        if (minutes > 0) l[cls] = minutes; else delete l[cls];
        limits = l;
        run(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "sh", limitsFile.path, JSON.stringify(l)], minutes > 0 ? "Denný limit " + minutes + " min" : "Limit zrušený");
    }
    function setWellOff(off) {
        wellOff = off;
        const f = (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos/pohoda";
        if (off) run(["sh", "-c", 'printf off > "$1"; pkill -f "apps/[p]ohoda.qml"', "sh", f], "Meranie času pozastavené");
        else run(["sh", "-c", 'rm -f "$1"; pgrep -f "apps/[p]ohoda.qml" >/dev/null || setsid latte-app pohoda >/dev/null 2>&1 &', "sh", f], "Meranie času zapnuté");
    }                  // latte-sysmon hw (Hardvér, ako CPU-Z/HWiNFO)
    property string autorunFilter: ""
    property string kindFilter: ""
    property string sortKey: "cpu"
    property bool tree: (Quickshell.env("LATTE_APP_ARGS") || "").trim() === "strom"   // strom procesov (rodič → deti)
    property bool byApp: !tree                   // procesy zoskupené podľa aplikácie (ako Správca úloh)
    property var expanded: ({})                  // kľúč aplikácie → rozbalená
    property string selApp: "-"                  // vybraná skupina ("-" = žiadna, "" = ostatné procesy)
    readonly property var selGroup: selApp === "-" ? null : (shown.find(r => r.group && r.key === selApp) || null)
    function devText(d) {
        const n = { mic: "mikrofón", camera: "kamera", sound: "prehráva zvuk", gpu: "grafická karta" };
        return d && d.length ? d.map(x => n[x] || x).join(", ") : "žiadne zariadenie";
    }
    function toggleGroup(k) { const e = Object.assign({}, expanded); e[k] = !e[k]; expanded = e; }
    function stopApp(g) {
        if (!g || g.key === "") return;
        const pids = (snap.procs || []).filter(p => p.app === g.key && p.kind !== "system").map(p => String(p.pid));
        if (!pids.length) return;
        if (confirm !== "app:" + g.key) { confirm = "app:" + g.key; status = "Ukončiť aplikáciu " + g.name + " (" + pids.length + " procesov)? Klikni znova."; return; }
        confirm = "";
        run(["kill", "-TERM"].concat(pids), "Ukončujem aplikáciu " + g.name + "…");
    }
    property int selPid: -1
    property string detTab: "prehlad"       // detail procesu: prehlad | subory | siet (ako karty v Process Exploreri)
    property var pdet: null                // latte-sysmon proces PID: stav, priorita, súbory, spojenia, pôvod
    onSelPidChanged: { pdet = null; if (selPid > 0) { detProc.command = ["latte-sysmon", "proces", String(selPid)]; detProc.running = true; } }
    Process { id: detProc; stdout: StdioCollector { onStreamFinished: { try { app.pdet = JSON.parse(this.text); } catch (e) { app.pdet = null; } } } }
    function procAct(p, act, arg, msg) { run(["latte-sysmon", "proces", String(p.pid), act].concat(arg ? [arg] : []), msg); Qt.callLater(() => { detProc.running = true; }); }
    function priorityMenu(p, x, y) {
        ctx.open(x, y, [{ glyph: "chevron-down", label: "Nízka", hint: "na pozadí", action: () => procAct(p, "priorita", "nizka", "Priorita nízka: " + progName(p)) },
                        { glyph: "minus", label: "Normálna", action: () => procAct(p, "priorita", "normalna", "Priorita normálna: " + progName(p)) },
                        { glyph: "arrow-up", label: "Vysoká", hint: "heslo správcu", action: () => procAct(p, "priorita", "vysoka", "Priorita vysoká: " + progName(p)) }], "Priorita · " + progName(p));
    }
    property string confirm: ""           // "term:PID" | "kill:PID" čaká na druhé kliknutie
    property var autorun: []
    readonly property var sel: snap.procs ? (snap.procs.find(p => p.pid === selPid) || null) : null

    readonly property var kinds: ({ app: "Aplikácia", desktop: "Prostredie", helper: "Pomocný", system: "Systém" })
    readonly property var kindHints: ({
        app: "Má okno. Ukončenie zavrie aplikáciu (neuložená práca sa môže stratiť).",
        desktop: "Časť plochy LatteOS (kompozitor, lišta, zvuk, portály). Ukončenie môže zhodiť lištu alebo celú reláciu.",
        helper: "Proces tvojho účtu bez okna (služba, skript, terminál).",
        system: "Patrí systému alebo inému účtu. Ukončiť ho môže iba správca."
    })

    function human(b) {
        if (!b || b < 1024) return (b || 0) + " B";
        const u = ["kB", "MB", "GB", "TB"]; let v = b / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return v.toFixed(v < 10 ? 1 : 0).replace(".", ",") + " " + u[i];
    }
    function push(arr, v) { const a = arr.concat([v]); return a.length > 60 ? a.slice(a.length - 60) : a; }
    function progName(p) {   // „MainThread“ a podobné názvy vlákien nahradí menom programu z príkazu
        const generic = ["MainThread", "Main", "python3", "python", "node", "sh", "bash"];
        if (p.cmd && generic.indexOf(p.name) >= 0) {
            const parts = p.cmd.split(" ");
            const pick = (p.name === "python3" || p.name === "python" || p.name === "node" || p.name === "sh" || p.name === "bash") && parts[1] ? parts[1] : parts[0];
            return pick.split("/").pop() || p.name;
        }
        return p.name;
    }

    // ── dáta: latte-sysmon stream (JSON riadok za sekundu) ─────────────────────────
    Process {
        id: stream
        running: app.live
        command: ["latte-sysmon", "stream", "1", "senzory"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const s = JSON.parse(line);
                    app.snap = s;
                    app.cpuHist = app.push(app.cpuHist, s.cpu);
                    app.memHist = app.push(app.memHist, 100 * s.mem.used / Math.max(1, s.mem.total));
                    app.netHist = app.push(app.netHist, (s.net.rx || 0) + (s.net.tx || 0));
                    app.diskHist = app.push(app.diskHist, (s.disk.read || 0) + (s.disk.write || 0));
                    if (s.gpu) app.gpuHist = app.push(app.gpuHist, s.gpu.busy);
                    // história každého zariadenia (stránka Výkon): disk = aktívny čas %, sieťovka = B/s
                    const dh = Object.assign({}, app.devHist);
                    for (const d of (s.disks || [])) dh["disk:" + d.name] = app.push(dh["disk:" + d.name] || [], d.active);
                    for (const n of (s.nics || [])) dh["nic:" + n.name] = app.push(dh["nic:" + n.name] || [], (n.rx || 0) + (n.tx || 0));
                    app.devHist = dh;
                } catch (e) {}
            }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: if (app.live) stream.running = true }

    Process {
        id: autorunProc
        command: ["latte-sysmon", "autorun"]
        stdout: StdioCollector { onStreamFinished: { try { app.autorun = JSON.parse(this.text); } catch (e) {} } }
    }
    property var services: []
    property var users: []
    property bool hideSystem: false          // Po štarte: skryť položky systému a balíkov (ako „Hide Windows Entries“)
    property string svcFilter: ""
    Process { id: svcProc; command: ["latte-sysmon", "sluzby"]; stdout: StdioCollector { onStreamFinished: { try { app.services = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: usrProc; command: ["latte-sysmon", "pouzivatelia"]; stdout: StdioCollector { onStreamFinished: { try { app.users = JSON.parse(this.text); } catch (e) {} } } }
    Timer { id: reloadSvc; interval: 900; onTriggered: svcProc.running = true }
    function svc(sv, act) { run(["latte-sysmon", "sluzba", sv.scope, act, sv.unit], ({ start: "Spúšťam ", stop: "Zastavujem ", restart: "Reštartujem ", enable: "Pri štarte: ", disable: "Nie pri štarte: " })[act] + sv.unit); reloadSvc.start(); }
    function go(k) { if (k === "sluzby") svcProc.running = true; if (k === "pouzivatelia") usrProc.running = true; section = k; if (k === "pohoda" && !wellProc.running) wellProc.running = true; if (k === "autorun") autorunProc.running = true; if (k === "hardver" && !hwProc.running) hwProc.running = true; }
    Process {
        id: hwProc
        command: ["latte-sysmon", "hw"]
        stdout: StdioCollector { onStreamFinished: { try { app.hw = JSON.parse(this.text); } catch (e) {} } }
    }
    function uptimeText(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return (d ? d + " d " : "") + h + " h " + m + " min";
    }
    Component.onCompleted: go(section)

    Process { id: runner; onExited: (code) => { if (code !== 0 && app.status.indexOf("…") > 0) app.status = "Nepodarilo sa (kód " + code + ")"; } }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) app.status = msg; }

    function stop(p, force) {
        if (!p) return;
        if (p.kind === "system") { status = "Systémový proces: ukončiť ho môže iba správca"; return; }
        const key = (force ? "kill:" : "term:") + p.pid;
        if (confirm !== key) { confirm = key; status = (force ? "Vynútiť ukončenie " : "Ukončiť ") + progName(p) + "? Klikni znova."; return; }
        confirm = "";
        run(["kill", force ? "-KILL" : "-TERM", String(p.pid)], (force ? "Vynútené ukončenie: " : "Ukončujem: ") + progName(p) + "…");
    }
    function toggleAutorun(it) {
        if (it.kind === "autostart") {
            const dst = (Quickshell.env("HOME") || "") + "/.config/autostart/" + it.id;
            if (it.enabled) run(["sh", "-c", "mkdir -p \"$(dirname \"$2\")\"; [ \"$1\" = \"$2\" ] || cp -f \"$1\" \"$2\"; grep -q '^Hidden=' \"$2\" && sed -i 's/^Hidden=.*/Hidden=true/' \"$2\" || printf 'Hidden=true\\n' >> \"$2\"", "sh", it.origin, dst],
                                "Vypnuté pri štarte: " + it.name + " (iba pre tvoj účet)");
            else run(["sh", "-c", "if [ -e \"/etc/xdg/autostart/$(basename \"$1\")\" ] && grep -q '^Hidden=true' \"$1\"; then rm -f \"$1\"; else sed -i 's/^Hidden=.*/Hidden=false/' \"$1\"; fi", "sh", dst],
                     "Zapnuté pri štarte: " + it.name);
        } else if (it.kind === "user-service" || (it.kind === "timer" && it.owner === "používateľ")) {
            run(["systemctl", "--user", it.enabled ? "disable" : "enable", it.id], (it.enabled ? "Vypnuté: " : "Zapnuté: ") + it.id);
        } else if (it.kind === "service" || it.kind === "timer") {     // systémové: polkit sa opýta na heslo správcu
            run(["latte-sysmon", "sluzba", "system", it.enabled ? "disable" : "enable", it.id], (it.enabled ? "Vypnuté (systém): " : "Zapnuté (systém): ") + it.id);
        } else { status = "Túto položku mení iba správca v jej súbore"; return; }
        reloadAutorun.start();
    }
    Timer { id: reloadAutorun; interval: 700; onTriggered: autorunProc.running = true }

    readonly property var shown: {
        let list = (snap.procs || []).filter(p => (kindFilter === "" || p.kind === kindFilter)
            && (search === "" || (p.name + " " + (p.cmd || "") + " " + p.pid).toLowerCase().includes(search.toLowerCase())));
        const k = sortKey;
        const cmp = (a, b) => k === "name" ? progName(a).localeCompare(progName(b)) : (k === "pid" ? a.pid - b.pid : ((b[k] || 0) - (a[k] || 0)));
        if (byApp && !tree) {
            const names = {}, groups = {};
            for (const a of (snap.apps || [])) names[a.key] = a.name;
            for (const p of list) {
                const key = p.app || "";
                const g = groups[key] = groups[key] || { group: true, key: key, name: key === "" ? "Ostatné procesy" : (names[key] || key), cpu: 0, rss: 0, disk: 0, gpu: 0, net: 0, pid: 0, n: 0, procs: [], hasWin: false, kind: "app",
                                                         dev: key === "" ? [] : (((snap.apps || []).find(a => a.key === key) || {}).dev || []) };
                g.cpu += p.cpu; g.rss += p.rss; g.disk += p.disk || 0; g.gpu += p.gpu || 0; g.net += p.net || 0; g.n++; g.procs.push(p); if (p.window) g.hasWin = true;
            }
            const gcmp = (a, b) => k === "name" ? a.name.localeCompare(b.name) : (k === "pid" || k === "kind" ? a.name.localeCompare(b.name) : ((b[k] || 0) - (a[k] || 0)));
            const gl = Object.values(groups).filter(g => g.key !== "").sort(gcmp);
            if (groups[""]) gl.push(groups[""]);
            const out = [];
            for (const g of gl) {
                out.push(g);
                if (expanded[g.key] || (search !== "" && g.key !== "")) for (const p of g.procs.slice().sort(cmp).slice(0, 200)) out.push(Object.assign({ depth: 1 }, p));
            }
            return out;
        }
        if (!tree) return list.slice().sort(cmp).slice(0, 150);
        // strom: koreň = proces, ktorého rodič nie je v zozname; deti pod rodičom, poradie podľa triedenia
        const byPid = {}, kids = {};
        for (const p of list) byPid[p.pid] = p;
        for (const p of list) { const pp = byPid[p.ppid] ? p.ppid : 0; (kids[pp] = kids[pp] || []).push(p); }
        const out = [];
        const walk = (pid, depth) => { for (const c of (kids[pid] || []).sort(cmp)) { out.push(Object.assign({ depth: depth }, c)); if (out.length < 400) walk(c.pid, depth + 1); } };
        walk(0, 0);
        return out;
    }

    // ── okno ─────────────────────────────────────────────────────────────────────
    Item {
        id: root
        anchors.fill: parent

        SideBar {
            id: side
            visible: !app.embedded; width: app.embedded ? 0 : 250
            theme: app.theme
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            heading: "Monitor"; headingGlyph: "activity"
            current: app.section
            model: [
                { title: "Stav", items: [
                    { key: "prehlad", glyph: "activity", label: "Prehľad", sub: "CPU " + Math.round(app.snap.cpu) + " % · RAM " + app.human(app.snap.mem.used) },
                    { key: "procesy", glyph: "list-check", label: "Procesy", sub: (app.snap.procCount || 0) + " bežiacich" },
                    { key: "vykon", glyph: "activity", label: "Výkon", sub: "každé zariadenie s grafom (ako Win11)" }
                ] },
                { title: "Ty", items: [
                    { key: "pohoda", glyph: "clock", label: "Čas v aplikáciách", sub: app.well ? "dnes " + app.dur(app.well.days[app.well.days.length - 1].s) : "digitálna pohoda" }
                ] },
                { title: "Systém", items: [
                    { key: "hardver", glyph: "cpu", label: "Hardvér", sub: "ako CPU-Z: procesor, pamäť, SPD, disky" },
                    { key: "senzory", glyph: "activity", label: "Senzory", sub: "ako HWiNFO: takty, teploty, záťaž, grafy" }
                ] },
                { title: "Správa", items: [
                    { key: "autorun", glyph: "player-play", label: "Po štarte", sub: "ako Autoruns: všetko, čo sa spúšťa" },
                    { key: "sluzby", glyph: "server", label: "Služby", sub: "systemd: spustiť, zastaviť, pri štarte" },
                    { key: "pouzivatelia", glyph: "users", label: "Používatelia", sub: "prihlásení a ich procesy" },
                    { key: "telemetria", glyph: "device-desktop", label: "Výstupy telemetrie", sub: "OLED, Stream Deck, panel" }
                ] }
            ]
            onActivated: (it) => app.go(it.key)
        }

        HeaderBar {
            id: header
            theme: app.theme
            appId: "latteos-monitor"
            windowControls: !app.embedded; netVisible: !app.embedded
            anchors { left: side.right; right: parent.right; top: parent.top }
            title: ({ prehlad: "Prehľad", procesy: "Procesy", autorun: "Po štarte", telemetria: "Výstupy telemetrie", hardver: "Hardvér", senzory: "Senzory", pohoda: "Čas v aplikáciách" })[app.section]
            searchPlaceholder: app.section === "autorun" ? "Hľadať v štarte" : (app.section === "sluzby" ? "Hľadať službu" : "Hľadať proces")
            onSearchChanged: (t) => { if (app.section === "autorun" || app.section === "sluzby") { app.autorunFilter = t; return; } app.search = t; if (t !== "") app.section = "procesy"; }
            onCloseRequested: app.closeRequested()
        }

        Loader {
            id: content
            anchors { left: side.right; top: header.bottom; bottom: statusBar.top; right: app.section === "procesy" ? detail.left : parent.right; margins: 20 }
            sourceComponent: ({ prehlad: pPrehlad, procesy: pProcesy, vykon: pVykon, autorun: pAutorun, sluzby: pSluzby, pouzivatelia: pPouzivatelia, telemetria: pTelemetria, hardver: pHardver, senzory: pSenzory, pohoda: pPohoda })[app.section] || pPrehlad
        }

        // detail vybraného procesu (návrh V2: pravý panel)
        Rectangle {
            id: detail
            visible: app.section === "procesy"
            anchors { right: parent.right; top: header.bottom; bottom: statusBar.top; margins: 14 }
            width: 280; radius: theme.radius; clip: true
            color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.16 : 0.04); border { color: theme.line; width: 1 }
            Column {
                anchors { fill: parent; margins: 16 }
                spacing: 10
                readonly property var p: app.sel
                readonly property var g: app.selGroup
                Text {
                    visible: !!parent.g && !parent.p
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    text: parent.g ? parent.g.name : ""
                    color: theme.fg; font { family: theme.fontDisplay; pixelSize: 19; weight: Font.DemiBold }
                }
                Text {
                    visible: !!parent.g && !parent.p
                    width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                    text: !parent.g ? "" : (parent.g.key === "" ? "Procesy, ktoré nepatria žiadnej aplikácii: prostredie, služby, terminály a systém."
                          : "Aplikácia a všetky jej procesy spolu (okná, pomocné procesy, izolácia Flatpaku). Súčet sa obnovuje každú sekundu.")
                }
                Repeater {
                    model: parent.g && !parent.p ? [["Procesy", String(parent.g.n)], ["CPU spolu", parent.g.cpu.toFixed(1).replace(".", ",") + " %"], ["Pamäť spolu", app.human(parent.g.rss)],
                                                    ["Práve používa", app.devText(parent.g.dev)],
                                                    ["Kľúč", parent.g.key || "—"]] : []
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 1
                        Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                        Text { width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                }
                Text {
                    visible: !parent.g || !!parent.p
                    width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                    text: parent.p ? app.progName(parent.p) : "Vyber proces"
                    color: theme.fg; font { family: theme.fontDisplay; pixelSize: 19; weight: Font.DemiBold }
                }
                Text {
                    visible: !!parent.p
                    text: parent.p ? "● " + app.kinds[parent.p.kind] + (parent.p.window ? " · okno " + parent.p.window : "") : ""
                    color: parent.p && (parent.p.kind === "desktop" || parent.p.kind === "system") ? theme.error : theme.primary
                    font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold }
                }
                Text {
                    visible: !parent.g || !!parent.p
                    width: parent.width; wrapMode: Text.WordWrap
                    text: parent.p ? app.kindHints[parent.p.kind] : "Klikni na proces v zozname. Pravý klik otvorí ponuku."
                    color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                }
                Row {                                   // karty detailu
                    visible: !!parent.p; spacing: 4
                    Repeater {
                        model: [["prehlad", "Prehľad"], ["subory", "Súbory" + (app.pdet ? " " + app.pdet.files.length : "")], ["siet", "Sieť" + (app.pdet ? " " + app.pdet.conns.length : "")]]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: app.detTab === modelData[0]
                            width: dtt.implicitWidth + 18; height: 26; radius: 13
                            color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2) : (dtm.containsMouse ? theme.hover : theme.field)
                            border { color: on ? theme.primary : "transparent"; width: 1 }
                            Text { id: dtt; anchors.centerIn: parent; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                            MouseArea { id: dtm; anchors.fill: parent; hoverEnabled: true; onClicked: app.detTab = modelData[0] }
                        }
                    }
                }
                // Súbory: klik ukáže súbor v Súboroch
                Repeater {
                    model: !!parent.p && app.detTab === "subory" && app.pdet ? app.pdet.files.slice(0, 12) : []
                    Rectangle {
                        required property string modelData
                        width: parent.width; height: 34; radius: 8; color: fm2.containsMouse ? theme.hover : theme.field
                        Column { x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.split("/").pop(); color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.substring(0, modelData.lastIndexOf("/")); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10 } } }
                        MouseArea { id: fm2; anchors.fill: parent; hoverEnabled: true; onClicked: app.run(["latte-app", "subory", modelData]) }
                    }
                }
                // Sieť: spojenia procesu
                Repeater {
                    model: !!parent.p && app.detTab === "siet" && app.pdet ? app.pdet.conns.slice(0, 12) : []
                    Rectangle {
                        required property var modelData
                        width: parent.width; height: 34; radius: 8; color: theme.field
                        Column { x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.remote; color: theme.fg; font { family: theme.fontMono; pixelSize: 11 } }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.proto.toUpperCase() + " · " + modelData.state + " · z " + modelData.local; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10 } } }
                    }
                }
                Text { visible: !!parent.p && app.detTab !== "prehlad" && !!app.pdet && (app.detTab === "subory" ? app.pdet.files : app.pdet.conns).length > 12
                       text: "… a ďalších " + ((((app.detTab === "subory" ? (app.pdet || {}).files : (app.pdet || {}).conns)) || []).length - 12); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                Text { visible: !!parent.p && app.detTab !== "prehlad" && !!app.pdet && (app.detTab === "subory" ? app.pdet.files : app.pdet.conns).length === 0
                       text: app.detTab === "subory" ? "Proces nemá otvorené súbory" : "Žiadne sieťové spojenia"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                Repeater {
                    model: parent.p && app.detTab === "prehlad" ? [["Používa", app.devText(parent.p.dev)], ["Aplikácia", parent.p.app ? ((app.snap.apps || []).find(a => a.key === parent.p.app) || { name: parent.p.app }).name : "žiadna"],
                                       ["PID / rodič", parent.p.pid + " / " + parent.p.ppid], ["Vlastník", parent.p.user],
                                       ["CPU", parent.p.cpu.toFixed(1).replace(".", ",") + " %"], ["Pamäť", app.human(parent.p.rss) + (app.pdet && app.pdet.swap ? " · swap " + app.human(app.pdet.swap) : "")],
                                       ["Stav", app.pdet ? app.pdet.state + " · " + app.pdet.threads + " vlákien · priorita " + (app.pdet.nice > 0 ? "nízka" : (app.pdet.nice < 0 ? "vysoká" : "normálna")) + " (nice " + app.pdet.nice + ")" : "…"],
                                       ["Disk / GPU / sieť", ((parent.p.disk || 0) > 0 ? app.human(parent.p.disk) + "/s" : "–") + " · " + (parent.p.gpu !== undefined && parent.p.gpu !== null ? parent.p.gpu.toFixed(1).replace(".", ",") + " %" : "–") + " · " + (parent.p.net || 0) + " spojení"],
                                       ["Pôvod", app.pdet ? app.pdet.origin || "—" : "…"],
                                       ["Beží od", app.pdet ? Qt.formatDateTime(new Date(app.pdet.start * 1000), "d. M. yyyy HH:mm") : "…"],
                                       ["Príkaz", parent.p.cmd || parent.p.name]] : []
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 1
                        Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                        Text { width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 5; elide: Text.ElideRight; text: modelData[1]; color: theme.fg
                               font { family: modelData[0] === "Príkaz" ? theme.fontMono : theme.fontUi; pixelSize: modelData[0] === "Príkaz" ? 11 : 12 } }
                    }
                }
                Item { width: 1; height: 4 }
                component Action: Rectangle {
                    id: act
                    property string glyph; property string label; property bool danger: false; property bool on: true
                    signal clicked()
                    width: parent.width; height: 36; radius: 10; opacity: on ? 1 : 0.45
                    color: am.containsMouse && on ? (danger ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2) : theme.hover) : theme.field
                    Row { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                          Glyph { name: act.glyph; size: 16; color: act.danger ? theme.error : theme.fg }
                          Text { text: act.label; color: act.danger ? theme.error : theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } } }
                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; onClicked: if (act.on) act.clicked() }
                }
                Action { visible: !!parent.g && !parent.p && parent.g.key !== ""; glyph: "x"
                         label: parent.g && app.confirm === "app:" + parent.g.key ? "Naozaj ukončiť aplikáciu?" : "Ukončiť aplikáciu"; onClicked: app.stopApp(app.selGroup) }
                Action { visible: !!parent.p; on: !!parent.p && parent.p.kind !== "system"; glyph: "x"
                         label: parent.p && app.confirm === "term:" + parent.p.pid ? "Naozaj ukončiť?" : "Ukončiť"; onClicked: app.stop(app.sel, false) }
                Action { visible: !!parent.p; on: !!parent.p && parent.p.kind !== "system"; danger: true; glyph: "alert-triangle"
                         label: parent.p && app.confirm === "kill:" + parent.p.pid ? "Naozaj vynútiť?" : "Vynútiť ukončenie"; onClicked: app.stop(app.sel, true) }
                Action { visible: !!parent.p; glyph: "clipboard"; label: "Kopírovať príkaz"; onClicked: app.run(["wl-copy", "--", app.sel.cmd || app.sel.name], "Príkaz skopírovaný") }
                // ako Správca úloh Win11: priorita, úsporný režim, pozastaviť, ukončiť strom
                Action { visible: !!parent.p && parent.p.mine; glyph: "adjustments"; label: "Priorita…"
                         onClicked: { const q = mapToItem(app, 0, height); app.priorityMenu(app.sel, q.x, q.y); } }
                Action { visible: !!parent.p && parent.p.mine; glyph: "moon"; label: app.pdet && app.pdet.nice === 19 ? "Vypnúť úsporný režim" : "Úsporný režim"
                         onClicked: app.procAct(app.sel, "usporny", app.pdet && app.pdet.nice === 19 ? "off" : "on", "Úsporný režim: " + app.progName(app.sel)) }
                Action { visible: !!parent.p && parent.p.mine; glyph: parent.p && parent.p.state === "T" ? "player-play" : "player-pause"
                         label: parent.p && parent.p.state === "T" ? "Pokračovať" : "Pozastaviť"
                         onClicked: app.procAct(app.sel, app.sel.state === "T" ? "pokracuj" : "pauza", "", (app.sel.state === "T" ? "Pokračuje: " : "Pozastavené: ") + app.progName(app.sel)) }
                Action { visible: !!parent.p && parent.p.mine; danger: true; glyph: "list-tree"
                         label: parent.p && app.confirm === "tree:" + parent.p.pid ? "Naozaj ukončiť aj potomkov?" : "Ukončiť strom procesov"
                         onClicked: { if (app.confirm !== "tree:" + app.sel.pid) { app.confirm = "tree:" + app.sel.pid; return; } app.confirm = ""; app.procAct(app.sel, "ukonci-strom", "", "Ukončujem strom: " + app.progName(app.sel)); } }
            }
        }

        Rectangle {
            id: statusBar
            anchors { left: side.right; right: parent.right; bottom: parent.bottom }
            height: app.live ? 30 : 0; visible: app.live; color: "transparent"
            Rectangle { width: parent.width; height: 1; color: theme.line }
            Text {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                text: "záťaž " + (app.snap.load || []).join(" · ") + "   ·   beží " + Math.floor((app.snap.uptime || 0) / 3600) + " h " + Math.floor(((app.snap.uptime || 0) % 3600) / 60) + " min"
                      + (app.status !== "" ? "   ·   " + app.status : "")
                color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
            }
        }

        ContextMenu { id: ctx; theme: app.theme }
    }

    // ── súčasti ──────────────────────────────────────────────────────────────────
    component Graph: Rectangle {
        id: gr
        property string title; property string value; property var values: []; property real maxValue: 100
        height: 160; radius: 14; color: theme.field
        Text { x: 14; y: 10; text: gr.title; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        Text { x: 14; y: 28; width: parent.width - 28; elide: Text.ElideRight; text: gr.value; color: theme.fg; font { family: theme.fontUi; pixelSize: 18; weight: Font.Bold } }
        Canvas {
            id: cv
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; margins: 14; topMargin: 58 }
            onPaint: {
                const c = getContext("2d"); c.reset();
                const v = gr.values, n = v.length; if (n < 2) return;
                const mx = Math.max(gr.maxValue, ...v);
                c.strokeStyle = theme.primary; c.lineWidth = 2; c.beginPath();
                for (let i = 0; i < n; i++) { const x = width * (i + 60 - n) / 59, y = height - height * v[i] / mx; if (i === 0) c.moveTo(x, y); else c.lineTo(x, y); }
                c.stroke();
                c.lineTo(width, height); c.lineTo(width * (60 - n) / 59, height); c.closePath();
                c.fillStyle = Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.14); c.fill();
            }
            Connections { target: gr; function onValuesChanged() { cv.requestPaint(); } }
        }
    }
    component Heading: Text { color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.8 } }
    // bunka tabuľky procesov sfarbená podľa záťaže (ako Správca úloh Win11): sýtejšia = viac
    component HeatCell: Item {
        id: hc
        property real level: 0; property string label; property bool hot: false; property bool strong: false
        height: 32
        Rectangle { anchors { fill: parent; topMargin: 3; bottomMargin: 3; rightMargin: 4 } radius: 6; visible: hc.level > 0.01
                    color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.08 + 0.42 * Math.min(1, hc.level)) }
        Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; text: hc.label; color: hc.hot ? theme.error : theme.fg
               font { family: theme.fontUi; pixelSize: 12; weight: hc.strong ? Font.DemiBold : Font.Normal } }
    }
    component MiniGraph: Canvas {             // malý graf v zozname zariadení (Výkon)
        id: mg
        property var values: []; property real maxValue: 100
        onValuesChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const v = mg.values, n = v.length; if (n < 2) return;
            const mx = Math.max(mg.maxValue, ...v);
            c.strokeStyle = theme.primary; c.lineWidth = 1.5; c.beginPath();
            for (let i = 0; i < n; i++) { const x = width * (i + 60 - n) / 59, y = height - height * v[i] / mx; if (i === 0) c.moveTo(x, y); else c.lineTo(x, y); }
            c.stroke(); c.lineTo(width, height); c.lineTo(width * (60 - n) / 59, height); c.closePath();
            c.fillStyle = Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18); c.fill();
        }
    }

    // ── stránky ──────────────────────────────────────────────────────────────────
    Component {
        id: pPrehlad
        Flickable {
            id: rolovanie1
            ScrollHint { flick: rolovanie1; colors: theme }
            contentHeight: col.implicitHeight; clip: true
            Column {
                id: col
                width: parent.width; spacing: 14
                Row {
                    width: parent.width; spacing: 12
                    Graph { width: (parent.width - 24) / 3; title: "PROCESOR"; value: Math.round(app.snap.cpu) + " %"; values: app.cpuHist }
                    Graph { width: (parent.width - 24) / 3; title: "PAMÄŤ"; value: app.human(app.snap.mem.used) + " / " + app.human(app.snap.mem.total); values: app.memHist }
                    Graph { width: (parent.width - 24) / 3; title: "SIEŤ"; value: "↓ " + app.human(app.snap.net.rx) + "/s  ↑ " + app.human(app.snap.net.tx) + "/s"; values: app.netHist; maxValue: 1024 * 64 }
                }
                Row {
                    width: parent.width; spacing: 12
                    Graph { width: app.snap.gpu ? (parent.width - 24) / 3 : (parent.width - 12) / 2; title: "DISK"; value: "čítanie " + app.human(app.snap.disk.read) + "/s · zápis " + app.human(app.snap.disk.write) + "/s"; values: app.diskHist; maxValue: 1024 * 1024 }
                    Graph { visible: !!app.snap.gpu; width: (parent.width - 24) / 3; title: "GRAFIKA"; value: app.snap.gpu ? app.snap.gpu.busy + " %" + (app.snap.gpu.vramTotal ? " · VRAM " + app.human(app.snap.gpu.vramUsed) + " / " + app.human(app.snap.gpu.vramTotal) : "") : ""; values: app.gpuHist }
                    // súhrn ako vo Win11 Správcovi úloh › Výkon
                    Rectangle {
                        width: app.snap.gpu ? (parent.width - 24) / 3 : (parent.width - 12) / 2; height: 160; radius: 14; color: theme.field
                        Grid {
                            x: 14; y: 12; columns: 2; columnSpacing: 18; rowSpacing: 8
                            Repeater {
                                model: [["Rýchlosť", (app.snap.freq ? (app.snap.freq / 1000).toFixed(2).replace(".", ",") + " GHz" : "—")],
                                        ["Procesy", String(app.snap.procCount || 0)], ["Vlákna", String(app.snap.threads || 0)],
                                        ["Záťaž", (app.snap.load || []).join(" · ")], ["Doba behu", app.uptimeText(app.snap.uptime || 0)],
                                        ["Swap", app.human(app.snap.mem.swapUsed || 0) + " / " + app.human(app.snap.mem.swapTotal || 0)]]
                                Column {
                                    required property var modelData
                                    Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
                                    Text { text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                                }
                            }
                        }
                    }
                }
                Heading { text: "JADRÁ PROCESORA" }
                Flow {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: app.snap.cores || []
                        Rectangle {
                            required property real modelData
                            required property int index
                            width: 110; height: 44; radius: 10; color: theme.field
                            Text { x: 10; y: 6; text: "jadro " + index; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                            Text { anchors { right: parent.right; rightMargin: 10 } y: 5; text: Math.round(modelData) + " %"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                            Rectangle { x: 10; y: 30; width: parent.width - 20; height: 4; radius: 2; color: theme.line
                                        Rectangle { width: parent.width * Math.min(1, parent.parent.modelData / 100); height: 4; radius: 2; color: theme.primary } }
                        }
                    }
                }
                Heading { text: "DISKY" }
                Repeater {
                    model: app.snap.fs || []
                    Rectangle {
                        required property var modelData
                        width: Math.min(parent.width, 620); height: 50; radius: 12; color: theme.field
                        Text { x: 14; y: 8; text: modelData.mount + "  ·  " + modelData.fs; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                        Text { anchors { right: parent.right; rightMargin: 14 } y: 8; text: app.human(modelData.used) + " z " + app.human(modelData.total); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                        Rectangle { x: 14; y: 34; width: parent.width - 28; height: 4; radius: 2; color: theme.line
                                    Rectangle { width: parent.width * parent.parent.modelData.used / Math.max(1, parent.parent.modelData.total); height: 4; radius: 2; color: theme.primary } }
                    }
                }
                Text { text: "Čítanie " + app.human(app.snap.disk.read) + "/s · zápis " + app.human(app.snap.disk.write) + "/s"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                Heading { text: "TEPLOTY" }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: (app.snap.temps || []).length ? app.snap.temps.map(t => t.label + " " + Math.round(t.c) + " °C").join("   ·   ")
                                                        : "Senzory teploty nie sú dostupné (vo VM bežné; na reálnom HW sa ukážu CPU, GPU a disky)."
                    color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                }
            }
        }
    }

    Component {
        id: pProcesy
        Item {
            Row {
                id: filters
                spacing: 6
                Rectangle {
                    width: tt.implicitWidth + 26; height: 32; radius: 10
                    color: app.tree ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : theme.field
                    border { color: app.tree ? theme.primary : "transparent"; width: 1.5 }
                    Text { id: tt; anchors.centerIn: parent; text: app.tree ? "Strom ✓" : "Strom"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: { app.tree = !app.tree; if (app.tree) app.byApp = false; } }
                }
                Rectangle {
                    width: ta.implicitWidth + 26; height: 32; radius: 10
                    color: app.byApp ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : theme.field
                    border { color: app.byApp ? theme.primary : "transparent"; width: 1.5 }
                    Text { id: ta; anchors.centerIn: parent; text: app.byApp ? "Podľa aplikácií ✓" : "Podľa aplikácií"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: { app.byApp = !app.byApp; if (app.byApp) app.tree = false; app.selApp = "-"; } }
                }
                Item { width: 8; height: 1 }
                Repeater {
                    model: [["", "Všetky"], ["app", "Aplikácie"], ["desktop", "Prostredie"], ["helper", "Pomocné"], ["system", "Systém"]]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: app.kindFilter === modelData[0]
                        width: ft.implicitWidth + 26; height: 32; radius: 10
                        color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (fm.containsMouse ? theme.hover : theme.field)
                        border { color: on ? theme.primary : "transparent"; width: 1.5 }
                        Text { id: ft; anchors.centerIn: parent; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: on ? Font.Bold : Font.Medium } }
                        MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; onClicked: app.kindFilter = modelData[0] }
                    }
                }
            }
            Row {
                id: head
                anchors { top: filters.bottom; topMargin: 12; left: parent.left; right: parent.right }
                height: 28
                readonly property real nameW: width - 110 - 80 - 100 - 90 - 70 - 60 - 80
                component Col: Item {
                    id: c
                    property string label; property string key; property real w
                    width: w; height: parent.height
                    Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8
                           text: c.label + (app.sortKey === c.key ? "  ↓" : ""); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: app.sortKey = c.key }
                }
                Col { label: "Názov"; key: "name"; w: head.nameW }
                Col { label: "Druh"; key: "kind"; w: 110 }
                Col { label: "CPU"; key: "cpu"; w: 80 }
                Col { label: "Pamäť"; key: "rss"; w: 100 }
                Col { label: "Disk"; key: "disk"; w: 90 }
                Col { label: "GPU"; key: "gpu"; w: 70 }
                Col { label: "Sieť"; key: "net"; w: 60 }
                Col { label: "PID"; key: "pid"; w: 80 }
            }
            ListView {
                id: list
                ScrollHint { flick: list; colors: theme }
                anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: app.shown
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool picked: modelData.group ? app.selApp === modelData.key : app.selPid === modelData.pid
                    width: list.width; height: 32; radius: 8
                    color: picked ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (rm.containsMouse ? theme.hover : "transparent")
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        Item {
                            width: head.nameW; height: 32
                            Glyph { x: 8 + (row.modelData.depth || 0) * 16; anchors.verticalCenter: parent.verticalCenter; size: 15
                                    name: row.modelData.group ? (app.expanded[row.modelData.key] ? "chevron-up" : "chevron-right")
                                                              : ({ app: "window", desktop: "coffee", helper: "terminal-2", system: "shield" })[row.modelData.kind]
                                    color: row.modelData.kind === "app" ? theme.primary : theme.fgDim }
                            Row {                                                            // zariadenia, ktoré aplikácia práve používa
                                id: devIcons
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                Repeater {
                                    model: row.modelData.dev || []
                                    Glyph { required property string modelData; size: 14
                                            name: ({ mic: "microphone", camera: "camera", sound: "volume", gpu: "cpu" })[modelData] || "cpu"
                                            color: modelData === "mic" || modelData === "camera" ? theme.error : (modelData === "sound" ? theme.primary : theme.fgDim) }
                                }
                            }
                            Text { x: 32 + (row.modelData.depth || 0) * 16; width: parent.width - 40 - (row.modelData.depth || 0) * 16 - devIcons.width; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                   text: row.modelData.group ? row.modelData.name + (row.modelData.key !== "" && !row.modelData.hasWin ? "   · na pozadí" : "")
                                         : ((row.modelData.depth || 0) > 0 && !app.byApp ? "└ " : "") + app.progName(row.modelData) + (row.modelData.window && !app.byApp ? "  —  " + row.modelData.window : "")
                                   color: row.modelData.group && row.modelData.key === "" ? theme.fgDim : theme.fg
                                   font { family: theme.fontUi; pixelSize: 13; weight: row.modelData.group || row.modelData.kind === "app" ? Font.DemiBold : Font.Normal } }
                        }
                        Text { width: 110; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                               text: row.modelData.group ? row.modelData.n + (row.modelData.n === 1 ? " proces" : (row.modelData.n < 5 ? " procesy" : " procesov")) : app.kinds[row.modelData.kind] }
                        HeatCell { width: 80; strong: true; label: row.modelData.cpu.toFixed(1).replace(".", ",") + " %"; hot: row.modelData.cpu > 50
                                   level: row.modelData.cpu / Math.max(25, 100 * Math.max(1, (app.snap.cores || []).length) / 4) }
                        HeatCell { width: 100; label: app.human(row.modelData.rss); level: row.modelData.rss / Math.max(1, ((app.snap.mem || {}).total || 1) * 0.25) }
                        // disk (čítanie + zápis za s), GPU (% času na grafike), sieť (počet spojení) — ako stĺpce Správcu úloh Win11
                        HeatCell { width: 90; label: (row.modelData.disk || 0) > 0 ? app.human(row.modelData.disk) + "/s" : "–"; hot: (row.modelData.disk || 0) > 20971520
                                   level: (row.modelData.disk || 0) / 52428800 }
                        HeatCell { width: 70; label: row.modelData.gpu === undefined || row.modelData.gpu === null ? "–" : row.modelData.gpu.toFixed(1).replace(".", ",") + " %"
                                   hot: (row.modelData.gpu || 0) > 50; level: (row.modelData.gpu || 0) / 100 }
                        Text { width: 60; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: (row.modelData.net || 0) > 0 ? row.modelData.net : "–"
                               color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                        Text { width: 80; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.group ? "" : row.modelData.pid; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                    MouseArea {
                        id: rm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            app.confirm = "";
                            if (row.modelData.group) {
                                const g = row.modelData;
                                app.selApp = g.key; app.selPid = -1;
                                if (m.button !== Qt.RightButton) { app.toggleGroup(g.key); return; }
                                const q = mapToItem(app, m.x, m.y), items = [
                                    { glyph: app.expanded[g.key] ? "chevron-up" : "chevron-right", label: app.expanded[g.key] ? "Zbaliť procesy" : "Rozbaliť procesy", action: () => app.toggleGroup(g.key) }];
                                if (g.key !== "") {
                                    items.push({ separator: true });
                                    items.push({ glyph: "x", label: "Ukončiť aplikáciu", hint: g.n + " procesov", action: () => { app.confirm = "app:" + g.key; app.stopApp(g); } });
                                    if (!g.key.startsWith("latte:")) items.push({ glyph: "apps", label: "Detail v App Manageri", action: () => app.run(["sh", "-c", "setsid latte-app aplikacie detail \"$1\" >/dev/null 2>&1 &", "sh", g.key]) });
                                }
                                ctx.open(q.x, q.y, items, g.name);
                                return;
                            }
                            app.selPid = row.modelData.pid; app.selApp = "-";
                            if (m.button !== Qt.RightButton) return;
                            const p = row.modelData, pt = mapToItem(app, m.x, m.y), sys = p.kind === "system";
                            ctx.open(pt.x, pt.y, [
                                { glyph: "x", label: "Ukončiť", hint: sys ? "správca" : "", enabled: !sys, action: () => { app.confirm = "term:" + p.pid; app.stop(p, false); } },
                                { glyph: "alert-triangle", label: "Vynútiť ukončenie", danger: true, enabled: !sys, action: () => { app.confirm = "kill:" + p.pid; app.stop(p, true); } },
                                { separator: true },
                                { glyph: "clipboard", label: "Kopírovať príkaz", action: () => app.run(["wl-copy", "--", p.cmd || p.name], "Príkaz skopírovaný") },
                                { glyph: "folder", label: "Priečinok programu", action: () => app.run(["sh", "-c", "d=$(dirname \"$(readlink /proc/$1/exe)\") && latte-app subory \"$d\"", "sh", String(p.pid)]) },
                                { separator: true },
                                { glyph: "adjustments", label: "Priorita…", enabled: p.mine, action: () => Qt.callLater(() => app.priorityMenu(p, pt.x, pt.y)) },
                                { glyph: "moon", label: p.nice === 19 ? "Vypnúť úsporný režim" : "Úsporný režim", enabled: p.mine, action: () => app.procAct(p, "usporny", p.nice === 19 ? "off" : "on", "Úsporný režim: " + app.progName(p)) },
                                { glyph: p.state === "T" ? "player-play" : "player-pause", label: p.state === "T" ? "Pokračovať" : "Pozastaviť", enabled: p.mine,
                                  action: () => app.procAct(p, p.state === "T" ? "pokracuj" : "pauza", "", app.progName(p)) },
                                { glyph: "list-tree", label: "Ukončiť strom procesov", danger: true, enabled: p.mine, action: () => { app.selPid = p.pid; app.confirm = "tree:" + p.pid; app.status = "Ukončiť " + app.progName(p) + " aj s potomkami? Klikni v detaile znova."; } }
                            ], app.progName(p) + " · " + app.kinds[p.kind]);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pAutorun
        Flickable {
            id: rolovanie3
            ScrollHint { flick: rolovanie3; colors: theme }
            contentHeight: acol.implicitHeight; clip: true
            Column {
                id: acol
                width: parent.width; spacing: 6
                Text { width: parent.width; wrapMode: Text.WordWrap; bottomPadding: 6; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                       text: "Čo sa spúšťa po prihlásení a pri štarte systému, odkiaľ to je a aký príkaz. Pôvod: balík systému, Flatpak, LatteOS, tvoje — „neznáme“ nepatrí žiadnemu balíku a stojí za pohľad. Systémové položky sa menia s heslom správcu." }
                Row {
                    spacing: 8
                    Rectangle { width: hs.implicitWidth + 24; height: 30; radius: 15; color: app.hideSystem ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2) : theme.field
                                border { color: app.hideSystem ? theme.primary : theme.line; width: 1 }
                                Text { id: hs; anchors.centerIn: parent; text: (app.hideSystem ? "☑ " : "☐ ") + "Skryť systémové a LatteOS"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                                MouseArea { anchors.fill: parent; onClicked: app.hideSystem = !app.hideSystem } }
                    Rectangle { width: kn.implicitWidth + 24; height: 30; radius: 15; color: theme.field; border { color: theme.line; width: 1 }
                                Text { id: kn; anchors.centerIn: parent; text: "Zapamätať súčasný stav"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                                MouseArea { anchors.fill: parent; onClicked: { app.run(["latte-sysmon", "autorun-znam"], "Zapamätané — nové položky sa odteraz označia"); reloadAutorun.start(); } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                           readonly property int nNew: app.autorun.filter(x => x.new).length
                           text: (app.autorun[0] || {}).since ? (nNew ? "⚠ " + nNew + " nových od " : "nič nové od ") + Qt.formatDate(new Date((app.autorun[0] || {}).since * 1000), "d. M. yyyy") : "porovnanie: najprv Zapamätať súčasný stav" }
                }
                Repeater {
                    model: [["session", "ŠTART RELÁCIE LatteOS (hyprland.lua)"], ["autostart", "AUTOŠTART APLIKÁCIÍ (XDG)"], ["user-service", "SLUŽBY TVOJHO ÚČTU (systemd --user)"],
                            ["timer", "ČASOVAČE"], ["service", "SYSTÉMOVÉ SLUŽBY"], ["cron", "CRON"], ["login", "PRIHLÁSENIE A PROSTREDIE"], ["module", "MODULY JADRA"],
                            ["security", "ZABEZPEČENIE (preload knižníc, sudo, polkit, udev)"]]
                    Column {
                        id: grp
                        required property var modelData
                        readonly property var items: app.autorun.filter(x => x.kind === modelData[0] && !(app.hideSystem && x.system) && (app.autorunFilter === ""
                                                     || (x.name + " " + (x.command || "") + " " + (x.origin || "")).toLowerCase().includes(app.autorunFilter.toLowerCase())))
                        visible: items.length > 0
                        width: acol.width; spacing: 4
                        Heading { text: grp.modelData[1] + "  ·  " + grp.items.length; topPadding: 8 }
                        Repeater {
                            model: grp.items
                            Rectangle {
                                id: ar
                                required property var modelData
                                // ako Autoruns: celý riadok farebne — podozrivé / neznáme (červenkasté), nové od zapamätaného stavu (farba témy)
                                readonly property bool warn: !!modelData.alert || modelData.src === "neznáme" || !!modelData.missing
                                width: grp.width; height: 48; radius: 10
                                color: arMa.containsMouse ? theme.hover : (warn ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.14)
                                       : (modelData.new ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.14) : theme.field))
                                border { color: warn ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.5) : (modelData.new ? theme.primary : "transparent"); width: 1 }
                                opacity: modelData.enabled ? 1 : 0.6
                                Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; size: 18; color: ar.warn ? theme.error : theme.fgDim
                                        name: ar.modelData.alert ? "alert-triangle" : ({ "LatteOS": "coffee", "Flatpak": "box", "tvoje": "user", "systém": "shield", "neznáme": "help" })[ar.modelData.src]
                                              || ((ar.modelData.src || "").startsWith("balík") ? "package" : "point") }
                                MouseArea {    // pravý klik: zapnúť/vypnúť, zdrojový súbor, príkaz
                                    id: arMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.RightButton
                                    onClicked: (m) => {
                                        const e = ar.modelData, q = mapToItem(app, m.x, m.y), items = [];
                                        if (e.canToggle) items.push({ glyph: e.enabled ? "player-pause" : "player-play", label: e.enabled ? "Vypnúť pri štarte" : "Zapnúť pri štarte", action: () => app.toggleAutorun(e) });
                                        if ((e.origin || "").startsWith("/")) {
                                            items.push({ glyph: "file-text", label: "Otvoriť súbor v Heidelbergu", action: () => app.run(["latte-app", "heidelberg", e.origin]) });
                                            items.push({ glyph: "folder", label: "Ukázať v Súboroch", action: () => app.run(["latte-app", "subory", e.origin.substring(0, e.origin.lastIndexOf("/"))]) });
                                        }
                                        if (e.command) items.push({ glyph: "clipboard", label: "Kopírovať príkaz", action: () => app.run(["wl-copy", "--", e.command], "Príkaz skopírovaný") });
                                        items.push({ glyph: "search", label: "Hľadať na webe", action: () => Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(e.name + " linux")) });
                                        ctx.open(q.x, q.y, items, e.name);
                                    }
                                }
                                Column {
                                    x: 44; width: parent.width - 180; anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; elide: Text.ElideRight; text: (ar.modelData.missing ? "⚠ " : "") + ar.modelData.name + (ar.modelData.note ? "  (" + ar.modelData.note + ")" : "") + (ar.modelData.missing ? "  · súbor chýba" : "")
                                           color: ar.modelData.missing ? theme.error : theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                                    Text { width: parent.width; elide: Text.ElideMiddle
                                           text: (ar.modelData.new ? "NOVÉ · " : "") + (ar.modelData.src ? ar.modelData.src + " · " : ar.modelData.owner + " · ")
                                                 + (ar.modelData.impact ? "štart " + (ar.modelData.impact >= 1000 ? (ar.modelData.impact / 1000).toFixed(1).replace(".", ",") + " s" : ar.modelData.impact + " ms") + " · " : "")
                                                 + (ar.modelData.command || ar.modelData.origin)
                                           color: ar.modelData.alert || ar.modelData.src === "neznáme" || ar.modelData.new ? theme.error : theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                                }
                                Rectangle {   // prepínač zapnuté / vypnuté
                                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                    width: 96; height: 30; radius: 15
                                    color: ar.modelData.enabled ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2) : theme.surface
                                    border { color: ar.modelData.enabled ? theme.primary : theme.line; width: 1 }
                                    opacity: ar.modelData.canToggle ? 1 : 0.5
                                    Text { anchors.centerIn: parent; text: (ar.modelData.enabled ? "● zapnuté" : "○ vypnuté"); color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                                    MouseArea { anchors.fill: parent; onClicked: app.toggleAutorun(ar.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pVykon
        Item {
            readonly property var cur: app.devices.find(d => d.key === app.vykonSel) || app.devices[0]
            // vľavo: zoznam zariadení s malými grafmi
            Flickable {
                id: vlist
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 250
                contentHeight: vcol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: vcol
                    width: parent.width; spacing: 6
                    Repeater {
                        model: app.devices
                        Rectangle {
                            id: dt
                            required property var modelData
                            readonly property bool on: app.vykonSel === modelData.key
                            width: vcol.width; height: 66; radius: 12
                            color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.16) : (dm.containsMouse ? theme.hover : theme.field)
                            border { color: on ? theme.primary : "transparent"; width: 1 }
                            MiniGraph { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 70; height: 44; values: dt.modelData.hist; maxValue: dt.modelData.max }
                            Column { x: 88; width: parent.width - 96; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { width: parent.width; elide: Text.ElideRight; text: dt.modelData.title; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: dt.modelData.value; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } } }
                            MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: app.vykonSel = dt.modelData.key }
                        }
                    }
                }
            }
            // vpravo: veľký graf a podrobnosti vybraného zariadenia
            Flickable {
                anchors { left: vlist.right; leftMargin: 16; right: parent.right; top: parent.top; bottom: parent.bottom }
                contentHeight: vdet.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: vdet
                    width: parent.width; spacing: 12
                    readonly property var c: parent.parent.cur
                    Graph { width: parent.width; height: 260; title: vdet.c ? vdet.c.title.toUpperCase() : ""; value: vdet.c ? vdet.c.value : ""; values: vdet.c ? vdet.c.hist : []; maxValue: vdet.c ? vdet.c.max : 100 }
                    // zloženie pamäte ako Win11 (aplikácie, jadro, zdieľaná, vyrovnávacia, voľná) a zram
                    Rectangle {
                        visible: !!vdet.c && vdet.c.key === "mem" && !!app.snap.memc; width: parent.width; height: 70; radius: 12; color: theme.field
                        readonly property var m: app.snap.memc || ({ total: 1 })
                        readonly property var parts: [["Aplikácie", m.apps, theme.primary], ["Jadro", m.kernel, theme.error], ["Zdieľaná", m.shared, theme.fg],
                                                      ["Vyrovnávacia (uvoľní sa)", m.cache, theme.fgDim], ["Voľná", m.free, theme.line]]
                        Row { x: 14; y: 14; width: parent.width - 28; height: 14
                              Repeater { model: parent.parent.parts
                                         Rectangle { required property var modelData; height: 14; color: modelData[2]
                                                     width: parent.width * (modelData[1] || 0) / Math.max(1, parent.parent.m.total) } } }
                        Text { x: 14; y: 40; width: parent.width - 28; elide: Text.ElideRight; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                               text: parent.parts.map(x => x[0] + " " + app.human(x[1] || 0)).join("  ·  ")
                                     + (parent.m.zram && parent.m.zram.orig > 0 ? "  ·  zram " + app.human(parent.m.zram.orig) + " → " + app.human(parent.m.zram.compr)
                                        + " (" + (parent.m.zram.orig / Math.max(1, parent.m.zram.compr)).toFixed(1).replace(".", ",") + "×)" : "") }
                    }
                    Grid {
                        columns: 3; columnSpacing: 28; rowSpacing: 12
                        Repeater {
                            model: !vdet.c ? [] : (vdet.c.key === "cpu" ? [["Využitie", Math.round(app.snap.cpu || 0) + " %"], ["Rýchlosť", app.snap.freq ? (app.snap.freq / 1000).toFixed(2).replace(".", ",") + " GHz" : "—"],
                                                                         ["Jadrá (vlákna)", String((app.snap.cores || []).length)], ["Procesy", String(app.snap.procCount || 0)], ["Vlákna", String(app.snap.threads || 0)],
                                                                         ["Doba behu", app.uptimeText(app.snap.uptime || 0)]]
                                   : vdet.c.key === "mem" ? [["Používaná", app.human(app.snap.mem.used)], ["Dostupná", app.human(app.snap.mem.avail)], ["Celkom", app.human(app.snap.mem.total)],
                                                             ["Swap", app.human(app.snap.mem.swapUsed || 0) + " / " + app.human(app.snap.mem.swapTotal || 0)], ["Neuložené na disk", app.human((app.snap.memc || {}).dirty || 0)]]
                                   : vdet.c.d ? [["Aktívny čas", vdet.c.d.active + " %"], ["Priemerná odozva", String(vdet.c.d.resp).replace(".", ",") + " ms"], ["Typ", vdet.c.d.rota ? "HDD (rotačný)" : "SSD"],
                                                 ["Čítanie", app.human(vdet.c.d.read) + "/s"], ["Zápis", app.human(vdet.c.d.write) + "/s"], ["Model", vdet.c.d.model || "—"]]
                                   : vdet.c.n ? [["Prijíma", app.human(vdet.c.n.rx) + "/s"], ["Odosiela", app.human(vdet.c.n.tx) + "/s"], ["Druh", vdet.c.n.wifi ? "Wi-Fi" : "Ethernet"],
                                                 ["Rýchlosť linky", parseInt(vdet.c.n.speed) > 0 ? vdet.c.n.speed + " Mb/s" : "—"]]
                                   : vdet.c.key === "gpu" ? [["Vyťaženie", app.snap.gpu.busy + " %"], ["VRAM", app.snap.gpu.vramTotal ? app.human(app.snap.gpu.vramUsed) + " / " + app.human(app.snap.gpu.vramTotal) : "—"],
                                                             ["Teplota", app.snap.gpu.temp ? app.snap.gpu.temp + " °C" : "—"], ["Takt", app.snap.gpu.clock ? app.snap.gpu.clock + " MHz" : "—"],
                                                             ["Príkon", app.snap.gpu.power ? app.snap.gpu.power + " W" : "—"]] : [])
                            Column {
                                required property var modelData
                                spacing: 2
                                Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
                                Text { text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 16; weight: Font.Bold } }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: pSluzby
        Flickable {
            id: rolSvc
            ScrollHint { flick: rolSvc; colors: theme }
            contentHeight: scol.implicitHeight; clip: true
            Column {
                id: scol
                width: parent.width; spacing: 4
                Text { width: parent.width; wrapMode: Text.WordWrap; bottomPadding: 6; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                       text: "Služby systému a tvojho účtu (systemd). Klik na stav ju spustí alebo zastaví, pravý klik ponúkne reštart a štart s počítačom. Systémové služby chcú heslo správcu." }
                Repeater {
                    model: [["system", "SYSTÉMOVÉ SLUŽBY"], ["user", "SLUŽBY TVOJHO ÚČTU"]]
                    Column {
                        id: sg
                        required property var modelData
                        readonly property var items: app.services.filter(x => x.scope === modelData[0] && (app.autorunFilter === ""
                                                     || (x.unit + " " + x.desc).toLowerCase().includes(app.autorunFilter.toLowerCase())))
                                                                 .sort((a, b) => (a.active === "active" ? 0 : 1) - (b.active === "active" ? 0 : 1) || a.unit.localeCompare(b.unit))
                        width: scol.width; spacing: 4
                        Heading { text: sg.modelData[1] + "  ·  " + sg.items.filter(x => x.active === "active").length + " beží z " + sg.items.length; topPadding: 8 }
                        Repeater {
                            model: sg.items.slice(0, 300)
                            Rectangle {
                                id: sr
                                required property var modelData
                                width: sg.width; height: 44; radius: 10; color: srm.containsMouse ? theme.hover : theme.field
                                opacity: modelData.active === "active" ? 1 : 0.7
                                MouseArea { id: srm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.RightButton
                                    onClicked: (m) => { const e = sr.modelData, q = mapToItem(app, m.x, m.y);
                                        ctx.open(q.x, q.y, [
                                            { glyph: e.active === "active" ? "player-pause" : "player-play", label: e.active === "active" ? "Zastaviť" : "Spustiť", action: () => app.svc(e, e.active === "active" ? "stop" : "start") },
                                            { glyph: "refresh", label: "Reštartovať", action: () => app.svc(e, "restart") },
                                            { separator: true },
                                            { glyph: "power", label: e.enabled === "enabled" ? "Nespúšťať s počítačom" : "Spúšťať s počítačom", enabled: e.enabled === "enabled" || e.enabled === "disabled",
                                              action: () => app.svc(e, e.enabled === "enabled" ? "disable" : "enable") },
                                            { glyph: "clipboard", label: "Kopírovať názov", action: () => app.run(["wl-copy", "--", e.unit], "Skopírované") },
                                            { glyph: "search", label: "Hľadať na webe", action: () => Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(e.unit + " linux")) }
                                        ], e.unit); } }
                                Column { x: 14; width: parent.width - 260; anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; elide: Text.ElideRight; text: sr.modelData.unit.replace(/\.service$/, ""); color: sr.modelData.active === "failed" ? theme.error : theme.fg
                                           font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                                    Text { width: parent.width; elide: Text.ElideRight; text: sr.modelData.desc; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } } }
                                Text { anchors { right: stb.left; rightMargin: 12; verticalCenter: parent.verticalCenter } color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                                       text: ({ enabled: "pri štarte", disabled: "ručne", static: "závislosť", masked: "zablokovaná", "enabled-runtime": "pri štarte" })[sr.modelData.enabled] || sr.modelData.enabled }
                                Rectangle {
                                    id: stb
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    width: 110; height: 28; radius: 14
                                    color: sr.modelData.active === "active" ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2) : (sr.modelData.active === "failed" ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2) : theme.surface)
                                    border { color: sr.modelData.active === "active" ? theme.primary : (sr.modelData.active === "failed" ? theme.error : theme.line); width: 1 }
                                    Text { anchors.centerIn: parent; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold }
                                           text: ({ active: "● beží", inactive: "○ zastavená", failed: "✕ zlyhala", activating: "… štartuje", deactivating: "… končí" })[sr.modelData.active] || sr.modelData.active }
                                    MouseArea { anchors.fill: parent; onClicked: app.svc(sr.modelData, sr.modelData.active === "active" ? "stop" : "start") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: pPouzivatelia
        Column {
            spacing: 8
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                   text: "Kto je prihlásený na tomto počítači (aj na diaľku cez SSH) a koľko procesov a pamäte používa." }
            Repeater {
                model: app.users
                Rectangle {
                    required property var modelData
                    width: Math.min(parent.width, 620); height: 58; radius: 12; color: theme.field
                    Text { x: 14; y: 10; text: modelData.user + (modelData.sessions.some(x => x.remote) ? "  ·  na diaľku" : ""); color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                    Text { x: 14; y: 32; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                           text: modelData.sessions.length + (modelData.sessions.length === 1 ? " relácia" : " relácie") + " (" + modelData.sessions.map(x => x.tty || x.seat || x.id).join(", ") + ")  ·  "
                                 + modelData.procs + " procesov  ·  " + app.human(modelData.rss) }
                }
            }
            Text { visible: app.users.length === 0; text: "Načítavam…"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
        }
    }
    Component {
        id: pHardver
        HardverView {
            theme: app.th
            hw: app.hw; root: app.hwRoot; snap: app.snap
            rootBusy: app.rootBusy; rootError: app.rootError
            onRefresh: hwProc.running = true
            onLoadRoot: (pw) => app.loadRoot(pw)
            onSaveReport: (t) => app.saveReport(t)
            onCopyText: (t) => app.run(["wl-copy", "--", t], "Správa o hardvéri skopírovaná")
            onOpenDevices: app.run(["latte-app", "zariadenia"], "Správca zariadení")
            onMenu: (t, x, y) => ctx.open(x, y, [{ glyph: "clipboard", label: "Kopírovať", action: () => app.run(["wl-copy", "--", t], "Skopírované") }], "")
        }
    }

    Component {
        id: pSenzory
        SenzoryView {
            theme: app.th
            groups: app.snap.sensors || []
            onOpenMenu: (items, x, y, title) => ctx.open(x, y, items, title)
            onStatus: (t) => app.status = t
        }
    }

    Component {
        id: pPohoda
        // vzhľad podľa serpantinum (AGPL-3.0) je v samostatnom súbore data/PohodaView.qml
        Item {
            id: pohodaPage
            // karty podľa Pulse (data/PohodaPulse.qml); „Aplikácie“ = pôvodný pohľad (data/PohodaView.qml)
            property string tab: "prehlad"
            Row {
                id: pohodaTabs
                spacing: 4
                Repeater {
                    model: [["prehlad", "Prehľad"], ["obrazovka", "Čas obrazovky"], ["aplikacie", "Aplikácie"], ["sustredenie", "Sústredenie"], ["sluch", "Sluch"], ["prehlady", "Prehľady"]]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: pohodaPage.tab === modelData[0]
                        width: ptl.implicitWidth + 24; height: 32; radius: 10
                        color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (ptm.containsMouse ? theme.hover : theme.field)
                        border { color: on ? theme.primary : "transparent"; width: 1.5 }
                        Text { id: ptl; anchors.centerIn: parent; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: on ? Font.Bold : Font.Medium } }
                        MouseArea { id: ptm; anchors.fill: parent; hoverEnabled: true; onClicked: pohodaPage.tab = modelData[0] }
                    }
                }
            }
            PohodaPulse {
                visible: pohodaPage.tab !== "aplikacie"
                anchors { fill: parent; topMargin: 44; bottomMargin: 40 }
                theme: app.th
                page: pohodaPage.tab
                onOpenApps: pohodaPage.tab = "aplikacie"
                onStatus: (t) => app.status = t
            }
            PohodaView {
                id: pview
                visible: pohodaPage.tab === "aplikacie"
                anchors { fill: parent; topMargin: 44; bottomMargin: 40 }
                theme: app.th
                limits: app.limits
                onLimitMenu: (e, x, y) => {
                    const c = e["class"], lim = app.limits[c], items = [];
                    for (const mins of [15, 30, 60, 120, 180])
                        items.push({ glyph: "clock", label: "Denný limit " + (mins < 60 ? mins + " min" : (mins / 60) + " h"), hint: lim === mins ? "✓" : "", action: () => app.setLimit(c, mins) });
                    if (lim) items.push({ glyph: "x", label: "Zrušiť limit", action: () => app.setLimit(c, 0) });
                    if (e.desktop) { items.push({ separator: true });
                        items.push({ glyph: "apps", label: "Detail v App Manageri", action: () => app.run(["latte-app", "aplikacie", "detail", e.desktop]) }); }
                    ctx.open(x, y, items, e.name);
                }
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom } spacing: 12
                Rectangle {
                    width: 46; height: 26; radius: 13; anchors.verticalCenter: parent.verticalCenter
                    color: !app.wellOff ? theme.primary : theme.field; border { color: theme.line; width: 1 }
                    Rectangle { width: 20; height: 20; radius: 10; y: 3; x: !app.wellOff ? 23 : 3; color: !app.wellOff ? theme.fgOnPrimary : theme.fgDim }
                    MouseArea { anchors.fill: parent; onClicked: app.setWellOff(!app.wellOff) }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: "Merať čas v aplikáciách · iba aktívne okno, nie pri 5 min nečinnosti · údaje ostávajú v PC · pravý klik na aplikáciu = denný limit · ←/→ deň" }
            }
        }
    }

    Component {
        id: pTelemetria
        Column {
            spacing: 12
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 }
                   text: "Monitor dáva živé údaje iným zobrazovačom (OLED displej vodného chladenia, Stream Deck, panel lišty) cez jednoduché lokálne rozhranie. Nič na nich nenastavuje." }
            Heading { text: "SÚBOR (obnovuje sa každú sekundu, kým beží Monitor alebo latte-sysmon stream)" }
            Rectangle {
                width: parent.width; height: 40; radius: 10; color: theme.field
                Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "$XDG_RUNTIME_DIR/latteos/telemetry.json"; color: theme.fg; font { family: theme.fontMono; pixelSize: 12 } }
            }
            Heading { text: "UKÁŽKA" }
            Rectangle {
                width: parent.width; height: sample.implicitHeight + 24; radius: 10; color: theme.field
                Text {
                    id: sample
                    x: 12; y: 12; width: parent.width - 24; wrapMode: Text.WrapAnywhere
                    text: JSON.stringify({ cpu: app.snap.cpu, mem: app.snap.mem, net: app.snap.net, disk: app.snap.disk, temps: app.snap.temps, load: app.snap.load })
                    color: theme.fgDim; font { family: theme.fontMono; pixelSize: 11 }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Pripravujeme: stála služba (bez otvoreného Monitora), výber údajov pre každý výstup, pluginy pre Stream Deck a displeje (liquidctl)." }
        }
    }
}
