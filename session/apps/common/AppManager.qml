// AppManager — jadro App Managera LatteOS (Obchod, Aktualizácie, Nainštalované, Oprávnenia a NET, Bude to fungovať?).
// Jedna implementácia pre samostatné okno (aplikacie.qml) aj stránky Nastavení (embedded: bez bočného panelu
// a okenných tlačidiel, sekcia zvonku). Rozdelené 26. 9. podľa zásady „všetko nastavenie v Nastaveniach“.
// Pôvodný popis okna:
// LatteOS — Aplikácie (App Manager). Podľa old/main_setting_v2.md §63: Objavovať · Aktualizácie ·
// Nainštalované · Oprávnenia, a „Bude to fungovať?“ pred inštaláciou súboru (.rpm, .flatpakref,
// .AppImage, .exe, .apk, .deb). Nastavenia › Softvér vedú sem, nie do druhej implementácie.
// Backend: latte-apps. Spúšťa sa: latte-app aplikacie [objavovat|aktualizacie|nainstalovane|opravnenia|check SÚBOR]
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: app
    required property var theme
    property bool embedded: false             // vložené do Nastavení
    signal closeRequested()

    readonly property string home: Quickshell.env("HOME") || "/"
    property var args: []                   // argumenty (hostiteľ: LATTE_APP_ARGS; Nastavenia: sekcia)
    // „check“ bez súboru (spustenie z ponuky, .desktop má %f) = Objavovať
    property string section: args[0] === "check" ? (args.length > 1 && args[1] !== "" ? "check" : "objavovat")
                           : (({ aplikacie: "nainstalovane", instalacia: "objavovat", hladat: "objavovat", detail: "objavovat" })[args[0]] || args[0] || "objavovat")
    property string status: ""
    property string query: ""
    property var results: []
    property bool searching: false
    property var installedApps: []
    property var updatesList: []
    property bool updatesLoading: false
    property string selId: ""
    property var perms: ({})
    property string checkPath: args[0] === "check" ? args.slice(1).join(" ") : ""
    property var verdict: null
    property var downloads: []
    property string busyId: ""
    // obchod (Flathub API cez latte-apps store)
    property var store: null
    property string category: ""
    property string categoryName: ""
    property var categoryApps: []
    property int categoryPage: 1
    property var appPage: null              // detail aplikácie v obchode
    property string appPageId: ""
    property var searchRpm: []
    // aktualizácie: súčasti LatteOS, ovládače a firmvér
    property var latte: null
    // čas v aplikáciách (Digitálna pohoda, 30 dní) pre detail nainštalovanej aplikácie
    property var well: null
    readonly property var selWell: well && sel ? well.apps.find(w => w.desktop === sel.id || w["class"].toLowerCase() === sel.id.toLowerCase()) || null : null
    function dur(sec) { sec = Math.round(sec || 0); const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60); return h > 0 ? h + " h " + m + " min" : (m > 0 ? m + " min" : (sec > 0 ? "< 1 min" : "0 min")); }
    property var drv: null
    readonly property var categories: [["game", "Hry"], ["network", "Internet"], ["audiovideo", "Hudba a video"], ["graphics", "Grafika"],
                                       ["office", "Kancelária"], ["development", "Vývoj"], ["education", "Vzdelávanie"], ["science", "Veda"],
                                       ["system", "Systém"], ["utility", "Nástroje"]]

    readonly property var sel: installedApps.find(a => a.id === selId) || null

    // odporúčané (IDEAS: základný balík — prehrávač, kancelária, hry, komunikácia, kalendár a úlohy)
    readonly property var picks: [
        { title: "Základ", items: [["org.mozilla.firefox", "Firefox", "Prehliadač"], ["org.videolan.VLC", "VLC", "Prehrávač videa a hudby"],
                                   ["org.libreoffice.LibreOffice", "LibreOffice", "Kancelária (doc, xls, odt)"], ["org.gnome.Calculator", "Kalkulačka", "Kalkulačka"]] },
        { title: "Hry", items: [["com.valvesoftware.Steam", "Steam", "Obchod a knižnica hier"], ["com.heroicgameslauncher.hgl", "Heroic", "Epic, GOG, Amazon"],
                                ["org.zdoom.GZDoom", "GZDoom", "DOOM (vlastné WAD súbory)"], ["org.yamagi.YamagiQ2", "Yamagi Quake II", "Quake II"]] },
        { title: "Tvorba", items: [["org.gimp.GIMP", "GIMP", "Úprava fotiek"], ["org.kde.krita", "Krita", "Kreslenie"],
                                   ["com.obsproject.Studio", "OBS Studio", "Nahrávanie a streamovanie"], ["org.kde.kdenlive", "Kdenlive", "Strih videa"]] },
        { title: "Komunikácia a čas", items: [["com.discordapp.Discord", "Discord", "Hlas a chat"], ["org.signal.Signal", "Signal", "Bezpečné správy"],
                                              ["io.github.alainm23.planify", "Planify", "Úlohy a plánovač (Todoist, CalDAV)"], ["org.gnome.Calendar", "Kalendár", "Google, iCloud, CalDAV"]] }
    ]

    function human(b) {
        if (!b) return "";
        const u = ["B", "kB", "MB", "GB"]; let v = b, i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return v.toFixed(v < 10 && i > 0 ? 1 : 0).replace(".", ",") + " " + u[i];
    }
    function srcName(a) { return a.latteos ? "LatteOS" : ({ flatpak: "Flatpak", rpm: "Fedora (RPM)", local: "miestne" })[a.source] || a.source; }
    function isInstalled(id) { return installedApps.some(a => a.id === id || a.package === id); }

    component Cmd: Process {
        id: c
        signal done(string out, int code)
        property string buf: ""
        stdout: StdioCollector { onStreamFinished: c.buf = this.text }
        onExited: (code) => c.done(c.buf, code)
    }
    Cmd { id: listProc; command: ["latte-apps", "installed"]; running: true
          onDone: (out) => { try { app.installedApps = JSON.parse(out); } catch (e) {} } }
    Cmd { id: updProc; command: ["latte-apps", "updates"]
          onDone: (out) => { app.updatesLoading = false; try { app.updatesList = JSON.parse(out); } catch (e) {} } }
    Cmd { id: searchProc; onDone: (out) => { app.searching = false; try { const r = JSON.parse(out); app.results = r.apps || []; app.searchRpm = r.rpm || []; } catch (e) { app.results = []; app.searchRpm = []; } } }
    Cmd { id: storeProc; command: ["latte-apps", "store", "home"]; onDone: (out) => { try { app.store = JSON.parse(out); } catch (e) { app.store = { error: true }; } } }
    Cmd { id: catProc; onDone: (out) => { try { const r = JSON.parse(out); app.categoryApps = app.categoryPage > 1 ? app.categoryApps.concat(r.apps) : r.apps; } catch (e) {} } }
    Cmd { id: appProc; onDone: (out) => { try { const r = JSON.parse(out); if (r && r.id === app.appPageId) app.appPage = r; } catch (e) {} } }
    Cmd { id: wellProc; command: ["latte-sysmon", "pohoda", "30"]; onDone: (out) => { try { app.well = JSON.parse(out); } catch (e) {} } }
    Cmd { id: latteProc; command: ["latte-apps", "latteos"]; onDone: (out) => { try { app.latte = JSON.parse(out); } catch (e) {} } }
    Cmd { id: drvProc; command: ["latte-apps", "drivers"]; onDone: (out) => { try { app.drv = JSON.parse(out); } catch (e) {} } }
    Cmd { id: permProc; onDone: (out) => { try { app.perms = JSON.parse(out); } catch (e) { app.perms = {}; } } }
    Cmd { id: checkProc; onDone: (out) => { try { app.verdict = JSON.parse(out); } catch (e) { app.verdict = null; } } }
    Cmd { id: dlProc
          command: ["sh", "-c", "ls -t \"$HOME\"/Stiahnuté/* \"$HOME\"/Downloads/* 2>/dev/null | grep -iE '\\.(rpm|flatpakref|flatpak|appimage|exe|msi|apk|deb|sh|run)$' | head -12"]
          onDone: (out) => app.downloads = out.split("\n").filter(l => l !== "") }
    Cmd { id: installProc
          onDone: (out, code) => { app.status = code === 0 ? "Hotovo: " + app.busyId : "Nepodarilo sa: " + app.busyId + " (kód " + code + ")"; app.busyId = ""; listProc.running = true;
                                   if (app.appPageId !== "") { appProc.command = ["latte-apps", "store", "app", app.appPageId]; appProc.running = true; } } }
    // Setup Plan (vzor Flatseal): pred inštaláciou Flatpaku a v Oprávneniach — schváliť celý, časť alebo upraviť
    property var plan: null
    property bool planOpen: false
    property bool planInstall: false
    property string planName: ""
    property var planDenied: []
    readonly property string planProfile: !plan || !plan.items ? "" : (planDenied.length === 0 ? "trusted"
        : (plan.untrusted.length > 0 && plan.untrusted.every(k => planDenied.indexOf(k) >= 0) && planDenied.every(k => plan.untrusted.indexOf(k) >= 0) ? "untrusted" : "custom"))
    Cmd { id: planProc; onDone: (out) => { try { app.plan = JSON.parse(out); } catch (e) { app.plan = { error: "Plán sa nepodarilo načítať" }; }
                                            app.planDenied = app.plan.items ? app.plan.items.filter(i => !i.allowed).map(i => i.key) : []; } }
    Cmd { id: planApply; onDone: (out, code) => { app.status = code === 0 ? "Setup Plan uložený: " + app.planName + " (platí po reštarte aplikácie)" : "Setup Plan sa nepodarilo uložiť";
                                                  if (app.perms.app) { permProc.command = ["latte-apps", "permissions", app.perms.app]; permProc.running = true; } listProc.running = true; } }
    function openPlan(id, name, forInstall) {
        plan = null; planDenied = []; planName = name || id; planInstall = forInstall; planOpen = true;
        planProc.command = ["latte-apps", "plan", id]; planProc.running = true;
    }
    function togglePlan(key) { planDenied = planDenied.indexOf(key) >= 0 ? planDenied.filter(k => k !== key) : planDenied.concat([key]); }
    function approvePlan() {
        const id = plan.app, denied = JSON.stringify(planDenied);
        planOpen = false;
        if (planInstall) {
            busyId = id; status = "Inštalujem " + planName + " z Flathubu podľa Setup Planu…";
            installProc.command = ["sh", "-c", "latte-apps install flatpak \"$1\" && latte-apps plan-apply \"$1\" \"$2\"", "sh", id, denied]; installProc.running = true;
        } else { planApply.command = ["latte-apps", "plan-apply", id, denied]; planApply.running = true; }
    }
    // okamžité NET potrebuje systémovú službu latte-netd (nftables podľa cgroup)
    property bool netd: true
    Process { running: true; command: ["systemctl", "is-active", "--quiet", "latte-netd"]; onExited: (c) => app.netd = c === 0 }
    Process { id: runner }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) app.status = msg; }

    Timer { id: debounce; interval: 600; onTriggered: app.doSearch() }
    function doSearch() {
        if (query.trim().length < 2) { results = []; return; }
        appPage = null; category = "";
        searching = true; searchProc.command = ["latte-apps", "store", "search", query.trim()]; searchProc.running = true;
    }
    function install(src, id, name) {
        if (src === "flatpak") openPlan(id, name, true);        // inštalácia až po schválení Setup Planu
        else run(["latte-app", "instalator", "install", id], "Inštalácia: " + id);
    }
    function uninstall(a) {
        if (a.source === "flatpak") {
            busyId = a.id; status = "Odinštalujem " + a.name + "…";
            installProc.command = ["latte-apps", "remove", "flatpak", a.id]; installProc.running = true;
        } else if (a.package) run(["latte-app", "instalator", "--nazov=Odinštalovať_" + a.name.replace(/ /g, "_"), "remove", a.package], "Odinštalovanie: " + a.name);
    }
    function launch(a) {
        const ex = (a.exec || "").replace(/%[fFuUdDnNickvm]/g, "").trim();
        if (ex) run(["sh", "-c", "setsid " + ex + " >/dev/null 2>&1 &"], "Spúšťam " + a.name);
    }
    // história pohybu (Späť / Dopredu v hlavičke): sekcia, detail aplikácie, kategória
    property var history: []
    property int historyIndex: -1
    function push(st) {
        const cur = history[historyIndex];
        if (cur && JSON.stringify(cur) === JSON.stringify(st)) return;
        history = history.slice(0, historyIndex + 1).concat([st]);
        historyIndex = history.length - 1;
    }
    function restore(st) {
        if (st.app) openApp(st.app, false);
        else if (st.cat) openCategory(st.cat, st.catName, 1, false);
        else { go(st.section, false); if (st.section === "objavovat") storeHome(false); }
    }
    function back() { if (historyIndex > 0) { historyIndex--; restore(history[historyIndex]); } }
    function forward() { if (historyIndex < history.length - 1) { historyIndex++; restore(history[historyIndex]); } }
    function openApp(id, rec) {
        if (rec !== false) push({ section: "objavovat", app: id });
        appPageId = id; appPage = null; section = "objavovat";
        appProc.command = ["latte-apps", "store", "app", id]; appProc.running = true;
        content.contentY = 0;
    }
    function openCategory(key, name, page, rec) {
        if (rec !== false && (page || 1) === 1) push({ section: "objavovat", cat: key, catName: name });
        category = key; categoryName = name; categoryPage = page || 1; appPage = null; if (categoryPage === 1) categoryApps = [];
        catProc.command = ["latte-apps", "store", "category", key, String(categoryPage)]; catProc.running = true;
        if (categoryPage === 1) content.contentY = 0;
    }
    function storeHome(rec) { if (rec !== false) push({ section: "objavovat" }); appPage = null; appPageId = ""; category = ""; header.searchText = ""; content.contentY = 0; }
    function fmtCount(n) { return n >= 1000000 ? (n / 1000000).toFixed(1).replace(".", ",") + " mil." : (n >= 1000 ? Math.round(n / 1000) + " tis." : String(n)); }
    function runFlatpak(id) { run(["sh", "-c", "setsid flatpak run \"$1\" >/dev/null 2>&1 &", "sh", id], "Spúšťam " + id); }
    function check(p) { checkPath = p; verdict = null; checkProc.command = ["latte-apps", "check", p]; checkProc.running = true; }
    function go(k, rec) {
        if (rec !== false) push({ section: k });
        section = k;
        if (k === "aktualizacie" && updatesList.length === 0) { updatesLoading = true; updProc.running = true; }
        if (k === "aktualizacie") { latteProc.running = true; drvProc.running = true; }
        if (k === "objavovat" && !store && !storeProc.running) storeProc.running = true;
        if (k === "check") { dlProc.running = true; if (checkPath !== "") check(checkPath); }
        if (k === "nainstalovane" || k === "opravnenia") { listProc.running = true; if (!wellProc.running) wellProc.running = true; }
    }
    Component.onCompleted: {
        go(section);
        // latte-app aplikacie hladat <názov alebo id> (napr. zo Súborov › Otvoriť v › Nainštalovať): rovno hľadá
        // latte-app aplikacie detail <id> (rýchle spustenie › pravý klik › Detail): stránka aplikácie v obchode
        if (args[0] === "detail" && args.length > 1) Qt.callLater(() => app.openApp(args[1]));
        if (args[0] === "hladat" && args.length > 1) { query = args.slice(1).join(" "); doSearch(); Qt.callLater(() => header.searchText = query); }
    }

    Item {
        id: root
        anchors.fill: parent

        SideBar {
            id: side
            theme: app.theme
            visible: !app.embedded; width: app.embedded ? 0 : 250
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            heading: "Aplikácie"; headingGlyph: "apps"
            current: app.section
            model: [
                { title: "App Manager", items: [
                    { key: "objavovat", glyph: "search", label: "Obchod", sub: "Flathub, Fedora, výber LatteOS" },
                    { key: "aktualizacie", glyph: "refresh", label: "Aktualizácie", sub: app.updatesLoading ? "zisťujem…" : (app.updatesList.length ? app.updatesList.length + " dostupných" : "skontrolovať") },
                    { key: "nainstalovane", glyph: "apps", label: "Nainštalované", sub: app.installedApps.length + " aplikácií" },
                    { key: "opravnenia", glyph: "shield", label: "Oprávnenia a NET", sub: "internet, súbory, zariadenia" }
                ] },
                { title: "Inštalácia súboru", items: [
                    { key: "check", glyph: "help", label: "Bude to fungovať?", sub: "zložka, CD, .zip .rar .exe .rpm .AppImage" }
                ] }
            ]
            onActivated: (it) => app.go(it.key)
        }

        HeaderBar {
            id: header
            theme: app.theme
            appId: "latteos-aplikacie"
            windowControls: !app.embedded; netVisible: !app.embedded
            anchors { left: side.right; right: parent.right; top: parent.top }
            title: ({ objavovat: app.appPage ? app.appPage.name : (app.category ? app.categoryName : "Obchod"), aktualizacie: "Aktualizácie", nainstalovane: "Nainštalované", opravnenia: "Oprávnenia a NET", check: "Bude to fungovať?" })[app.section] || ""
            canBack: app.historyIndex > 0
            canForward: app.historyIndex < app.history.length - 1
            onBack: app.back()
            onForward: app.forward()
            searchPlaceholder: "Hľadať aplikáciu"
            onSearchChanged: (t) => { app.query = t; if (t !== "" && app.section !== "nainstalovane") app.section = "objavovat"; debounce.restart(); }
            onCloseRequested: app.closeRequested()
        }

        Flickable {
            id: content
            ScrollHint { flick: content; colors: theme }
            anchors { left: side.right; top: header.bottom; bottom: statusBar.top; right: detail.visible ? detail.left : parent.right; margins: 20 }
            contentHeight: body.implicitHeight + 20; clip: true
            Loader {
                id: body
                width: content.width
                sourceComponent: ({ objavovat: pDiscover, aktualizacie: pUpdates, nainstalovane: pInstalled, opravnenia: pPerms, check: pCheck })[app.section] || pDiscover
            }
        }

        // detail vybranej aplikácie
        Rectangle {
            id: detail
            visible: (app.section === "nainstalovane" || app.section === "opravnenia") && (!app.embedded || !!app.sel)
            anchors { right: parent.right; top: header.bottom; bottom: statusBar.top; margins: 14 }
            width: 280; radius: theme.radius
            color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.16 : 0.04); border { color: theme.line; width: 1 }
            Column {
                anchors { fill: parent; margins: 16 }
                spacing: 10
                readonly property var a: app.sel
                Text { width: parent.width; wrapMode: Text.WordWrap; text: parent.a ? parent.a.name : "App Manager"
                       color: theme.fg; font { family: theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold } }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: parent.a ? (parent.a.comment || "") : "Inštalácia jedným klikom z Flathubu (bez hesla, v izolácii) alebo z Fedory. Pred inštaláciou súboru povie, či bude fungovať."
                       color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                Repeater {
                    model: parent.a ? [["Zdroj", app.srcName(parent.a) + (parent.a.scope === "user" ? " · tvoj účet" : " · systém")],
                                       ["Na disku", parent.a.sizeText || "—"],
                                       ["Čas v aplikácii", app.selWell ? "dnes " + app.dur(app.selWell.today) + " · 30 dní " + app.dur(app.selWell.s) : "zatiaľ nepoužitá (meria Digitálna pohoda)"],
                                       ["V pamäti obvykle", app.selWell && app.selWell.rss ? app.human(app.selWell.rss * 1024) + (app.selWell.rssMax ? " · najviac " + app.human(app.selWell.rssMax * 1024) : "") : "—"],
                                       ["Balík", parent.a.package || "—"], ["Spúšťa", parent.a.exec || "—"]] : []
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 1
                        Text { text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                        Text { width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                }
                Item { width: 1; height: 4 }
                component Action: Rectangle {
                    id: act
                    property string glyph; property string label; property bool danger: false
                    signal clicked()
                    width: parent.width; height: 36; radius: 10
                    color: am.containsMouse ? (danger ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2) : theme.hover) : theme.field
                    Row { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                          Glyph { name: act.glyph; size: 16; color: act.danger ? theme.error : theme.fg }
                          Text { text: act.label; color: act.danger ? theme.error : theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } } }
                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; onClicked: act.clicked() }
                }
                Action { visible: !!parent.a; glyph: "player-play"; label: "Spustiť"; onClicked: app.launch(app.sel) }
                Action { visible: !!parent.a && parent.a.source === "flatpak"; glyph: "shield"; label: "Oprávnenia a NET"
                         onClicked: { app.section = "opravnenia"; permProc.command = ["latte-apps", "permissions", app.sel.id]; permProc.running = true; } }
                Action { visible: !!parent.a && !parent.a.latteos; glyph: "list-check"; label: "Setup Plan (čo smie)"
                         onClicked: app.openPlan(app.sel.id, app.sel.name, false) }
                Action { visible: !!parent.a && !parent.a.latteos && (parent.a.source === "flatpak" || !!parent.a.package); danger: true; glyph: "trash"
                         label: "Odinštalovať"; onClicked: app.uninstall(app.sel) }
            }
        }

        Rectangle {
            id: statusBar
            anchors { left: side.right; right: parent.right; bottom: parent.bottom }
            height: 30; color: "transparent"
            Rectangle { width: parent.width; height: 1; color: theme.line }
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: app.status || (app.busyId ? "Pracujem…" : "Flatpak: pre tvoj účet bez hesla · RPM a systém: Inštalátor s heslom správcu")
                   color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
        }
        PlanSheet { anchors.fill: parent; visible: app.planOpen }
        // bočné tlačidlá myši Späť / Dopredu (ako Microsoft Store)
        MouseArea {
            anchors.fill: parent; z: 900
            acceptedButtons: Qt.BackButton | Qt.ForwardButton
            onPressed: (m) => { if (m.button === Qt.BackButton) app.back(); else app.forward(); }
        }
        ContextMenu { id: ctx; theme: app.theme }
    }

    component PlanSheet: Rectangle {
        id: ps
        color: Qt.rgba(0, 0, 0, 0.55); z: 50
        readonly property var groups: {
            const order = ["Internet", "Súbory", "Zariadenia", "Zvuk", "Tajomstvá", "Systém", "Okná"], out = [];
            const items = app.plan && app.plan.items ? app.plan.items : [];
            for (const g of order) { const it = items.filter(i => i.group === g); if (it.length) out.push({ name: g, items: it }); }
            return out;
        }
        MouseArea { anchors.fill: parent; onClicked: app.planOpen = false }
        Keys.onEscapePressed: app.planOpen = false
        Rectangle {
            id: card
            width: Math.min(660, parent.width - 60); height: Math.min(parent.height - 60, 640)
            anchors.centerIn: parent; radius: 18; color: theme.surface; border { color: theme.line; width: 1 }
            MouseArea { anchors.fill: parent }                       // kliky vnútri nezatvárajú
            Column {
                id: head
                x: 22; y: 20; width: parent.width - 44; spacing: 6
                Text { text: "Setup Plan · " + app.planName; width: parent.width; elide: Text.ElideRight; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
                Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                       text: app.plan && app.plan.native
                             ? "Natívna aplikácia (RPM) si nič nežiada — plán navrhuje LatteOS. Čo vypneš, zablokuje izolácia (bubblewrap) pri každom spustení z LatteOS; nedôveryhodná dostane súkromný domov."
                             : "Toto si aplikácia žiada. Schváľ celý plán, vypni, čo nechceš, alebo zvoľ profil. LatteOS to zapíše do izolácie Flatpaku a kedykoľvek to zmeníš v Oprávneniach." }
                Text { visible: !!app.plan && !!app.plan.items; width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 }
                       text: !app.plan || !app.plan.items ? "" : [app.plan.size ? "Veľkosť: " + app.plan.size : "",
                             app.plan.runtime ? "Runtime " + app.plan.runtime.split("/")[0] + " " + app.plan.runtime.split("/").pop() + (app.plan.runtimeInstalled ? " (už máš)" : " (stiahne sa)") : ""].filter(x => x).join("  ·  ") }
                Row {
                    visible: !!app.plan && !!app.plan.items; spacing: 8; topPadding: 6
                    Repeater {
                        model: [["trusted", "Dôveryhodná", "všetko, čo žiada"], ["untrusted", "Nedôveryhodná", "bez internetu a citlivých prístupov"], ["custom", "Vlastná", "podľa prepínačov"]]
                        Rectangle {
                            required property var modelData
                            readonly property bool cur: app.planProfile === modelData[0]
                            width: 190; height: 48; radius: 12
                            color: cur ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (prm.containsMouse ? theme.hover : theme.field)
                            border { color: cur ? theme.primary : "transparent"; width: 1 }
                            Column { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: modelData[1]; color: parent.parent.cur ? theme.primary : theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                Text { text: modelData[2]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10 } } }
                            MouseArea { id: prm; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { if (modelData[0] === "trusted") app.planDenied = []; else if (modelData[0] === "untrusted") app.planDenied = app.plan.untrusted.slice(); } }
                        }
                    }
                }
            }
            Flickable {
                id: planFlick
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 22; topMargin: 14; bottomMargin: 10 }
                contentHeight: planCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollHint { flick: planFlick; colors: theme }
                Column {
                    id: planCol
                    width: planFlick.width - 10; spacing: 4
                    Text { visible: !app.plan; text: "Zisťujem, čo si aplikácia žiada…"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13 } }
                    Text { visible: !!app.plan && !!app.plan.error; width: parent.width; wrapMode: Text.WordWrap; text: app.plan ? app.plan.error || "" : ""; color: theme.error; font { family: theme.fontUi; pixelSize: 13 } }
                    Text { visible: !!app.plan && !!app.plan.items && app.plan.items.length === 0; text: "Aplikácia si nežiada nič navyše — beží úplne izolovaná."; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                    Repeater {
                        model: ps.groups
                        Column {
                            required property var modelData
                            width: planCol.width; spacing: 4
                            Heading { text: modelData.name.toUpperCase(); topPadding: 8 }
                            Repeater {
                                model: modelData.items
                                Rectangle {
                                    required property var modelData
                                    readonly property bool allowed: app.planDenied.indexOf(modelData.key) < 0 || !!modelData.required
                                    width: planCol.width; height: 44; radius: 10; color: rim.containsMouse && !modelData.required ? theme.hover : theme.field
                                    Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                                                color: modelData.risk >= 2 ? theme.error : (modelData.risk === 1 ? theme.primary : theme.fgDim) }
                                    Text { x: 30; width: parent.width - 120; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                           text: modelData.label; color: parent.allowed ? theme.fg : theme.fgDim; font { family: theme.fontUi; pixelSize: 13; strikeout: !parent.allowed } }
                                    Text { visible: !!modelData.required; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                           text: "nutné"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                                    Rectangle {                                                     // prepínač
                                        visible: !modelData.required
                                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        width: 40; height: 22; radius: 11; color: parent.allowed ? theme.primary : theme.outline
                                        Rectangle { width: 16; height: 16; radius: 8; y: 3; x: parent.parent.allowed ? 21 : 3; color: parent.parent.allowed ? theme.fgOnPrimary : theme.fgDim
                                                    Behavior on x { NumberAnimation { duration: 120 } } }
                                    }
                                    MouseArea { id: rim; anchors.fill: parent; hoverEnabled: true; enabled: !parent.modelData.required
                                                onClicked: app.togglePlan(parent.modelData.key) }
                                }
                            }
                        }
                    }
                }
            }
            Row {
                id: foot
                anchors { right: parent.right; bottom: parent.bottom; margins: 20 }
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; rightPadding: 8; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: app.plan && app.plan.items ? (app.planDenied.length ? "Zamietnuté: " + app.planDenied.length : "Schvaľuješ celý plán") : "" }
                Pill { label: "Zrušiť"; onClicked: app.planOpen = false }
                Pill { primaryStyle: true; on: !!app.plan && !!app.plan.items
                       label: app.planInstall ? (app.planDenied.length ? "Schváliť upravený a inštalovať" : "Schváliť a inštalovať") : "Uložiť plán"
                       onClicked: app.approvePlan() }
            }
        }
    }

    // ── súčasti ──────────────────────────────────────────────────────────────────
    component Heading: Text { color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.8 } }
    component Pill: Rectangle {
        id: pill
        property string label; property bool primaryStyle: false; property bool on: true
        signal clicked()
        width: pt.implicitWidth + 24; height: 32; radius: 10; opacity: on ? 1 : 0.5
        color: primaryStyle ? theme.primary : (pm.containsMouse ? theme.hover : theme.surface)
        border { color: primaryStyle ? "transparent" : theme.line; width: 1 }
        Text { id: pt; anchors.centerIn: parent; text: pill.label; color: pill.primaryStyle ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: if (pill.on) pill.clicked() }
    }
    // riadok aplikácie (výsledok hľadania, odporúčanie, aktualizácia)
    component AppRow: Rectangle {
        id: ar
        property string title; property string sub; property string badge; property string glyph: "package"
        property string actionLabel: ""; property bool actionPrimary: true; property bool actionOn: true
        signal action()
        width: parent ? parent.width : 400; height: 58; radius: 12; color: theme.field
        Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; name: ar.glyph; size: 24; color: theme.primary }
        Column {
            x: 52; width: parent.width - 52 - (btn.visible ? btn.width + 24 : 16); anchors.verticalCenter: parent.verticalCenter; spacing: 2
            Row {
                spacing: 8
                Text { text: ar.title; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                Rectangle { visible: ar.badge !== ""; anchors.verticalCenter: parent.verticalCenter; width: bt.implicitWidth + 12; height: 18; radius: 9
                            color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.15)
                            Text { id: bt; anchors.centerIn: parent; text: ar.badge; color: theme.primary; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } } }
            }
            Text { width: parent.width; elide: Text.ElideRight; text: ar.sub; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
        }
        Pill { id: btn; visible: ar.actionLabel !== ""; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               label: ar.actionLabel; primaryStyle: ar.actionPrimary; on: ar.actionOn; onClicked: ar.action() }
    }

    // ── stránky ──────────────────────────────────────────────────────────────────
    // karta aplikácie z obchodu (ikona, názov, zhrnutie, overený vývojár, inštalácie)
    component AppCard: Rectangle {
        id: cardItem
        required property var info
        width: 232; height: 104; radius: 16
        color: cm.containsMouse ? theme.hover : theme.field
        border { color: cm.containsMouse ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.5) : "transparent"; width: 1 }
        Rectangle {
            id: icBox; x: 12; y: 12; width: 56; height: 56; radius: 14; color: "transparent"; clip: true
            Image { id: icImg; anchors.fill: parent; source: cardItem.info.icon || ""; asynchronous: true; fillMode: Image.PreserveAspectFit; sourceSize { width: 112; height: 112 } }
            Glyph { anchors.centerIn: parent; visible: icImg.status !== Image.Ready; name: "package"; size: 30; color: theme.primary }
        }
        Column {
            x: 80; y: 12; width: parent.width - 92; spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: cardItem.info.name; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: cardItem.info.summary || ""
                   color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
        }
        Row {
            x: 80; anchors { bottom: parent.bottom; bottomMargin: 10 } spacing: 8
            Text { visible: cardItem.info.installed; text: "✓ nainštalované"; color: theme.primary; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
            Text { visible: !cardItem.info.installed && !!cardItem.info.verified; text: "✔ overený"; color: theme.primary; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
            Text { visible: !cardItem.info.installed && (cardItem.info.installs || 0) > 0; text: "↓ " + app.fmtCount(cardItem.info.installs) + "/mes."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10 } }
        }
        MouseArea {
            id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => {
                if (m.button !== Qt.RightButton) { app.openApp(cardItem.info.id); return; }
                const i = cardItem.info, q = mapToItem(app, m.x, m.y);
                const items = [{ glyph: "info-circle", label: "Zobraziť detail", action: () => app.openApp(i.id) }];
                if (i.installed) {
                    items.push({ glyph: "player-play", label: "Otvoriť", action: () => app.runFlatpak(i.id) });
                    items.push({ glyph: "shield", label: "Oprávnenia a NET", action: () => { app.section = "opravnenia"; app.selId = i.id; permProc.command = ["latte-apps", "permissions", i.id]; permProc.running = true; } });
                    items.push({ glyph: "list-check", label: "Setup Plan (čo smie)", action: () => app.openPlan(i.id, i.name, false) });
                } else items.push({ glyph: "download", label: "Inštalovať", enabled: app.busyId === "", action: () => app.install("flatpak", i.id, i.name) });
                items.push({ separator: true });
                items.push({ glyph: "external-link", label: "Otvoriť na Flathube", action: () => Qt.openUrlExternally("https://flathub.org/apps/" + i.id) });
                items.push({ glyph: "clipboard", label: "Kopírovať ID aplikácie", action: () => app.run(["wl-copy", "--", i.id], "Skopírované: " + i.id) });
                if (i.installed) { items.push({ separator: true });
                    items.push({ glyph: "trash", label: "Odinštalovať", danger: true, action: () => { app.busyId = i.id; app.status = "Odinštalujem " + i.name + "…"; installProc.command = ["latte-apps", "remove", "flatpak", i.id]; installProc.running = true; } }); }
                ctx.open(q.x, q.y, items, i.name);
            }
        }
    }
    component Shelf: Column {
        id: shelf
        property string title; property var items: []
        width: parent ? parent.width : 600; spacing: 8; visible: items.length > 0
        Heading { text: shelf.title.toUpperCase(); topPadding: 6 }
        ListView {
            id: rolovanie2
            ScrollHint { flick: rolovanie2; colors: theme; horizontal: true }
            width: parent.width; height: 104; orientation: ListView.Horizontal; spacing: 10; clip: true
            model: shelf.items; boundsBehavior: Flickable.StopAtBounds
            delegate: AppCard { required property var modelData; info: modelData }
        }
    }

    Component {
        id: pDiscover
        Column {
            spacing: 14
            width: parent ? parent.width : 800

            // ── detail aplikácie ────────────────────────────────────────────────
            Column {
                visible: app.appPageId !== ""
                width: parent.width; spacing: 14
                readonly property var d: app.appPage
                Text { visible: !parent.d; text: "Načítavam z Flathubu…"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13 } }
                Row {
                    visible: !!parent.d; spacing: 18; width: parent.width
                    Rectangle {
                        width: 104; height: 104; radius: 24; color: theme.field
                        Image { anchors { fill: parent; margins: 8 } source: parent.parent.parent.d ? parent.parent.parent.d.icon : ""; fillMode: Image.PreserveAspectFit; asynchronous: true
                                sourceSize { width: 192; height: 192 } }
                    }
                    Column {
                        width: parent.width - 122; spacing: 6
                        readonly property var d: parent.parent.d
                        Text { text: parent.d ? parent.d.name : ""; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 28; weight: Font.DemiBold } }
                        Text { text: parent.d ? parent.d.developer + (parent.d.verified ? "  ✔ overený" + (parent.d.verifiedBy ? " (" + parent.d.verifiedBy + ")" : "") : "") : ""
                               color: parent.d && parent.d.verified ? theme.primary : theme.fgDim; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: parent.d ? parent.d.summary : ""; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                        Row {
                            spacing: 10; topPadding: 6
                            readonly property var d: parent.d
                            Pill { visible: !!parent.d && !parent.d.installed; primaryStyle: true; on: app.busyId === ""
                                   label: parent.d && app.busyId === parent.d.id ? "Inštalujem…" : "Inštalovať"
                                   onClicked: app.install("flatpak", parent.d.id, parent.d.name) }
                            Pill { visible: !!parent.d && parent.d.installed; primaryStyle: true; label: "Otvoriť"; onClicked: app.runFlatpak(parent.d.id) }
                            Pill { visible: !!parent.d && parent.d.installed; label: app.busyId !== "" ? "Pracujem…" : "Odinštalovať"; on: app.busyId === ""
                                   onClicked: { app.busyId = parent.d.id; app.status = "Odinštalujem " + parent.d.name + "…"; installProc.command = ["latte-apps", "remove", "flatpak", parent.d.id]; installProc.running = true; } }
                            Pill { visible: !!parent.d && parent.d.homepage !== ""; label: "Web ↗"; onClicked: Qt.openUrlExternally(parent.d.homepage) }
                        }
                    }
                }
                // štatistiky
                Flow {
                    visible: !!parent.d; width: parent.width; spacing: 10
                    readonly property var d: parent.d
                    Repeater {
                        model: parent.d ? [["Na stiahnutie", app.human(parent.d.downloadSize) || "—"], ["Po inštalácii", app.human(parent.d.installedSize) || "—"],
                                           ["Inštalácie", app.fmtCount(parent.d.installsTotal)], ["Verzia", (parent.d.releases[0] || {}).version || "—"],
                                           ["Licencia", parent.d.free ? "slobodná" : "vlastnícka"], ["Zdroj", "Flathub · izolácia"]] : []
                        Rectangle {
                            required property var modelData
                            width: 150; height: 58; radius: 12; color: theme.field
                            Text { x: 12; y: 9; text: modelData[0].toUpperCase(); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
                            Text { x: 12; y: 27; width: parent.width - 24; elide: Text.ElideRight; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        }
                    }
                }
                // snímky obrazovky
                ListView {
                    id: rolovanie3
                    ScrollHint { flick: rolovanie3; colors: theme; horizontal: true }
                    visible: !!parent.d && parent.d.screenshots.length > 0
                    width: parent.width; height: 300; orientation: ListView.Horizontal; spacing: 12; clip: true
                    model: parent.d ? parent.d.screenshots : []
                    delegate: Rectangle {
                        required property string modelData
                        width: shot.status === Image.Ready ? Math.min(560, shot.implicitWidth * 300 / Math.max(1, shot.implicitHeight)) : 480; height: 300; radius: 14
                        color: theme.field; clip: true
                        Image { id: shot; anchors.fill: parent; source: modelData; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.height: 600 }
                        Text { anchors.centerIn: parent; visible: shot.status !== Image.Ready; text: "…"; color: theme.fgDim; font.pixelSize: 22 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(modelData) }
                    }
                }
                Heading { visible: !!parent.d; text: "O APLIKÁCII" }
                Text { visible: !!parent.d; width: parent.width; wrapMode: Text.WordWrap; text: parent.d ? parent.d.description : ""
                       color: theme.fg; lineHeight: 1.25; font { family: theme.fontUi; pixelSize: 13 } }
                Heading { visible: !!parent.d && parent.d.releases.length > 0; text: "VERZIE" }
                Repeater {
                    model: parent.d ? parent.d.releases : []
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 2
                        Text { text: modelData.version + (modelData.date ? "  ·  " + Qt.formatDate(new Date(parseInt(modelData.date) * 1000), "d. M. yyyy") : "")
                               color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                        Text { visible: modelData.text !== ""; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                               text: modelData.text; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                }
                Text { visible: !!parent.d; width: parent.width; wrapMode: Text.WordWrap; topPadding: 6; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: "Popisy sú z Flathubu (väčšinou po anglicky). Flatpak beží v izolácii; prístup k súborom, sieti a zariadeniam upravíš v Oprávnenia a NET." }
            }

            // ── vyhľadávanie ────────────────────────────────────────────────────
            Column {
                visible: app.appPageId === "" && app.query !== ""
                width: parent.width; spacing: 10
                Text { visible: app.searching; text: "Hľadám „" + app.query + "“…"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13 } }
                Heading { visible: app.results.length > 0; text: "FLATHUB  ·  " + app.results.length }
                Flow { width: parent.width; spacing: 10; Repeater { model: app.results; AppCard { required property var modelData; info: modelData } } }
                Heading { visible: app.searchRpm.length > 0; text: "SYSTÉMOVÉ BALÍKY FEDORY" }
                Repeater {
                    model: app.searchRpm
                    AppRow {
                        required property var modelData
                        width: parent.width; title: modelData.name; sub: modelData.comment; badge: "Fedora"; glyph: "box"
                        readonly property bool has: app.isInstalled(modelData.id)
                        actionLabel: has ? "Nainštalované" : "Inštalovať (heslo)"; actionPrimary: !has; actionOn: !has
                        onAction: app.install("rpm", modelData.id, modelData.name)
                    }
                }
                Text { visible: !app.searching && app.results.length === 0 && app.searchRpm.length === 0; text: "Nič sa nenašlo."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
            }

            // ── kategória ──────────────────────────────────────────────────────
            Column {
                visible: app.appPageId === "" && app.query === "" && app.category !== ""
                width: parent.width; spacing: 10
                Flow { width: parent.width; spacing: 10; Repeater { model: app.categoryApps; AppCard { required property var modelData; info: modelData } } }
                Text { visible: app.categoryApps.length === 0; text: "Načítavam…"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13 } }
                Pill { visible: app.categoryApps.length >= 48 * app.categoryPage; label: "Ďalšie"; onClicked: app.openCategory(app.category, app.categoryName, app.categoryPage + 1) }
            }

            // ── úvod obchodu ────────────────────────────────────────────────────
            Column {
                visible: app.appPageId === "" && app.query === "" && app.category === ""
                width: parent.width; spacing: 16
                Text { visible: !app.store; text: "Načítavam obchod z Flathubu…"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13 } }
                Text { visible: !!app.store && !!app.store.error; text: "Obchod sa nenačítal (bez internetu?). Výber LatteOS nižšie funguje."; color: theme.error; font { family: theme.fontUi; pixelSize: 13 } }
                // banner: trendová aplikácia so snímkou
                Rectangle {
                    readonly property var b: app.store ? app.store.banner : null
                    visible: !!b; width: parent.width; height: 230; radius: 20; clip: true; color: theme.field
                    Image { anchors.fill: parent; source: parent.b ? parent.b.screenshot : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: 0.9 }
                    Rectangle { anchors.fill: parent; gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.97) }
                        GradientStop { position: 0.55; color: Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.75) }
                        GradientStop { position: 1.0; color: "transparent" } } }
                    Column {
                        x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.5; spacing: 8
                        Text { text: "TRENDY TENTO TÝŽDEŇ"; color: theme.primary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold; letterSpacing: 1 } }
                        Text { text: parent.parent.b ? parent.parent.b.name : ""; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 30; weight: Font.DemiBold } }
                        Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                               text: parent.parent.b ? parent.parent.b.summary : ""; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                        Pill { label: "Zobraziť"; primaryStyle: true; onClicked: app.openApp(parent.parent.b.id) }
                    }
                }
                // kategórie
                Flow {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: app.categories
                        Pill { required property var modelData; label: modelData[1]; onClicked: app.openCategory(modelData[0], modelData[1], 1) }
                    }
                }
                Shelf { title: "Trendy"; items: app.store && app.store.trendy ? app.store.trendy : [] }
                Shelf { title: "Obľúbené"; items: app.store && app.store.oblubene ? app.store.oblubene : [] }
                Shelf { title: "Nové na Flathube"; items: app.store && app.store.nove ? app.store.nove : [] }
                Shelf { title: "Nedávno aktualizované"; items: app.store && app.store.aktualizovane ? app.store.aktualizovane : [] }
                // výber LatteOS
                Repeater {
                    model: app.picks
                    Column {
                        id: grp
                        required property var modelData
                        width: parent.width; spacing: 6
                        Heading { text: "VÝBER LATTEOS · " + grp.modelData.title.toUpperCase(); topPadding: 6 }
                        Repeater {
                            model: grp.modelData.items
                            AppRow {
                                required property var modelData
                                width: grp.width; title: modelData[1]; sub: modelData[2]; badge: "Flathub"
                                readonly property bool has: app.isInstalled(modelData[0])
                                actionLabel: app.busyId === modelData[0] ? "Inštalujem…" : (has ? "Nainštalované" : "Inštalovať")
                                actionPrimary: !has; actionOn: !has && app.busyId === ""
                                onAction: app.install("flatpak", modelData[0], modelData[1])
                                MouseArea { anchors { fill: parent; rightMargin: 160 } onClicked: app.openApp(modelData[0]) }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: pUpdates
        Column {
            id: upd
            spacing: 12
            width: parent ? parent.width : 800
            readonly property var rpms: app.updatesList.filter(u => u.source === "rpm")
            readonly property var flats: app.updatesList.filter(u => u.source === "flatpak")
            Row {
                spacing: 10
                Pill { label: "Aktualizovať všetko"; primaryStyle: true; on: app.updatesList.length > 0
                       onClicked: app.run(["sh", "-c", "flatpak update --user -y --noninteractive >/dev/null 2>&1; latte-app instalator upgrade"], "Aktualizácia: aplikácie (Flatpak) a potom systém") }
                Pill { label: app.updatesLoading ? "Zisťujem…" : "Skontrolovať znova"; on: !app.updatesLoading
                       onClicked: { app.updatesLoading = true; updProc.running = true; latteProc.running = true; drvProc.running = true; } }
            }
            component Block: Rectangle {
                id: blk
                property string title; property string glyph; property string sub; property string actionLabel: ""; property bool actionOn: true
                default property alias rows: bcol.data
                signal action()
                width: parent ? parent.width : 700; height: bhead.height + bcol.implicitHeight + 28; radius: 16; color: theme.field
                Row {
                    id: bhead; x: 16; y: 14; width: parent.width - 32; spacing: 12
                    Glyph { name: blk.glyph; size: 24; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        width: parent.width - 36 - (bb.visible ? bb.width + 12 : 0); anchors.verticalCenter: parent.verticalCenter
                        Text { text: blk.title; color: theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: blk.sub; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                    Pill { id: bb; visible: blk.actionLabel !== ""; label: blk.actionLabel; primaryStyle: true; on: blk.actionOn; anchors.verticalCenter: parent.verticalCenter; onClicked: blk.action() }
                }
                Column { id: bcol; x: 16; anchors { top: bhead.bottom; topMargin: 8 } width: parent.width - 32; spacing: 4 }
            }
            component Line: Text { width: parent ? parent.width : 600; elide: Text.ElideRight; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
            Block {
                title: "Systém (Fedora)"; glyph: "server"
                sub: app.updatesLoading ? "zisťujem…" : (upd.rpms.length ? upd.rpms.length + " balíkov na aktualizáciu" : "aktuálny (podľa poslednej kontroly dnf)")
                actionLabel: upd.rpms.length ? "Aktualizovať systém" : ""
                onAction: app.run(["latte-app", "instalator", "upgrade"], "Aktualizácia systému")
                Repeater { model: upd.rpms.slice(0, 12); Line { required property var modelData; text: modelData.id + "  " + modelData.version } }
                Line { visible: upd.rpms.length > 12; text: "… a ďalších " + (upd.rpms.length - 12) }
            }
            Block {
                title: "Aplikácie (Flatpak)"; glyph: "apps"
                sub: upd.flats.length ? upd.flats.length + " aplikácií má novú verziu" : "všetky aktuálne"
                actionLabel: upd.flats.length ? "Aktualizovať aplikácie" : ""; actionOn: app.busyId === ""
                onAction: { app.busyId = "aktualizácia aplikácií"; app.status = "Aktualizujem aplikácie (Flatpak)…"; installProc.command = ["flatpak", "update", "--user", "-y", "--noninteractive"]; installProc.running = true; }
                Repeater { model: upd.flats; Line { required property var modelData; text: modelData.id + "  " + modelData.version } }
            }
            Block {
                id: blkLatte
                title: "Súčasti LatteOS"; glyph: "coffee"
                readonly property var l: app.latte
                sub: !l ? "zisťujem…" : (l.error ? l.error : (l.behind > 0 ? l.behind + " nových zmien (nainštalované " + l.installed + " z " + l.date + ")"
                                                                            : "aktuálne · " + l.installed + " z " + l.date + " (vetva " + l.branch + ")"))
                actionLabel: l && l.behind > 0 ? "Aktualizovať LatteOS" : ""
                onAction: app.run(["latte-app", "instalator", "latteos"], "Aktualizácia súčastí LatteOS")
                Repeater { model: blkLatte.l ? blkLatte.l.log.slice(0, 10) : []; Line { required property var modelData; text: "• " + modelData.date + "  " + modelData.subject } }
                Line { visible: !!blkLatte.l && blkLatte.l.behind === 0 && (blkLatte.l.recent || []).length > 0; text: "Posledné zmeny:" }
                Repeater { model: blkLatte.l && blkLatte.l.behind === 0 ? (blkLatte.l.recent || []).slice(0, 4) : []; Line { required property var modelData; text: "  " + modelData.date + "  " + modelData.subject } }
            }
            Block {
                id: blkDrv
                title: "Ovládače a firmvér (Správca zariadení)"; glyph: "cpu"
                readonly property var d: app.drv
                sub: !d ? "zisťujem…" : ((d.firmware.length ? d.firmware.length + " aktualizácií firmvéru" : "firmvér aktuálny (fwupd)") + " · grafika: " + d.gpu.map(g => g.driver || "?").join(", ")
                                            + ((d.devices || []).length ? " · ⚠ " + d.devices.length + " zariadení bez ovládača/firmvéru" : " · všetky zariadenia majú ovládač"))
                actionLabel: d && d.firmware.length ? "Aktualizovať firmvér" : ""
                onAction: app.run(["sh", "-c", "fwupdmgr update -y --no-reboot-check >/dev/null 2>&1 && notify-send -a LatteOS 'Firmvér aktualizovaný' 'Niektoré zmeny sa prejavia po reštarte.' || notify-send -a LatteOS 'Firmvér' 'Aktualizácia sa nepodarila.'"], "Aktualizujem firmvér…")
                Repeater { model: blkDrv.d ? blkDrv.d.gpu : []; Line { required property var modelData; wrapMode: Text.WordWrap; elide: Text.ElideNone
                           text: "• " + modelData.name.replace(/\s*\[[0-9a-f:]+\]/g, "") + (modelData.driver ? " · ovládač " + modelData.driver : "") + (modelData.advice ? " — " + modelData.advice : "") } }
                Repeater { model: blkDrv.d ? blkDrv.d.firmware : []; Line { required property var modelData; text: "• " + modelData.device + ": " + modelData.current + " → " + modelData.new } }
                Repeater { model: blkDrv.d ? blkDrv.d.notes : []; Line { required property var modelData; text: modelData } }
                Repeater { model: blkDrv.d ? (blkDrv.d.devices || []) : []
                    Row { required property var modelData; spacing: 8
                          Line { width: 460; wrapMode: Text.WordWrap; elide: Text.ElideNone; text: "⚠ " + modelData.name + " · " + modelData.stateTitle + (modelData.reason ? " — " + modelData.reason : "") }
                          Pill { visible: modelData.packages.length > 0; primaryStyle: true; label: modelData.repo ? "Zapnúť " + modelData.repo + " a nainštalovať" : "Doinštalovať"
                                 onClicked: app.run(["latte-app", "instalator", "--nazov=Ovládač", "install"].concat(modelData.packages), "Inštalátor: " + modelData.packages.join(", ")) } } }
                Pill { label: "Správca zariadení ›"; onClicked: app.run(["latte-app", "zariadenia"], "Správca zariadení") }
            }
        }
    }
    Component {
        id: pInstalled
        Column {
            spacing: 6
            Repeater {
                model: app.installedApps.filter(a => app.query === "" || (a.name + " " + a.id).toLowerCase().includes(app.query.toLowerCase()))
                Rectangle {
                    id: ir
                    required property var modelData
                    width: parent.width; height: 52; radius: 12
                    color: app.selId === modelData.id ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.16) : (im.containsMouse ? theme.hover : theme.field)
                    Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; name: ir.modelData.latteos ? "coffee" : (ir.modelData.source === "flatpak" ? "package" : "box"); size: 22; color: theme.primary }
                    Column {
                        x: 50; width: parent.width - 210; anchors.verticalCenter: parent.verticalCenter
                        Text { width: parent.width; elide: Text.ElideRight; text: ir.modelData.name; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                        Text { width: parent.width; elide: Text.ElideRight; text: ir.modelData.comment || ir.modelData.id; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                    }
                    Text { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                           text: app.srcName(ir.modelData) + (ir.modelData.sizeText ? "  ·  " + ir.modelData.sizeText : ""); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    MouseArea {
                        id: im; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            app.selId = ir.modelData.id;
                            if (m.button !== Qt.RightButton) return;
                            const a = ir.modelData, p = mapToItem(app, m.x, m.y);
                            const items = [{ glyph: "player-play", label: "Spustiť", action: () => app.launch(a) }];
                            if (a.source === "flatpak") items.push({ glyph: "shield", label: "Oprávnenia a NET", action: () => { app.section = "opravnenia"; permProc.command = ["latte-apps", "permissions", a.id]; permProc.running = true; } });
                            if (!a.latteos) items.push({ glyph: "list-check", label: "Setup Plan (čo smie)", action: () => app.openPlan(a.id, a.name, false) });
                            items.push({ glyph: "folder", label: "Súbor .desktop", action: () => app.run(["latte-app", "subory", a.desktop.substring(0, a.desktop.lastIndexOf("/"))]) });
                            if (!a.latteos && (a.source === "flatpak" || a.package)) { items.push({ separator: true }); items.push({ glyph: "trash", label: "Odinštalovať", danger: true, action: () => app.uninstall(a) }); }
                            ctx.open(p.x, p.y, items, a.name + " · " + app.srcName(a));
                        }
                        onDoubleClicked: app.launch(ir.modelData)
                    }
                }
            }
        }
    }
    Component {
        id: pPerms
        Column {
            spacing: 10
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                   text: "NET = smie aplikácia na internet. Vypnutie platí **hneď**: bežiaca aplikácia okamžite stratí spojenie (Discord sa odpojí, video dohrá iba to, čo má načítané) a platí aj pri ďalšom spustení. Stará sa o to služba latte-netd."; textFormat: Text.MarkdownText }
            Repeater {
                model: app.installedApps.filter(a => !a.latteos)
                AppRow {
                    required property var modelData
                    width: parent.width; height: 54; title: modelData.name; sub: modelData.id + (modelData.source === "flatpak" ? "  ·  podrobnosti: klik na riadok" : "")
                    badge: app.srcName(modelData); glyph: modelData.net === "off" ? "world-off" : "world"
                    actionLabel: modelData.net === "off" ? "○ NET vypnutý" : "● NET zapnutý"; actionPrimary: modelData.net !== "off"
                    onAction: { app.run(["latte-apps", "net", modelData.id, modelData.net === "off" ? "on" : "off"], "NET " + (modelData.net === "off" ? "zapnutý" : "vypnutý") + ": " + modelData.name); netRefresh.restart(); }
                    MouseArea { anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: 150 }
                                enabled: parent.modelData.source === "flatpak"
                                onClicked: { app.selId = parent.modelData.id; permProc.command = ["latte-apps", "permissions", parent.modelData.id]; permProc.running = true; } }
                }
            }
            Timer { id: netRefresh; interval: 700; onTriggered: listProc.running = true }
            Rectangle {
                visible: !!app.perms.app
                width: parent.width; height: pc.implicitHeight + 28; radius: 14; color: theme.field; border { color: theme.primary; width: 1 }
                Column {
                    id: pc
                    x: 14; y: 14; width: parent.width - 28; spacing: 8
                    Row {
                        width: parent.width; spacing: 12
                        Text { width: parent.width - netBtn.width - 130; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: app.perms.app || ""; color: theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        Pill { label: "Setup Plan"; onClicked: app.openPlan(app.perms.app, app.perms.app, false) }
                        Pill {
                            id: netBtn
                            label: app.perms.network ? "● NET zapnutý" : "○ NET vypnutý"; primaryStyle: app.perms.network
                            onClicked: { app.run(["latte-apps", "net", app.perms.app, app.perms.network ? "off" : "on"], "NET " + (app.perms.network ? "vypnutý" : "zapnutý") + ": " + app.perms.app); refreshPerm.start(); }
                        }
                    }
                    Repeater {
                        model: app.perms.summary || []
                        Row {
                            required property var modelData
                            spacing: 10
                            Text { width: 110; text: modelData[0]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                            Text { width: pc.width - 120; wrapMode: Text.WrapAnywhere; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                        }
                    }
                    Text { text: app.netd ? "NET platí hneď, aj pre bežiacu aplikáciu. Ostatné oprávnenia po reštarte aplikácie." : "Služba latte-netd nebeží — NET platí až po reštarte aplikácie."
                           color: app.netd ? theme.fgDim : theme.error; font { family: theme.fontUi; pixelSize: 11 } }
                }
                Timer { id: refreshPerm; interval: 600; onTriggered: { permProc.command = ["latte-apps", "permissions", app.perms.app]; permProc.running = true; } }
            }
        }
    }
    Component {
        id: pCheck
        Column {
            spacing: 12
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                   text: "Stiahol si inštalačku alebo hru? LatteOS povie vopred, či pôjde a ako — aj pre zložku (napr. setup.exe a .bin súbory), CD/DVD, prenosnú hru (iba .exe) a archív .zip, .rar, .7z, .iso. V Súboroch: pravý klik › Bude to fungovať?" }
            Heading { text: "NEDÁVNO STIAHNUTÉ" }
            Text { visible: app.downloads.length === 0; text: "V priečinku Stiahnuté nie sú inštalačné súbory."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: app.downloads
                    Pill { required property string modelData; label: modelData.split("/").pop(); primaryStyle: app.checkPath === modelData; onClicked: app.check(modelData) }
                }
            }
            Rectangle {
                visible: !!app.verdict
                width: parent.width; height: vc.implicitHeight + 32; radius: 14
                color: theme.field
                border { color: !app.verdict ? theme.line : (app.verdict.verdict === "ano" ? theme.primary : (app.verdict.verdict === "nie" ? theme.error : theme.fgDim)); width: 1.5 }
                Column {
                    id: vc
                    x: 16; y: 16; width: parent.width - 32; spacing: 8
                    Text {
                        text: app.verdict ? (({ ano: "✓ Áno, bude to fungovať", podmienecne: "◐ Pravdepodobne, s podmienkou", nie: "× Zatiaľ nie" })[app.verdict.verdict] + " — " + app.verdict.title) : ""
                        color: app.verdict && app.verdict.verdict === "nie" ? theme.error : theme.fg; font { family: theme.fontUi; pixelSize: 16; weight: Font.Bold }
                    }
                    Text { text: app.verdict ? app.verdict.name : ""; color: theme.fgDim; font { family: theme.fontMono; pixelSize: 11 } }
                    Repeater {
                        model: app.verdict ? app.verdict.reasons : []
                        Text { required property string modelData; width: vc.width; wrapMode: Text.WordWrap; text: "•  " + modelData; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                    }
                    Heading { visible: !!app.verdict && (app.verdict.plan || []).length > 0; text: "AKO TO LATTEOS SPRAVÍ"; topPadding: 6 }
                    Repeater {
                        model: app.verdict ? (app.verdict.plan || []) : []
                        Row {
                            required property string modelData
                            required property int index
                            width: vc.width; spacing: 10
                            Rectangle { width: 22; height: 22; radius: 11; color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.2)
                                        Text { anchors.centerIn: parent; text: String(index + 1); color: theme.primary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } } }
                            Text { width: vc.width - 32; wrapMode: Text.WordWrap; text: modelData; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                        }
                    }
                    Text { visible: !!app.verdict && (app.verdict.plan || []).length > 0; width: vc.width; wrapMode: Text.WordWrap; topPadding: 4
                           text: "Samotnú inštaláciu do sandboxu (Proton/Wine) App Manager zatiaľ nespúšťa — najprv overujeme, či rozpozná každý typ."
                           color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                    Flow {
                        visible: !!app.verdict && (app.verdict.needs || []).length > 0
                        width: vc.width; spacing: 8
                        Repeater {
                            model: app.verdict ? (app.verdict.needs || []) : []
                            Pill { required property var modelData; label: "Doinštalovať: " + modelData.label
                                   onClicked: app.run(["latte-app", "instalator", "--nazov=" + modelData.label.replace(/ /g, "_"), "install", modelData.pkg], "Inštalátor: " + modelData.label) }
                        }
                    }
                    Pill {
                        visible: !!app.verdict && (app.verdict.action || []).length > 0 && app.verdict.verdict !== "nie"
                        label: "Inštalovať / spustiť"; primaryStyle: true
                        // argv sa odovzdá ako argumenty ("$@"), názov súboru sa nikdy nevkladá do príkazu shellu
                        onClicked: app.verdict.action[0] === "latte-app"
                                   ? app.run(app.verdict.action, "Inštalátor: " + app.verdict.name)          // grafický Inštalátor (RPM)
                                   : app.run(["foot", "-e", "sh", "-c", "\"$@\"; echo; read -p 'Enter zavrie okno…' x", "sh"].concat(app.verdict.action), "V termináli: " + app.verdict.action.join(" "))
                    }
                }
            }
        }
    }
}
