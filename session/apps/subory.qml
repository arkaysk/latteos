// LatteOS — Súbory (Data Manager), prototyp v Quickshelli. Dva režimy (zadanie 24. 9., bod 7):
//   Forklift         jeden panel (alebo dva), panel náhľadu dá sa skryť, zobrazenie ako vo Win11 (ikony v 4
//                    veľkostiach, zoznam, podrobnosti), Nový priečinok/súbor, „Otvoriť v…“ s odporúčaniami
//                    App Managera (latte-otvor)
//   Total Commander  dva panely, lišta F-kláves (F3 zobraziť, F4 upraviť, F5 kopírovať, F6 presunúť,
//                    F7 nový priečinok, F8 kôš, F9 server), FTP/SFTP ako priečinky (latte-siet, rclone) Skutočná štruktúra Linuxu ostáva, pohľad „Tento počítač“ je iba zobrazenie
// diskov z lsblk (radar: „Súbory a inštalácie“). Spúšťa sa: qs -p /usr/share/latteos/apps/subory.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "common"
import "data"

ShellRoot {
    id: app
    LatteTheme { id: theme }

    readonly property string home: Quickshell.env("HOME") || "/"
    property bool dual: false
    property int activeIndex: 0
    property string mode: "forklift"     // forklift | commander
    property bool showDetail: true       // panel náhľadu vpravo
    property string view: "detaily"      // detaily | zoznam | ikony (spoločné pre oba panely)
    property int iconSize: 72
    readonly property bool commander: mode === "commander"
    property bool showTree: false             // strom priečinkov ako trvalý panel (Ctrl+F8, ako oddelený strom v TC)
    // ľavé ťahanie v režime Forklift: windows (ten istý disk = presun) | copy (vždy kopírovať) | ask (vždy ponuka, ako KDE)
    property string dragRule: "windows"
    FileView { path: (Quickshell.env("XDG_CONFIG_HOME") || (app.home + "/.config")) + "/latteos/subory-tahanie"; printErrors: false; watchChanges: true
               onFileChanged: reload(); onLoaded: app.dragRule = (["copy", "ask"].indexOf(text().trim()) >= 0) ? text().trim() : "windows"
               onLoadFailed: app.dragRule = "windows" }
    function setMode(m) {
        mode = m;
        if (m === "commander") { dual = true; showDetail = false; view = "detaily"; }
        else { showDetail = true; }
        saveState();
    }
    property var disks: []
    property string confirm: ""          // "trash" = čaká na potvrdenie koša
    property string status: ""
    readonly property var activePane: activeIndex === 0 ? paneA : paneB
    readonly property var otherPane: activeIndex === 0 ? paneB : paneA
    readonly property var sel: activePane ? activePane.current : null
    // Kôš podľa freedesktop (~/.local/share/Trash); v Súboroch je zložkou Obľúbených (old/docs/nastavenia.md)
    readonly property string trashDir: app.home + "/.local/share/Trash/files"
    property int trashCount: 0
    function inTrash(p) { return p === app.trashDir || p.startsWith(app.trashDir + "/"); }
    Process {
        id: trashProc; running: true
        command: ["sh", "-c", "mkdir -p \"$HOME/.local/share/Trash/files\" \"$HOME/.local/share/Trash/info\"; ls -A \"$HOME/.local/share/Trash/files\" | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                app.trashCount = parseInt(this.text) || 0;
                for (const p of [paneA, paneB]) if (p && app.inTrash(p.path)) p.refresh();
            }
        }
    }
    // kopírovanie s priebehom (rsync --info=progress2); presun v rámci disku je okamžitý (mv)
    property int copyPct: -1
    property string copyLabel: ""
    Process {
        id: copyProc
        stdout: SplitParser {
            onRead: (line) => { const m = line.match(/\s(\d+)%\s/); if (m) app.copyPct = parseInt(m[1]); }
        }
        onExited: (code) => { app.status = code === 0 ? "Hotovo: " + app.copyLabel : "Kopírovanie zlyhalo (kód " + code + ")"; app.copyPct = -1; trashProc.running = true; }
    }

    // ── farebné štítky a vlastné obľúbené (~/.config/latteos/tags.json) ─────────────
    // Štítok nemení priečinok, je to iba pohľad Súborov (IDEAS: „farba v kontextovom menu“).
    property var tags: ({})           // cesta → #rrggbb
    property var favorites: []        // ďalšie obľúbené priečinky (pravý klik › Pridať do Obľúbených)
    readonly property var tagColors: [
        { key: "", color: "", label: "bez" },
        { key: "#E5484D", color: "#E5484D", label: "červená" }, { key: "#F07F32", color: "#F07F32", label: "oranžová" },
        { key: "#E8C33B", color: "#E8C33B", label: "žltá" },    { key: "#46A758", color: "#46A758", label: "zelená" },
        { key: "#3E7BFA", color: "#3E7BFA", label: "modrá" },   { key: "#8E4EC6", color: "#8E4EC6", label: "fialová" },
        { key: "#8B8D98", color: "#8B8D98", label: "sivá" }
    ]
    FileView {
        id: tagsView
        path: (Quickshell.env("XDG_CONFIG_HOME") || (app.home + "/.config")) + "/latteos/tags.json"
        printErrors: false
        onLoaded: { try { const j = JSON.parse(text()); app.tags = j.tags || {}; app.favorites = j.favorites || []; } catch (e) {} }
    }
    function saveTags() { tagsView.setText(JSON.stringify({ tags: app.tags, favorites: app.favorites }, null, 1) + "\n"); }
    function setTag(path, color) {
        const t = Object.assign({}, app.tags);
        if (color) t[path] = color; else delete t[path];
        app.tags = t; saveTags();
        app.status = color ? "Štítok: " + path.split("/").pop() : "Štítok odstránený";
    }
    function toggleFavorite(path) {
        app.favorites = app.favorites.indexOf(path) >= 0 ? app.favorites.filter(f => f !== path) : app.favorites.concat([path]);
        saveTags();
    }
    function rename(e, name) {
        name = (name || "").trim();
        if (name === "" || name === e.name) return;
        if (name.includes("/")) { app.status = "Názov nesmie obsahovať /"; return; }
        const dst = e.path.substring(0, e.path.lastIndexOf("/") + 1) + name;
        run(["mv", "-n", "--", e.path, dst], "Premenované na " + name);
        pushUndo({ kind: "move", pairs: [[e.path, dst]], label: "premenovanie " + e.name });
        if (app.tags[e.path]) { const c = app.tags[e.path]; setTag(e.path, ""); setTag(dst, c); }
        if (app.favorites.indexOf(e.path) >= 0) { app.favorites = app.favorites.map(f => f === e.path ? dst : f); saveTags(); }
    }
    function newFile(pane, base, ext) {
        run(["sh", "-c", "n=\"$2$3\"; i=2; while [ -e \"$1/$n\" ]; do n=\"$2 $i$3\"; i=$((i+1)); done; : > \"$1/$n\"", "sh", pane.path, base, ext], "Nový súbor: " + base + ext);
    }
    function newMenu(x, y, pane) {
        ctx.open(x, y, [
            { glyph: "folder-plus", label: "Nový priečinok", hint: app.commander ? "F7" : "", action: () => app.newFolder(pane) },
            { glyph: "file-text", label: "Textový súbor (.txt)", action: () => app.newFile(pane, "Nový textový súbor", ".txt") },
            { glyph: "pencil", label: "Dokument Heidelberg (.md)", action: () => app.newFile(pane, "Nový dokument", ".md") },
            { glyph: "file", label: "Prázdny súbor", action: () => app.newFile(pane, "Nový súbor", "") }
        ], "Nový v " + (pane.path.split("/").pop() || "/"));
    }
    // zobrazenie ako vo Windows 11
    function viewMenu(x, y) {
        const v = (key, size, label, glyph) => ({ glyph: glyph, label: label, hint: (app.view === key && (key !== "ikony" || app.iconSize === size)) ? "✓" : "",
                                                  action: () => { app.view = key; if (size) app.iconSize = size; } });
        ctx.open(x, y, [
            v("ikony", 176, "Extra veľké ikony", "photo"), v("ikony", 112, "Veľké ikony", "photo"),
            v("ikony", 72, "Stredné ikony", "layout-grid"), v("ikony", 48, "Malé ikony", "layout-grid"),
            { separator: true },
            v("zoznam", 0, "Zoznam", "layout-list"), v("detaily", 0, "Podrobnosti", "layout-list"),
            { separator: true },
            { glyph: "info-circle", label: app.showDetail ? "Skryť panel náhľadu" : "Ukázať panel náhľadu", hint: "Alt+P", action: () => app.showDetail = !app.showDetail }
        ], "Zobraziť");
    }
    // „Otvoriť v…“: aplikácie pre typ súboru, odporúčané z App Managera (latte-otvor)
    property var openWithEntry: null
    Process {
        id: openWith
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l !== "");
                const e = app.openWithEntry; if (!e || lines.length === 0) return;
                const kind = (lines[0].split("\t")[1] || "");
                const apps = lines.slice(1).map(l => l.split("\t"));
                const hints = { predvolena: "predvolená", odporucana: "odporúčaná", ina: "", nainstalovat: "nainštalovať" };
                const items = apps.filter(a => a[0] !== "nainstalovat").map(a => ({ glyph: a[0] === "predvolena" ? "check" : "external-link", label: a[2], hint: hints[a[0]],
                                                                                     action: () => app.run(["latte-otvor", "spusti", a[1], e.path], "Otváram v " + a[2]) }));
                const setDefault = apps.filter(a => a[0] === "odporucana" || a[0] === "ina");
                if (setDefault.length) {
                    items.push({ separator: true });
                    for (const a of setDefault.slice(0, 4))
                        items.push({ glyph: "star", label: "Vždy otvárať v " + a[2], action: () => app.run(["latte-otvor", "predvolena", a[1], e.path], a[2] + " je predvolená pre " + kind) });
                }
                const inst = apps.filter(a => a[0] === "nainstalovat");
                if (inst.length) {
                    items.push({ separator: true });
                    for (const a of inst) items.push({ glyph: "download", label: "Nainštalovať " + a[2] + "…", hint: "App Manager", action: () => app.run(["latte-app", "aplikacie", "hladat", a[1]]) });
                }
                if (items.length === 0) items.push({ glyph: "help", label: "Žiadna aplikácia pre " + kind, enabled: false, action: () => {} });
                ctx.replace(items, "Otvoriť v… · " + kind);
            }
        }
    }
    function openWithMenu(e) { app.openWithEntry = e; openWith.command = ["latte-otvor", "aplikacie", e.path]; openWith.running = true; }

    // ── sieť: FTP/SFTP servery ako priečinky (latte-siet → ~/Siet/…) ─────────────
    property var servers: []
    Process {
        id: serverScan; running: true
        command: ["latte-siet", "zoznam"]
        stdout: StdioCollector { onStreamFinished: app.servers = this.text.split("\n").filter(l => l !== "").map(l => { const f = l.split("\t"); return { path: f[0], url: f[1] || "" }; }) }
    }
    property bool connectOpen: false
    property string connectError: ""
    property bool connecting: false
    Process {
        id: connectProc
        stdinEnabled: true
        stdout: StdioCollector { id: connectOut }
        stderr: StdioCollector { id: connectErr }
        onExited: (code) => {
            app.connecting = false;
            if (code === 0) { app.connectOpen = false; serverScan.running = true; app.activePane.go(connectOut.text.trim()); app.status = "Pripojené: " + connectOut.text.trim().split("/").pop(); }
            else app.connectError = connectErr.text.trim().replace(/^latte-siet: /, "") || "Pripojenie zlyhalo";
        }
    }
    function connectServer(url, pw) {
        connectError = ""; connecting = true;
        connectProc.command = ["latte-siet", "pripoj", url.trim()].concat(pw !== "" ? ["--heslo-stdin"] : []);
        connectProc.running = true;
        if (pw !== "") connectProc.write(pw + "\n");
        connectProc.stdinEnabled = false;     // zatvoriť stdin (heslo nikam inam nejde)
        connectProc.stdinEnabled = true;
    }

    function newFolder(pane) {
        run(["sh", "-c", "n='Nový priečinok'; i=2; while [ -e \"$1/$n\" ]; do n=\"Nový priečinok $i\"; i=$((i+1)); done; mkdir -- \"$1/$n\"", "sh", pane.path], "Nový priečinok");
    }

    // kontextové menu položky v zozname (e = null → prázdne miesto v priečinku)
    function showMenu(e, x, y, pane) {
        const other = pane === paneA ? paneB : paneA;
        let items;
        if (!e) {
            // Zobraziť / Zoradiť podľa ako vo Windows a Linuxe (FolderListModel: 1 názov, 2 dátum, 3 veľkosť, 4 typ)
            const sortPick = (f, label, hint) => ({ label: label, hint: hint, checked: pane.sortField === f, action: () => { pane.sortField = f; } });
            const viewPick = (v, label, hint) => ({ label: label, hint: hint, checked: app.view === v, action: () => { app.view = v; } });
            items = [
                { glyph: "layout-grid", label: "Zobraziť", sub: [viewPick("ikony", "Ikony", "Ctrl+Shift+F1"), viewPick("zoznam", "Zoznam", "Ctrl+F1"), viewPick("detaily", "Podrobnosti", "Ctrl+F2")] },
                { glyph: "arrows-exchange", label: "Zoradiť podľa", sub: [
                    sortPick(1, "Názov", "Ctrl+F3"), sortPick(2, "Dátum úpravy", "Ctrl+F5"), sortPick(4, "Typ", "Ctrl+F4"), sortPick(3, "Veľkosť", "Ctrl+F6"),
                    { separator: true },
                    { label: "Vzostupne", checked: !pane.sortReversed, action: () => pane.sortReversed = false },
                    { label: "Zostupne", checked: pane.sortReversed, action: () => pane.sortReversed = true } ] },
                { glyph: "refresh", label: "Obnoviť", hint: "Ctrl+R", action: () => pane.refresh() },
                { separator: true },
                { glyph: "clipboard", label: "Prilepiť", hint: "Ctrl+V", action: () => app.clipPaste() },
                { glyph: "plus", label: "Nový", sub: [
                    { glyph: "folder-plus", label: "Priečinok", hint: app.commander ? "F7" : "", action: () => app.newFolder(pane) },
                    { glyph: "file-text", label: "Textový súbor (.txt)", action: () => app.newFile(pane, "Nový textový súbor", ".txt") },
                    { glyph: "pencil", label: "Dokument Heidelberg (.md)", action: () => app.newFile(pane, "Nový dokument", ".md") },
                    { glyph: "file", label: "Prázdny súbor", action: () => app.newFile(pane, "Nový súbor", "") } ] },
                { separator: true },
                { glyph: "terminal-2", label: "Otvoriť v termináli", action: () => app.run(["foot", "--working-directory=" + pane.path]) },
                { glyph: pane.showHidden ? "eye-off" : "eye", label: pane.showHidden ? "Skryť skryté súbory" : "Ukázať skryté súbory", hint: "Ctrl+H", action: () => pane.showHidden = !pane.showHidden },
                { separator: true },
                { glyph: "clipboard", label: "Kopírovať cestu priečinka", action: () => app.run(["wl-copy", "--", pane.path], "Cesta skopírovaná") },
                { glyph: "star", label: app.favorites.indexOf(pane.path) >= 0 ? "Odobrať z Obľúbených" : "Pridať do Obľúbených", action: () => app.toggleFavorite(pane.path) }
            ];
            if (app.inTrash(pane.path)) items.unshift({ glyph: "trash", label: "Vysypať kôš (" + app.trashCount + ")", danger: true, enabled: app.trashCount > 0,
                                                        action: () => { app.run(["latte-kos", "vysypat"], "Kôš vysypaný"); trashRefresh.restart(); } });
            ctx.open(x, y, items, pane.path);
            return;
        }
        if (app.inTrash(e.path) && e.path.substring(0, e.path.lastIndexOf("/")) === app.trashDir) {
            ctx.open(x, y, [
                { glyph: "refresh", label: "Obnoviť na pôvodné miesto", action: () => { app.run(["latte-kos", "obnov", e.name], "Obnovené: " + e.name); trashRefresh.restart(); } },
                { glyph: "clipboard", label: "Kopírovať cestu", action: () => app.run(["wl-copy", "--", e.path], "Cesta skopírovaná") },
                { separator: true },
                { glyph: "trash", label: "Odstrániť natrvalo", danger: true, action: () => { app.run(["sh", "-c", "rm -rf -- \"$1\" \"$HOME/.local/share/Trash/info/$(basename \"$1\").trashinfo\"", "sh", e.path], "Odstránené natrvalo: " + e.name); trashRefresh.restart(); } }
            ], e.name + " · v koši");
            return;
        }
        items = [
            { glyph: "external-link", label: e.isDir ? "Otvoriť" : "Otvoriť v aplikácii", hint: "Enter", action: () => { if (e.isDir) pane.go(e.path); else app.openPath(e.path); } }
        ];
        if (!e.isDir) items.push({ glyph: "apps", label: "Otvoriť v…", keepOpen: true, action: () => app.openWithMenu(e) });
        if (!e.isDir && /\.(mp4|webm|mkv|mov|avi|gif|webp|jpe?g|png|avif)$/i.test(e.name))
            items.push({ glyph: "photo", label: "Nastaviť ako tapetu", action: () => app.run(["latte-tapety", "nastav", e.path], "Tapeta: " + e.name + " (živé video iba s GPU)") });
        if (e.isDir) items.push({ glyph: "columns-2", label: "Otvoriť v druhom paneli", action: () => { app.dual = true; other.go(e.path); } });
        items.push({ separator: true });
        items.push({ colors: app.tagColors, current: app.tags[e.path] || "", label: "Farba", action: (c) => app.setTag(e.path, c) });
        items.push({ separator: true });
        items.push({ glyph: "pencil", label: "Premenovať…", keepOpen: true, action: () => ctx.replace([{ input: e.name, wholeName: e.isDir, action: (t) => app.rename(e, t) }], "Nový názov · Enter uloží, Esc zruší") });
        items.push({ glyph: "clipboard", label: "Kopírovať cestu", action: () => app.run(["wl-copy", "--", e.path], "Cesta skopírovaná") });
        if (e.isDir || /\.(rpm|flatpakref|flatpak|appimage|exe|msi|apk|deb|run|zip|rar|7z|iso)$/i.test(e.name))
            items.push({ glyph: "help", label: "Bude to fungovať?", hint: "App Manager", action: () => app.run(["latte-app", "aplikacie", "check", e.path]) });
        if (app.dual) {
            items.push({ glyph: "copy", label: "Kopírovať do druhého", hint: "F5", action: () => app.openOp(false) });
            items.push({ glyph: "arrows-exchange", label: "Presunúť do druhého", hint: "F6", action: () => app.openOp(true) });
        }
        if (e.isDir) {
            items.push({ glyph: "star", label: app.favorites.indexOf(e.path) >= 0 ? "Odobrať z Obľúbených" : "Pridať do Obľúbených", action: () => app.toggleFavorite(e.path) });
            items.push({ glyph: "terminal-2", label: "Terminál tu", action: () => app.run(["foot", "--working-directory=" + e.path]) });
        }
        items.push({ separator: true });
        items.push({ glyph: "trash", label: "Do koša", hint: "Del", danger: true, action: () => { app.run(["latte-kos", "vyhod", e.path], "Do koša: " + e.name); trashRefresh.restart(); } });
        ctx.open(x, y, items, e.name);
    }
    // kontextové menu položky bočnej lišty (disky, obľúbené)
    function showSideMenu(it, x, y) {
        const items = [
            { glyph: "external-link", label: "Otvoriť", action: () => app.activePane.go(it.path) },
            { glyph: "columns-2", label: "Otvoriť v druhom paneli", action: () => { app.dual = true; app.otherPane.go(it.path); } },
            { glyph: "clipboard", label: "Kopírovať cestu", action: () => app.run(["wl-copy", "--", it.path], "Cesta skopírovaná") }
        ];
        if (!it.key.startsWith("disk:")) {
            items.push({ separator: true });
            items.push({ colors: app.tagColors, current: app.tags[it.path] || "", label: "Farba", action: (c) => app.setTag(it.path, c) });
        }
        if (it.key === "fav:trash") { items.push({ separator: true }); items.push({ glyph: "trash", label: "Vysypať kôš", danger: true, enabled: app.trashCount > 0, action: () => { app.run(["latte-kos", "vysypat"], "Kôš vysypaný"); trashRefresh.restart(); } }); }
        if (it.key.startsWith("net:") && it.path) { items.push({ separator: true }); items.push({ glyph: "x", label: "Odpojiť server", danger: true, action: () => { app.run(["latte-siet", "odpoj", it.path], "Odpojené: " + it.label); serverRefresh.restart(); if (app.activePane.path.startsWith(it.path)) app.activePane.go(app.home); } }); }
        if (it.custom) { items.push({ separator: true }); items.push({ glyph: "star", label: "Odobrať z Obľúbených", action: () => app.toggleFavorite(it.path) }); }
        ctx.open(x, y, items, it.label);
    }

    // hľadanie všade (Enter v hľadaní): find v aktívnom priečinku a podpriečinkoch, bez skrytých, najviac 300
    property var found: []
    property string foundQuery: ""
    property bool finding: false
    Process {
        id: findProc
        stdout: StdioCollector {
            onStreamFinished: {
                app.finding = false;
                app.found = this.text.split("\n").filter(l => l !== "").map(l => { const i = l.indexOf("|"); return { dir: l.slice(0, 1) === "d", path: l.slice(i + 1) }; });
                app.status = app.found.length + (app.found.length >= 300 ? "+" : "") + " nájdených pre „" + app.foundQuery + "“";
            }
        }
    }
    function findAll(q) {
        q = (q || "").trim();
        if (q.length < 2) { found = []; foundQuery = ""; return; }
        foundQuery = q; finding = true; status = "Hľadám „" + q + "“ v " + activePane.path + "…";
        findProc.command = ["sh", "-c", "find \"$1\" -mindepth 1 \\( -name '.*' -prune \\) -o -iname \"*$2*\" -printf '%y|%p\\n' 2>/dev/null | head -300", "sh", activePane.path, q];
        findProc.running = true;
    }

    // pripojené cloudové priečinky (~/Cloud/*, latte-cloud)
    property var cloudDirs: []
    Process {
        id: cloudScan; running: true
        command: ["sh", "-c", "for d in \"$HOME\"/Cloud/*/; do [ -d \"$d\" ] && mountpoint -q \"$d\" && basename \"$d\"; done"]
        stdout: StdioCollector { onStreamFinished: app.cloudDirs = this.text.split("\n").filter(l => l !== "") }
    }

    // test bez myši (setup/f1/headless.sh): LATTE_APP_TEST=menu otvorí kontextové menu prvej položky
    Timer {
        running: Quickshell.env("LATTE_APP_TEST") === "menu"; interval: 2500
        onTriggered: { if (paneA.count > 0) { paneA.moveSelection(1); app.showMenu(paneA.current, 420, 180, paneA); } }
    }
    // LATTE_APP_TEST=drop: ponuka po pustení pravým tlačidlom (súbor zo Stiahnutých do Dokumentov)
    Timer {
        running: Quickshell.env("LATTE_APP_TEST") === "drop"; interval: 2500
        onTriggered: app.dropOp([{ path: app.home + "/Stiahnuté/archiv.zip", name: "archiv.zip", isDir: false }], app.home + "/Dokumenty", "ask", 520, 260)
    }

    // ── pamäť stavu: dva panely a ich cesty (~/.config/latteos/subory.json) ─────────
    readonly property string stateFile: (Quickshell.env("XDG_CONFIG_HOME") || (app.home + "/.config")) + "/latteos/subory.json"
    property bool stateLoaded: false
    FileView {
        id: stateView
        path: app.stateFile
        printErrors: false
        onLoaded: {
            try {
                const st = JSON.parse(text());
                app.dual = !!st.dual;
                if (st.mode) app.mode = st.mode;
                if (st.showDetail !== undefined) app.showDetail = !!st.showDetail;
                if (st.view) app.view = st.view;
                if (st.iconSize) app.iconSize = st.iconSize;
                app.showTree = !!st.showTree;
                if (st.tabs && st.tabs.length === 2) { app.tabs = st.tabs; app.tabIdx = st.tabIdx || [0, 0]; }
                if (st.left) paneA.go(st.left);
                if (st.right) paneB.go(st.right);
            } catch (e) {}
            app.openArg();
            app.stateLoaded = true;
        }
        onLoadFailed: { app.openArg(); app.stateLoaded = true; }
    }
    // latte-app subory <priečinok>: otvorí zadaný priečinok v ľavom paneli (file:// URL alebo cesta)
    function openArg() {
        let a = (Quickshell.env("LATTE_APP_ARGS") || "").trim();
        if (a.startsWith("file://")) a = decodeURIComponent(a.slice(7));
        if (a !== "") { paneA.go(a); app.activeIndex = 0; }
    }
    function saveState() {
        if (!app.stateLoaded) return;
        saver.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", app.stateFile,
                         JSON.stringify({ dual: app.dual, left: paneA.path, right: paneB.path, mode: app.mode, tabs: app.tabs, tabIdx: app.tabIdx,
                                         showDetail: app.showDetail, view: app.view, iconSize: app.iconSize, showTree: app.showTree })];
        saver.running = true;
    }
    Process { id: saver }
    onDualChanged: saveState()
    onShowDetailChanged: saveState()
    onViewChanged: saveState()
    onIconSizeChanged: saveState()

    // ── disky: lsblk (Systém, oddiely, USB) ───────────────────────────────────
    Process {
        id: lsblk
        running: true
        command: ["lsblk", "-J", "-b", "-o", "NAME,LABEL,SIZE,FSAVAIL,FSUSED,MOUNTPOINT,TYPE,RM,TRAN,MODEL"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = [];
                    const walk = (d, disk) => {
                        if (d.mountpoint && d.mountpoint !== "[SWAP]" && !d.mountpoint.startsWith("/boot")) {
                            const size = Number(d.size) || 0, used = Number(d.fsused) || 0, avail = Number(d.fsavail) || 0;
                            const usb = disk.rm || disk.tran === "usb";
                            out.push({
                                key: "disk:" + d.mountpoint, path: d.mountpoint,
                                glyph: usb ? "usb" : (d.mountpoint === "/" ? "device-desktop" : "database"),
                                label: d.mountpoint === "/" ? "Systém" : (d.label || d.mountpoint.split("/").pop() || d.name),
                                sub: app.human(avail) + " voľných z " + app.human(used + avail),
                                usage: (used + avail) > 0 ? used / (used + avail) : 0
                            });
                        }
                        for (const c of (d.children || [])) walk(c, disk);
                    };
                    for (const d of JSON.parse(this.text).blockdevices) walk(d, d);
                    app.disks = out;
                } catch (e) { console.warn("lsblk:", e); }
            }
        }
    }
    Timer { interval: 15000; running: true; repeat: true; onTriggered: { lsblk.running = true; cloudScan.running = true; serverScan.running = true; } }
    Timer { id: serverRefresh; interval: 700; onTriggered: serverScan.running = true }

    function human(b) {
        if (b < 1024) return b + " B";
        const u = ["kB", "MB", "GB", "TB"]; let v = b / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return v.toFixed(v < 10 ? 1 : 0).replace(".", ",") + " " + u[i];
    }

    readonly property var sidebarModel: [
        { title: "Tento počítač", items: app.disks },
        { title: "Obľúbené", items: [
            { key: "fav:home", path: app.home, glyph: "home", label: "Domov" },
            { key: "fav:desk", path: app.home + "/Plocha", glyph: "device-desktop", label: "Plocha" },
            { key: "fav:docs", path: app.home + "/Dokumenty", glyph: "file-text", label: "Dokumenty" },
            { key: "fav:down", path: app.home + "/Stiahnuté", glyph: "download", label: "Stiahnuté" },
            { key: "fav:pics", path: app.home + "/Obrázky", glyph: "photo", label: "Obrázky" },
            { key: "fav:music", path: app.home + "/Hudba", glyph: "music", label: "Hudba" },
            { key: "fav:video", path: app.home + "/Videá", glyph: "movie", label: "Videá" },
            { key: "fav:trash", path: app.trashDir, glyph: "trash", label: "Kôš", sub: app.trashCount ? app.trashCount + " položiek · pravý klik: vysypať" : "prázdny" }
        ].concat(app.favorites.map(f => ({ key: "fav+:" + f, path: f, glyph: "folder", label: f.split("/").pop() || f, custom: true })))
         .map(it => Object.assign({}, it, { tag: app.tags[it.path] || "" })) },
        { title: "Cloud", items: app.cloudDirs.map(c => ({ key: "cloud:" + c, path: app.home + "/Cloud/" + c, glyph: "cloud", label: c, sub: "cloudový účet" }))
                                  .concat([{ key: "cloud:add", path: "", glyph: "plus", label: "Pridať cloudový účet", sub: "Nastavenia › Dáta", dim: app.cloudDirs.length > 0 }]) },
        { title: "Sieť", items: app.servers.map(sv => ({ key: "net:" + sv.path, path: sv.path, glyph: "server", label: sv.path.split("/").pop(), sub: sv.url || "server" }))
                                  .concat([{ key: "net:add", path: "", glyph: "plus", label: "Pripojiť server…", sub: "FTP, SFTP, SMB, WebDAV" + (app.commander ? " · F9" : ""), dim: app.servers.length > 0 }]) },
        { title: "Aplikácie", items: [
            { key: "apps:flatpak", path: "/var/lib/flatpak/app", glyph: "package", label: "Flatpak (systém)", sub: "každá appka vo vlastnom priečinku" },
            { key: "apps:flatpak-user", path: app.home + "/.local/share/flatpak/app", glyph: "package", label: "Flatpak (používateľ)" },
            { key: "apps:desktop", path: "/usr/share/applications", glyph: "apps", label: "Nainštalované (.desktop)" }
        ] },
        { title: "Systém Linux", items: [
            { key: "sys:root", path: "/", glyph: "server", label: "/ koreň", sub: "skutočná štruktúra, nič skryté" },
            { key: "sys:etc", path: "/etc", glyph: "settings", label: "/etc", sub: "nastavenia systému" },
            { key: "sys:mnt", path: "/run/media/" + (Quickshell.env("USER") || ""), glyph: "usb", label: "Pripojené médiá" }
        ] }
    ]

    // ── akcie ──────────────────────────────────────────────────────────────────
    Process { id: runner }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) app.status = msg; }
    function openPath(p) { run(["xdg-open", p]); }
    function copyToOther(move) {
        const e = app.sel; if (!e || !app.dual) { app.status = "F5/F6 potrebuje dva panely (F3)"; return; }
        const dst = app.otherPane.path;
        if (move) { run(["mv", "-n", "--", e.path, dst], "Presúvam " + e.name + " → " + dst); return; }
        if (copyProc.running) { app.status = "Ešte kopírujem " + app.copyLabel; return; }
        app.copyLabel = e.name + " → " + dst; app.copyPct = 0; app.status = "Kopírujem " + app.copyLabel;
        // --ignore-existing = neprepíše nič v cieli (ako cp -n); \r z priebehu rsync sa mení na nové riadky
        copyProc.command = ["sh", "-c", "rsync -a --ignore-existing --no-inc-recursive --info=progress2 -- \"$1\" \"$2/\" | stdbuf -o0 tr '\\r' '\\n'", "sh", e.path, dst];
        copyProc.running = true;
    }
    Timer { id: trashRefresh; interval: 600; onTriggered: trashProc.running = true }
    function trash() {
        const e = app.sel; if (!e) return;
        if (app.confirm !== "trash") { app.confirm = "trash"; app.status = "Stlač Delete znova (alebo tlačidlo) na presun do koša: " + e.name; return; }
        app.confirm = "";
        run(["latte-kos", "vyhod", e.path], "Do koša: " + e.name);
        trashRefresh.restart();
    }

    // ═══ Total Commander (zadanie 25. 9.: plná funkčnosť originálu) ════════════════════════════
    // karty: pre každý panel zoznam { path, locked }; uzamknutá karta pri zmene priečinka otvorí novú
    property var tabs: [[{ path: app.home, locked: false }], [{ path: "/", locked: false }]]
    property var tabIdx: [0, 0]
    function paneAt(i) { return i === 0 ? paneA : paneB; }
    function idxOf(pane) { return pane === paneA ? 0 : 1; }
    function setTabs(i, list, idx) {
        const t = tabs.slice(), ti = tabIdx.slice();
        t[i] = list; ti[i] = Math.max(0, Math.min(list.length - 1, idx)); tabs = t; tabIdx = ti; saveState();
    }
    function onPanePath(i, p) {
        const list = tabs[i].slice(), k = tabIdx[i];
        if (!list[k]) return;
        if (list[k].path === p) return;
        if (list[k].locked) { list.splice(k + 1, 0, { path: p, locked: false }); setTabs(i, list, k + 1); return; }
        list[k] = { path: p, locked: false }; setTabs(i, list, k);
    }
    function newTab(i) { const list = tabs[i].slice(); list.splice(tabIdx[i] + 1, 0, { path: paneAt(i).path, locked: false }); setTabs(i, list, tabIdx[i] + 1); }
    function closeTab(i, k) {
        if (k === undefined) k = tabIdx[i];
        const list = tabs[i].slice(); if (list.length <= 1) { app.status = "Posledná karta sa nedá zavrieť"; return; }
        list.splice(k, 1);
        const ni = Math.min(k, list.length - 1); setTabs(i, list, ni); paneAt(i).go(list[ni].path);
    }
    function switchTab(i, k) { const list = tabs[i]; if (!list.length) return; k = (k + list.length) % list.length; setTabs(i, list, k); paneAt(i).go(list[k].path); }
    function toggleLock(i, k) { const list = tabs[i].slice(); list[k] = { path: list[k].path, locked: !list[k].locked }; setTabs(i, list, tabIdx[i]); }
    function tabName(t) { return (t.path === app.trashDir ? "Kôš" : (t.path.split("/").pop() || "/")); }

    // hotlist priečinkov (Ctrl+D) = Obľúbené + pridať aktuálny
    function hotlist(x, y) {
        const p = app.activePane, items = [];
        for (const s of app.sidebarModel.slice(1, 2)) for (const it of s.items) items.push({ glyph: it.glyph, label: it.label, hint: it.path.replace(app.home, "~"), action: () => p.go(it.path) });
        items.push({ separator: true });
        items.push({ glyph: "star", label: app.favorites.indexOf(p.path) >= 0 ? "Odobrať aktuálny priečinok" : "Pridať aktuálny priečinok", action: () => app.toggleFavorite(p.path) });
        ctx.open(x, y, items, "Hotlist priečinkov (Ctrl+D)");
    }
    function driveMenu(i, x, y) {
        ctx.open(x, y, app.disks.concat(app.cloudDirs.map(c => ({ path: app.home + "/Cloud/" + c, glyph: "cloud", label: c, sub: "cloud" })))
                           .map(d => ({ glyph: d.glyph, label: d.label, hint: d.sub || "", action: () => { app.dual = app.dual || i === 1; app.paneAt(i).go(d.path); app.activeIndex = i; } })),
                 i === 0 ? "Disk vľavo (Alt+F1)" : "Disk vpravo (Alt+F2)");
    }
    function swapPanels() { const a = paneA.path, b = paneB.path, ta = tabs[0], tb = tabs[1], ia = tabIdx[0], ib = tabIdx[1]; tabs = [tb, ta]; tabIdx = [ib, ia]; paneA.go(b); paneB.go(a); }
    function toSide(i) {                       // Ctrl+←/→: priečinok pod kurzorom (alebo aktuálny) do panela vľavo/vpravo
        const e = app.sel, target = e && e.isDir ? e.path : app.activePane.path;
        app.dual = true; app.paneAt(i).go(target);
    }

    // veľkosti priečinkov (Medzerník, Alt+Shift+Enter)
    Process {
        id: duProc
        property var pane: null
        stdout: SplitParser { onRead: (l) => { const t = l.indexOf("\t"); if (t > 0 && duProc.pane) duProc.pane.setDirSize(l.slice(t + 1), parseInt(l.slice(0, t)) || 0); } }
    }
    function dirSizes(pane, paths) {
        if (!paths.length || duProc.running) return;
        duProc.pane = pane; duProc.command = ["du", "-sb", "--"].concat(paths); duProc.running = true;
        app.status = "Počítam veľkosť " + (paths.length === 1 ? paths[0].split("/").pop() : paths.length + " priečinkov") + "…";
    }

    // všeobecný dialóg s textovým poľom (F7, Shift+F4, výber maskou, premenovanie)
    property var ask: null                    // { title, text, hint, action(text) }
    function askInput(title, text, hint, action) { ask = { title: title, text: text, hint: hint || "", action: action }; }

    // ── rad úloh kopírovania a presunu (F5 / F6), vykonáva latte-kopia ─────────────────
    property var jobs: []                     // { move, target, sources, mode, mask, label, state: čaká|beží|hotovo|chyba, msg }
    property var job: null
    property int jobPct: 0
    property string jobFile: ""
    property bool jobPaused: false
    property bool jobsOpen: false
    Process {
        id: jobProc
        stdout: SplitParser {
            onRead: (l) => {
                const f = l.split(" ");
                if (f[0] === "P") { app.jobPct = parseInt(f[1]) || 0; app.jobFile = f.slice(4).join(" "); }
                else if (f[0] === "E") { if (app.job) app.job.msg = l.slice(2); }
                else if (f[0] === "OK" && app.job) app.job.result = "skopírované " + f[1] + (parseInt(f[2]) ? ", preskočené " + f[2] : "");
            }
        }
        onExited: (code) => {
            const j = app.job;
            if (j) { j.state = code === 0 && !j.msg ? "hotovo" : "chyba"; app.status = (j.state === "hotovo" ? "Hotovo: " : "Chyba: ") + j.label + (j.result ? " · " + j.result : "") + (j.msg ? " · " + j.msg : ""); }
            app.job = null; app.jobPct = 0; app.jobFile = ""; app.jobPaused = false; app.jobs = app.jobs.slice();
            paneA.refresh(); paneB.refresh(); trashRefresh.restart();
            Qt.callLater(app.nextJob);
        }
    }
    function enqueue(j) { j.state = "čaká"; jobs = jobs.concat([j]); if (!job) nextJob(); else app.status = "Do radu: " + j.label + " (" + jobs.filter(x => x.state === "čaká").length + " čaká)"; }
    function nextJob() {
        if (job) return;
        const j = jobs.find(x => x.state === "čaká"); if (!j) return;
        j.state = "beží"; job = j; jobs = jobs.slice();
        jobProc.command = ["latte-kopia", j.move ? "presun" : "kopiruj", "--rezim", j.mode, "--maska", j.mask || "*"].concat(j.verify ? ["--overit"] : [])
                          .concat(j.limit ? ["--limit", String(j.limit)] : []).concat([j.target]).concat(j.sources);
        jobProc.running = true;
        app.status = (j.move ? "Presúvam " : "Kopírujem ") + j.label;
    }
    function pauseJob() { if (!jobProc.running) return; run(["kill", jobPaused ? "-CONT" : "-STOP", String(jobProc.processId)]); jobPaused = !jobPaused; }
    function cancelJob() { if (!jobProc.running) return; if (jobPaused) run(["kill", "-CONT", String(jobProc.processId)]); jobProc.signal(15); if (job) job.msg = "zrušené"; }
    function clearDone() { jobs = jobs.filter(x => x.state === "čaká" || x.state === "beží"); }

    // dialóg F5 / F6
    property var op: null                     // { move, items[], target, mask, mode, verify }
    // Späť (Ctrl+Z) ako v Prieskumníkovi: presun, premenovanie, kópia, odkaz a Kôš (posledných 30 akcií)
    property var undoStack: []
    function pushUndo(u) { undoStack = undoStack.concat([u]).slice(-30); }
    function undo() {
        if (!undoStack.length) { app.status = "Nie je čo vrátiť"; return; }
        const u = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        if (u.kind === "move") run(["sh", "-c", 'while [ $# -gt 1 ]; do [ -e "$2" ] && mv -n -- "$2" "$1"; shift 2; done', "sh"].concat([].concat(...u.pairs)), "Vrátené: " + u.label);
        else if (u.kind === "copy" || u.kind === "link") run(["latte-kos", "vyhod"].concat(u.created), "Vrátené: " + u.label + " (do Koša)");
        else if (u.kind === "trash") run(["latte-kos", "obnov-cestu"].concat(u.paths), "Vrátené z Koša: " + u.label);
        refreshBoth.restart(); trashRefresh.restart();
    }
    function base(p) { return p.substring(p.lastIndexOf("/") + 1); }
    // Ctrl + koliesko: zoznam ↔ ikony malé · stredné · veľké · extra veľké (ako Prieskumník)
    function zoom(step) {
        const sizes = [48, 72, 112, 176];
        if (app.view !== "ikony") { if (step > 0) { app.view = "ikony"; app.iconSize = 48; } return; }
        const i = sizes.indexOf(app.iconSize) < 0 ? 1 : sizes.indexOf(app.iconSize);
        if (step < 0 && i === 0) { app.view = "zoznam"; return; }
        app.iconSize = sizes[Math.max(0, Math.min(sizes.length - 1, i + step))];
    }

    // pustenie myšou (FilePane) ako vo Windows: action copy | move | link | ask (pravé/stredné tlačidlo = ponuka).
    // Režim TC: kópia/presun cez dialóg F5/F6 (ako Total Commander); režim Forklift: hneď, konflikty sa opýtajú.
    function dropOp(items, dir, action, wx, wy) {
        if (action === "ask") {
            const def = app.commander ? "copy" : app.activePane.dropAction(0, items.map(e => e.path), dir, Qt.LeftButton, true);
            const one = items.length === 1 ? items[0] : null;
            const list = [
                { glyph: "copy", label: "Kopírovať sem", bold: def === "copy", action: () => app.dropDo(items, dir, "copy") },
                { glyph: "arrows-move", label: "Presunúť sem", bold: def === "move", action: () => app.dropDo(items, dir, "move") },
                { glyph: "link", label: items.length > 1 ? "Vytvoriť odkazy sem" : "Vytvoriť odkaz sem", action: () => app.dropDo(items, dir, "link") }];
            if (one && !one.isDir && app.archiveRe.test(one.name))
                list.push({ glyph: "file-zip", label: "Rozbaliť sem", action: () => { app.run(["latte-tc", "archiv", "rozbal", one.path, dir + "/" + one.name.replace(app.archiveRe, "")], "Rozbaľujem do " + dir.replace(app.home, "~")); refreshBoth.restart(); } });
            if (one && !one.isDir && /\.(jpe?g|png|webp|gif|bmp|avif|jxl)$/i.test(one.name) && /\/(Plocha|Desktop)$/.test(dir))
                list.push({ glyph: "photo", label: "Nastaviť ako tapetu", action: () => app.run(["latte-tapety", "pouzi", one.path], "Tapeta: " + one.name) });
            list.push({ separator: true }, { glyph: "x", label: "Zrušiť", action: () => {} });
            ctx.open(wx, wy, list, (items.length === 1 ? items[0].name : items.length + " položiek") + " → " + dir.replace(app.home, "~"));
            return;
        }
        dropDo(items, dir, action);
    }
    function dropDo(items, dir, action) {
        if (action === "link") {
            pushUndo({ kind: "link", created: items.map(e => dir + "/" + app.base(e.path)), label: "odkaz" });
            app.run(["sh", "-c", 'd="$1"; shift; for f in "$@"; do ln -s -- "$f" "$d/" 2>/dev/null || ln -s -- "$f" "$d/Odkaz na $(basename "$f")"; done', "sh", dir].concat(items.map(e => e.path)),
                    (items.length === 1 ? "Odkaz na " + items[0].name : items.length + " odkazov") + " v " + dir.replace(app.home, "~"));
            refreshBoth.restart(); return;
        }
        op = { move: action === "move", items: items, target: dir + "/", mask: "*.*", mode: "ask", verify: false };
        if (!app.commander) startOp(false);          // Forklift: hneď ako Windows (pri konflikte sa opýta)
    }
    function openOp(move) {
        const items = app.activePane.selection();
        if (!items.length) { app.status = "Nič nie je vybrané"; return; }
        const tgt = app.dual ? app.otherPane.path : app.activePane.path;
        op = { move: move, items: items, target: (items.length === 1 && !app.dual ? items[0].path : tgt + "/"), mask: "*.*", mode: "ask", verify: false };
    }
    Process {
        id: conflictProc
        property var pending: null
        stdout: StdioCollector {
            onStreamFinished: {
                const names = this.text.split("\n").filter(l => l !== ""), j = conflictProc.pending;
                if (!j) return;
                if (names.length) { app.conflict = { job: j, names: names }; return; }
                j.mode = "preskocit"; app.enqueue(j);
            }
        }
    }
    property var conflict: null               // { job, names[] }
    function startOp(queueOnly) {
        const o = op; if (!o) return;
        const target = o.target.trim(); if (target === "") return;
        const j = { move: o.move, target: target, sources: o.items.map(e => e.path), mode: o.mode, mask: o.mask, verify: o.verify, limit: o.limit || 0,
                    label: (o.items.length === 1 ? o.items[0].name : o.items.length + " položiek") + " → " + target.replace(app.home, "~") };
        op = null;
        app.activePane.clearMarks();
        if (target.endsWith("/")) {
            const lbl = (o.items.length === 1 ? o.items[0].name : o.items.length + " položiek");
            if (o.move) pushUndo({ kind: "move", pairs: j.sources.map(p => [p, target + app.base(p)]), label: "presun " + lbl });
            else pushUndo({ kind: "copy", created: j.sources.map(p => target + app.base(p)), label: "kópia " + lbl });
        }
        if (j.mode === "ask") {
            const dir = target.endsWith("/") ? target : (o.items.length > 1 ? target : target.substring(0, target.lastIndexOf("/")));
            if (o.items.length === 1 && !target.endsWith("/")) { j.mode = "preskocit"; enqueue(j); return; }   // premenovanie na nové meno
            conflictProc.pending = j; conflictProc.command = ["latte-kopia", "konflikty", dir].concat(j.sources); conflictProc.running = true;
            return;
        }
        enqueue(j);
    }
    function resolveConflict(mode) { const c = conflict; conflict = null; if (!c || !mode) { app.status = "Zrušené"; return; } c.job.mode = mode; enqueue(c.job); }

    // mazanie: do koša (F8 / Del), natrvalo (Shift+Del) s potvrdením
    property var delAsk: null                 // { items[], permanent }
    function askDelete(permanent) {
        const items = app.activePane.selection(); if (!items.length) return;
        if (!permanent && !app.commander) { doDelete({ items: items, permanent: false }); return; }   // Windows: Del bez otázky (Ctrl+Z vráti)
        delAsk = { items: items, permanent: permanent };
    }
    function doDelete(direct) {
        const d = direct || delAsk; delAsk = null; if (!d) return;
        const paths = d.items.map(e => e.path);
        if (d.permanent) run(["rm", "-rf", "--"].concat(paths), "Odstránené natrvalo: " + (paths.length === 1 ? d.items[0].name : paths.length + " položiek"));
        else {
            run(["latte-kos", "vyhod"].concat(paths), "Do koša: " + (paths.length === 1 ? d.items[0].name : paths.length + " položiek"));
            pushUndo({ kind: "trash", paths: paths, label: paths.length === 1 ? d.items[0].name : paths.length + " položiek" });
        }
        app.activePane.clearMarks(); trashRefresh.restart(); refreshBoth.restart();
    }
    Timer { id: refreshBoth; interval: 500; onTriggered: { paneA.refresh(); paneB.refresh(); } }

    // schránka súborov (Ctrl+C / Ctrl+X / Ctrl+V) — text/uri-list, spolupracuje s inými aplikáciami
    property bool cutMode: false
    function clipCopy(cut) {
        const items = app.activePane.selection(); if (!items.length) return;
        cutMode = cut;
        run(["sh", "-c", 'printf "%s\\n" "$@" | wl-copy --type text/uri-list', "sh"].concat(items.map(e => "file://" + encodeURI(e.path))),
            (cut ? "Vystrihnuté: " : "Skopírované: ") + (items.length === 1 ? items[0].name : items.length + " položiek") + " (Ctrl+V vloží)");
    }
    Process {
        id: pasteProc
        stdout: StdioCollector {
            onStreamFinished: {
                const src = this.text.split(/\r?\n/).filter(l => l.startsWith("file://")).map(l => decodeURI(l.slice(7)));
                if (!src.length) { app.status = "Schránka neobsahuje súbory"; return; }
                app.enqueue({ move: app.cutMode, target: app.activePane.path + "/", sources: src, mode: "premenovat", mask: "*",
                              label: (src.length === 1 ? src[0].split("/").pop() : src.length + " položiek") + " → " + app.activePane.path.replace(app.home, "~") });
                app.cutMode = false;
            }
        }
    }
    function clipPaste() { pasteProc.command = ["wl-paste", "--no-newline", "--type", "text/uri-list"]; pasteProc.running = true; }

    // ── nástroje TC (data/TcDialogy.qml, latte-tc) ──────────────────────────────────────
    readonly property var archiveRe: /\.(zip|7z|rar|tar|tgz|tbz2|txz|tar\.gz|tar\.bz2|tar\.xz|tar\.zst|iso|cab|jar|apk|deb|rpm|cpio)$/i
    function tool(t) {
        const items = app.activePane.selection();
        if (["atributy", "zbal", "rozdel", "archiv"].indexOf(t) >= 0 && !items.length) { app.status = "Nič nie je vybrané"; return; }
        if (t === "rozdel" && items[0].isDir) { app.status = "Rozdeliť sa dá iba súbor"; return; }
        if (t === "sync" && !app.dual) { app.dual = true; }
        tcd.open(t, items, app.activePane.path, app.dual ? app.otherPane.path : app.activePane.path);
    }
    function lister(e) { if (e && !e.isDir) run(["latte-app", "lister", e.path]); }
    // Shift+F2: porovnať priečinky — označí nové a novšie súbory na oboch stranách
    Process {
        id: cmpProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}; try { r = JSON.parse(this.text); } catch (e) { return; }
                const ma = {}, mb = {}; let na = 0, nb = 0, same = 0;
                for (const n in r) {
                    if (r[n] === "iba_vlavo" || r[n] === "novsie_vlavo") { ma[paneA.path + "/" + n] = true; na++; }
                    else if (r[n] === "iba_vpravo" || r[n] === "novsie_vpravo") { mb[paneB.path + "/" + n] = true; nb++; }
                    else if (r[n] === "rovnake") same++;
                }
                paneA.setMarks(ma); paneB.setMarks(mb);
                app.status = "Porovnanie: vľavo " + na + " nových/novších, vpravo " + nb + ", rovnakých " + same + (na + nb === 0 ? " — priečinky sú rovnaké" : " (označené; F5 skopíruje)");
            }
        }
    }
    function compareDirs(byContent) { if (!app.dual) app.dual = true; cmpProc.command = ["latte-tc", "porovnaj", paneA.path, paneB.path].concat(byContent ? ["--obsah"] : []); cmpProc.running = true; }
    // Ctrl+B: plochý pohľad (všetky súbory z podpriečinkov) do výsledkov
    function branchView() { app.foundQuery = "plochý pohľad"; app.finding = true; findProc.command = ["sh", "-c", "find \"$1\" -mindepth 1 -type f -printf 'f|%p\\n' 2>/dev/null | head -3000", "sh", app.activePane.path]; findProc.running = true; }
    // kontrolné súčty, spojenie
    Process { id: sumProc; stdout: StdioCollector { onStreamFinished: { app.status = "Súčet vytvorený: " + this.text.trim().split("/").pop(); refreshBoth.restart(); } } }
    Process {
        id: verProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = []; try { r = JSON.parse(this.text); } catch (e) {}
                const bad = r.filter(x => x[1] !== "ok");
                app.status = bad.length ? "⚠ Kontrola: " + bad.length + " z " + r.length + " nesedí (" + bad.slice(0, 3).map(x => x[0] + " " + x[1]).join(", ") + ")" : "✓ Kontrola: všetkých " + r.length + " súborov v poriadku";
            }
        }
    }
    function checksum(algo) { const it = app.activePane.selection().filter(e => !e.isDir); if (!it.length) return; sumProc.command = ["latte-tc", "sucet", algo].concat(it.map(e => e.path)); sumProc.running = true; app.status = "Počítam " + algo.toUpperCase() + "…"; }
    function verify() { const e = app.sel; if (!e || !/\.(md5|sha1|sha256|sha512)$/i.test(e.name)) { app.status = "Vyber súbor .sha256 / .md5"; return; } verProc.command = ["latte-tc", "over", e.path]; verProc.running = true; app.status = "Overujem…"; }
    function combine() { const e = app.sel; if (!e || !/\.\d{3}$/.test(e.name)) { app.status = "Vyber prvú časť (.001)"; return; } run(["latte-tc", "spoj", e.path, app.dual ? app.otherPane.path : app.activePane.path], "Spájam " + e.name + "…"); refreshBoth.restart(); }
    // ── Súbory / Označiť (TC): porovnanie obsahu, odkazy, kódovanie, mená do schránky, uložený výber ──
    function markExt(on) {
        const p = app.activePane, e = p.current; if (!e || e.isDir) return;
        const m = e.name.match(/\.[^.]+$/), ext = m ? m[0].toLowerCase() : "";
        const mk = Object.assign({}, p.marked);
        for (let i = 0; i < p.count; i++) { const x = p.entryAt(i); if (x.isDir) continue; const xm = x.name.match(/\.[^.]+$/);
            if ((xm ? xm[0].toLowerCase() : "") === ext) { if (on) mk[x.path] = x.size; else delete mk[x.path]; } }
        p.setMarks(mk); app.status = (on ? "Označené" : "Odznačené") + " všetky " + (ext || "bez prípony");
    }
    function compareFiles() {
        const it = app.activePane.selection().filter(e => !e.isDir);
        let a = "", b = "";
        if (it.length >= 2) { a = it[0].path; b = it[1].path; }
        else if (it.length === 1 && app.dual) { a = it[0].path; b = app.otherPane.path + "/" + it[0].name;
                                                const o = app.otherPane.current; if (o && !o.isDir && o.name !== it[0].name) b = o.path; }
        else { app.status = "Označ dva súbory alebo súbor s rovnomenným v druhom paneli"; return; }
        run(["latte-app", "porovnaj", a, b], "Porovnávam " + a.split("/").pop() + " ↔ " + b.split("/").pop());
    }
    function makeLink(kind) {
        const e = app.sel; if (!e) return;
        const dir = app.dual ? app.otherPane.path : app.activePane.path;
        app.askInput(kind === "symbolicky" ? "Symbolický odkaz (Ctrl+Shift+F5)" : "Pevný odkaz", (dir === app.activePane.path ? "odkaz na " : "") + e.name,
                     "vznikne v " + dir.replace(app.home, "~") + " a ukazuje na " + e.name + (kind === "pevny" ? " · pevný odkaz iba pre súbor na tom istom disku" : ""),
                     (t) => { run(["latte-tc", "odkaz", kind, e.path, dir + "/" + t], (kind === "symbolicky" ? "Symbolický" : "Pevný") + " odkaz: " + t); refreshBoth.restart(); });
    }
    function encode(kind) {
        const it = app.activePane.selection().filter(e => !e.isDir); if (!it.length) { app.status = "Vyber súbor"; return; }
        const dir = app.dual ? app.otherPane.path : app.activePane.path;
        run(["sh", "-c", 'k="$1"; d="$2"; shift 2; for f in "$@"; do latte-tc kod "$k" "$f" "$d" || exit 1; done', "sh", kind, dir].concat(it.map(e => e.path)), "Zakódované (" + kind.toUpperCase() + ") do " + dir.replace(app.home, "~"));
        refreshBoth.restart();
    }
    function decode() {
        const e = app.sel; if (!e || e.isDir) return;
        run(["latte-tc", "dekod", e.path, app.dual ? app.otherPane.path : app.activePane.path], "Dekódované: " + e.name); refreshBoth.restart();
    }
    function copyNames(withPath) {
        const it = app.activePane.selection(); if (!it.length) return;
        run(["wl-copy", "--", it.map(e => withPath ? e.path : e.name).join("\n")], it.length + (withPath ? " ciest" : " mien") + " v schránke");
    }
    function listToFile() {
        const it = app.activePane.selection(); if (!it.length) return;
        app.askInput("Zoznam súborov do textu", "zoznam.txt", "uloží sa do " + app.activePane.path.replace(app.home, "~") + " (cesta a veľkosť na riadok)",
                     (t) => run(["sh", "-c", 'o="$1"; shift; for f in "$@"; do printf "%s\t%s\n" "$f" "$(stat -c %s -- "$f")"; done > "$o"', "sh", app.activePane.path + "/" + t].concat(it.map(e => e.path)), "Zoznam uložený: " + t));
    }
    // tlač zoznamu (TC): tabuľka označených položiek (inak celého priečinka) sa otvorí v Heidelbergu, ten ju vytlačí / uloží do PDF
    function printList() {
        const p = app.activePane, out = [];
        const all = p.markedCount ? p.selection() : (function () { const l = []; for (let i = 0; i < p.count; i++) l.push(p.entryAt(i)); return l; })();
        const rows = all.filter(e => e.name !== "..").map(e => "| " + e.name.replace(/\|/g, "\\|") + " | " + (e.isDir ? "priečinok" : p.human(e.size)) + " | "
                                                        + Qt.formatDateTime(e.modified, "d. M. yyyy HH:mm") + " |");
        const md = "# " + p.path.replace(app.home, "~") + "\n\n" + all.length + " položiek · " + Qt.formatDateTime(new Date(), "d. M. yyyy HH:mm")
                 + "\n\n| Názov | Veľkosť | Zmenené |\n|---|---:|---|\n" + rows.join("\n") + "\n";
        const f = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos/Zoznam " + (p.path.split("/").pop() || "koreň") + ".md";
        run(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1" && latte-otvor spusti latteos-heidelberg "$1"', "sh", f, md], "Zoznam otvorený v Heidelbergu na tlač");
    }
    property var savedSel: []
    function saveSelection() { savedSel = app.activePane.selection().map(e => e.name); app.status = "Výber uložený (" + savedSel.length + ")"; }
    function restoreSelection() {
        const p = app.activePane, mk = {};
        for (let i = 0; i < p.count; i++) { const x = p.entryAt(i); if (savedSel.indexOf(x.name) >= 0) mk[x.path] = x.isDir ? 0 : x.size; }
        p.setMarks(mk); app.status = "Výber obnovený (" + Object.keys(mk).length + ")";
    }
    function addToArchive() {
        const o = app.otherPane.current, it = app.activePane.selection();
        if (!app.dual || !o || !/\.(7z|zip|tar|tar\.gz|tgz|tar\.xz)$/i.test(o.name) || !it.length) { app.status = "V druhom paneli vyber archív 7z/zip/tar"; return; }
        run(["latte-tc", "archiv", "pridaj", o.path].concat(it.map(e => e.path)), "Pridávam do " + o.name + "…"); refreshBoth.restart();
    }
    function commandsMenu(x, y) {
        const e = app.sel;
        ctx.open(x, y, [
            { glyph: "pencil", label: "Hromadné premenovanie…", hint: "Ctrl+M", action: () => app.tool("premenuj") },
            { glyph: "refresh", label: "Späť posledné premenovanie", action: () => { app.run(["latte-tc", "spat"], "Vrátené posledné hromadné premenovanie"); refreshBoth.restart(); } },
            { glyph: "search", label: "Hľadať súbory…", hint: "Alt+F7", action: () => app.tool("hladaj") },
            { glyph: "list", label: "Plochý pohľad (všetko z podpriečinkov)", hint: "Ctrl+B", action: () => app.branchView() },
            { glyph: "folder", label: "Strom priečinkov…", hint: "Alt+F10", action: () => app.tool("strom") },
            { separator: true },
            { glyph: "columns-2", label: "Porovnať súbory podľa obsahu", action: () => app.compareFiles() },
            { glyph: "columns-2", label: "Porovnať priečinky (označiť rozdiely)", hint: "Shift+F2", action: () => app.compareDirs(false) },
            { glyph: "copy", label: "Označiť, čo je aj v druhom paneli", enabled: app.dual, action: () => { const n = app.activePane.markByOther(app.otherPane, true); app.status = "Rovnaké mená: " + n; } },
            { glyph: "plus", label: "Označiť, čo v druhom paneli chýba", enabled: app.dual, action: () => { const n = app.activePane.markByOther(app.otherPane, false); app.status = "Chýba v druhom paneli: " + n; } },
            { glyph: "columns-2", label: "Porovnať podľa obsahu", action: () => app.compareDirs(true) },
            { glyph: "refresh", label: "Synchronizovať priečinky…", action: () => app.tool("sync") },
            { separator: true },
            { glyph: "file-zip", label: "Zbaliť…", hint: "Alt+F5", action: () => app.tool("zbal") },
            { glyph: "file-zip", label: "Otvoriť archív ako priečinok", hint: "Enter", enabled: !!e && app.archiveRe.test(e.name), action: () => app.tool("archiv") },
            { glyph: "download", label: "Rozbaliť celý archív do druhého panela", hint: "Alt+F9", enabled: !!e && app.archiveRe.test(e.name), action: () => app.extractAll() },
            { glyph: "plus", label: "Pridať označené do archívu v druhom paneli", action: () => app.addToArchive() },
            { separator: true },
            { glyph: "external-link", label: "Vytvoriť symbolický odkaz…", hint: "Ctrl+Shift+F5", enabled: !!e, action: () => app.makeLink("symbolicky") },
            { glyph: "external-link", label: "Vytvoriť pevný odkaz…", enabled: !!e && !e.isDir, action: () => app.makeLink("pevny") },
            { glyph: "file-code", label: "Zakódovať (Base64)", enabled: !!e, action: () => app.encode("base64") },
            { glyph: "file-code", label: "Zakódovať (UUE)", enabled: !!e, action: () => app.encode("uue") },
            { glyph: "file-code", label: "Dekódovať (Base64 / UUE)", enabled: !!e && !e.isDir, action: () => app.decode() },
            { separator: true },
            { glyph: "check", label: "Označiť rovnakú príponu", hint: "Alt+Num +", enabled: !!e && !e.isDir, action: () => app.markExt(true) },
            { glyph: "clipboard", label: "Kopírovať mená do schránky", action: () => app.copyNames(false) },
            { glyph: "clipboard", label: "Kopírovať mená s cestou", action: () => app.copyNames(true) },
            { glyph: "file-text", label: "Zoznam súborov do textu…", action: () => app.listToFile() },
            { glyph: "printer", label: "Tlač zoznamu…", action: () => app.printList() },
            { glyph: "star", label: "Uložiť výber", action: () => app.saveSelection() },
            { glyph: "history", label: "Obnoviť výber", enabled: app.savedSel.length > 0, action: () => app.restoreSelection() },
            { separator: true },
            { glyph: "check", label: "Vytvoriť kontrolný súčet SHA-256", action: () => app.checksum("sha256") },
            { glyph: "check", label: "Vytvoriť kontrolný súčet MD5", action: () => app.checksum("md5") },
            { glyph: "check", label: "Overiť kontrolné súčty", enabled: !!e && /\.(md5|sha1|sha256|sha512)$/i.test(e.name), action: () => app.verify() },
            { glyph: "layout-list", label: "Rozdeliť súbor…", action: () => app.tool("rozdel") },
            { glyph: "layout-list", label: "Spojiť časti (.001)", enabled: !!e && /\.\d{3}$/.test(e.name), action: () => app.combine() },
            { separator: true },
            { glyph: "info-circle", label: "Vlastnosti a atribúty…", hint: "Alt+Enter", action: () => app.tool("atributy") },
            { glyph: "file-text", label: "Lister (rýchly náhľad)", hint: "F3", enabled: !!e && !e.isDir, action: () => app.lister(e) },
            { glyph: "terminal-2", label: "Terminál tu", action: () => app.run(["foot", "--working-directory=" + app.activePane.path]) }
        ], "Príkazy · Total Commander");
    }
    function extractAll() { const e = app.sel; if (!e || !app.archiveRe.test(e.name)) return; const d = (app.dual ? app.otherPane.path : app.activePane.path) + "/" + e.name.replace(app.archiveRe, "");
                            run(["latte-tc", "archiv", "rozbal", e.path, d], "Rozbaľujem do " + d.replace(app.home, "~")); refreshBoth.restart(); }

    // riadok príkazu (ako v TC): príkaz sa spustí v aktívnom priečinku v termináli; ↑/↓ história, Ctrl+Enter vloží meno
    property var cmdHistory: []
    property int cmdHi: -1
    function runCommand(c) {
        c = c.trim(); if (!c) return;
        if (/^cd\s+/.test(c)) { let d = c.replace(/^cd\s+/, "").replace(/^~/, app.home); if (!d.startsWith("/")) d = app.activePane.path + "/" + d; app.activePane.go(d); }
        else run(["foot", "--working-directory=" + app.activePane.path, "sh", "-c", c + '; echo; printf "[Enter zavrie] "; read x'], "Spúšťam: " + c);
        cmdHistory = [c].concat(cmdHistory.filter(x => x !== c)).slice(0, 50); cmdHi = -1;
    }
    // lišta tlačidiel (~/.config/latteos/subory-tlacidla.json: [{ label, glyph, cmd }], %P priečinok, %N meno, %F cesta)
    property var buttons: [
        { label: "Terminál", glyph: "terminal-2", cmd: "foot --working-directory=%P" },
        { label: "Heidelberg", glyph: "pencil", cmd: "latte-app heidelberg %F" },
        { label: "Porovnať", glyph: "columns-2", cmd: ":porovnaj" },
        { label: "Synchronizovať", glyph: "refresh", cmd: ":sync" },
        { label: "Hľadať", glyph: "search", cmd: ":hladaj" },
        { label: "Premenovať", glyph: "pencil", cmd: ":premenuj" },
        { label: "Zbaliť", glyph: "file-zip", cmd: ":zbal" }
    ]
    FileView { id: buttonsFile; path: (Quickshell.env("XDG_CONFIG_HOME") || (app.home + "/.config")) + "/latteos/subory-tlacidla.json"; printErrors: false
               onLoaded: { try { const b = JSON.parse(text()); if (Array.isArray(b) && b.length) app.buttons = b; } catch (e) {} } }
    readonly property var defaultButtons: [
        { label: "Terminál", glyph: "terminal-2", cmd: "foot --working-directory=%P" }, { label: "Heidelberg", glyph: "pencil", cmd: "latte-app heidelberg %F" },
        { label: "Porovnať", glyph: "columns-2", cmd: ":porovnaj" }, { label: "Synchronizovať", glyph: "refresh", cmd: ":sync" },
        { label: "Hľadať", glyph: "search", cmd: ":hladaj" }, { label: "Premenovať", glyph: "pencil", cmd: ":premenuj" }, { label: "Zbaliť", glyph: "file-zip", cmd: ":zbal" }]
    // úprava lišty tlačidiel myšou (ako v TC: pravý klik › Upraviť / Posunúť / Odstrániť / Pridať)
    readonly property var builtinButtons: [["porovnaj", "Porovnať priečinky", "columns-2"], ["sync", "Synchronizovať", "refresh"], ["hladaj", "Hľadať", "search"],
        ["premenuj", "Hromadné premenovanie", "pencil"], ["zbal", "Zbaliť", "file-zip"], ["archiv", "Otvoriť archív", "file-zip"],
        ["strom", "Strom priečinkov", "list-tree"], ["atributy", "Vlastnosti a práva", "info-circle"], ["rozdel", "Rozdeliť súbor", "columns-2"]]
    function saveButtons(b) { app.buttons = b; mkState.running = true; buttonsFile.setText(JSON.stringify(b, null, 1)); }
    Process { id: mkState; command: ["mkdir", "-p", (Quickshell.env("XDG_CONFIG_HOME") || (app.home + "/.config")) + "/latteos"] }
    function addButtonMenu(x, y, at) {
        const put = (b) => { const l = app.buttons.slice(); l.splice(at < 0 ? l.length : at + 1, 0, b); app.saveButtons(l); };
        ctx.open(x, y, [
            { glyph: "terminal-2", label: "Vlastný príkaz…", keepOpen: true, action: () => ctx.replace([{ input: "", label: "Názov tlačidla", action: (n) => {
                ctx.open(x, y, [{ input: "foot --working-directory=%P", label: "Príkaz", action: (c) => put({ label: n, glyph: "terminal-2", cmd: c }) }],
                         "Príkaz · %P priečinok, %N meno, %F cesta k súboru"); } }], "Názov nového tlačidla") },
            { glyph: "apps", label: "Vstavaný nástroj", sub: app.builtinButtons.map(t => ({ glyph: t[2], label: t[1], action: () => put({ label: t[1], glyph: t[2], cmd: ":" + t[0] }) })) },
            { separator: true },
            { glyph: "refresh", label: "Obnoviť predvolené tlačidlá", action: () => app.saveButtons(app.defaultButtons) }], "Pridať tlačidlo");
    }
    function buttonMenu(i, x, y) {
        const b = app.buttons[i], l = () => app.buttons.slice();
        ctx.open(x, y, [
            { glyph: "pencil", label: "Premenovať…", keepOpen: true, action: () => ctx.replace([{ input: b.label, action: (t) => { const n = l(); n[i] = Object.assign({}, b, { label: t }); app.saveButtons(n); } }], "Názov tlačidla") },
            { glyph: "terminal-2", label: "Zmeniť príkaz…", enabled: !b.cmd.startsWith(":"), keepOpen: true,
              action: () => ctx.replace([{ input: b.cmd, action: (t) => { const n = l(); n[i] = Object.assign({}, b, { cmd: t }); app.saveButtons(n); } }], "Príkaz · %P priečinok, %N meno, %F cesta") },
            { glyph: "arrow-left", label: "Posunúť vľavo", enabled: i > 0, action: () => { const n = l(); n.splice(i - 1, 0, n.splice(i, 1)[0]); app.saveButtons(n); } },
            { glyph: "arrow-right", label: "Posunúť vpravo", enabled: i < app.buttons.length - 1, action: () => { const n = l(); n.splice(i + 1, 0, n.splice(i, 1)[0]); app.saveButtons(n); } },
            { separator: true },
            { glyph: "plus", label: "Pridať tlačidlo sem…", action: () => app.addButtonMenu(x, y, i) },
            { glyph: "trash", label: "Odstrániť tlačidlo", danger: true, action: () => { const n = l(); n.splice(i, 1); app.saveButtons(n); } }], b.label);
    }
    function pressButton(b) {
        if (b.cmd.startsWith(":")) { const t = b.cmd.slice(1); if (t === "porovnaj") app.compareDirs(false); else app.tool(t); return; }
        const e = app.sel, q = (x) => "'" + String(x).replace(/'/g, "'\\''") + "'";
        const c = b.cmd.replace(/%P/g, q(app.activePane.path)).replace(/%N/g, q(e ? e.name : "")).replace(/%F/g, q(e ? e.path : app.activePane.path));
        run(["sh", "-c", "cd " + q(app.activePane.path) + " && " + c], b.label);
    }

    // rýchle hľadanie písaním (ako v TC / Prieskumníkovi)
    property string quick: ""
    Timer { id: quickReset; interval: 1600; onTriggered: app.quick = "" }

    FloatingWindow {

        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        id: win
        title: "Súbory — LatteOS"
        implicitWidth: 1280
        implicitHeight: 780
        color: theme.surface

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: (ev) => {
                const p = app.activePane, ctrl = ev.modifiers & Qt.ControlModifier, shift = ev.modifiers & Qt.ShiftModifier, alt = ev.modifiers & Qt.AltModifier;
                const i = app.activeIndex, k = ev.key;
                if (app.connectOpen || app.ask || app.op || app.conflict || app.delAsk || tcd.visible) return;
                ev.accepted = true;
                // ── pohyb ──
                if (k === Qt.Key_Down && !alt) p.moveRow(1);
                else if (k === Qt.Key_Up && !alt) p.moveRow(-1);
                else if (k === Qt.Key_Right && p.icons && !ctrl && !alt) p.moveSelection(1);
                else if (k === Qt.Key_Left && p.icons && !ctrl && !alt) p.moveSelection(-1);
                else if (k === Qt.Key_PageDown) p.moveSelection(15);
                else if (k === Qt.Key_PageUp) p.moveSelection(-15);
                else if (k === Qt.Key_Home) p.home_();
                else if (k === Qt.Key_End) p.end_();
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    if (alt && shift) app.dirSizes(p, (function () { const l = []; for (let x = 0; x < p.count; x++) { const e = p.entryAt(x); if (e.isDir) l.push(e.path); } return l; })());
                    else if (alt) app.tool("atributy");
                    else if (ctrl && app.commander) { const e = app.sel; if (e) { cmdIn.insert(cmdIn.cursorPosition, (cmdIn.text && !cmdIn.text.endsWith(" ") ? " " : "") + (/\s/.test(e.name) ? '"' + e.name + '"' : e.name) + " "); cmdIn.forceActiveFocus(); } }
                    else if (app.commander && app.sel && !app.sel.isDir && app.archiveRe.test(app.sel.name)) app.tool("archiv");
                    else p.openCurrent();
                }
                // ── Prieskumník (režim Forklift) ako Windows; v režime TC ostávajú klávesy TC ──
                else if (k === Qt.Key_Z && ctrl) app.undo();
                else if ((k === Qt.Key_Left && alt) || k === Qt.Key_Back) p.back();
                else if ((k === Qt.Key_Right && alt) || k === Qt.Key_Forward) p.forward();
                else if (k === Qt.Key_Up && alt) p.up();
                else if (k === Qt.Key_N && ctrl && shift) app.newFolder(p);
                else if (k === Qt.Key_N && ctrl) app.run(["latte-app", "subory", p.path], "Nové okno");
                else if ((k === Qt.Key_F && ctrl) || (k === Qt.Key_E && ctrl) || (k === Qt.Key_F3 && !app.commander && !ctrl && !alt && !shift)) header.focusSearch();
                else if ((k === Qt.Key_L && ctrl) || (k === Qt.Key_D && alt) || (k === Qt.Key_F4 && !app.commander && !shift && !alt))
                    app.askInput("Prejsť na priečinok", p.path, "cesta, napr. ~/Dokumenty alebo /media", (t) => p.go(t.replace(/^~(?=\/|$)/, app.home).replace(/\/+$/, "") || "/"));
                else if (k === Qt.Key_F2 && !app.commander && !shift && !ctrl && !alt) {
                    const e = p.current;
                    if (e) { const q = p.itemPoint(); ctx.open(q.x, q.y, [{ input: e.name, wholeName: e.isDir, action: (t) => app.rename(e, t) }], "Nový názov · Enter uloží, Esc zruší"); }
                }
                else if (k === Qt.Key_F5 && !app.commander && !ctrl && !shift && !alt) { p.refresh(); app.status = "Obnovené"; }
                else if ((k === Qt.Key_F10 && shift) || k === Qt.Key_Menu) { const q = p.itemPoint(); app.showMenu(p.current, q.x, q.y, p); }
                else if (k === Qt.Key_Space && !app.commander) { const e = p.current; if (e && !e.isDir) app.lister(e); }
                else if (k === Qt.Key_C && ctrl && shift) app.run(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", (p.current || { path: p.path }).path], "Cesta skopírovaná");
                else if (k === Qt.Key_Backspace && !app.commander) p.back();
                else if (k === Qt.Key_Backspace) p.up();
                else if (k === Qt.Key_Tab && !ctrl && app.dual) app.activeIndex = 1 - i;
                // ── karty ──
                else if (k === Qt.Key_T && ctrl) app.newTab(i);
                else if (k === Qt.Key_W && ctrl) app.closeTab(i);
                else if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && ctrl) app.switchTab(i, app.tabIdx[i] + ((shift || k === Qt.Key_Backtab) ? -1 : 1));
                else if (k === Qt.Key_D && ctrl) { const q = header.mapToItem(null, 60, header.height); app.hotlist(q.x, q.y); }
                else if (k === Qt.Key_F1 && alt) { const q = header.mapToItem(null, 20, header.height); app.driveMenu(0, q.x, q.y); }
                else if (k === Qt.Key_F2 && alt) { const q = header.mapToItem(null, header.width / 2, header.height); app.driveMenu(1, q.x, q.y); }
                else if (k === Qt.Key_U && ctrl) app.swapPanels();
                else if (k === Qt.Key_Left && ctrl) app.toSide(0);
                else if (k === Qt.Key_Right && ctrl) app.toSide(1);
                // ── zobrazenie a triedenie ──
                else if (k === Qt.Key_F1 && ctrl && shift) app.view = "ikony";
                else if (k === Qt.Key_F1 && ctrl) app.view = "zoznam";
                else if (k === Qt.Key_F2 && ctrl) app.view = "detaily";
                else if (k === Qt.Key_F3 && ctrl) { p.sortReversed = p.sortField === 1 ? !p.sortReversed : false; p.sortField = 1; }
                else if (k === Qt.Key_F4 && ctrl) { p.sortReversed = p.sortField === 4 ? !p.sortReversed : false; p.sortField = 4; }
                else if (k === Qt.Key_F5 && ctrl && !shift) { p.sortReversed = p.sortField === 2 ? !p.sortReversed : false; p.sortField = 2; }
                else if (k === Qt.Key_F6 && ctrl) { p.sortReversed = p.sortField === 3 ? !p.sortReversed : false; p.sortField = 3; }
                else if ((k === Qt.Key_Q && ctrl) || (k === Qt.Key_P && alt)) app.showDetail = !app.showDetail;
                else if ((k === Qt.Key_R && ctrl) || (k === Qt.Key_F2 && !shift)) { p.refresh(); app.status = "Obnovené"; }
                else if (k === Qt.Key_H && ctrl) p.showHidden = !p.showHidden;
                // ── označovanie ──
                else if (k === Qt.Key_Insert) { p.toggleMark(p.cur); p.moveSelection(1); }
                else if (k === Qt.Key_Space && !ctrl) { const e = p.current; if (e) { p.toggleMark(p.cur); if (e.isDir && p.isMarked(e.path)) app.dirSizes(p, [e.path]); p.moveSelection(1); } }
                else if (k === Qt.Key_A && ctrl) p.markAll();
                else if (k === Qt.Key_Plus && alt) app.markExt(true);
                else if (k === Qt.Key_Minus && alt) app.markExt(false);
                else if (k === Qt.Key_Plus && !ctrl) app.askInput("Označiť podľa masky (Num +)", "*.*", "napr. *.jpg;*.png · priečinky sa neoznačia, pridaj aj „/“ na koniec: foto*/", (t) => p.markMask(t.replace(/\/$/, ""), true, t.endsWith("/")));
                else if (k === Qt.Key_Minus && !ctrl) app.askInput("Zrušiť označenie podľa masky (Num −)", "*.*", "napr. *.tmp", (t) => p.markMask(t.replace(/\/$/, ""), false, true));
                else if (k === Qt.Key_Asterisk) p.invertMarks();
                // ── schránka súborov ──
                else if (k === Qt.Key_C && ctrl) app.clipCopy(false);
                else if (k === Qt.Key_X && ctrl) app.clipCopy(true);
                else if (k === Qt.Key_V && ctrl) app.clipPaste();
                // ── nástroje TC ──
                else if (k === Qt.Key_M && ctrl) app.tool("premenuj");
                else if (k === Qt.Key_F7 && alt) app.tool("hladaj");
                else if (k === Qt.Key_F5 && alt) app.tool("zbal");
                else if (k === Qt.Key_F9 && alt) app.extractAll();
                else if (k === Qt.Key_F2 && shift) app.compareDirs(false);
                else if (k === Qt.Key_B && ctrl) app.branchView();
                else if (k === Qt.Key_F10 && alt) app.tool("strom");
                else if (k === Qt.Key_F8 && ctrl) { app.showTree = !app.showTree; app.saveState(); }
                else if (k === Qt.Key_F5 && ctrl && shift) app.makeLink("symbolicky");
                // ── F-klávesy ──
                else if (k === Qt.Key_F3 && app.commander) { if (app.sel) { if (app.sel.isDir) p.openCurrent(); else app.lister(app.sel); } }
                else if (k === Qt.Key_F3) { app.dual = !app.dual; if (!app.dual) app.activeIndex = 0; }
                else if (k === Qt.Key_F4 && shift) app.askInput("Nový súbor (Shift+F4)", "nový.txt", "súbor sa vytvorí v " + p.path.replace(app.home, "~") + " a otvorí v Heidelbergu",
                                                             (t) => app.run(["sh", "-c", 'f="$1/$2"; [ -e "$f" ] || : > "$f"; latte-otvor spusti latteos-heidelberg "$f"', "sh", p.path, t], "Nový súbor: " + t));
                else if (k === Qt.Key_F4) { if (app.sel && !app.sel.isDir) app.run(["latte-otvor", "spusti", "latteos-heidelberg", app.sel.path], "Upraviť: " + app.sel.name); }
                else if (k === Qt.Key_F5) app.openOp(false);
                else if (k === Qt.Key_F6 && shift) { const e = app.sel; if (e) app.askInput("Premenovať (Shift+F6)", e.name, "", (t) => app.rename(e, t)); }
                else if (k === Qt.Key_F6) app.openOp(true);
                else if (k === Qt.Key_F7) app.askInput("Nový priečinok (F7)", "", "aj vnorené: a/b/c", (t) => app.run(["mkdir", "-p", "--", p.path + "/" + t], "Nový priečinok: " + t));
                else if ((k === Qt.Key_F8 || k === Qt.Key_Delete) && shift) app.askDelete(true);
                else if (k === Qt.Key_F8 || k === Qt.Key_Delete) app.askDelete(false);
                else if (k === Qt.Key_F9) { app.connectError = ""; app.connectOpen = true; }
                else if (k === Qt.Key_Escape) { if (app.quick !== "") app.quick = ""; else if (p.markedCount) p.clearMarks(); app.confirm = ""; app.status = ""; }
                // ── rýchle hľadanie písaním ──
                else if (!ctrl && !alt && ev.text && ev.text.length === 1 && ev.text > " ") {
                    app.quick += ev.text; quickReset.restart();
                    if (!p.quickFind(app.quick)) app.status = "Nič sa nezačína na „" + app.quick + "“";
                }
                else ev.accepted = false;
            }

            SideBar {
                id: side
                theme: theme
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                heading: "Súbory"; headingGlyph: "folder"
                model: app.sidebarModel
                current: {
                    const p = app.activePane ? app.activePane.path : "";
                    for (const s of app.sidebarModel) for (const it of s.items) if (it.path === p) return it.key;
                    return "";
                }
                onActivated: (it) => { if (it.key === "cloud:add") { app.run(["latte-app", "nastavenia", "synchronizacia"]); return; }
                                       if (it.key === "net:add") { app.connectError = ""; app.connectOpen = true; return; }
                                       app.activePane.go(it.path); root.forceActiveFocus(); }
                onContextRequested: (it, x, y) => app.showSideMenu(it, x, y)
            }

            HeaderBar {
                id: header
                theme: theme
                appId: "latteos-subory"
                anchors { left: side.right; right: parent.right; top: parent.top }
                title: app.activePane ? (app.activePane.path === app.trashDir ? "Kôš" : app.activePane.path) : ""
                crumbPath: app.activePane && app.activePane.path !== app.trashDir && !app.activePane.path.includes("://") ? app.activePane.path : ""
                onCrumbClicked: (p) => { app.activePane.go(p); root.forceActiveFocus(); }
                canBack: app.activePane && app.activePane.historyIndex > 0
                canForward: app.activePane && app.activePane.historyIndex < app.activePane.history.length - 1
                searchPlaceholder: "Hľadať (Enter = všade)"
                onBack: app.activePane.back()
                onForward: app.activePane.forward()
                onSearchChanged: (t) => { app.activePane.filter = t; if (t === "") app.found = []; }
                onSearchSubmitted: (t) => app.findAll(t)
                onCloseRequested: Qt.quit()

                IconButton { theme: theme; glyph: "arrow-up"; tip: "O úroveň vyššie (Alt+↑)"; onClicked: app.activePane.up() }
                IconButton { theme: theme; glyph: "list-tree"; tip: "Strom priečinkov (Ctrl+F8)"; onClicked: { app.showTree = !app.showTree; app.saveState(); } }
                IconButton { id: cmdBtn; visible: app.commander; theme: theme; glyph: "menu-2"; tip: "Príkazy (premenovanie, hľadanie, porovnanie, archívy, súčty…)"
                             onClicked: { const q = cmdBtn.mapToItem(null, 0, cmdBtn.height + 4); app.commandsMenu(q.x, q.y); } }
                IconButton { id: newBtn; theme: theme; glyph: "plus"; tip: "Nový priečinok alebo súbor"
                             onClicked: { const q = newBtn.mapToItem(null, 0, newBtn.height + 4); app.newMenu(q.x, q.y, app.activePane); } }
                IconButton { id: viewBtn; theme: theme; glyph: app.view === "ikony" ? "layout-grid" : "layout-list"; tip: "Zobrazenie (ikony, zoznam, podrobnosti)"
                             onClicked: { const q = viewBtn.mapToItem(null, 0, viewBtn.height + 4); app.viewMenu(q.x, q.y); } }
                IconButton { theme: theme; glyph: "info-circle"; checked: app.showDetail; tip: "Panel náhľadu (Alt+P)"; onClicked: app.showDetail = !app.showDetail }
                IconButton { visible: !app.commander; theme: theme; glyph: "columns-2"; checked: app.dual; tip: "Dva panely (F3)"; onClicked: { app.dual = !app.dual; if (!app.dual) app.activeIndex = 0; } }
                IconButton { theme: theme; glyph: "layout-columns"; checked: app.commander; tip: app.commander ? "Režim Total Commander · klik: Forklift" : "Režim Forklift · klik: Total Commander"
                             onClicked: app.setMode(app.commander ? "forklift" : "commander") }
                IconButton { theme: theme; glyph: app.activePane && app.activePane.showHidden ? "eye" : "eye-off"; tip: "Skryté súbory (Ctrl+H)"; onClicked: app.activePane.showHidden = !app.activePane.showHidden }
                IconButton { theme: theme; glyph: "terminal-2"; tip: "Terminál tu"; onClicked: app.run(["foot", "--working-directory=" + app.activePane.path]) }
            }

            // lišta tlačidiel (TC) — vlastné tlačidlá v ~/.config/latteos/subory-tlacidla.json
            Row {
                id: btnBar
                anchors { left: side.right; leftMargin: 10; top: header.bottom; topMargin: app.commander ? 6 : 0 }
                height: app.commander ? 30 : 0; visible: app.commander; spacing: 4
                Repeater {
                    model: app.buttons
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: bbl.implicitWidth + 36; height: 28; radius: 8; color: bbm.containsMouse ? theme.hover : theme.field
                        Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; name: modelData.glyph || "terminal-2"; size: 14; color: theme.primary }
                        Text { id: bbl; x: 28; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                        MouseArea { id: bbm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (m) => { if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); app.buttonMenu(index, q.x, q.y); }
                                                        else { app.pressButton(modelData); root.forceActiveFocus(); } } }
                    }
                }
                // prázdne miesto za tlačidlami: pravý klik = pridať
                Rectangle {
                    width: 30; height: 28; radius: 8; color: abm.containsMouse ? theme.hover : "transparent"
                    Glyph { anchors.centerIn: parent; name: "plus"; size: 14; color: theme.fgDim }
                    MouseArea { id: abm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => { const q = mapToItem(null, m.x, m.y); app.addButtonMenu(q.x, q.y, -1); } }
                }
            }
            // riadok príkazu (TC)
            Rectangle {
                id: cmdLine
                anchors { left: side.right; right: parent.right; bottom: statusBar.top; leftMargin: 10; rightMargin: 10; bottomMargin: app.commander ? 4 : 0 }
                height: app.commander ? 30 : 0; visible: app.commander; radius: 8; color: theme.field
                border { color: cmdIn.activeFocus ? theme.primary : "transparent"; width: 1 }
                Text { id: prompt; x: 10; anchors.verticalCenter: parent.verticalCenter; text: app.activePane ? app.activePane.path.replace(app.home, "~") + " $" : "$"
                       color: theme.primary; font { family: theme.fontMono; pixelSize: 12 } }
                TextInput {
                    id: cmdIn
                    anchors { left: prompt.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: theme.fg; clip: true; selectByMouse: true; font { family: theme.fontMono; pixelSize: 12 }
                    Keys.onReturnPressed: (ev) => { ev.accepted = true; app.runCommand(text); text = ""; root.forceActiveFocus(); }
                    Keys.onEscapePressed: (ev) => { ev.accepted = true; text = ""; root.forceActiveFocus(); }
                    Keys.onUpPressed: (ev) => { ev.accepted = true; if (app.cmdHistory.length) { app.cmdHi = Math.min(app.cmdHistory.length - 1, app.cmdHi + 1); text = app.cmdHistory[app.cmdHi]; } }
                    Keys.onDownPressed: (ev) => { ev.accepted = true; app.cmdHi = Math.max(-1, app.cmdHi - 1); text = app.cmdHi >= 0 ? app.cmdHistory[app.cmdHi] : ""; }
                }
                Text { visible: cmdIn.text === "" && !cmdIn.activeFocus; anchors { left: prompt.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                       text: "príkaz (klik sem) · Ctrl+Enter vloží meno · cd priečinok"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
            }

            // panely + detail
            Row {
                id: body
                anchors { left: side.right; right: parent.right; top: btnBar.bottom; bottom: cmdLine.top; margins: 10 }
                spacing: 10
                readonly property real detailW: 280
                readonly property real treeW: 240
                readonly property real paneW: (width - (app.showDetail ? detailW + spacing : 0) - (app.showTree ? treeW + spacing : 0) - (app.dual ? spacing : 0)) / (app.dual ? 2 : 1)

                component TabBar: Row {
                    id: tb
                    property int side: 0
                    visible: app.tabs[side].length > 1 || app.commander
                    height: visible ? 30 : 0; spacing: 3
                    Repeater {
                        model: app.tabs[tb.side]
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool on: app.tabIdx[tb.side] === index
                            width: Math.min(170, tl.implicitWidth + 30 + (modelData.locked ? 14 : 0)); height: 26; radius: 8
                            color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, app.activeIndex === tb.side ? 0.22 : 0.1) : (tm.containsMouse ? theme.hover : theme.field)
                            Row { x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                  Glyph { visible: modelData.locked; name: "lock"; size: 11; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                  Text { id: tl; width: Math.min(implicitWidth, 130); elide: Text.ElideRight; text: app.tabName(modelData); color: theme.fg
                                         font { family: theme.fontUi; pixelSize: 11; weight: on ? Font.Bold : Font.Normal } } }
                            MouseArea {
                                id: tm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: (m) => {
                                    if (m.button === Qt.MiddleButton) { app.closeTab(tb.side, index); return; }
                                    if (m.button === Qt.RightButton) {
                                        const q = mapToItem(null, m.x, m.y);
                                        ctx.open(q.x, q.y, [
                                            { glyph: "plus", label: "Nová karta", hint: "Ctrl+T", action: () => app.newTab(tb.side) },
                                            { glyph: "lock", label: modelData.locked ? "Odomknúť kartu" : "Uzamknúť kartu", hint: "dvojklik", action: () => app.toggleLock(tb.side, index) },
                                            { glyph: "columns-2", label: "Otvoriť v druhom paneli", action: () => { app.dual = true; app.paneAt(1 - tb.side).go(modelData.path); } },
                                            { separator: true },
                                            { glyph: "x", label: "Zavrieť kartu", hint: "Ctrl+W", enabled: app.tabs[tb.side].length > 1, action: () => app.closeTab(tb.side, index) }
                                        ], app.tabName(modelData));
                                        return;
                                    }
                                    app.activeIndex = tb.side; app.switchTab(tb.side, index); root.forceActiveFocus();
                                }
                                onDoubleClicked: app.toggleLock(tb.side, index)
                            }
                        }
                    }
                    Rectangle { width: 26; height: 26; radius: 8; color: pm.containsMouse ? theme.hover : "transparent"
                                Glyph { anchors.centerIn: parent; name: "plus"; size: 13; color: theme.fgDim }
                                MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: app.newTab(tb.side) } }
                }
                StromPanel {
                    visible: app.showTree
                    width: body.treeW; height: body.height
                    theme: theme
                    path: app.activePane ? app.activePane.path : "/"
                    onOpenDir: (p) => { app.activePane.go(p); root.forceActiveFocus(); }
                    onDropRequested: (d, p, area) => app.activePane.acceptDrop(d, p, area)
                    onContextRequested: (p, x, y) => ctx.open(x, y, [
                        { glyph: "folder-open", label: "Otvoriť", action: () => app.activePane.go(p) },
                        { glyph: "columns-2", label: "Otvoriť v druhom paneli", enabled: app.dual, action: () => app.otherPane.go(p) },
                        { glyph: "plus", label: "Otvoriť v novej karte", action: () => { app.newTab(app.activeIndex); app.activePane.go(p); } },
                        { separator: true },
                        { glyph: "terminal-2", label: "Terminál tu", action: () => app.run(["foot", "--working-directory=" + p]) },
                        { glyph: "copy", label: "Kopírovať cestu", action: () => app.run(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", p], "Cesta skopírovaná") },
                        { separator: true },
                        { glyph: "x", label: "Skryť strom", hint: "Ctrl+F8", action: () => { app.showTree = false; app.saveState(); } }], p.split("/").pop() || "/")
                }
                Column {
                    width: body.paneW; height: body.height; spacing: 4
                    TabBar { side: 0 }
                    FilePane {
                        id: paneA
                        theme: theme
                        tags: app.tags
                        dotdot: app.commander
                        view: app.view; iconSize: app.iconSize
                        onContextRequested: (e, x, y) => app.showMenu(e, x, y, paneA)
                        onDropRequested: (items, dir, action, wx, wy) => app.dropOp(items, dir, action, wx, wy)
                        onZoomRequested: (st) => app.zoom(st)
                        dragRule: app.commander ? "copy" : app.dragRule
                        width: parent.width; height: parent.height - y
                        active: app.dual && app.activeIndex === 0
                        Component.onCompleted: go(app.home)
                        onPathChanged: { app.onPanePath(0, path); app.saveState(); }
                        onFocusRequested: { app.activeIndex = 0; app.confirm = ""; root.forceActiveFocus(); }
                        onOpenFile: (p) => app.openPath(p)
                    }
                }
                Column {
                    visible: app.dual
                    width: app.dual ? body.paneW : 0; height: body.height; spacing: 4
                    TabBar { side: 1 }
                    FilePane {
                        id: paneB
                        theme: theme
                        tags: app.tags
                        dotdot: app.commander
                        view: app.view; iconSize: app.iconSize
                        onContextRequested: (e, x, y) => app.showMenu(e, x, y, paneB)
                        onDropRequested: (items, dir, action, wx, wy) => app.dropOp(items, dir, action, wx, wy)
                        onZoomRequested: (st) => app.zoom(st)
                        dragRule: app.commander ? "copy" : app.dragRule
                        width: parent.width; height: parent.height - y
                        active: app.dual && app.activeIndex === 1
                        Component.onCompleted: go("/")
                        onPathChanged: { app.onPanePath(1, path); app.saveState(); }
                        onFocusRequested: { app.activeIndex = 1; app.confirm = ""; root.forceActiveFocus(); }
                        onOpenFile: (p) => app.openPath(p)
                    }
                }

                // detail vybranej položky (návrh V2: pravý panel)
                Rectangle {
                    visible: app.showDetail
                    width: body.detailW; height: body.height; radius: theme.radius
                    color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.16 : 0.04)
                    border { color: theme.line; width: 1 }
                    Column {
                        anchors { fill: parent; margins: 16 }
                        spacing: 10
                        readonly property var e: app.sel
                        readonly property var k: e ? app.activePane.kind(e) : ["", "folder"]

                        Rectangle {
                            width: parent.width; height: 150; radius: 12; color: theme.field; clip: true
                            Glyph { anchors.centerIn: parent; visible: !preview.visible; name: parent.parent.k[1]; size: 64; color: theme.primary }
                            Image {
                                id: preview
                                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                sourceSize { width: 520; height: 300 }
                                visible: status === Image.Ready && parent.parent.k[0] === "Obrázok"
                                source: parent.parent.e && parent.parent.k[0] === "Obrázok" ? "file://" + parent.parent.e.path : ""
                            }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                            text: parent.e ? parent.e.name : (app.activePane ? (app.activePane.path === app.trashDir ? "Kôš" : (app.activePane.path.split("/").pop() || "/")) : "")
                            color: theme.fg; font { family: theme.fontDisplay; pixelSize: 18; weight: Font.DemiBold }
                        }
                        Text {
                            text: parent.e ? parent.k[0] : (app.activePane ? app.activePane.count + " položiek" : "")
                            color: theme.primary; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold }
                        }
                        Repeater {
                            model: parent.e ? [
                                ["Veľkosť", parent.e.isDir ? "—" : app.human(parent.e.size)],
                                ["Upravené", Qt.formatDateTime(parent.e.modified, "d. M. yyyy HH:mm")],
                                ["Cesta", parent.e.path]
                            ] : []
                            Column {
                                required property var modelData
                                width: parent.width; spacing: 1
                                Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                                Text { width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                            }
                        }
                        Item { width: 1; height: 6 }
                        component Action: Rectangle {
                            id: act
                            property string glyph; property string label; property bool danger: false
                            signal clicked()
                            width: parent.width; height: 36; radius: 10
                            color: am.containsMouse ? (danger ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2) : theme.hover) : theme.field
                            Row {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                Glyph { name: act.glyph; size: 16; color: act.danger ? theme.error : theme.fg }
                                Text { text: act.label; color: act.danger ? theme.error : theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                            }
                            MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; onClicked: act.clicked() }
                        }
                        Action { visible: !!parent.e; glyph: "external-link"; label: parent.e && parent.e.isDir ? "Otvoriť priečinok" : "Otvoriť"; onClicked: app.activePane.openCurrent() }
                        Action { visible: !!parent.e; glyph: "clipboard"; label: "Kopírovať cestu"; onClicked: app.run(["wl-copy", "--", app.sel.path], "Cesta skopírovaná") }
                        Action { visible: !!parent.e && app.dual; glyph: "copy"; label: "Kopírovať do druhého (F5)"; onClicked: app.openOp(false) }
                        Action { visible: !!parent.e && app.dual; glyph: "arrows-exchange"; label: "Presunúť do druhého (F6)"; onClicked: app.openOp(true) }
                        Action {
                            visible: !!parent.e; danger: true; glyph: "trash"
                            label: app.confirm === "trash" ? "Naozaj do koša?" : "Do koša (Delete)"
                            onClicked: app.askDelete(false)
                        }
                    }
                }
            }

            Rectangle {
                id: statusBar
                anchors { left: side.right; right: parent.right; bottom: parent.bottom }
                height: 30; color: "transparent"
                Rectangle { width: parent.width; height: 1; color: theme.line }
                Rectangle {   // priebeh úlohy z radu (F5/F6)
                    visible: !!app.job
                    anchors { left: parent.left; bottom: parent.bottom }
                    width: parent.width * app.jobPct / 100; height: 3; color: app.jobPaused ? theme.fgDim : theme.primary
                }
                Rectangle {   // priebeh kopírovania
                    visible: app.copyPct >= 0
                    anchors { left: parent.left; bottom: parent.bottom }
                    width: parent.width * Math.max(0, app.copyPct) / 100; height: 3; color: theme.primary
                }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - (app.commander ? fkeys.width + 10 : 470); elide: Text.ElideRight
                    text: (app.activePane ? (app.activePane.markedCount ? "označené " + app.activePane.markedCount + (app.activePane.markedBytes ? " · " + app.human(app.activePane.markedBytes) : "") + " z " + app.activePane.count : app.activePane.count + " položiek") : "")
                          + (app.quick !== "" ? "   ·   hľadám: " + app.quick : "")
                          + (app.job ? "   ·   " + (app.jobPaused ? "⏸ " : "") + app.jobPct + " % " + (app.jobFile || app.job.label) : "")
                          + (app.jobs.filter(j => j.state === "čaká").length ? "   ·   v rade " + app.jobs.filter(j => j.state === "čaká").length : "")
                          + (app.copyPct >= 0 ? "   ·   " + app.copyPct + " % · " + app.copyLabel : (app.status !== "" && !app.job ? "   ·   " + app.status : ""))
                    MouseArea { anchors.fill: parent; enabled: app.jobs.length > 0; onClicked: app.jobsOpen = !app.jobsOpen }
                    color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                }
                Text {
                    visible: !app.commander
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Pravý klik: ponuka · pravé ťahanie: Kopírovať / Presunúť sem · F2 premenovať · Del do Koša · Ctrl+Z späť · Medzerník náhľad"
                    color: theme.fgDim; opacity: 0.8; font { family: theme.fontUi; pixelSize: 11 }
                }
                // Total Commander: lišta F-kláves (klik = to isté ako kláves)
                Row {
                    id: fkeys
                    visible: app.commander
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [["F3", "Zobraziť"], ["F4", "Upraviť"], ["F5", "Kopírovať"], ["F6", "Presunúť"], ["F7", "Priečinok"], ["F8", "Zmazať"], ["F9", "Server"]]
                        Rectangle {
                            required property var modelData
                            width: fkt.implicitWidth + 16; height: 24; radius: 6; color: fkm.containsMouse ? theme.hover : theme.field
                            Text { id: fkt; anchors.centerIn: parent; text: modelData[0] + " " + modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                            MouseArea {
                                id: fkm; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    const k = modelData[0], p = app.activePane;
                                    if (k === "F3") { if (app.sel) { if (app.sel.isDir) p.openCurrent(); else app.openPath(app.sel.path); } }
                                    else if (k === "F4") { if (app.sel && !app.sel.isDir) app.run(["latte-otvor", "spusti", "latteos-heidelberg", app.sel.path], "Upraviť: " + app.sel.name); }
                                    else if (k === "F5") app.openOp(false);
                                    else if (k === "F6") app.openOp(true);
                                    else if (k === "F7") app.askInput("Nový priečinok (F7)", "", "aj vnorené: a/b/c", (t) => app.run(["mkdir", "-p", "--", p.path + "/" + t], "Nový priečinok: " + t));
                                    else if (k === "F8") app.askDelete(false);
                                    else if (k === "F9") { app.connectError = ""; app.connectOpen = true; }
                                    root.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // výsledky hľadania všade — prekryjú panely, klik otvorí priečinok s nájdenou položkou
            Rectangle {
                visible: app.found.length > 0 || app.finding
                anchors { left: side.right; top: header.bottom; bottom: statusBar.top; right: parent.right; margins: 10; rightMargin: 300 }
                radius: 10; color: theme.surface; border { color: theme.primary; width: 1 }
                Row {
                    id: fhead; x: 14; y: 10; spacing: 10
                    Glyph { name: "search"; size: 16; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: app.finding ? "Hľadám…" : "Nájdené „" + app.foundQuery + "“ · " + app.found.length; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                }
                IconButton { anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 6 } theme: theme; glyph: "x"; tip: "Zavrieť výsledky"; onClicked: app.found = [] }
                ListView {
                    id: rolovanie1
                    ScrollHint { flick: rolovanie1; colors: theme }
                    anchors { left: parent.left; right: parent.right; top: fhead.bottom; bottom: parent.bottom; margins: 8; topMargin: 10 }
                    clip: true; model: app.found; boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: fr
                        required property var modelData
                        width: ListView.view.width; height: 40; radius: 8; color: frm.containsMouse ? theme.hover : "transparent"
                        readonly property string name: modelData.path.split("/").pop()
                        readonly property string dir: modelData.path.substring(0, modelData.path.lastIndexOf("/"))
                        Glyph { x: 10; anchors.verticalCenter: parent.verticalCenter; name: fr.modelData.dir ? "folder" : "file"; size: 17; color: fr.modelData.dir ? theme.primary : theme.fgDim }
                        Column {
                            x: 36; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: fr.name; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: fr.dir.replace(app.home, "~"); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                        }
                        MouseArea {
                            id: frm; anchors.fill: parent; hoverEnabled: true
                            onClicked: { app.activePane.filter = ""; header.searchText = ""; app.activePane.go(fr.modelData.dir ? fr.modelData.path : fr.dir); app.found = []; }
                            onDoubleClicked: if (!fr.modelData.dir) app.openPath(fr.modelData.path)
                        }
                    }
                }
            }

            // pripojenie servera (FTP/SFTP): adresa + voliteľné heslo (ide iba do latte-siet cez stdin)
            Rectangle {
                visible: app.connectOpen
                anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35)
                MouseArea { anchors.fill: parent; onClicked: app.connectOpen = false }
                Rectangle {
                    anchors.centerIn: parent; width: 520; height: dlg.implicitHeight + 40; radius: 16
                    color: theme.surface; border { color: theme.outline; width: 1 }
                    MouseArea { anchors.fill: parent }
                    Column {
                        id: dlg; x: 20; y: 20; width: parent.width - 40; spacing: 12
                        Text { text: "Pripojiť server"; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                               text: "Server sa otvorí ako priečinok v ~/Siet (v bočnej lište pod Sieť). SMB = zdieľané priečinky Windows a NAS, WebDAV = Nextcloud a iné cloudy (davs = https). SFTP bez hesla použije tvoje SSH kľúče. Heslo sa nikam neukladá." }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10; color: theme.field; border { color: urlIn.activeFocus ? theme.primary : "transparent"; width: 1 }
                            TextInput { id: urlIn; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                                        color: theme.fg; font { family: theme.fontMono; pixelSize: 13 }
                                        KeyNavigation.tab: pwIn
                                        onAccepted: app.connectServer(urlIn.text, pwIn.text) }
                            Text { x: 12; anchors.verticalCenter: parent.verticalCenter; visible: urlIn.text === ""; text: "smb://meno@pc/zdieľanie  ·  sftp://meno@server  ·  davs://cloud/dav"; color: theme.fgDim; font { family: theme.fontMono; pixelSize: 13 } }
                        }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10; color: theme.field; border { color: pwIn.activeFocus ? theme.primary : "transparent"; width: 1 }
                            TextInput { id: pwIn; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password; passwordCharacter: "•"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                                        onAccepted: app.connectServer(urlIn.text, pwIn.text) }
                            Text { x: 12; anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text === ""; text: "Heslo (ak treba)"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                        }
                        Text { visible: app.connectError !== ""; width: parent.width; wrapMode: Text.WordWrap; text: app.connectError; color: theme.error; font { family: theme.fontUi; pixelSize: 12 } }
                        Row {
                            spacing: 10
                            Rectangle {
                                width: cbt.implicitWidth + 28; height: 38; radius: 10; color: app.connecting ? theme.field : theme.primary
                                Text { id: cbt; anchors.centerIn: parent; text: app.connecting ? "Pripájam…" : "Pripojiť"; color: app.connecting ? theme.fg : theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                MouseArea { anchors.fill: parent; enabled: !app.connecting; onClicked: app.connectServer(urlIn.text, pwIn.text) }
                            }
                            Rectangle {
                                width: zbt.implicitWidth + 28; height: 38; radius: 10; color: zm.containsMouse ? theme.hover : theme.field
                                Text { id: zbt; anchors.centerIn: parent; text: "Zrušiť"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                MouseArea { id: zm; anchors.fill: parent; hoverEnabled: true; onClicked: app.connectOpen = false }
                            }
                        }
                    }
                }
                onVisibleChanged: if (visible) { pwIn.text = ""; urlIn.forceActiveFocus(); } else root.forceActiveFocus()
            }

            // ═══ dialógy Total Commandera ═══════════════════════════════════════════════
            component Dlg: Rectangle {
                id: dlgRoot
                default property alias content: box.data
                property string title
                property real boxW: 560
                signal dismissed()
                anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4); z: 60
                MouseArea { anchors.fill: parent; onClicked: dlgRoot.dismissed() }
                Rectangle {
                    anchors.centerIn: parent; width: dlgRoot.boxW; height: box.implicitHeight + 64; radius: 16
                    color: theme.surface; border { color: theme.outline; width: 1 }
                    MouseArea { anchors.fill: parent }
                    Text { x: 20; y: 16; text: dlgRoot.title; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 18; weight: Font.DemiBold } }
                    Column { id: box; x: 20; y: 50; width: parent.width - 40; spacing: 10 }
                }
            }
            component Field: Rectangle {
                id: fld
                property alias text: fin.text
                property alias input: fin
                signal accepted()
                width: parent.width; height: 38; radius: 10; color: theme.field; border { color: fin.activeFocus ? theme.primary : "transparent"; width: 1 }
                TextInput { id: fin; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter; clip: true
                            color: theme.fg; selectByMouse: true; font { family: theme.fontMono; pixelSize: 13 }
                            // Enter spracovať tu a zastaviť, inak by prebublal do okna (otvoril by položku pod kurzorom)
                            Keys.onReturnPressed: (ev) => { ev.accepted = true; fld.accepted(); }
                            Keys.onEnterPressed: (ev) => { ev.accepted = true; fld.accepted(); } }
            }
            component Btn: Rectangle {
                id: bt
                property string label; property bool primary: false; property bool on: false
                signal clicked()
                width: btl.implicitWidth + 26; height: 34; radius: 10
                color: primary ? theme.primary : (on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2) : (btm.containsMouse ? theme.hover : theme.field))
                border { color: on ? theme.primary : "transparent"; width: 1 }
                Text { id: btl; anchors.centerIn: parent; text: bt.label; color: bt.primary ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                MouseArea { id: btm; anchors.fill: parent; hoverEnabled: true; onClicked: bt.clicked() }
            }
            component Note: Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }

            // vstupné pole (F7, Shift+F4, maska, premenovanie)
            Dlg {
                visible: !!app.ask
                title: app.ask ? app.ask.title : ""
                onDismissed: { app.ask = null; root.forceActiveFocus(); }
                Field { id: askIn; onAccepted: { const a = app.ask; app.ask = null; if (a && askIn.text.trim() !== "") a.action(askIn.text.trim()); root.forceActiveFocus(); }
                        input.Keys.onEscapePressed: { app.ask = null; root.forceActiveFocus(); } }
                Note { visible: !!app.ask && app.ask.hint !== ""; text: app.ask ? app.ask.hint : "" }
                Row { spacing: 8
                      Btn { label: "OK (Enter)"; primary: true; onClicked: askIn.accepted() }
                      Btn { label: "Zrušiť (Esc)"; onClicked: { app.ask = null; root.forceActiveFocus(); } } }
                onVisibleChanged: if (visible) { askIn.text = app.ask.text; askIn.input.selectAll(); askIn.input.forceActiveFocus(); }
            }

            // F5 kopírovať / F6 presunúť
            Dlg {
                id: opDlg
                visible: !!app.op
                boxW: 640
                title: app.op ? (app.op.move ? "Presunúť / premenovať (F6)" : "Kopírovať (F5)") + " · " + (app.op.items.length === 1 ? app.op.items[0].name : app.op.items.length + " položiek") : ""
                onDismissed: { app.op = null; root.forceActiveFocus(); }
                Note { text: app.op ? (app.op.items.length === 1 ? app.op.items[0].path : app.op.items.slice(0, 4).map(e => e.name).join(", ") + (app.op.items.length > 4 ? " … +" + (app.op.items.length - 4) : "")) : "" }
                Text { text: "CIEĽ"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                Field { id: opTarget; onAccepted: { app.op.target = opTarget.text; app.op.mask = opMask.text; app.startOp(false); root.forceActiveFocus(); }
                        input.Keys.onEscapePressed: { app.op = null; root.forceActiveFocus(); }
                        input.Keys.onPressed: (ev) => { if (ev.key === Qt.Key_F2) { app.op.target = opTarget.text; app.op.mask = opMask.text; app.startOp(true); root.forceActiveFocus(); ev.accepted = true; } } }
                Row { spacing: 10; width: parent.width
                      Text { anchors.verticalCenter: parent.verticalCenter; text: "Iba súbory:"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                      Field { id: opMask; width: 180; onAccepted: opTarget.accepted() } }
                Text { text: "AK UŽ SÚBOR V CIELI EXISTUJE"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                Flow { width: parent.width; spacing: 6
                    Repeater { model: [["ask", "Opýtať sa"], ["prepisat", "Prepísať"], ["preskocit", "Preskočiť"], ["starsie", "Prepísať staršie"], ["premenovat", "Premenovať kópiu"]]
                        Btn { required property var modelData; label: modelData[1]; on: !!app.op && app.op.mode === modelData[0]
                              onClicked: { const o = app.op; o.mode = modelData[0]; app.op = Object.assign({}, o); } } } }
                Row { spacing: 8
                      Btn { label: (app.op && app.op.verify ? "☑" : "☐") + " Overiť po skopírovaní (SHA-256)"; onClicked: { const o = app.op; o.verify = !o.verify; app.op = Object.assign({}, o); } } }
                Text { text: "OBMEDZIŤ RÝCHLOSŤ"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                Flow { width: parent.width; spacing: 6
                    Repeater { model: [[0, "Bez obmedzenia"], [5, "5 MB/s"], [20, "20 MB/s"], [50, "50 MB/s"], [100, "100 MB/s"]]
                        Btn { required property var modelData; label: modelData[1]; on: !!app.op && (app.op.limit || 0) === modelData[0]
                              onClicked: { const o = app.op; o.limit = modelData[0]; app.op = Object.assign({}, o); } } } }
                Row { spacing: 8
                      Btn { label: "OK (Enter)"; primary: true; onClicked: opTarget.accepted() }
                      Btn { label: "Do radu (F2)"; onClicked: { app.op.target = opTarget.text; app.op.mask = opMask.text; app.startOp(true); root.forceActiveFocus(); } }
                      Btn { label: "Zrušiť (Esc)"; onClicked: { app.op = null; root.forceActiveFocus(); } } }
                onVisibleChanged: if (visible) { opTarget.text = app.op.target; opMask.text = app.op.mask; opTarget.input.forceActiveFocus(); opTarget.input.selectAll(); }
            }

            // kolízie mien v cieli
            Dlg {
                visible: !!app.conflict
                title: app.conflict ? "V cieli už existuje " + app.conflict.names.length + (app.conflict.names.length === 1 ? " položka" : " položiek") : ""
                onDismissed: app.resolveConflict("")
                Note { text: app.conflict ? app.conflict.names.slice(0, 8).join(", ") + (app.conflict.names.length > 8 ? " …" : "") : "" }
                Flow { width: parent.width; spacing: 6
                       Btn { label: "Prepísať všetky"; primary: true; onClicked: app.resolveConflict("prepisat") }
                       Btn { label: "Preskočiť existujúce"; onClicked: app.resolveConflict("preskocit") }
                       Btn { label: "Prepísať iba staršie"; onClicked: app.resolveConflict("starsie") }
                       Btn { label: "Premenovať kópie"; onClicked: app.resolveConflict("premenovat") }
                       Btn { label: "Zrušiť"; onClicked: app.resolveConflict("") } }
            }

            // mazanie
            Dlg {
                visible: !!app.delAsk
                title: app.delAsk ? (app.delAsk.permanent ? "Odstrániť natrvalo?" : "Presunúť do koša?") : ""
                onDismissed: { app.delAsk = null; root.forceActiveFocus(); }
                Note { text: app.delAsk ? (app.delAsk.items.length === 1 ? app.delAsk.items[0].path : app.delAsk.items.length + " položiek: " + app.delAsk.items.slice(0, 6).map(e => e.name).join(", ") + (app.delAsk.items.length > 6 ? " …" : "")) : "" }
                Note { visible: !!app.delAsk && app.delAsk.permanent; text: "Natrvalo = bez koša, nedá sa vrátiť."; color: theme.error }
                Row { spacing: 8
                      Btn { id: delOk; label: app.delAsk && app.delAsk.permanent ? "Odstrániť natrvalo" : "Do koša"; primary: true; onClicked: { app.doDelete(); root.forceActiveFocus(); } }
                      Btn { label: "Zrušiť"; onClicked: { app.delAsk = null; root.forceActiveFocus(); } } }
                Item { focus: parent.visible; Keys.onReturnPressed: { app.doDelete(); root.forceActiveFocus(); } Keys.onEscapePressed: { app.delAsk = null; root.forceActiveFocus(); } }
            }

            // rad úloh (klik na stavový riadok)
            Rectangle {
                visible: app.jobsOpen && app.jobs.length > 0
                anchors { right: parent.right; bottom: statusBar.top; margins: 10 }
                width: 460; height: Math.min(360, jcol.implicitHeight + 24); radius: 14; z: 50
                color: theme.surface; border { color: theme.outline; width: 1 }
                Column {
                    id: jcol; x: 12; y: 12; width: parent.width - 24; spacing: 6
                    Row { width: parent.width; spacing: 6
                          Text { width: parent.width - 250; text: "Úlohy kopírovania"; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                          Btn { visible: !!app.job; label: app.jobPaused ? "▶ Pokračovať" : "⏸ Pauza"; onClicked: app.pauseJob() }
                          Btn { visible: !!app.job; label: "Zrušiť"; onClicked: app.cancelJob() }
                          Btn { label: "Vyčistiť"; onClicked: app.clearDone() } }
                    Repeater {
                        model: app.jobs.slice().reverse().slice(0, 10)
                        Row { required property var modelData; spacing: 8; width: jcol.width
                              Text { width: 70; text: modelData.state === "beží" ? app.jobPct + " %" : modelData.state; color: modelData.state === "chyba" ? theme.error : (modelData.state === "hotovo" ? theme.primary : theme.fgDim)
                                     font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                              Text { width: jcol.width - 80; elide: Text.ElideMiddle; text: (modelData.move ? "presun · " : "kópia · ") + modelData.label + (modelData.msg ? " · " + modelData.msg : "")
                                     color: theme.fg; font { family: theme.fontUi; pixelSize: 11 } } }
                    }
                }
            }

            TcDialogy {
                id: tcd
                theme: theme
                onDone: (m) => { app.status = m; refreshBoth.restart(); }
                onGoTo: (d, n) => { app.activePane.selectAfter = n; app.activePane.go(d); }
                onFeed: (l) => { app.found = l; app.foundQuery = "hľadanie Alt+F7"; }
                onVisibleChanged: if (!visible) root.forceActiveFocus()
            }

            // bočné tlačidlá myši Späť / Dopredu (ako v Prieskumníkovi); iné tlačidlá prejdú k položkám pod ním
            MouseArea {
                anchors.fill: parent; z: 900
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                onPressed: (m) => { if (m.button === Qt.BackButton) app.activePane.back(); else app.activePane.forward(); }
            }
            ContextMenu { id: ctx; theme: theme; onVisibleChanged: if (!visible) root.forceActiveFocus() }   // klávesy (Ctrl+Z, Del…) hneď po ponuke
        }
    }
}
