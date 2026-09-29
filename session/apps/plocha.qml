// LatteOS — plocha s ikonami (zadanie 24. 9., bod 7; 25. 9.: ako vo Windows/Linuxe).
//   Kôš je vždy prvý, pod ním súbory a priečinky z ~/Plocha v mriežke (stĺpce zhora nadol).
//   Myš: klik vyberie, Ctrl+klik pridá, ťahanie po prázdnom mieste = výber obdĺžnikom, dvojklik otvorí,
//        ťahanie ikony ju presunie (poloha sa pamätá), pustenie na priečinok = presun doň, na Kôš = do koša.
//   Klávesy (po kliknutí na plochu): Enter otvorí, F2 premenuje, Del do koša, Ctrl+A všetko, F5 obnoví, Esc zruší výber.
//   Pravý klik na prázdne miesto: Zobraziť › (veľkosť ikon, automaticky usporiadať, zarovnať do mriežky),
//   Zoradiť podľa › (názov, veľkosť, typ, dátum úpravy; vzostupne/zostupne), Obnoviť, Prilepiť, Nový ›, …
//   Pravý klik na ikonu: Otvoriť, Otvoriť v…, Vystrihnúť, Kopírovať, Kopírovať cestu, Premenovať, Do koša, Vlastnosti.
//   Súbor pretiahnutý z inej aplikácie sa skopíruje do ~/Plocha. Nastavenia: ~/.config/latteos/plocha.json.
//   Vrstva Bottom: nad tapetou, pod oknami. Vypnutie: Nastavenia › Pozadie (desktop-icons = off).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "common"

