// LatteOS — Digitálna pohoda: koľko času trávim v ktorej aplikácii (zadanie 24. 9. večer; nápad z videa
// „Hyprland as fluid as it gets“ / serpantinum, rozšírené podľa Pulse — kód je vlastný). Beží skryto na pozadí:
//   každých 5 s pripočíta čas aktívnemu oknu (trieda okna), ak používateľ nie je nečinný (ext-idle-notify,
//   5 min; prehrávané video nečinnosť blokuje, takže sa ráta) a relácia nie je zamknutá,
//   raz za minútu zmeria pamäť (RSS) aktívnej aplikácie aj s podprocesmi → „obvykle v RAM“,
//   denné limity (~/.config/latteos/pohoda-limity.json: { trieda: minúty }) → oznámenie 5 min pred a pri limite,
//   čas pred obrazovkou (úseky aktivity → sedenia a prestávky), prepnutia aplikácií, súvislé sústredenie v jednej
//   aplikácii, sluch (počúvanie a hlasné počúvanie v slúchadlách, latte-sysmon zvuk každých 10 s),
//   režim Sústredenie (IPC pohoda: fokusStart MINÚTY upozornit|odsunut, fokusStop): rozptyľujúca aplikácia
//   (kategória zábava) dostane upozornenie alebo sa minimalizuje (special:minimized, späť z lišty).
// Dáta: ~/.local/share/latteos/pohoda/RRRR-MM-DD.json
//        { apps: { trieda: { s, title, rss, rssN, rssMax } }, hours: [24 × { trieda: s }], halves: [48 × { trieda: s }],
//          screen: [[od, do] s od polnoci], switches, stretch: { n, sum, longest },
//          hearing: { listen, loud, loudHalves[48] }, focus: [{ start, planned, secs, distractions, mode, done }] }
// Stav sústredenia pre UI: $XDG_RUNTIME_DIR/latteos/fokus.json. Kategórie: ~/.config/latteos/pohoda-kategorie.json
// { trieda: "praca"|"zabava"|"neutral" } (inak podľa .desktop). Hlasitosť „hlasno“: ~/.config/latteos/pohoda-sluch (%, 70).
// Vypnutie: ~/.config/latteos/pohoda = off. Spúšťa: latte-app pohoda (hyprland.lua). Zobrazuje: Monitor › Čas v aplikáciách.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: ph
    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos"
    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/latteos/pohoda"
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos"
    property string day: ""
    property var data: ({ apps: {}, hours: [] })
    property bool loaded: false
    property bool dirty: false
    property var limits: ({})
    property var cats: ({})                 // prepísané kategórie
    property int loudPct: 70
    property var warned: ({})               // trieda → "5" | "limit" (dnes už upozornené)
    property string cls: ""
    property string title: ""
    property int pid: 0
    property string address: ""
    property string lastKey: ""
    property int stretchStart: 0            // s od polnoci, začiatok súvislého úseku v jednej aplikácii
    readonly property int step: 5

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
    function nowSec() { const n = new Date(); return n.getHours() * 3600 + n.getMinutes() * 60 + n.getSeconds(); }
    function emptyDay() {
        const h = [], hh = [], lh = [];
        for (let i = 0; i < 24; i++) h.push({});
        for (let i = 0; i < 48; i++) { hh.push({}); lh.push(0); }
        return { apps: {}, hours: h, halves: hh, screen: [], switches: 0, stretch: { n: 0, sum: 0, longest: 0 },
                 hearing: { listen: 0, loud: 0, loudHalves: lh }, focus: [] };
    }
    function normalize(d) {
        const e = emptyDay();
        if (!d.hours || d.hours.length !== 24) d.hours = e.hours;
        if (!d.halves || d.halves.length !== 48) d.halves = e.halves;
        for (const k of ["screen", "switches", "stretch", "hearing", "focus"]) if (d[k] === undefined) d[k] = e[k];
        if (!d.hearing.loudHalves || d.hearing.loudHalves.length !== 48) d.hearing.loudHalves = e.hearing.loudHalves;
        return d;
    }

    FileView { path: ph.cfg + "/pohoda"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: if (text().trim() === "off") Qt.quit() }
    FileView {
        path: ph.cfg + "/pohoda-limity.json"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { ph.limits = JSON.parse(text()) || {}; } catch (e) { ph.limits = {}; } }
        onLoadFailed: ph.limits = {}
    }
    FileView {
        path: ph.cfg + "/pohoda-kategorie.json"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { ph.cats = JSON.parse(text()) || {}; } catch (e) { ph.cats = {}; } }
        onLoadFailed: ph.cats = {}
    }
    FileView {
        path: ph.cfg + "/pohoda-sluch"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: ph.loudPct = parseInt(text()) || 70
    }
    FileView {
        id: store
        path: ph.day !== "" ? ph.dir + "/" + ph.day + ".json" : ""
        printErrors: false; atomicWrites: true
        onLoaded: { try { ph.data = ph.normalize(JSON.parse(text())); } catch (e) { ph.data = ph.emptyDay(); } ph.loaded = true; }
        onLoadFailed: { ph.data = ph.emptyDay(); ph.loaded = true; }
    }
    FileView { id: focusFile; path: ph.runDir + "/fokus.json"; printErrors: false; atomicWrites: true }
    Process { id: mk; running: true; command: ["mkdir", "-p", ph.dir, ph.runDir] }
    Component.onCompleted: day = today()

    IdleMonitor { id: idle; timeout: 300; respectInhibitors: true }

    Process {
        id: probe
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                let w = null;
                try { w = JSON.parse(this.text); } catch (e) {}
                ph.cls = w && w.class ? w["class"] : "";
                ph.title = w && w.title ? w.title : "";
                ph.pid = w && w.pid ? w.pid : 0;
                ph.address = w && w.address ? w.address : "";
                ph.tick();
            }
        }
    }
    // aktívne okno z IPC Quickshellu (bez procesu hyprctl každých 5 s; optimalizácia 26. 9.); lastIpcObject obnoví
    // refreshToplevels pri zmene okna, čas sa pripisuje každých step sekúnd
    Connections { target: Hyprland; function onRawEvent(e) { if (/^(activewindowv2|closewindow|windowtitlev2)$/.test(e.name)) Hyprland.refreshToplevels(); } }
    Timer {
        interval: ph.step * 1000; repeat: true; running: ph.loaded
        onTriggered: {
            const t = Hyprland.activeToplevel, w = t ? t.lastIpcObject : null;
            ph.cls = w && w["class"] ? w["class"] : (t ? (t.wayland ? t.wayland.appId : "") : "");
            ph.title = t ? t.title : "";
            ph.pid = w && w.pid ? w.pid : 0;
            ph.address = w && w.address ? w.address : (t ? "0x" + t.address : "");
            ph.tick();
        }
    }

    function tick() {
        const d0 = today();
        if (d0 !== day) { endStretch(); flush(); day = d0; loaded = false; warned = {}; lastKey = ""; return; }     // nový deň → nový súbor
        if (idle.isIdle || cls === "" || cls === "org.quickshell" && title === "") { endStretch(); lastKey = ""; focusTick(""); return; }
        const k = key(), now = new Date(), t = nowSec();
        const d = data;
        const a = d.apps[k] || { s: 0, title: "", rss: 0, rssN: 0 };
        a.s += step; a.title = title;
        d.apps[k] = a;
        const h = now.getHours(), hh = h * 2 + (now.getMinutes() >= 30 ? 1 : 0);
        d.hours[h][k] = (d.hours[h][k] || 0) + step;
        d.halves[hh][k] = (d.halves[hh][k] || 0) + step;
        // čas pred obrazovkou: predĺžiť posledný úsek, ak medzera < 30 s
        const last = d.screen[d.screen.length - 1];
        if (last && t - last[1] <= 30) last[1] = t; else d.screen.push([Math.max(0, t - step), t]);
        // prepnutia a súvislé sústredenie
        if (k !== lastKey) {
            if (lastKey !== "") d.switches++;
            endStretch();
            stretchStart = t - step;
            lastKey = k;
        }
        dirty = true;
        checkLimit(k, a.s);
        focusTick(k);
    }
    function endStretch() {
        if (lastKey === "" || stretchStart <= 0 || !data.stretch) return;
        const len = nowSec() - stretchStart;
        if (len >= 60) { data.stretch.n++; data.stretch.sum += len; data.stretch.longest = Math.max(data.stretch.longest, len); dirty = true; }
        stretchStart = 0;
    }
    // aplikácie LatteOS majú všetky triedu org.quickshell → rozlíšiť podľa titulku („Súbory — LatteOS“, „x — Heidelberg“)
    function key() {
        if (cls !== "org.quickshell") return cls;
        const m = title.match(/ — (Heidelberg)$/) || title.match(/^(.*) — LatteOS$/);
        return "latte:" + (m ? m[1] : title);
    }
    // kategória: práca / zábava / neutrálne (Pulse: Focus vs Leisure)
    readonly property var funApps: ["com.discordapp.discord", "discord", "steam", "com.valvesoftware.steam", "spotify", "com.spotify.client", "vlc", "org.videolan.vlc"]
    function category(c) {
        if (cats[c]) return cats[c];
        if (c === "latte:Heidelberg") return "praca";
        if (c.startsWith("latte:")) return "neutral";
        if (funApps.indexOf(c.toLowerCase()) >= 0) return "zabava";
        const e = DesktopEntries.heuristicLookup(c), cs = e ? (e.categories || []) : [];
        if (cs.some(x => ["Game", "AudioVideo", "Video", "Audio", "Player", "Music"].indexOf(x) >= 0)) return "zabava";
        if (cs.some(x => ["Development", "Office", "Education", "Science", "Engineering", "IDE", "TextEditor", "WordProcessor", "Spreadsheet"].indexOf(x) >= 0)) return "praca";
        return "neutral";
    }
    function checkLimit(c, secs) {
        const lim = limits[c];
        if (!lim) return;
        const left = lim * 60 - secs;
        if (left <= 0 && warned[c] !== "limit") { warned[c] = "limit"; tell("Denný limit: " + shortName(c), "Dnes už " + lim + " min. Čas na prestávku?"); }
        else if (left > 0 && left <= 300 && !warned[c]) { warned[c] = "5"; tell("Ešte 5 minút: " + shortName(c), "Denný limit je " + lim + " min."); }
    }
    function shortName(c) { if (c.startsWith("latte:")) return c.slice(6); const e = DesktopEntries.heuristicLookup(c); return e ? e.name : c; }
    Process { id: notify }
    function tell(t, b) { notify.command = ["notify-send", "-a", "LatteOS", "-i", "preferences-desktop-screensaver", t, b]; notify.startDetached(); }

    // ── režim Sústredenie ─────────────────────────────────────────────────────────────────
    property var focus: null                // { start (ms), planned (min), mode, distractions, lastApp, lastWarn }
    function writeFocus() { focusFile.setText(JSON.stringify(focus ? { active: true, start: focus.start, planned: focus.planned, mode: focus.mode, distractions: focus.distractions } : { active: false })); }
    function focusStart(mins, mode) {
        if (focus) focusEnd(false);
        focus = { start: Date.now(), planned: mins, mode: mode === "odsunut" ? "odsunut" : "upozornit", distractions: 0, lastApp: "", lastWarn: 0 };
        writeFocus();
        tell("Sústredenie na " + mins + " min", focus.mode === "odsunut" ? "Rozptyľujúce aplikácie odsuniem nabok." : "Upozorním ťa, ak otvoríš rozptyľujúcu aplikáciu.");
    }
    function focusEnd(done) {
        if (!focus) return;
        const secs = Math.round((Date.now() - focus.start) / 1000);
        data.focus.push({ start: Qt.formatTime(new Date(focus.start), "HH:mm"), planned: focus.planned, secs: secs, distractions: focus.distractions, mode: focus.mode, done: done });
        dirty = true; flush();
        tell(done ? "Sústredenie hotové ✓" : "Sústredenie ukončené", Math.round(secs / 60) + " min · rozptýlenia: " + focus.distractions);
        focus = null; writeFocus();
    }
    Process { id: moveAway }
    function focusTick(k) {
        if (!focus) return;
        if (Date.now() - focus.start >= focus.planned * 60000) { focusEnd(true); return; }
        if (k === "" || category(k) !== "zabava") { if (k !== "") focus.lastApp = ""; return; }
        if (focus.lastApp !== k) { focus.distractions++; focus.lastApp = k; writeFocus(); }
        if (focus.mode === "odsunut" && address !== "") {
            // rovnako ako tlačidlo minimalizovať (latte/bars.lua): skrytá plocha special:minimized, späť z lišty
            moveAway.command = ["hyprctl", "eval", 'hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + address + '" }))'];
            moveAway.running = true;
            tell("Sústredenie: " + shortName(k) + " odsunuté", "Je medzi minimalizovanými oknami na lište, vrátiš ho kedykoľvek.");
        } else if (Date.now() - focus.lastWarn > 60000) {
            focus.lastWarn = Date.now();
            tell("Sústredenie: " + shortName(k) + " ťa rozptyľuje", "Zostáva " + Math.ceil((focus.planned * 60000 - (Date.now() - focus.start)) / 60000) + " min.");
        }
    }
    IpcHandler {
        target: "pohoda"
        function fokusStart(mins: int, mode: string): void { ph.focusStart(mins, mode); }
        function fokusStop(): void { ph.focusEnd(false); }
    }

    // ── sluch: počúvanie a hlasné počúvanie v slúchadlách ─────────────────────────────────
    Process {
        id: sound
        command: ["latte-sysmon", "zvuk"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(" ").map(x => parseInt(x) || 0);
                if (f.length < 4 || !f[0] || f[3] || !ph.loaded) return;       // nehrá alebo stlmené
                const hr = ph.data.hearing;
                hr.listen += 10;
                if (f[2] && f[1] >= ph.loudPct) {
                    hr.loud += 10;
                    const n = new Date(), i = n.getHours() * 2 + (n.getMinutes() >= 30 ? 1 : 0);
                    hr.loudHalves[i] += 10;
                }
                ph.dirty = true;
            }
        }
    }
    Timer { interval: 10000; repeat: true; running: ph.loaded; onTriggered: if (!sound.running) sound.running = true }

    // pamäť aktívnej aplikácie (RSS celého stromu procesov) raz za minútu
    Process {
        id: rssProc
        property string c: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const kb = parseInt(this.text) || 0;
                const a = ph.data.apps[rssProc.c];
                if (!a || kb <= 0) return;
                a.rss = Math.round(((a.rss || 0) * (a.rssN || 0) + kb) / ((a.rssN || 0) + 1));   // priemer
                a.rssN = (a.rssN || 0) + 1;
                a.rssMax = Math.max(a.rssMax || 0, kb);
                ph.dirty = true;
            }
        }
    }
    Timer {
        interval: 60000; repeat: true; running: ph.loaded
        onTriggered: {
            if (!idle.isIdle && ph.pid > 0 && ph.cls !== "" && !rssProc.running) {
                rssProc.c = ph.key(); rssProc.command = ["latte-sysmon", "rss", String(ph.pid)]; rssProc.running = true;
            }
            ph.flush();
        }
    }
    function flush() { if (dirty && loaded) { store.setText(JSON.stringify(data)); dirty = false; } }
}