ShellRoot {
    id: pl
    LatteTheme { id: theme }

    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos"
    property string desk: home + "/Plocha"
    readonly property string trashDir: home + "/.local/share/Trash/files"
    property int trashCount: 0
    property var sel: ({})                   // cesta → true
    readonly property int selCount: Object.keys(sel).length
    property string renaming: ""             // cesta ikony, ktorá sa práve premenúva

    // ── nastavenia plochy (ako Zobraziť / Zoradiť podľa vo Windows) ──
    property var prefs: ({ size: "stredne", auto: false, grid: true, sort: "nazov", desc: false, pos: {} })
    FileView {
        id: prefsFile
        path: pl.cfg + "/plocha.json"; printErrors: false
        onLoaded: { try { pl.prefs = Object.assign({}, pl.prefs, JSON.parse(text())); } catch (e) {} }
    }
    function setPref(k, v) { const p = Object.assign({}, prefs); p[k] = v; prefs = p; savePrefs.restart(); }
    Timer { id: savePrefs; interval: 400; onTriggered: { mkCfg.running = true; prefsFile.setText(JSON.stringify(pl.prefs)); } }
    Process { id: mkCfg; command: ["mkdir", "-p", pl.cfg] }
    readonly property var sizes: ({ male: [88, 78, 36], stredne: [110, 96, 52], velke: [140, 124, 72] })   // bunka š × v, dlaždica
    readonly property int cellW: (sizes[prefs.size] || sizes.stredne)[0] + 6
    readonly property int cellH: (sizes[prefs.size] || sizes.stredne)[1] + 6
    readonly property int tileSz: (sizes[prefs.size] || sizes.stredne)[2]

    FileView { path: pl.cfg + "/desktop-icons"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: if (text().trim() === "off") Qt.quit() }
    Process {
        running: true; command: ["sh", "-c", "xdg-user-dir DESKTOP 2>/dev/null || echo \"$HOME/Plocha\""]
        stdout: StdioCollector { onStreamFinished: { const d = this.text.trim(); if (d !== "" && d !== pl.home) pl.desk = d; mk.running = true; } }
    }
    Process { id: mk; command: ["mkdir", "-p", pl.desk, pl.trashDir, pl.home + "/.local/share/Trash/info"] }
    Process {
        id: trashProc
        command: ["sh", "-c", "ls -A \"$1\" 2>/dev/null | wc -l", "sh", pl.trashDir]
        stdout: StdioCollector { onStreamFinished: pl.trashCount = parseInt(this.text) || 0 }
    }
    // počet vecí v Koši sleduje FolderListModel (inotify) — predtým každé 4 s sh + ls + wc (optimalizácia 26. 9.)
    FolderListModel { id: trashModel; folder: "file://" + pl.trashDir; showDirs: true; showHidden: true; showDotAndDotDot: false
                      onCountChanged: pl.trashCount = count; onStatusChanged: if (status === FolderListModel.Ready) pl.trashCount = count }
    Component.onCompleted: trashProc.running = true
    Process { id: run; onExited: files.refresh() }
    function sh(cmd, args) { run.command = ["sh", "-c", cmd, "sh"].concat(args || []); run.running = true; }
    function open(p) { sh(p === pl.trashDir ? 'latte-app subory "$1" >/dev/null 2>&1 &' : (p.endsWith(".desktop") ? 'gio launch "$1" >/dev/null 2>&1 &' : 'xdg-open "$1" >/dev/null 2>&1 &'), [p]); }
    function selected() { return Object.keys(sel).filter(p => p !== trashDir); }

    // ── súbory a ich poradie ──
    FolderListModel {
        id: files
        folder: "file://" + pl.desk
        showDirsFirst: true; showDotAndDotDot: false; showHidden: false
        sortField: ({ nazov: FolderListModel.Name, velkost: FolderListModel.Size, typ: FolderListModel.Type, datum: FolderListModel.Time })[pl.prefs.sort] || FolderListModel.Name
        sortReversed: pl.prefs.desc
        // FolderListModel nemá refresh(); zmena priečinka a späť ho načíta znova
        function refresh() { const f = folder; folder = ""; folder = f; }
    }
    // poradie ikon: Kôš + súbory; pri „Automaticky usporiadať“ podľa triedenia, inak uložené bunky a voľné miesta
    readonly property int rows: Math.max(1, Math.floor((win.height - 24) / cellH))
    readonly property int cols: Math.max(1, Math.floor((win.width - 24) / cellW))
    property var layout: ({})                // cesta → [stĺpec, riadok]
    function relayout() {
        const used = {}, out = {}, list = [trashDir];
        for (let i = 0; i < files.count; i++) list.push(files.get(i, "filePath"));
        const free = () => { for (let c = 0; ; c++) for (let r = 0; r < rows; r++) if (!used[c + ":" + r]) return [c, r]; };
        if (!prefs.auto) for (const p of list) {
            const s = prefs.pos[posKey(p)] || (p === trashDir ? [0, 0] : null);
            if (s && s[1] < rows && !used[s[0] + ":" + s[1]]) { out[p] = s; used[s[0] + ":" + s[1]] = true; }
        }
        for (const p of list) if (!out[p]) { const c = free(); out[p] = c; used[c[0] + ":" + c[1]] = true; }
        layout = out;
    }
    Connections { target: files; function onCountChanged() { relayoutT.restart(); } }
    onRowsChanged: relayoutT.restart()
    onPrefsChanged: relayoutT.restart()
    Timer { id: relayoutT; interval: 30; onTriggered: pl.relayout() }

    // presun ikon myšou: nové bunky (pri skupine všetky o rovnaký posun), mimo mriežky sa nepúšťa
    function moveIcons(paths, dc, dr) {
        const pos = Object.assign({}, prefs.pos), taken = {};
        for (const p in layout) if (paths.indexOf(p) < 0) taken[layout[p][0] + ":" + layout[p][1]] = true;
        for (const p of paths) {
            const l = layout[p]; if (!l) continue;
            let c = Math.max(0, l[0] + dc), r = Math.max(0, Math.min(rows - 1, l[1] + dr));
            while (taken[c + ":" + r]) { r++; if (r >= rows) { r = 0; c++; } }
            taken[c + ":" + r] = true;
            pos[posKey(p)] = [c, r];
        }
        const p2 = Object.assign({}, prefs); p2.pos = pos; p2.auto = false; prefs = p2; savePrefs.restart();
    }
    function posKey(p) { return p === trashDir ? "::kos" : p.split("/").pop(); }
    function iconAt(x, y) {
        const c = Math.floor((x - 12) / cellW), r = Math.floor((y - 12) / cellH);
        for (const p in layout) if (layout[p][0] === c && layout[p][1] === r) return p;
        return "";
    }

    // ── ponuky ──
    function desktopMenu(x, y) {
        const s = prefs;
        const pick = (k, v, label) => ({ label: label, checked: s[k] === v, action: () => pl.setPref(k, v) });
        ctx.open(x, y, [
            { glyph: "layout-grid", label: "Zobraziť", sub: [
                pick("size", "velke", "Veľké ikony"), pick("size", "stredne", "Stredné ikony"), pick("size", "male", "Malé ikony"),
                { separator: true },
                { label: "Automaticky usporiadať ikony", checked: s.auto, action: () => pl.setPref("auto", !s.auto) },
                { separator: true },
                { label: "Skryť ikony na ploche", glyph: "eye-off", action: () => pl.sh('mkdir -p "$1" && printf off > "$1/desktop-icons"', [pl.cfg]) } ] },
            { glyph: "arrows-exchange", label: "Zoradiť podľa", sub: [
                { label: "Názov", checked: s.sort === "nazov", action: () => pl.sortBy("nazov") },
                { label: "Veľkosť", checked: s.sort === "velkost", action: () => pl.sortBy("velkost") },
                { label: "Typ", checked: s.sort === "typ", action: () => pl.sortBy("typ") },
                { label: "Dátum úpravy", checked: s.sort === "datum", action: () => pl.sortBy("datum") },
                { separator: true },
                { label: "Vzostupne", checked: !s.desc, action: () => pl.setPref("desc", false) },
                { label: "Zostupne", checked: s.desc, action: () => pl.setPref("desc", true) } ] },
            { glyph: "refresh", label: "Obnoviť", hint: "F5", action: () => { files.refresh(); trashProc.running = true; } },
            { separator: true },
            { glyph: "clipboard", label: "Prilepiť", hint: "Ctrl+V", action: () => pl.paste() },
            { glyph: "plus", label: "Nový", sub: [
                { glyph: "folder-plus", label: "Priečinok", action: () => pl.newItem("Nový priečinok", "", true) },
                { glyph: "file-text", label: "Textový súbor", action: () => pl.newItem("Nový textový súbor", ".txt", false) },
                { glyph: "pencil", label: "Dokument Heidelberg", action: () => pl.newItem("Nový dokument", ".md", false) },
                { glyph: "file", label: "Prázdny súbor", action: () => pl.newItem("Nový súbor", "", false) } ] },
            { separator: true },
            { glyph: "folder", label: "Otvoriť Plochu v Súboroch", action: () => pl.sh('latte-app subory "$1" >/dev/null 2>&1 &', [pl.desk]) },
            { glyph: "terminal-2", label: "Otvoriť v termináli", action: () => pl.sh('cd "$1" && setsid foot >/dev/null 2>&1 &', [pl.desk]) },
            { separator: true },
            { glyph: "device-desktop", label: "Nastavenia obrazovky", action: () => pl.sh('latte-app zariadenia obrazovky >/dev/null 2>&1 &') },
            { glyph: "photo", label: "Prispôsobiť pozadie…", action: () => pl.sh('latte-app nastavenia pozadie >/dev/null 2>&1 &') },
            { glyph: "palette", label: "Prispôsobiť (motív, pozadie)", action: () => pl.sh('latte-app nastavenia pozadie >/dev/null 2>&1 &') }
        ]);
    }
    function sortBy(k) { const p = Object.assign({}, prefs); p.sort = k; p.pos = {}; prefs = p; savePrefs.restart(); }   // ako vo Windows: zoradenie preusporiada
    function newItem(base, ext, dir) {
        sh('d="$1"; b="$2"; e="$3"; n="$b$e"; i=2; while [ -e "$d/$n" ]; do n="$b $i$e"; i=$((i+1)); done; '
           + (dir ? 'mkdir -- "$d/$n"' : ': > "$d/$n"') + '; printf "%s" "$d/$n" > "$4"', [desk, base, ext, renameFile]);
        renameAfter.restart();
    }
    // po vytvorení hneď premenovať (ako vo Windows)
    readonly property string renameFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latte-plocha-nove"
    Timer { id: renameAfter; interval: 500; onTriggered: newName.reload() }
    FileView { id: newName; path: pl.renameFile; printErrors: false; onLoaded: { const p = text().trim(); if (p) { pl.sel = {}; const s = {}; s[p] = true; pl.sel = s; pl.renaming = p; } } }

    function itemMenu(path, isDir, x, y) {
        if (!sel[path]) { const s = {}; s[path] = true; sel = s; }
        if (path === trashDir) {
            ctx.open(x, y, [{ glyph: "external-link", label: "Otvoriť", action: () => pl.open(pl.trashDir) },
                            { glyph: "trash", label: "Vysypať kôš (" + trashCount + ")", danger: true, enabled: trashCount > 0, action: () => { pl.sh("latte-kos vysypat"); trashProc.running = true; } }]);
            return;
        }
        const many = selected().length > 1;
        const items = [{ glyph: "external-link", label: many ? "Otvoriť (" + selected().length + ")" : "Otvoriť", hint: "Enter", action: () => { for (const p of pl.selected()) pl.open(p); } }];
        if (!isDir && !many) items.push({ glyph: "apps", label: "Otvoriť v…", keepOpen: true, action: () => { withProc.path = path; withProc.command = ["latte-otvor", "aplikacie", path]; withProc.running = true; } });
        items.push({ separator: true });
        items.push({ glyph: "arrows-exchange", label: "Vystrihnúť", hint: "Ctrl+X", action: () => pl.clip(true) });
        items.push({ glyph: "copy", label: "Kopírovať", hint: "Ctrl+C", action: () => pl.clip(false) });
        items.push({ glyph: "clipboard", label: "Kopírovať cestu", action: () => pl.sh('wl-copy -- "$1"', [path]) });
        items.push({ separator: true });
        if (!many) items.push({ glyph: "pencil", label: "Premenovať", hint: "F2", action: () => pl.renaming = path });
        items.push({ glyph: "trash", label: "Do koša", hint: "Del", danger: true, action: () => pl.toTrash() });
        items.push({ separator: true });
        items.push({ glyph: "folder", label: "Ukázať v Súboroch", action: () => pl.sh('latte-app subory "$1" >/dev/null 2>&1 &', [pl.desk]) });
        if (!many) items.push({ glyph: "info-circle", label: "Vlastnosti", hint: "Alt+Enter", action: () => pl.showProps(path) });
        ctx.open(x, y, items, many ? selected().length + " položiek" : path.split("/").pop());
    }
    Process {
        id: withProc
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.split("\n").filter(x => x !== "").slice(1).map(x => x.split("\t")).filter(a => a[0] !== "nainstalovat");
                const items = l.map(a => ({ glyph: a[0] === "predvolena" ? "star" : "apps", label: a[2], action: () => pl.sh('latte-otvor spusti "$1" "$2"', [a[1], withProc.path]) }));
                ctx.replace(items.length ? items : [{ glyph: "help", label: "Žiadna aplikácia", enabled: false, action: () => {} }], "Otvoriť v…");
            }
        }
    }
    function toTrash() { const l = selected(); if (!l.length) return; sh('latte-kos vyhod "$@"', l); sel = {}; trashProc.running = true; }
    // schránka súborov (rovnaký formát ako Súbory: x-special/gnome-copied-files)
    function clip(cut) {
        const l = selected(); if (!l.length) return;
        sh('m="$1"; shift; { echo "$m"; for f in "$@"; do printf "file://%s\\n" "$f"; done; } | wl-copy -t x-special/gnome-copied-files', [cut ? "cut" : "copy"].concat(l));
    }
    function paste() {
        sh('d="$1"; c=$(wl-paste -t x-special/gnome-copied-files 2>/dev/null) || c=$(wl-paste -t text/uri-list 2>/dev/null) || exit 0; '
           + 'm=$(printf "%s\\n" "$c" | head -1); printf "%s\\n" "$c" | grep "^file://" | sed "s|^file://||" | while read -r f; do '
           + 'f=$(printf "%b" "$(printf "%s" "$f" | sed "s/%/\\\\x/g")"); if [ "$m" = cut ]; then mv -n -- "$f" "$d/"; else cp -rn -- "$f" "$d/"; fi; done', [desk]);
    }
    function rename(path, name) {
        renaming = "";
        name = name.trim(); if (!name || name.indexOf("/") >= 0 || name === path.split("/").pop()) return;
        const old = path.split("/").pop(), pos = Object.assign({}, prefs.pos);
        if (pos[old]) { pos[name] = pos[old]; delete pos[old]; const p = Object.assign({}, prefs); p.pos = pos; prefs = p; savePrefs.restart(); }
        sh('[ -e "$2" ] && exit 1; mv -n -- "$1" "$2"', [path, desk + "/" + name]);
    }
    // vlastnosti (latte-tc vlastnosti)
    property var props: null
    Process { id: propsProc; stdout: StdioCollector { onStreamFinished: { try { pl.props = JSON.parse(this.text); } catch (e) { pl.props = null; } } } }
    function showProps(path) { propsProc.command = ["latte-tc", "vlastnosti", path]; propsProc.running = true; }
    function human(b) { const u = ["B", "KB", "MB", "GB", "TB"]; let v = b || 0, i = 0; while (v >= 1024 && i < 4) { v /= 1024; i++; } return v.toFixed(i ? 1 : 0).replace(".", ",") + " " + u[i]; }

    function glyphFor(name, isDir) {
        if (isDir) return "folder";
        const s = (name.split(".").pop() || "").toLowerCase();
        if (["jpg", "jpeg", "png", "webp", "gif", "svg"].includes(s)) return "photo";
        if (["mp3", "flac", "ogg", "wav"].includes(s)) return "music";
        if (["mp4", "mkv", "webm"].includes(s)) return "movie";
        if (["zip", "gz", "xz", "tar", "7z"].includes(s)) return "file-zip";
        if (["txt", "md", "odt", "docx", "pdf", "rtf"].includes(s)) return "file-text";
        if (s === "desktop") return "apps";
        return "file";
    }

    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal          // rešpektuje lištu (ikony sa nekreslia pod ňu)
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "latte-plocha"
        // klávesnica iba po kliknutí na plochu (F2, Del, Enter…); inak ju plocha neberie oknám
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onPressed: (ev) => {
                const ctrl = ev.modifiers & Qt.ControlModifier, alt = ev.modifiers & Qt.AltModifier;
                if (pl.renaming !== "") return;
                ev.accepted = true;
                const one = pl.selected().length === 1 ? pl.selected()[0] : "";
                if (ev.key === Qt.Key_F2 && one) pl.renaming = one;
                else if (ev.key === Qt.Key_Delete) pl.toTrash();
                else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && alt && one) pl.showProps(one);
                else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { for (const p of Object.keys(pl.sel)) pl.open(p); }
                else if (ev.key === Qt.Key_A && ctrl) { const s = {}; for (const p in pl.layout) if (p !== pl.trashDir) s[p] = true; pl.sel = s; }
                else if (ev.key === Qt.Key_C && ctrl) pl.clip(false);
                else if (ev.key === Qt.Key_X && ctrl) pl.clip(true);
                else if (ev.key === Qt.Key_V && ctrl) pl.paste();
                else if (ev.key === Qt.Key_F5) files.refresh();
                else if (ev.key === Qt.Key_Escape) { pl.sel = {}; pl.props = null; }
                else ev.accepted = false;
            }

            // prázdne miesto: pravý klik = ponuka plochy, ľavý zruší výber, ťahanie = výber obdĺžnikom
            MouseArea {
                id: bgMouse
                anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                property point start
                property bool band: false
                onPressed: (m) => { root.forceActiveFocus(); start = Qt.point(m.x, m.y); band = false;
                                    if (m.button === Qt.LeftButton && !(m.modifiers & Qt.ControlModifier)) pl.sel = {}; }
                onPositionChanged: (m) => {
                    if (!(m.buttons & Qt.LeftButton)) return;
                    band = Math.abs(m.x - start.x) + Math.abs(m.y - start.y) > 6;
                    if (!band) return;
                    const x0 = Math.min(start.x, m.x), x1 = Math.max(start.x, m.x), y0 = Math.min(start.y, m.y), y1 = Math.max(start.y, m.y);
                    rubber.x = x0; rubber.y = y0; rubber.width = x1 - x0; rubber.height = y1 - y0;
                    const s = {};
                    for (const p in pl.layout) { const l = pl.layout[p], ix = 12 + l[0] * pl.cellW, iy = 12 + l[1] * pl.cellH;
                        if (ix < x1 && ix + pl.cellW - 6 > x0 && iy < y1 && iy + pl.cellH - 6 > y0) s[p] = true; }
                    pl.sel = s;
                }
                onReleased: band = false
                onClicked: (m) => { if (m.button === Qt.RightButton) pl.desktopMenu(m.x, m.y); }
            }
            Rectangle {
                id: rubber
                visible: bgMouse.band
                color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18)
                border { color: theme.primary; width: 1 }
            }
            DropArea {
                anchors.fill: parent; keys: ["text/uri-list"]
                onDropped: (d) => pl.externalDrop(d, pl.desk)
            }

            component Icon: Item {
                id: ic
                property string path
                property string name
                property bool isDir: false
                property string glyph: "file"
                property string badge: ""
                property string iconSrc: ""
                readonly property bool selected: pl.sel[path] === true
                readonly property var cell: pl.layout[path] || [0, 0]
                property bool dragging: false
                property real dx: 0
                property real dy: 0
                // pri ťahaní skupiny sa hýbu všetky označené ikony naraz
                readonly property bool groupMove: pl.dragPath !== "" && selected && pl.dragPath !== path
                x: 12 + cell[0] * pl.cellW + (dragging ? dx : (groupMove ? pl.dragDx : 0))
                y: 12 + cell[1] * pl.cellH + (dragging ? dy : (groupMove ? pl.dragDy : 0))
                z: dragging || groupMove ? 10 : 0
                width: pl.cellW - 6; height: pl.cellH - 6
                Behavior on x { enabled: !ic.dragging && !ic.groupMove && theme.animMs > 0; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !ic.dragging && !ic.groupMove && theme.animMs > 0; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                opacity: dragging || groupMove ? 0.8 : 1
                Rectangle {
                    anchors.fill: parent; radius: 12
                    color: ic.selected ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.35)
                                       : (ima.containsMouse || pl.dropTarget === ic.path || dz.containsDrag ? Qt.rgba(1, 1, 1, 0.14) : "transparent")
                    border { color: pl.dropTarget === ic.path || dz.containsDrag ? theme.primary : "transparent"; width: 2 }
                }
                Rectangle {
                    id: tile
                    width: pl.tileSz; height: pl.tileSz; radius: pl.tileSz * 0.27
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                    color: Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.88)
                    border { color: Qt.rgba(theme.outline.r, theme.outline.g, theme.outline.b, 0.6); width: 1 }
                    Glyph { anchors.centerIn: parent; visible: appImg.status !== Image.Ready; name: ic.glyph; size: pl.tileSz * 0.54; color: ic.isDir || ic.glyph === "trash" ? theme.primary : theme.fg }
                    Image { id: appImg; anchors { fill: parent; margins: 6 } source: ic.iconSrc; sourceSize { width: 144; height: 144 } fillMode: Image.PreserveAspectFit; asynchronous: true }
                    Rectangle {
                        visible: ic.badge !== ""
                        anchors { right: parent.right; top: parent.top; rightMargin: -6; topMargin: -6 }
                        width: Math.max(20, bt.implicitWidth + 10); height: 20; radius: 10; color: theme.primary
                        Text { id: bt; anchors.centerIn: parent; text: ic.badge; color: theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                    }
                }
                Text {
                    visible: pl.renaming !== ic.path
                    anchors { top: tile.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                    width: parent.width - 8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                    text: ic.name; color: "white"; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.55)
                    font { family: theme.fontUi; pixelSize: pl.prefs.size === "male" ? 11 : 12; weight: Font.DemiBold }
                }
                // premenovanie priamo pod ikonou (F2): kurzor v poli, názov bez prípony označený, Enter/klik mimo uloží
                Rectangle {
                    visible: pl.renaming === ic.path
                    anchors { top: tile.bottom; topMargin: 3; horizontalCenter: parent.horizontalCenter }
                    width: parent.width + 20; height: 24; radius: 6; color: theme.surface; border { color: theme.primary; width: 1 }
                    z: 20
                    TextInput {
                        id: ren
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 } verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignHCenter
                        clip: true; color: theme.fg; selectionColor: theme.primary; selectByMouse: true
                        font { family: theme.fontUi; pixelSize: 12 }
                        onVisibleChanged: if (visible) { text = ic.path.split("/").pop(); Qt.callLater(() => { forceActiveFocus(); const dot = text.lastIndexOf("."); select(0, dot > 0 && !ic.isDir ? dot : text.length); }); }
                        Keys.onReturnPressed: (ev) => { ev.accepted = true; pl.rename(ic.path, text); root.forceActiveFocus(); }
                        Keys.onEnterPressed: (ev) => { ev.accepted = true; pl.rename(ic.path, text); root.forceActiveFocus(); }
                        Keys.onEscapePressed: (ev) => { ev.accepted = true; pl.renaming = ""; root.forceActiveFocus(); }
                        onActiveFocusChanged: if (!activeFocus && pl.renaming === ic.path) pl.rename(ic.path, text)
                    }
                }
                MouseArea {
                    id: ima; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    property point start
                    onPressed: (m) => {
                        root.forceActiveFocus(); start = mapToItem(root, m.x, m.y);    // v súradniciach plochy — ikona sa počas ťahania hýbe
                        pl.dragBtn = m.button; pl.justDragged = false;
                        if (ic.path !== pl.trashDir) winsProc.running = true;          // kde sú okná (ťahanie von do aplikácie)
                        if (m.button === Qt.LeftButton) {
                            if (m.modifiers & Qt.ControlModifier) { const s = Object.assign({}, pl.sel); if (s[ic.path]) delete s[ic.path]; else s[ic.path] = true; pl.sel = s; }
                            else if (!ic.selected) { const s = {}; s[ic.path] = true; pl.sel = s; }
                        }
                    }
                    onPositionChanged: (m) => {
                        if (!(m.buttons & (Qt.LeftButton | Qt.RightButton | Qt.MiddleButton))) return;
                        const q = mapToItem(root, m.x, m.y), ddx = q.x - start.x, ddy = q.y - start.y;
                        if (!ic.dragging && Math.abs(ddx) + Math.abs(ddy) < 8) return;
                        if (ic.path !== pl.trashDir && pl.overWindow(q.x, q.y)) {             // nad oknom: systémové ťahanie do aplikácie
                            const paths = pl.sel[ic.path] ? Object.keys(pl.sel).filter(p => p !== pl.trashDir) : [ic.path];
                            ic.dragging = false; ic.dx = 0; ic.dy = 0; pl.dragPath = ""; pl.dragDx = 0; pl.dragDy = 0; pl.dropTarget = "";
                            pl.winRects = []; pl.justDragged = true;
                            sysDrag.Drag.mimeData = { "text/uri-list": paths.map(p => "file://" + encodeURI(p)).join("\r\n") + "\r\n" };
                            sysDrag.Drag.startDrag();
                            return;
                        }
                        ic.dragging = true; ic.dx = ddx; ic.dy = ddy;
                        pl.dragPath = ic.path; pl.dragDx = ddx; pl.dragDy = ddy;
                        const t = pl.iconAt(q.x, q.y);
                        pl.dropTarget = t !== "" && !pl.sel[t] && (t === pl.trashDir || pl.isDirPath(t)) ? t : "";
                    }
                    onReleased: (m) => {
                        if (!ic.dragging) return;
                        pl.justDragged = true;
                        const paths = pl.sel[ic.path] ? Object.keys(pl.sel) : [ic.path];
                        const target = pl.dropTarget;
                        const dc = Math.round(ic.dx / pl.cellW), dr = Math.round(ic.dy / pl.cellH);
                        ic.dragging = false; ic.dx = 0; ic.dy = 0; pl.dragPath = ""; pl.dragDx = 0; pl.dragDy = 0; pl.dropTarget = "";
                        const movable = paths.filter(p => p !== pl.trashDir);
                        const q = mapToItem(root, m.x, m.y), ctrl = m.modifiers & Qt.ControlModifier, shift = m.modifiers & Qt.ShiftModifier, alt = m.modifiers & Qt.AltModifier;
                        if (target !== "" && pl.dragBtn !== Qt.LeftButton) pl.dropMenu(movable, target, q.x, q.y);     // pravé / stredné: ponuka
                        else if (target === pl.trashDir) { pl.sh('latte-kos vyhod "$@"', movable); pl.sel = {}; trashProc.running = true; }
                        else if (target !== "") pl.fileOp((ctrl && shift) || alt ? "link" : (ctrl ? "copy" : "move"), movable, target);
                        else if (dc !== 0 || dr !== 0) pl.moveIcons(paths, dc, dr);
                    }
                    onClicked: (m) => { if (pl.justDragged) { pl.justDragged = false; return; }
                                        if (m.button === Qt.RightButton) { const q = mapToItem(root, m.x, m.y); pl.itemMenu(ic.path, ic.isDir, q.x, q.y); } }
                    onDoubleClicked: pl.open(ic.path)
                }
                // Kôš a priečinky prijmú súbor pretiahnutý z inej aplikácie
                DropArea {
                    id: dz; anchors.fill: parent; keys: ["text/uri-list"]; enabled: ic.path === pl.trashDir || ic.isDir
                    onDropped: (d) => {
                        if (!d.hasUrls) return;
                        const l = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")));
                        if (ic.path === pl.trashDir) { pl.sh('latte-kos vyhod "$@"', l); trashProc.running = true; d.accept(Qt.MoveAction); }
                        else pl.externalDrop(d, ic.path);
                    }
                }
            }
            Icon { path: pl.trashDir; name: "Kôš"; glyph: "trash"; badge: pl.trashCount > 0 ? String(pl.trashCount) : "" }
            Repeater {
                model: files
                Icon {
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    readonly property var de: fileName.endsWith(".desktop") ? DesktopEntries.byId(fileName.slice(0, -8)) : null
                    path: filePath; name: de ? de.name : fileName; isDir: fileIsDir; glyph: pl.glyphFor(fileName, fileIsDir)
                    iconSrc: de && de.icon ? Quickshell.iconPath(de.icon, true) : ""
                }
            }

            // vlastnosti (Alt+Enter)
            Rectangle {
                visible: pl.props !== null
                anchors.centerIn: parent
                width: 440; height: pcol.implicitHeight + 32; radius: 14
                color: theme.surface; border { color: theme.outline; width: 1 }
                z: 50
                MouseArea { anchors.fill: parent }
                Column {
                    id: pcol
                    x: 16; y: 16; width: parent.width - 32; spacing: 6
                    Row { width: parent.width
                        Text { width: parent.width - 30; elide: Text.ElideMiddle; text: pl.props ? pl.props.path.split("/").pop() : ""; color: theme.fg; font { family: theme.fontUi; pixelSize: 16; weight: Font.Bold } }
                        IconButton { theme: theme; glyph: "x"; onClicked: pl.props = null } }
                    Repeater {
                        model: pl.props ? [["Typ", pl.props.mime + (pl.props.link ? " · odkaz na " + pl.props.link : "")], ["Umiestnenie", pl.props.path.substring(0, pl.props.path.lastIndexOf("/"))],
                                           ["Veľkosť", pl.human(pl.props.size) + " (" + pl.props.size + " B)"], ["Vlastník", pl.props.owner + " : " + pl.props.group],
                                           ["Práva", pl.props.rwx + " (" + pl.props.mode + ")"], ["Zmenené", pl.props.modified], ["Otvorené", pl.props.accessed]] : []
                        Row { required property var modelData; spacing: 10; width: pcol.width
                              Text { width: 100; text: modelData[0]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                              Text { width: parent.width - 110; wrapMode: Text.WrapAnywhere; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } } }
                    }
                }
            }
            ContextMenu { id: ctx; theme: theme }
        }
    }
    property string dragPath: ""
    property real dragDx: 0
    property real dragDy: 0
    property string dropTarget: ""
    // ── ťahanie ako vo Windows (alfatest 1) ─────────────────────────────────────────
    //   ľavé: na priečinok presunúť (ten istý disk), Ctrl = kópia, Alt alebo Ctrl+Shift = odkaz; do Koša = zahodiť
    //   pravé / stredné: po pustení ponuka Kopírovať sem · Presunúť sem · Vytvoriť odkaz sem · Zrušiť
    //   ikona nad okno aplikácie: systémové ťahanie (súbor do prehliadača, Discordu, Súborov…)
    //   súbory z iných aplikácií: ten istý disk = presunúť, iný disk alebo aplikácia bez presunu = kopírovať
    property int dragBtn: Qt.LeftButton
    property bool justDragged: false          // pravý klik po pravom ťahaní neotvorí ponuku položky
    property var winRects: []                 // okná na aktívnej ploche (hyprctl clients) pri začiatku ťahania
    Process {
        id: winsProc
        command: ["sh", "-c", "hyprctl clients -j; echo; hyprctl activeworkspace -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const t = this.text, i = t.lastIndexOf("\n{");
                    const cl = JSON.parse(t.substring(0, i)), ws = JSON.parse(t.substring(i + 1));
                    pl.winRects = cl.filter(c => c.mapped && !c.hidden && c.workspace.id === ws.id).map(c => ({ x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] }));
                } catch (e) { pl.winRects = []; }
            }
        }
    }
    function overWindow(x, y) { return winRects.some(r => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h); }
    Item {
        id: sysDrag
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.keys: ["text/uri-list"]
    }
    // presunúť / kopírovať / odkaz; mv a cp nič neprepíšu (-n), rovnako ako doteraz
    function fileOp(action, paths, dir) {
        if (action === "move") sh('d="$1"; shift; mv -n -- "$@" "$d/"', [dir].concat(paths));
        else if (action === "copy") sh('d="$1"; shift; cp -rn -- "$@" "$d/"', [dir].concat(paths));
        else if (action === "link") sh('d="$1"; shift; for f in "$@"; do ln -s -- "$f" "$d/" 2>/dev/null || ln -s -- "$f" "$d/Odkaz na $(basename "$f")"; done', [dir].concat(paths));
        else if (action === "auto") sh('d="$1"; shift; dd=$(stat -c %d "$d"); for u in "$@"; do if [ "$(stat -c %d "$u" 2>/dev/null)" = "$dd" ]; then mv -n -- "$u" "$d/"; else cp -rn -- "$u" "$d/"; fi; done', [dir].concat(paths));
        else if (action === "autocopy") sh('d="$1"; shift; for u in "$@"; do cp -rn -- "$u" "$d/"; done', [dir].concat(paths));
        sel = {};
    }
    function dropMenu(paths, dir, x, y) {
        const toTrash = dir === trashDir;
        const list = toTrash ? [{ glyph: "trash", label: "Presunúť do Koša", bold: true, action: () => { sh('latte-kos vyhod "$@"', paths); trashProc.running = true; pl.sel = {}; } }]
            : [{ glyph: "copy", label: "Kopírovať sem", action: () => pl.fileOp("copy", paths, dir) },
               { glyph: "arrows-move", label: "Presunúť sem", bold: true, action: () => pl.fileOp("move", paths, dir) },
               { glyph: "link", label: paths.length > 1 ? "Vytvoriť odkazy sem" : "Vytvoriť odkaz sem", action: () => pl.fileOp("link", paths, dir) }];
        list.push({ separator: true }, { glyph: "x", label: "Zrušiť", action: () => {} });
        ctx.open(x, y, list, (paths.length === 1 ? paths[0].substring(paths[0].lastIndexOf("/") + 1) : paths.length + " položiek") + " → " + (toTrash ? "Kôš" : dir.substring(dir.lastIndexOf("/") + 1)));
    }
    // súbory pretiahnuté z inej aplikácie; akcia podľa modifikátorov a toho, či zdroj dovolí presun
    function externalDrop(d, dir) {
        if (!d.hasUrls) return;
        const l = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
        if (!l.length) return;
        const mods = d.modifiers || 0, canMove = (d.supportedActions & Qt.MoveAction) !== 0;
        let a = !canMove ? "autocopy" : "auto";
        if (mods & Qt.ControlModifier) a = (mods & Qt.ShiftModifier) ? "link" : "copy";
        else if (mods & Qt.AltModifier) a = "link";
        else if ((mods & Qt.ShiftModifier) && canMove) a = "move";
        fileOp(a, l, dir);
        d.accept(a === "move" || a === "auto" ? Qt.MoveAction : (a === "link" ? Qt.LinkAction : Qt.CopyAction));
    }
    function isDirPath(p) { for (let i = 0; i < files.count; i++) if (files.get(i, "filePath") === p) return files.get(i, "fileIsDir"); return false; }
}
