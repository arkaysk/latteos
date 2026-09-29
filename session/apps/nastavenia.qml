// LatteOS — Nastavenia. Navigácia vrstvenými kartami (old/main_setting_v2.md: päť oblastí + Systém,
// vždy otvorená jedna karta), obsah v strede, detail vpravo (návrh V2: Stav · Oblasť · Uložené v).
// Radar: „Všetko prepínačmi, žiadne editovanie súborov“. Spúšťa sa: latte-app nastavenia [stránka]
import QtQuick
import Quickshell
import Quickshell.Io
import "common"
import "data"

ShellRoot {
    id: app
    LatteTheme { id: theme }
    readonly property var th: theme
    // Pre pokročilých
    property string terminal: "foot"
    property var terminals: []
    property var envLines: []
    property string memInfo: ""
    property string remotes: ""
    FileView { path: app.cfgHome + "/latteos/terminal"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.terminal = text().trim() || "foot"; onLoadFailed: app.terminal = "foot" }
    readonly property string envFile: app.cfgHome + "/environment.d/90-latteos.conf"
    FileView { path: app.envFile; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.envLines = text().split("\n").filter(l => /^[A-Za-z_][A-Za-z0-9_]*=/.test(l)); onLoadFailed: app.envLines = [] }
    Process { id: advProc
              command: ["sh", "-c", "for t in foot kitty alacritty wezterm konsole ptyxis gnome-terminal xterm; do command -v $t >/dev/null && echo T:$t; done; "
                        + "swapon --show=NAME,TYPE,SIZE,USED --noheadings 2>/dev/null | sed 's/^/M:/'; flatpak remotes --columns=name,url 2>/dev/null | sed 's/^/R:/'"]
              stdout: StdioCollector { onStreamFinished: { const l = this.text.split("\n");
                  app.terminals = l.filter(x => x.startsWith("T:")).map(x => x.slice(2));
                  app.memInfo = l.filter(x => x.startsWith("M:")).map(x => x.slice(2).trim().replace(/\s+/g, " · ")).join("\n");
                  app.remotes = l.filter(x => x.startsWith("R:")).map(x => x.slice(2).trim().replace(/\s+/g, " · ")).join("\n"); } } }
    function saveEnv(lines) {
        run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && shift && printf '%s\\n' \"# LatteOS › Nastavenia › Pre pokročilých (platí po odhlásení)\" \"$@\" > \"$0\"",
             app.envFile, app.envFile].concat(lines), "Premenné prostredia uložené — platia po odhlásení");
    }
    property string kapsaHist: ""          // "off" = história schránky vypnutá
    property string kapsaMax: ""
    property int kapsaCount: -1
    FileView { path: app.cfgHome + "/latteos/kapsa-historia"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.kapsaHist = text().trim(); onLoadFailed: app.kapsaHist = "" }
    FileView { path: app.cfgHome + "/latteos/kapsa-max"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.kapsaMax = text().trim(); onLoadFailed: app.kapsaMax = "" }
    Process { id: kapsaCnt; command: ["sh", "-c", "cliphist list 2>/dev/null | wc -l"]
              stdout: StdioCollector { onStreamFinished: app.kapsaCount = parseInt(this.text) || 0 } }
    property string snapOff: ""
    property string snapBarOff: ""
    FileView { path: app.cfgHome + "/latteos/bez-prichytenia"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.snapOff = "off"; onLoadFailed: app.snapOff = "" }
    FileView { path: app.cfgHome + "/latteos/bez-listy-rozlozeni"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.snapBarOff = "off"; onLoadFailed: app.snapBarOff = "" }
    property string zoomPick: "1"          // Prístupnosť › Lupa (Win+Plus/Mínus mení aj mimo Nastavení)
    property string pozadieTab: ""       // "" = moja knižnica, "online" = katalógy tapiet (bývalá stránka Tapety online)
    property bool ulRozsirene: false     // Úložisko: rozbaliť Rozšírené (disky a oddiely) — pri príchode z „disky“             // pre vložené komponenty s vlastnou vlastnosťou theme (theme: theme by ukazovalo na seba)
    readonly property var latteTheme: theme      // pre vnorené prvky s vlastnou vlastnosťou „theme“ (IconButton)

    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string cfgHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    property string section: (Quickshell.env("LATTE_APP_ARGS") || "").trim() || "domov"
    property var history: []
    property int historyIndex: -1
    property string search: ""
    onSearchChanged: Qt.callLater(() => { if (search !== "" && side.areas.length && !side.areas.some(a => a.key === side.openArea)) side.openArea = side.areas[0].key; })
    property string status: ""

    // ── stav LatteOS ─────────────────────────────────────────────────────────────
    property var mode: ({})
    property string tierChoice: "auto"
    property string windowMode: "paska"
    property bool forceSafe: false
    property int crashCount: 0
    property var themes: []
    property var wallpapers: []
    property string greeter: "latte"
    property string modePref: "tema"
    property var bar: ({})            // prepisy [bar.main] z ~/.local/state/noctalia/settings.toml
    property var location: ({})       // prepisy [location]
    property var notif: ({})          // prepisy [notification]
    property var access: ({})         // prepisy [accessibility]
    property string fullName: ""
    property var clouds: []           // latte-cloud list
    property var accounts: []         // [{ name, full, admin, me }]
    property string newUser: ""
    property var backup: ({})        // latte-backup status
    property var backupDrives: []
    property var backupList: []
    property int backupPct: -1
    property var locales: []          // nainštalované (locale -a)
    property var localeConf: ({})     // ~/.config/latteos/locale
    property var avatarChoices: []
    property int avatarRev: 0          // obnovenie náhľadu po zmene
    property var idle: ({})           // [idle.behavior.*] → { lock: {enabled, timeout}, … }
    property var shellAnim: ({})      // prepisy [shell.animation]
    property bool noAnim: false
    property string cursorSize: "24"
    property bool dnd: false
    property var greeterConf: ({ background: "/usr/share/backgrounds/latteos/latteos-wallpaper1.jpg", color: "#1B1410", dim: "0.55", panel: "log", panel_title: "", panel_text: "",
                                 rss_url: "https://www.aktuality.sk/rss/", lat: "48.74", lon: "19.15", place: "Banská Bystrica" })
    property string crashLog: ""
    property var ai: ({})             // latte-ai status
    property var aiModels: []
    property string aiAnswer: ""
    property var clockZones: []
    property string about: ""
    property string storage: ""
    property string mascot: "macka"
    property string barAnim: ""        // prázdne = podľa stupňa (VM: pod kurzorom)
    property string ctrlProfile: "windows"   // profil ovládania (latte/skratky.lua): windows | linux | mac
    property string numlockPref: ""          // "" = podľa typu počítača, on, off
    property string suboryTahanie: ""        // ľavé ťahanie v Súboroch: "" (ako Windows) | copy | ask
    property bool skloPref: true             // softvérové sklo pod panelmi (common/Sklo.qml)
    property string mascotEscape: ""   // "off" = maskot neuteká
    property string mascotMode: ""     // off | slot | world | chaos (plugin latteos/cat); "" = podľa mascot-escape
    property string cupQuick: ""       // prázdne = šálka ukazuje stupeň a režim okien, "off" = skryté
    property string deskIcons: ""      // prázdne = ikony na ploche s košom, "off" = bez ikon
    property string barScene: "para"
    property string barSceneRight: ""      // vlastná textúra pravého L (prázdne = ako vľavo)
    property real barDim: 0.55
    property string barZoom: ""            // "" = priblížiť GIF na pohyb, "off" = celý obrázok (bar-priblizenie)
    property bool wsWallpaper: false
    property string liveWp: ""

    // ── strom Nastavení (kanonický, main_setting_v2.md §58) ──────────────────────
    // status: ready = funguje · partial = časť · planned = zatiaľ len plán
    readonly property var areas: [
        { key: "softver", title: "Softvér", glyph: "apps", summary: "AI: " + (ai.ok === "1" ? (ai.model || "pripravené") : "nenastavené"), owner: "App Manager",
          pages: [
            { key: "aplikacie", label: "Aplikácie", glyph: "apps", status: "ready" },
            { key: "predvolene", label: "Predvolené aplikácie", glyph: "star", status: "ready" },
            { key: "instalacia", label: "Inštalácia aplikácií", glyph: "download", status: "ready" },
            { key: "aktualizacie", label: "Aktualizácie", glyph: "refresh", status: "ready" },
            { key: "ai", label: "AI", glyph: "sparkles", status: "ready" },
            { key: "spustanie", label: "Spúšťanie a na pozadí", glyph: "player-play", status: "ready" },
            { key: "sukromie", label: "Súkromie a NET", glyph: "world", status: "ready" } ] },
        { key: "data", title: "Dáta", glyph: "folder", summary: "Súbory · farebné štítky", owner: "Data Manager",
          pages: [
            { key: "subory", label: "Súbory a priečinky", glyph: "folder", status: "ready" },
            { key: "ulozisko", label: "Úložisko", glyph: "database", status: "partial" },
            { key: "zalohy", label: "Zálohovanie a obnova", glyph: "history", status: "ready" },
            { key: "synchronizacia", label: "Cloud a synchronizácia", glyph: "cloud", status: "ready" } ] },
        { key: "hardver", title: "Hardvér", glyph: "cpu", summary: (mode.renderer || "?") + " · stupeň " + (mode.tier || "?"), owner: "Device Manager",
          pages: [
            { key: "vykon", label: "Výkon a grafika", glyph: "bolt", status: "ready" },
            { key: "hry", label: "Hry a herný režim", glyph: "device-gamepad", status: "ready" },
            { key: "obrazovky", label: "Obrazovky", glyph: "device-desktop", status: "ready" },
            { key: "zvuk", label: "Zvuk", glyph: "volume", status: "ready" },
            { key: "siet", label: "Sieť", glyph: "wifi", status: "ready" },
            { key: "bluetooth", label: "Bluetooth a periférie", glyph: "bluetooth", status: "ready" },
            { key: "vstup", label: "Myš, touchpad a ovládače", glyph: "mouse", status: "ready" },
            { key: "tlac", label: "Tlač a skenovanie", glyph: "printer", status: "partial" },
            { key: "napajanie", label: "Napájanie", glyph: "battery", status: "ready" },
            { key: "diagnostika", label: "Diagnostika a pády", glyph: "stethoscope", status: "partial" } ] },
        { key: "ucet", title: "Účet", glyph: "user", summary: user, owner: "Session Manager",
          pages: [
            { key: "mojucet", label: "Môj účet", glyph: "user", status: "ready" },
            { key: "heslo", label: "Heslo a zabezpečenie", glyph: "key", status: "ready" },
            { key: "pouzivatelia", label: "Používatelia", glyph: "users", status: "ready" },
            { key: "prihlasovanie", label: "Prihlasovanie", glyph: "login", status: "ready" },
            { key: "uzamknutie", label: "Uzamknutie a nečinnosť", glyph: "lock", status: "ready" } ] },
        { key: "prostredie", title: "Prostredie", glyph: "palette", summary: theme.themeName + " · " + modeName(modePref), owner: "Prispôsobenie",
          pages: [
            { key: "motiv", label: "Motív a farby", glyph: "palette", status: "ready" },
            { key: "pismo", label: "Písmo a mierka", glyph: "typography", status: "ready" },
            { key: "pozadie", label: "Pozadie", glyph: "photo", status: "ready" },
            { key: "okna", label: "Okná", glyph: "layout-columns", status: "ready" },
            { key: "lista", label: "Lišta a systémové menu", glyph: "layout-bottombar", status: "ready" },
            { key: "oznamenia", label: "Oznámenia", glyph: "bell", status: "ready" },
            { key: "efekty", label: "Animácie a efekty", glyph: "sparkles", status: "ready" },
            { key: "pristupnost", label: "Prístupnosť", glyph: "accessible", status: "ready" } ] },
        { key: "system", title: "Systém", glyph: "shield", summary: (mode.mode || "?").toUpperCase() + " · pády " + crashCount, owner: "LatteOS",
          pages: [
            { key: "start", label: "Štart a režim", glyph: "shield", status: "ready" },
            { key: "cas", label: "Dátum, čas a poloha", glyph: "clock", status: "ready" },
            { key: "jazyk", label: "Jazyk a región", glyph: "language", status: "ready" },
            { key: "klavesnica", label: "Klávesnica a skratky", glyph: "keyboard", status: "ready" },
            { key: "bezpecnost", label: "Bezpečnosť", glyph: "shield-lock", status: "ready" },
            { key: "zdielanie", label: "Zdieľanie", glyph: "share", status: "partial" },
            { key: "schranka", label: "Schránka (Kapsa)", glyph: "clipboard", status: "ready" },
            { key: "pokrocile", label: "Pre pokročilých", glyph: "terminal-2", status: "ready" },
            { key: "o", label: "O LatteOS", glyph: "info-circle", status: "ready" } ] }
    ]
    readonly property var allPages: {
        const out = [{ key: "domov", label: "Domov", glyph: "home", status: "ready", area: "", areaTitle: "Prehľad", owner: "LatteOS" }];
        for (const a of areas) for (const p of a.pages) out.push(Object.assign({ area: a.key, areaTitle: a.title, owner: a.owner }, p));
        return out;
    }
    readonly property var current: allPages.find(p => p.key === section) || allPages[0]

    function go(key, push) {
        if (key === "zariadenia") key = "vykon";        // staré odkazy
        // zlúčené stránky (alfatest 2, duplicity): disky sú v Úložisku › Rozšírené, tapety online sú karta Pozadia
        if (key === "disky") { key = "ulozisko"; app.ulRozsirene = true; }
        if (key === "tapetyonline") { key = "pozadie"; app.pozadieTab = "online"; }
        else if (key === "pozadie" && push !== false) app.pozadieTab = "";
        if (key === "vzhlad") key = "motiv";
        section = key;
        const p = allPages.find(x => x.key === key);
        if (p && p.area) side.openArea = p.area;
        if (push !== false) { history = history.slice(0, historyIndex + 1).concat([key]); historyIndex = history.length - 1; }
        if (key === "ai") { aiStatus.running = true; aiList.running = true; }
        if (key === "o") aboutProc.running = true;
        dalsie.opened(key);
        if (key === "oznamenia") dndProc.running = true;
        if (key === "mojucet") accountProc.running = true;
        if (key === "jazyk") localeProc.running = true;
        if (key === "pouzivatelia") usersProc.running = true;
        if (key === "synchronizacia") cloudProc.running = true;
        if (key === "zalohy" || key === "domov") backupProc.running = true;
        if (key === "domov") { netProc.running = true; cloudProc.running = true; }
        if (key === "ulozisko" || key === "domov") storageProc.running = true;
    }
    Component.onCompleted: { go(section); aiStatus.running = true; }

    function modeName(m) { return ({ tema: "podľa témy", dark: "tmavý", light: "svetlý", auto: "automaticky" })[m] || m; }

    // ── načítanie stavu ─────────────────────────────────────────────────────────
    FileView {
        path: "/run/latteos/mode.toml"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: {
            const m = {};
            for (const l of text().split("\n")) { const r = l.match(/^(\w+) = "?([^"]*)"?$/); if (r && !(r[1] in m)) m[r[1]] = r[2]; }
            app.mode = m;
        }
    }
    FileView { path: app.cfgHome + "/latteos/tier"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.tierChoice = text().trim() || "auto"; onLoadFailed: app.tierChoice = "auto" }
    FileView { path: app.cfgHome + "/latteos/theme-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.modePref = text().trim() || "tema"; onLoadFailed: app.modePref = "tema" }
    FileView { path: app.stateHome + "/latteos/window-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.windowMode = text().trim() || "paska" }
    FileView { path: "/var/lib/latteos/crash-count"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.crashCount = parseInt(text()) || 0 }
    FileView { path: "/etc/latteos/boot.toml"; printErrors: false
               onLoaded: { const r = text().match(/^greeter = "(\w+)"/m); app.greeter = r ? r[1] : "latte"; } }
    FileView { path: "/var/lib/latteos/greeter/last-crash.log"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.crashLog = text().trim(); onLoadFailed: app.crashLog = "" }
    FileView {
        id: greeterFile
        path: "/var/lib/latteos/greeter/greeter.conf"; printErrors: false
        onLoaded: {
            const c = Object.assign({}, app.greeterConf);
            for (const l of text().split("\n")) { const r = l.match(/^\s*(\w+)\s*=\s*"(.*)"\s*$/); if (r) c[r[1]] = r[2].replace(/\\n/g, "\n"); }
            app.greeterConf = c;
        }
    }
    function setGreeter(k, v) {
        const c = Object.assign({}, greeterConf); c[k] = v; greeterConf = c;
        let out = "# LatteOS — vzhľad obrazovky prihlásenia (zapísali Nastavenia › Účet › Prihlasovanie)\n";
        for (const key of ["background", "color", "dim", "panel", "panel_title", "panel_text", "rss_url", "lat", "lon", "place"])
            out += key + " = \"" + String(c[key] || "").replace(/"/g, "'").replace(/\n/g, "\\n") + "\"\n";
        greeterFile.setText(out);
        status = "Obrazovka prihlásenia uložená (prejaví sa pri ďalšom prihlásení)";
    }
    FileView {
        path: app.stateHome + "/noctalia/settings.toml"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: {
            const t = {}; let sec = "";
            for (const l of text().split("\n")) {
                const h = l.match(/^\s*\[([^\]]+)\]\s*$/); if (h) { sec = h[1]; continue; }
                const r = l.match(/^\s*(\w+)\s*=\s*"?([^"]*)"?\s*$/); if (r) { (t[sec] = t[sec] || {})[r[1]] = r[2]; }
            }
            app.bar = t["bar.main"] || {}; app.location = t["location"] || {}; app.notif = t["notification"] || {}; app.access = t["accessibility"] || {};
            app.idle = { lock: t["idle.behavior.lock"] || {}, screen: t["idle.behavior.screen-off"] || {}, suspend: t["idle.behavior.lock-and-suspend"] || {} }; app.shellAnim = t["shell.animation"] || {};
        }
    }
    FileView {
        id: clockFile
        path: app.cfgHome + "/latteos/clock.conf"; printErrors: false
        onLoaded: { const r = text().match(/^zones = "(.*)"/m); app.clockZones = r && r[1] ? r[1].split(",") : []; }
    }
    FileView { path: app.cfgHome + "/latteos/mascot"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.mascot = text().trim() || "homebrew"; onLoadFailed: app.mascot = "homebrew" }
    FileView { path: app.cfgHome + "/latteos/profil-ovladania"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.ctrlProfile = (["linux", "mac"].indexOf(text().trim()) >= 0) ? text().trim() : "windows"; onLoadFailed: app.ctrlProfile = "windows" }
    FileView { path: app.cfgHome + "/latteos/sklo"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.skloPref = text().trim() !== "off"; onLoadFailed: app.skloPref = true }
    FileView { path: app.cfgHome + "/latteos/subory-tahanie"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.suboryTahanie = text().trim(); onLoadFailed: app.suboryTahanie = "" }
    FileView { path: app.cfgHome + "/latteos/numlock"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.numlockPref = text().trim(); onLoadFailed: app.numlockPref = "" }
    // zápis voľby a hneď hyprctl reload (skratky, fokus a Num Lock platia bez odhlásenia)
    function writePrefReload(name, value, msg) {
        if (value === "") run(["sh", "-c", "rm -f \"$1\"; hyprctl reload", "sh", app.cfgHome + "/latteos/" + name], msg);
        else run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\" && hyprctl reload", "sh", app.cfgHome + "/latteos/" + name, value], msg);
    }
    readonly property var shortcutSets: ({
        windows: [["Alt + Tab", "Prepínanie okien (drž Alt)"], ["Alt + F4", "Zavrieť okno (na ploche: Vypnúť)"], ["Ctrl + Alt + Del", "Zamknúť, odhlásiť, Správca úloh"],
                  ["Win  alebo  Ctrl + Esc", "Štart (App Manager)"], ["Win + E", "Súbory"], ["Win + I", "Nastavenia"], ["Win + S / Win + R", "Hľadať a spustiť (Text Bar)"],
                  ["Win + X", "Ponuka pre pokročilých (aj pravý klik na dlaždicu aplikácií)"], ["Win + A", "Rýchle nastavenia (Zariadenia)"], ["Win + N", "Oznámenia a kalendár"],
                  ["Win + V", "História schránky (Kapsa)"], ["Win + .", "Emoji"], ["Win + Shift + S  /  PrtSc", "Výstrižok oblasti"], ["Win + PrtSc", "Snímka celej obrazovky do Obrázkov"],
                  ["Shift + PrtSc", "Snímka s kreslením"], ["Win + Alt + R / Win + Shift + R", "Nahrávanie obrazovky / oblasti (znova = stop)"], ["Win + D", "Plocha (a späť)"], ["Win + M / Win + Shift + M", "Minimalizovať všetko / vrátiť"], ["Win + Home", "Minimalizovať ostatné"],
                  ["Win + ↑ / ↓", "Maximalizovať / obnoviť, minimalizovať"], ["Win + ← / →", "Prichytiť k polovici (plávajúce okná)"], ["Win + Z", "Rozloženia okna"],
                  ["Win + Tab", "Prehľad okien"], ["Win + Ctrl + D / ← → / F4", "Nová plocha / prepnúť / zavrieť"], ["Win + 1…9", "N-té okno na lište"],
                  ["Win + Shift + ← / →", "Okno na iný monitor"], ["Win + L", "Zamknúť"], ["Win + P", "Monitory"], ["Win + Plus / Mínus / Esc", "Lupa"],
                  ["Win + C", "AI rozhovor"], ["Win + G", "Herňa"], ["Alt + Medzerník", "Ponuka okna (aj pravý klik na titulok)"], ["Ctrl + Shift + Esc", "Správca úloh (Monitor)"],
                  ["Alt + Shift", "Rozloženie klávesnice sk / us"]],
        linux: [["Super", "Spúšťač aplikácií"], ["Super + Medzerník / Alt + F2", "Text Bar"], ["Super + Enter / Ctrl + Alt + T", "Terminál"], ["Super + Q", "Zavrieť okno"],
                ["Alt + Tab", "Prepínanie okien"], ["Super + Tab", "Prehľad pásky"], ["Super + šípky", "Fokus (v páske stĺpce)"], ["Super + Ctrl + šípky", "Presun okna"],
                ["Super + 1…9 / Shift", "Plocha / okno na plochu"], ["Ctrl + Alt + ← / →", "Predošlá / ďalšia plocha"], ["Super + F", "Celá obrazovka"], ["Super + V", "Plávajúce okno"],
                ["Super + W", "Režim okien"], ["Super + N / Shift + N", "Minimalizovať / ukázať minimalizované"], ["Super + D", "Plocha"], ["Super + A", "Zariadenia"],
                ["Super + I", "AI rozhovor"], ["PrtSc / Super + Shift + S", "Snímka oblasti"], ["Super + ťahanie ľavým / pravým", "Presun / veľkosť okna"],
                ["Stredný klik", "Vloží označený text"], ["Ctrl + Alt + Del", "Zamknúť, odhlásiť, Správca úloh"], ["Super + L", "Zamknúť"]],
        mac: [["Cmd + Medzerník", "Text Bar (Spotlight)"], ["Cmd + Tab / Cmd + `", "Prepínanie okien"], ["Cmd + Q / Cmd + W", "Zavrieť okno"], ["Cmd + M / Cmd + H", "Minimalizovať"],
              ["Cmd + Option + H", "Minimalizovať ostatné"], ["Cmd + Shift + 3 / 4 / 5", "Snímka: celá / oblasť / s kreslením"], ["Cmd + Ctrl + Q", "Zamknúť"],
              ["Cmd + Option + Esc", "Správca úloh (vynútiť ukončenie)"], ["Cmd + Ctrl + Medzerník", "Emoji"], ["Cmd + Ctrl + F", "Celá obrazovka"], ["Cmd + ,", "Nastavenia"],
              ["Cmd + Ctrl + ↑ / ← →", "Prehľad / plochy"], ["Cmd + D", "Plocha"], ["Cmd + V", "História schránky (Kapsa)"],
              ["Cmd + C / V v aplikáciách", "zatiaľ Ctrl + C / V (premapovanie Cmd pripravujeme)"]]
    })
    FileView { path: app.cfgHome + "/latteos/bar-anim"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.barAnim = text().trim(); onLoadFailed: app.barAnim = "" }
    FileView { path: app.cfgHome + "/latteos/desktop-icons"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.deskIcons = text().trim(); onLoadFailed: app.deskIcons = "" }
    FileView { path: app.cfgHome + "/latteos/mascot-escape"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.mascotEscape = text().trim(); onLoadFailed: app.mascotEscape = "" }
    FileView { path: app.cfgHome + "/latteos/mascot-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.mascotMode = text().trim(); onLoadFailed: app.mascotMode = "" }
    FileView { path: app.cfgHome + "/latteos/cup-quick"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.cupQuick = text().trim(); onLoadFailed: app.cupQuick = "" }
    FileView { path: app.cfgHome + "/latteos/bar-scene"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.barScene = text().trim() || "para"; onLoadFailed: app.barScene = "para" }
    FileView { path: app.cfgHome + "/latteos/bar-priblizenie"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.barZoom = text().trim(); onLoadFailed: app.barZoom = "" }
    FileView { path: app.cfgHome + "/latteos/bar-scene-vpravo"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.barSceneRight = text().trim(); onLoadFailed: app.barSceneRight = "" }
    FileView { path: app.cfgHome + "/latteos/bar-stlmenie"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: { const v = parseFloat(text()); app.barDim = isNaN(v) ? 0.55 : v; }
               onLoadFailed: app.barDim = 0.55 }
    FileView { path: app.cfgHome + "/latteos/wallpaper-per-workspace"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.wsWallpaper = true; onLoadFailed: app.wsWallpaper = false }
    FileView { path: app.cfgHome + "/latteos/no-animations"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.noAnim = true; onLoadFailed: app.noAnim = false }
    FileView { path: app.cfgHome + "/latteos/cursor-size"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.cursorSize = text().trim() || "24"; onLoadFailed: app.cursorSize = "24" }
    // nečinnosť: Noctalia prepíše celé správanie, preto sa vždy zapíše enabled + timeout + action
    function setIdle(name, action, minutes, msg) {
        const k = "idle.behavior." + name + ".";
        run(["sh", "-c", "latte-shellset set \"$1enabled\" \"$2\" && latte-shellset set \"$1timeout\" \"$3\" && latte-shellset set \"$1action\" \"$4\"",
             "sh", k, minutes > 0 ? "true" : "false", String(Math.max(60, minutes * 60)), action], msg);
    }
    function idleMin(b) { return b && b.enabled === "true" ? Math.round((parseFloat(b.timeout) || 0) / 60) : 0; }
    function setNoAnim(on) {
        app.noAnim = on;
        app.writePref("no-animations", on ? "1" : "", on ? "Animácie vypnuté" : "Animácie podľa stupňa výkonu");
        shellSet("shell.animation.enabled", on ? false : null);
        run(["sh", "-c", "sleep 0.3; hyprctl reload"]);
    }
    FileView { path: app.cfgHome + "/latteos/live-wallpaper"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: app.liveWp = text().trim() || "tema"; onLoadFailed: app.liveWp = "" }
    function setLive(v) {
        liveWp = v;
        writePref("live-wallpaper", v, v === "" ? "Živá tapeta vypnutá" : "Živá tapeta: " + v);
        if (v === "") run(["pkill", "-f", "latteos/apps/[z]ivatapeta.qml"]);   // [z]: vzor nenájde sám seba
        else run(["sh", "-c", "pgrep -f latteos/apps/[z]ivatapeta.qml >/dev/null || setsid latte-app zivatapeta >/dev/null 2>&1 &"]);
    }
    function writePref(name, value, msg) {
        if (value === "") run(["rm", "-f", app.cfgHome + "/latteos/" + name], msg);
        else run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"", "sh", app.cfgHome + "/latteos/" + name, value], msg);
    }
    function toggleZone(z) {
        const zs = clockZones.indexOf(z) >= 0 ? clockZones.filter(x => x !== z) : clockZones.concat([z]);
        clockZones = zs;
        clockFile.setText("# LatteOS — ďalšie časové pásma v paneli Čas (Nastavenia › Systém › Dátum a čas)\nzones = \"" + zs.join(",") + "\"\n");
    }

    component Cmd: Process {
        id: c
        signal done(string out)
        stdout: StdioCollector { onStreamFinished: c.done(this.text) }
    }
    Cmd {
        id: scan; running: true
        command: ["sh", "-c", "test -e /var/lib/latteos/force-safe && echo FORCE; for f in /usr/share/latteos/themes/*.theme; do printf 'T %s|%s|%s\\n' \"$(basename $f .theme)\" \"$(sed -n 's/^name = //p' $f)\" \"$(sed -n 's/^desc = //p' $f)\"; done; for f in /usr/share/backgrounds/latteos/*; do echo \"W $f\"; done"]
        onDone: (out) => {
            const th = [], wp = []; let fs = false;
            for (const l of out.split("\n")) {
                if (l === "FORCE") fs = true;
                else if (l.startsWith("T ")) { const p = l.slice(2).split("|"); th.push({ id: p[0], name: p[1], desc: p[2] }); }
                else if (l.startsWith("W ")) wp.push(l.slice(2));
            }
            app.forceSafe = fs; app.themes = th; app.wallpapers = wp;
        }
    }
    Timer { interval: 4000; repeat: true; running: true; onTriggered: scan.running = true }
    Cmd {
        id: aiStatus; command: ["latte-ai", "status"]
        onDone: (out) => { const s = {}; for (const l of out.split("\n")) { const i = l.indexOf("="); if (i > 0) s[l.slice(0, i)] = l.slice(i + 1); } app.ai = s; }
    }
    Cmd {
        id: aiList; command: ["latte-ai", "models"]
        onDone: (out) => app.aiModels = out.split("\n").filter(l => l !== "").map(l => { const p = l.split("\t"); return { id: p[0], state: p[1] || "" }; })
    }
    Cmd {
        id: aiAsk; command: ["latte-ai", "ask", "Predstav sa jednou krátkou vetou po slovensky."]
        onDone: (out) => app.aiAnswer = out.trim() || "(bez odpovede — pozri stav vpravo)"
    }
    Cmd {
        id: accountProc
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1; ls /usr/share/latteos/noctalia/plugins/cat/mascots/*-sedi.png 2>/dev/null; ls -t \"$HOME\"/Obrázky/*.png \"$HOME\"/Obrázky/*.jpg \"$HOME\"/Pictures/*.png \"$HOME\"/Pictures/*.jpg 2>/dev/null | head -8"]
        onDone: (out) => { const l = out.split("\n"); app.fullName = l[0] || ""; app.avatarChoices = l.slice(1).filter(x => x !== ""); }
    }
    function setAvatar(src) {
        const dst = "/var/lib/latteos/greeter/avatars/" + app.user + ".png";
        if (src === "") run(["sh", "-c", "rm -f \"$1\" \"$HOME/.face\"", "sh", dst], "Obrázok účtu odstránený");
        else run(["sh", "-c", "cp -f \"$1\" \"$2\" && chmod 664 \"$2\" && cp -f \"$1\" \"$HOME/.face\"", "sh", src, dst], "Obrázok účtu nastavený");
        avatarTick.restart();
    }
    Timer { id: avatarTick; interval: 500; onTriggered: app.avatarRev++ }
    Cmd {
        id: backupProc; command: ["latte-backup", "status"]
        onDone: (out) => {
            const b = {}, dr = [];
            for (const l of out.split("\n")) { const i = l.indexOf("="); if (i < 0) continue; const k = l.slice(0, i), v = l.slice(i + 1); if (k === "drive") dr.push(v.split("|")); else b[k] = v; }
            app.backup = b; app.backupDrives = dr;
            if (b.target) backupListProc.running = true;
        }
    }
    Cmd { id: backupListProc; command: ["latte-backup", "list"]; onDone: (out) => app.backupList = out.split("\n").filter(l => l !== "") }
    Process {
        id: backupRun
        command: ["latte-backup", "run"]
        stdout: SplitParser { onRead: (line) => { const m = line.match(/^pct=(\d+)/); if (m) app.backupPct = parseInt(m[1]); const e = line.match(/^error=(.*)/); if (e) app.status = e[1]; } }
        onExited: (code) => { app.backupPct = -1; if (code === 0) app.status = "Záloha hotová"; backupProc.running = true; }
    }
    Cmd {
        id: usersProc
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1\"|\"$5}'; echo '#wheel'; getent group wheel | cut -d: -f4"]
        onDone: (out) => {
            const [list, wheel] = out.split("#wheel");
            const admins = (wheel || "").trim().split(",");
            app.accounts = list.split("\n").filter(l => l).map(l => { const p = l.split("|"); return { name: p[0], full: (p[1] || "").split(",")[0], admin: admins.indexOf(p[0]) >= 0, me: p[0] === app.user }; });
        }
    }
    function term(cmd, msg) { run(["foot", "-e", "sh", "-c", cmd + "; echo; read -p 'Enter zavrie okno…' x"], msg); usersRefresh.restart(); }
    Timer { id: usersRefresh; interval: 15000; onTriggered: usersProc.running = true }
    Cmd { id: cloudProc; command: ["latte-cloud", "list"]
          onDone: (out) => app.clouds = out.split("\n").filter(l => l.includes("|")).map(l => { const p = l.split("|"); return { name: p[0], type: p[1], mounted: p[2] === "1", auto: p[3] === "1" }; }) }
    Timer { id: cloudRefresh; interval: 1500; onTriggered: cloudProc.running = true }
    property string netState: ""
    Cmd { id: netProc; command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | grep ':connected:\\|:pripojené:' | head -1"]
          onDone: (out) => { const p = out.trim().split(":"); app.netState = p.length >= 3 ? ({ ethernet: "Kábel", wifi: "Wi-Fi" })[p[0]] + " · " + p.slice(2).join(":") : "Bez pripojenia"; } }
    // upozornenia pre Domov (old/main_setting_v2.md §5: dôležité upozornenia na jednom mieste)
    readonly property var warnings: {
        const w = [];
        if ((mode.mode || "") === "safe") w.push(["shield", "Beží režim SAFE", mode.reason || "grafika bez GPU", "start"]);
        if (crashCount > 0) w.push(["alert-triangle", "Relácia NORMAL spadla " + crashCount + "×", "pri 2 pádoch naštartuje SAFE", "diagnostika"]);
        const root = (storage.split("\n").find(l => l.trim().startsWith("/ ")) || "").trim().split(/\s+/);
        if (root.length >= 5 && parseInt(root[4]) >= 90) w.push(["database", "Systémový disk je plný na " + root[4], "uprac v Súboroch alebo Monitore", "ulozisko"]);
        if (!backup.target) w.push(["history", "Zálohy nie sú nastavené", "pripoj USB disk a zapni zálohu", "zalohy"]);
        else if (!backup.last) w.push(["history", "Ešte žiadna záloha", "Zálohovať teraz", "zalohy"]);
        if (ai.ok === "0" && ai.disabled !== "1") w.push(["robot-off", "AI teraz neodpovedá", ai.target || "", "ai"]);
        return w;
    }
    Cmd { id: localeProc; command: ["sh", "-c", "locale -a"]; onDone: (out) => app.locales = out.split("\n").map(l => l.toLowerCase()) }
    FileView {
        id: localeFile
        path: app.cfgHome + "/latteos/locale"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { const c = {}; for (const l of text().split("\n")) { const r = l.match(/^(\w+)=(.*)$/); if (r) c[r[1]] = r[2]; } app.localeConf = c; }
        onLoadFailed: app.localeConf = ({})
    }
    function hasLocale(code) { return locales.indexOf(code.toLowerCase().replace("utf-8", "utf8")) >= 0; }
    function setLocale(key, code) {
        const c = Object.assign({}, localeConf); if (code) c[key] = code; else delete c[key]; localeConf = c;
        let out = "# LatteOS — jazyk a formáty (Nastavenia › Systém › Jazyk a región); platí po novom prihlásení\n";
        for (const k of Object.keys(c)) out += k + "=" + c[k] + "\n";
        localeFile.setText(out);
        status = "Uložené — platí po odhlásení a prihlásení";
    }
    Cmd { id: dndProc; command: ["noctalia", "msg", "notification-dnd-status"]; onDone: (out) => app.dnd = out.trim() === "on" }
    Cmd {
        id: aboutProc
        command: ["sh", "-c", ". /etc/os-release; echo \"Systém|$PRETTY_NAME\"; echo \"Jadro|$(uname -r)\"; echo \"Hyprland|$(rpm -q --qf '%{VERSION}-%{RELEASE}' hyprland 2>/dev/null)\"; echo \"Noctalia|$(noctalia --version 2>/dev/null | head -1)\"; echo \"Quickshell|$(qs --version 2>/dev/null | head -1)\"; echo \"Procesor|$(sed -n 's/^model name[^:]*: //p' /proc/cpuinfo | head -1)\"; echo \"Pamäť|$(free -h | awk '/^Mem/{print $2}')\""]
        onDone: (out) => app.about = out
    }
    Cmd {
        id: storageProc
        command: ["sh", "-c", "df -h --output=target,size,used,avail,pcent -x tmpfs -x devtmpfs -x efivarfs -x squashfs | tail -n +2"]
        onDone: (out) => app.storage = out
    }

    Process { id: runner }
    function run(cmd, msg) { runner.command = cmd; runner.running = true; if (msg) app.status = msg; }
    function setTier(t) {
        if (t === "auto") run(["sh", "-c", "rm -f \"$1\" && hyprctl reload", "sh", app.cfgHome + "/latteos/tier"], "Stupeň: automaticky");
        else run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\" && hyprctl reload", "sh", app.cfgHome + "/latteos/tier", t], "Stupeň: " + t);
        app.tierChoice = t;
    }
    function shellSet(key, value, msg) {
        if (value === null) run(["latte-shellset", "unset", key], msg);
        else run(["latte-shellset", "set", key, String(value)], msg);
    }
    function aiSet(key, value) { run(["sh", "-c", "latte-ai set \"$1\" \"$2\"", "sh", key, value], "AI: " + key + " = " + (value || "automaticky")); aiRefresh.restart(); }
    Timer { id: aiRefresh; interval: 400; onTriggered: { aiStatus.running = true; aiList.running = true; } }

    // ── okno ─────────────────────────────────────────────────────────────────────
    FloatingWindow {
        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: "Nastavenia — LatteOS"
        implicitWidth: 1220; implicitHeight: 780
        color: theme.glass ? "transparent" : theme.surface
        // pri skle je priehľadný iba bočný panel; obsah vpravo má plné pozadie
        Rectangle { visible: theme.glass; anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom } color: theme.surface }

        CardStack {
            id: side
            theme: theme
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            areas: app.search === "" ? app.areas
                 : app.areas.map(a => Object.assign({}, a, { pages: a.pages.filter(p => (p.label + " " + a.title).toLowerCase().includes(app.search.toLowerCase())) }))
                            .filter(a => a.pages.length > 0)
            current: app.section
            animMs: app.noAnim ? 0 : 200
            onActivated: (area, page) => app.go(page)
            onHomeRequested: app.go("domov")
            onContextRequested: (area, page, label, x, y) => ctx.open(x, y, [
                { glyph: "external-link", label: "Otvoriť", action: () => app.go(page) },
                { glyph: "device-desktop", label: "Skratka na ploche", action: () => app.run(["sh", "-c",
                    'd=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Plocha"); f="$d/latteos-nastavenia-$1.desktop"; mkdir -p "$d"; '
                    + 'printf "[Desktop Entry]\\nType=Application\\nName=Nastavenia · %s\\nIcon=preferences-system\\nExec=latte-app nastavenia %s\\n" "$2" "$1" > "$f"; chmod +x "$f"', "sh", page, label], "Skratka na ploche: " + label) },
                { glyph: "clipboard", label: "Kopírovať príkaz", hint: "latte-app nastavenia " + page, action: () => app.run(["wl-copy", "--", "latte-app nastavenia " + page], "Skopírované") }
            ], label)
        }
        // bočné tlačidlá myši Späť / Dopredu (ako Nastavenia vo Windows); ostatné tlačidlá idú ďalej
        MouseArea {
            anchors.fill: parent; z: 2900
            acceptedButtons: Qt.BackButton | Qt.ForwardButton
            onPressed: (m) => {
                if (m.button === Qt.BackButton && app.historyIndex > 0) { app.historyIndex--; app.go(app.history[app.historyIndex], false); }
                else if (m.button === Qt.ForwardButton && app.historyIndex < app.history.length - 1) { app.historyIndex++; app.go(app.history[app.historyIndex], false); }
            }
        }
        ContextMenu { id: ctx; theme: theme; z: 3000 }

        HeaderBar {
            id: header
            theme: theme
            appId: "latteos-nastavenia"
            anchors { left: side.right; right: parent.right; top: parent.top }
            title: (app.current.areaTitle ? app.current.areaTitle + " › " : "") + app.current.label
            canBack: app.historyIndex > 0
            canForward: app.historyIndex < app.history.length - 1
            searchPlaceholder: "Hľadať nastavenie"
            onBack: { app.historyIndex--; app.go(app.history[app.historyIndex], false); }
            onForward: { app.historyIndex++; app.go(app.history[app.historyIndex], false); }
            onSearchChanged: (t) => {
                app.search = t;
                const hit = app.allPages.find(p => t !== "" && p.label.toLowerCase().includes(t.toLowerCase()));
                if (hit && hit.area) side.openArea = hit.area;
            }
            onCloseRequested: Qt.quit()
        }

        Flickable {
            id: content
            ScrollHint { flick: content; colors: theme }
            anchors { left: side.right; top: header.bottom; bottom: parent.bottom; right: detail.left; margins: 24 }
            contentHeight: body.implicitHeight + 24; clip: true
            Column {
                id: body
                width: content.width
                spacing: 16
                Text { text: app.current.label; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 28; weight: Font.DemiBold } }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: app.intro(app.section); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } }
                Segments {
                    visible: app.section === "pozadie"
                    options: [["", "Moja knižnica"], ["online", "Tapety online (MotionBGS, Wallhaven, Bing…)"]]
                    value: app.pozadieTab
                    onPicked: (v) => app.pozadieTab = v
                }
                Loader { width: parent.width; sourceComponent: app.page(app.section) }
            }
        }

        // detail (návrh V2: stav stránky, oblasť, kde je uložená)
        Rectangle {
            id: detail
            anchors { right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 14 }
            width: 260; radius: theme.radius
            color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.16 : 0.04); border { color: theme.line; width: 1 }
            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 12
                Text { width: parent.width; wrapMode: Text.WordWrap; text: app.current.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 17; weight: Font.Bold } }
                Text {
                    text: ({ ready: "● Funguje", partial: "◐ Čiastočne", planned: "○ Zatiaľ len plán" })[app.current.status]
                    color: app.current.status === "planned" ? theme.fgDim : theme.primary; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold }
                }
                Text { text: "STAV"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.8 } }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: app.stateText(app.section); color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                Text { text: "OBLASŤ"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.8 } }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: (app.current.areaTitle || "Prehľad") + " · " + app.current.owner; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                Text { text: "ULOŽENÉ V"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.8 } }
                Text { width: parent.width; wrapMode: Text.WrapAnywhere; text: app.storedIn(app.section); color: theme.fgDim; font { family: theme.fontMono; pixelSize: 11 } }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
                wrapMode: Text.WordWrap; text: app.status; color: theme.primary; font { family: theme.fontUi; pixelSize: 12 }
            }
        }
    }

    // ── texty stránok ─────────────────────────────────────────────────────────────
    function intro(k) {
        return ({
            domov: "Stav systému na jednom mieste. Klik na kartu otvorí jej nastavenia.",
            aplikacie: "Nainštalované aplikácie priamo tu: spustiť, oprávnenia, Setup Plan, odinštalovať.",
            obrazovky: "Obrazovky spravuje Správca zariadení.", zvuk: "Zvuk spravuje Správca zariadení.", siet: "Sieť spravuje Správca zariadení.",
            bluetooth: "Bluetooth spravuje Správca zariadení.", napajanie: "Napájanie spravuje Správca zariadení.",
            instalacia: "Inštalácia jedným klikom a kontrola stiahnutých súborov.",
            aktualizacie: "Aktualizácie systému a aplikácií.",
            sukromie: "Kto smie na internet (NET) a k súborom.",
            spustanie: "Aplikácie a služby, ktoré sa spúšťajú samé.",
            ai: "Kam sa pýta režim AI v Text Bare: malý model na tomto PC, tvoj domáci server (napr. LM Studio), alebo veľké AI v cloude.",
            subory: "Súbory (Data Manager) otvoríš tlačidlom nižšie alebo Super+E. Priečinky sa dajú farebne označiť pravým klikom.",
            schranka: "Ako Windows › Systém › Schránka: história skopírovaných vecí (Win + V), jej veľkosť a vymazanie.",
            pokrocile: "Ako Windows 11 › Systém › Pre pokročilých: predvolený terminál, premenné prostredia, virtuálna pamäť a zdroje aplikácií.",
            ulozisko: "Pripojené disky a voľné miesto. Upratovanie a veľké súbory pribudnú v Data Manageri.",
            vykon: "Stupeň určuje efekty (sklo, tiene, žiara, animácie). Automaticky ho volí štart systému podľa hardvéru.",
            diagnostika: "Počítadlo pádov a prvý log z posledného pádu relácie. Ten istý záznam ukazuje vývojárska obrazovka prihlásenia.",
            prihlasovanie: "Vzhľad obrazovky prihlásenia: obrázok alebo farba a ľavý panel. Posledné dva účty sa ukazujú samé.",
            motiv: "Téma prefarbí lištu, panely, okná aj aplikácie naraz. Každá téma má tmavú aj svetlú verziu.",
            pozadie: "Tapeta plochy ako vo Windows: obrázok, plná farba, prezentácia alebo živá tapeta, pre všetky obrazovky naraz alebo každú zvlášť. Obrázok, video aj priečinok sem môžeš pretiahnuť zo Súborov.",
            tapetyonline: "Katalógy tapiet na internete: MotionBGS (živé), Wallhaven (4K/8K), Bing (denná fotka) a minimalistické. Klik stiahne tapetu do knižnice, v Pozadí ju hneď nájdeš.",
            okna: "Ako sa ukladajú okná. Super+W prepína režimy aj bez otvárania nastavení.",
            lista: "Spodná lišta z ostrovov. Šírku určuje odsadenie od okrajov obrazovky. Vľavo dlaždica aplikácií, vpravo maskot.",
            efekty: "Pohyblivé textúry tém (živá tapeta) a efekty okien.",
            start: "Režim NORMAL (Hyprland) alebo SAFE (labwc bez GPU). SAFE naskočí sám po dvoch pádoch za sebou.",
            cas: "Poloha určuje východ a západ slnka pre automatický svetlý/tmavý režim a nočné svetlo. Ďalšie časové pásma ukáže panel Čas.",
            o: "Verzie častí systému, z ktorých sa LatteOS skladá.",
            synchronizacia: "Cloudové účty (Google Drive, OneDrive, Dropbox, Nextcloud…) ako priečinky v ~/Cloud. Súbory sa stiahnu pri otvorení, zmeny sa odošlú na pozadí.",
            pouzivatelia: "Účty na tomto počítači. Každý má vlastný domov, nastavenia a kôš; obrazovka prihlásenia ukáže posledné dva.",
            zalohy: "Záloha domovského priečinka na USB disk alebo do priečinka. Každá záloha vyzerá ako celá kópia, nezmenené súbory zaberajú miesto iba raz.",
            jazyk: "Jazyk aplikácií a formáty dátumu, času, čísel a mien. Aplikácie LatteOS sú po slovensky; shell Noctalia zatiaľ nemá slovenský preklad (anglicky).",
            mojucet: "Meno, heslo a obrázok, ktorý ukáže obrazovka prihlásenia.",
            uzamknutie: "Čo sa stane, keď počítač chvíľu nepoužívaš. Pred akciou obrazovka 2 s pomaly stmavne — pohyb myšou to zruší.",
            pristupnost: "Väčšie rozhranie, vyšší kontrast, žiadny pohyb, väčší kurzor.",
            oznamenia: "Kde a ako sa ukazujú oznámenia. História a Nerušiť sú aj v paneli Čas na lište.",
            klavesnica: "Profil ovládania (Windows, Linux, macOS), Num Lock a prehľad skratiek. Rozloženia sk a us, prepínanie Alt+Shift."
        })[k] || dalsie.intros[k] || (plans[k] ? "Pripravujeme. Čo tu bude:" : "");
    }
    readonly property var plans: ({
        aplikacie: ["zoznam aplikácií (Flatpak, RPM, AppImage, Windows cez Proton, Android cez Waydroid)", "predvolené aplikácie", "App Manager: „Bude to fungovať?“ pred inštaláciou"],
        instalacia: ["inštalácia jedným klikom", "zdroje: Flathub, Fedora, LatteOS", "náhľad oprávnení pred inštaláciou"],
        aktualizacie: ["systém (Atomic: celý obraz naraz s návratom)", "aplikácie", "firmware (fwupd)", "„Aktualizovať všetko“"],
        spustanie: ["aplikácie pri prihlásení", "služby na pozadí", "Latte System Monitor: autorun položky s pôvodom"],
        sukromie: ["tlačidlo NET pre každú aplikáciu", "dôveryhodné / nedôveryhodné aplikácie", "kamera, mikrofón, poloha"],
    })
    function stateText(k) {
        const m = app.mode;
        if (k === "domov" || k === "start") return (m.mode || "?").toUpperCase() + " · " + (m.renderer || "?") + " · stupeň " + (m.tier || "?") + (m.reason ? "\n" + m.reason : "");
        if (k === "motiv") return "Téma " + theme.themeName + " · režim " + modeName(modePref) + " (teraz " + theme.mode + ")";
        if (k === "okna") return ({ paska: "Nekonečná páska", dlazdice: "Dlaždice", plavajuce: "Plávajúce okná" })[app.windowMode] || app.windowMode;
        if (k === "pozadie") {
            const n = tp.nastavenia || {}, t = n.typ || "obrazok";
            return ({ obrazok: "Obrázok", farba: "Plná farba " + (n.farba || ""), prezentacia: "Prezentácia · každých " + (n.rotacia || 30) + " min", ziva: "Živá tapeta" })[t]
                   + (t !== "farba" ? " · " + ({ crop: "Vyplniť", fit: "Prispôsobiť", stretch: "Roztiahnuť", repeat: "Dlaždica", center: "Centrovať", span: "Cez viac obrazoviek" })[tp.rezim || "crop"] : "")
                   + "\n" + tpOuts.length + (tpOuts.length === 1 ? " obrazovka" : " obrazovky") + (tpTarget !== "*" ? " · upravuješ " + tpTarget : "")
                   + (tp.gpu ? "" : "\nBez GPU: video sa spustí až s grafickou akceleráciou");
        }
        if (k === "tapetyonline") return tpLib.filter(x => x.online).length + " stiahnutých v knižnici" + (Object.keys(tpDownloads).length ? "\nSťahujem " + Object.keys(tpDownloads).length : "");
        if (k === "efekty") return "Živá tapeta: " + (liveWp === "" ? "vypnutá" : liveWp) + "\nStupeň: " + (app.tierChoice === "auto" ? "automaticky (" + (m.tier || "?") + ")" : app.tierChoice);
        if (k === "vykon") return app.tierChoice === "auto" ? "Automaticky (" + (m.tier || "?") + ")" : "Vynútený: " + app.tierChoice;
        if (k === "ai") return (ai.ok === "1" ? "● Dostupné" : "× Nedostupné") + "\n" + (ai.target || "") + (ai.model ? "\nmodel " + ai.model : "") + (ai.error ? "\n" + ai.error : "");
        if (k === "diagnostika") return "Pády NORMAL: " + crashCount + " / 2" + (crashLog ? "\n" + crashLog.split("\n")[0] : "\nbez záznamu pádu");
        if (k === "prihlasovanie") return "Greeter: " + greeter + " · panel " + greeterConf.panel;
        if (k === "lista") return "Hrúbka " + (bar.thickness || 56) + " · okraje " + (bar.margin_ends || 12) + " · spodok " + (bar.margin_edge || 10);
        if (k === "cas") return "Poloha " + (location.latitude || "48.74") + ", " + (location.longitude || "19.15") + (clockZones.length ? "\nPásma: " + clockZones.join(", ") : "");
        if (k === "synchronizacia") return clouds.length ? clouds.length + (clouds.length === 1 ? " účet" : (clouds.length <= 4 ? " účty" : " účtov")) + " · pripojené: " + clouds.filter(c => c.mounted).length : "Žiadny cloudový účet";
        if (k === "pouzivatelia") return accounts.length + (accounts.length === 1 ? " účet" : " účty") + " · správcovia: " + accounts.filter(a => a.admin).map(a => a.name).join(", ");
        if (k === "zalohy") return backup.target ? ("Cieľ: " + backup.target + "\nPosledná: " + (backup.last || "zatiaľ žiadna") + "\nSnímok: " + (backup.count || 0) + (backup.free ? " · voľné " + backup.free : "") + (backup.schedule === "on" ? "\nDenne automaticky" : "")) : "Cieľ zálohy nie je nastavený";
        if (k === "jazyk") return "Jazyk: " + (localeConf.LANG || "systémový (sk_SK.UTF-8)") + (localeConf.LC_TIME ? "\nFormáty: " + localeConf.LC_TIME : "");
        if (k === "mojucet") return (fullName || user) + " (" + user + ")";
        if (k === "uzamknutie") return "Zamknúť: " + (idleMin(idle.lock) ? idleMin(idle.lock) + " min" : "nikdy") + "\nObrazovka: " + (idleMin(idle.screen) ? idleMin(idle.screen) + " min" : "nikdy") + "\nUspať: " + (idleMin(idle.suspend) ? idleMin(idle.suspend) + " min" : "nikdy");
        if (k === "pristupnost") return "Mierka rozhrania " + Math.round((parseFloat(access.ui_scale) || 1) * 100) + " %" + (access.high_contrast === "true" ? " · vysoký kontrast" : "") + (noAnim ? " · bez animácií" : "") + "\nKurzor " + cursorSize + " px";
        if (k === "oznamenia") return (dnd ? "Nerušiť: zapnuté" : "Nerušiť: vypnuté") + "\nPoloha: " + ({ top_right: "vpravo hore", top_center: "hore v strede", top_left: "vľavo hore", bottom_right: "vpravo dole", bottom_left: "vľavo dole" })[notif.position || "top_right"];
        if (k === "klavesnica") return "Profil " + ({ windows: "Windows", linux: "Linux", mac: "macOS" })[ctrlProfile] + " · rozloženia sk, us (Alt+Shift)";
        if (dalsie.pages[k]) return dalsie.stateText(k);
        if (managed[k] && managed[k][0] === "Správca zariadení") return "Priamo tu: ten istý Správca zariadení ako okno z lišty";
        if (managed[k] && managed[k][0] === "Aplikácie") return "Priamo tu: ten istý App Manager ako okno Aplikácie";
        if (managed[k] && managed[k][0] === "Monitor") return "Priamo tu: ten istý zoznam ako Monitor › Po štarte";
        if (plans[k]) return "Zatiaľ len plán";
        return "—";
    }
    function storedIn(k) {
        return ({
            domov: "/run/latteos/mode.toml", motiv: "~/.config/latteos/theme\n~/.config/latteos/theme-mode", pozadie: "~/.config/latteos/tapety.json\n~/.local/state/noctalia/settings.toml [wallpaper]", tapetyonline: "~/.local/share/latteos/tapety",
            okna: "~/.local/state/latteos/window-mode", vykon: "~/.config/latteos/tier", efekty: "~/.config/latteos/live-wallpaper\n~/.config/latteos/tier",
            start: "/etc/latteos/boot.toml\n/var/lib/latteos/", ai: "~/.config/latteos/ai.toml\n~/.config/latteos/ai-keys (0600)",
            lista: "~/.local/state/noctalia/settings.toml [bar.main]\n~/.config/latteos/bar-anim, bar-scene, bar-scene-vpravo, bar-stlmenie, mascot", cas: "~/.local/state/noctalia/settings.toml [location]\n~/.config/latteos/clock.conf",
            prihlasovanie: "/var/lib/latteos/greeter/greeter.conf", diagnostika: "/var/lib/latteos/greeter/last-crash.log\n/var/lib/latteos/crash-count",
            subory: "~/.config/latteos/subory.json\n~/.config/latteos/tags.json\n~/.config/latteos/subory-tahanie",
            oznamenia: "~/.local/state/noctalia/settings.toml [notification]",
            uzamknutie: "~/.local/state/noctalia/settings.toml [idle.behavior.*]",
            mojucet: "/var/lib/latteos/greeter/avatars/<meno>.png\n~/.face",
            synchronizacia: "~/.config/rclone/rclone.conf\n~/Cloud/<účet>\nsystemd --user latte-cloud@<účet>",
            zalohy: "~/.config/latteos/backup.conf\n<cieľ>/LatteOS-zaloha-<meno>/<dátum>\n~/.config/systemd/user/latte-backup.timer",
            jazyk: "~/.config/latteos/locale (načíta latte-session)\n/etc/locale.conf (systém)",
            pristupnost: "~/.local/state/noctalia/settings.toml [accessibility]\n~/.config/latteos/no-animations, cursor-size",
            klavesnica: "~/.config/latteos/profil-ovladania, numlock\n/usr/share/latteos/hypr/latte/skratky.lua\n~/.config/latteos/hyprland.lua"
        })[k] || dalsie.stored[k] || "—";
    }

    // ── ovládacie prvky ──────────────────────────────────────────────────────────
    component Card: Rectangle {
        id: card
        property string title; property string sub; property bool selected: false; property string glyph: ""
        signal clicked()
        width: 200; height: 76; radius: 12
        color: selected ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.16) : (cm.containsMouse ? theme.hover : theme.field)
        border { color: selected ? theme.primary : "transparent"; width: 1.5 }
        Glyph { visible: card.glyph !== ""; x: 14; anchors.verticalCenter: parent.verticalCenter; name: card.glyph || "point"; size: 22; color: card.selected ? theme.primary : theme.fg }
        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14; leftMargin: card.glyph !== "" ? 48 : 14 }
            spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; text: card.title; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: card.sub; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
        }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: card.clicked() }
    }
    component Heading: Text { color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.8 } }
    // Rozšírené (rozhodnutie 26. 9., ako Windows): bežné nastavenia hore, pokročilé zbalené na konci stránky
    component Rozsirene: Column {
        id: rz
        property bool open: false
        property string hint: ""
        default property alias content: rzBody.data
        width: parent ? parent.width : 600; spacing: 10
        Rectangle {
            width: parent.width; height: 44; radius: 12
            color: rzm.containsMouse ? theme.hover : theme.field
            Row {
                x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                Glyph { name: rz.open ? "chevron-down" : "chevron-right"; size: 16; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Rozšírené"; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } anchors.verticalCenter: parent.verticalCenter }
                Text { text: rz.hint; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: rzm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rz.open = !rz.open }
        }
        Column { id: rzBody; visible: rz.open; width: parent.width; spacing: 10 }
    }
    component Button: Rectangle {
        id: btn
        property string label; property string glyph: ""; property bool danger: false; property bool primaryStyle: false
        signal clicked()
        width: row.implicitWidth + 28; height: 38; radius: 10
        color: primaryStyle ? theme.primary : (bm.containsMouse ? theme.hover : theme.field)
        Row { id: row; anchors.centerIn: parent; spacing: 8
            Glyph { visible: btn.glyph !== ""; name: btn.glyph || "x"; size: 16; color: btn.primaryStyle ? theme.fgOnPrimary : (btn.danger ? theme.error : theme.fg) }
            Text { text: btn.label; color: btn.primaryStyle ? theme.fgOnPrimary : (btn.danger ? theme.error : theme.fg); font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } } }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }
    // voľby vedľa seba (segmenty)
    component Segments: Flow {           // zalomí sa, keď sa voľby nezmestia do riadku
        id: seg
        width: parent ? parent.width : 600
        property var options: []      // [[hodnota, text]]
        property string value
        signal picked(string v)
        spacing: 6
        Repeater {
            model: seg.options
            Rectangle {
                required property var modelData
                readonly property bool on: seg.value === modelData[0]
                width: st.implicitWidth + 28; height: 36; radius: 10
                color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (sm.containsMouse ? theme.hover : theme.field)
                border { color: on ? theme.primary : "transparent"; width: 1.5 }
                Text { id: st; anchors.centerIn: parent; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: on ? Font.Bold : Font.Medium } }
                MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; onClicked: seg.picked(modelData[0]) }
            }
        }
    }
    // číslo so šípkami (– hodnota +)
    component Stepper: Row {
        id: sp
        property string label; property real value; property real step: 1; property real min: 0; property real max: 100; property string unit: " px"
        signal stepped(real v)
        spacing: 10
        Text { width: 230; anchors.verticalCenter: parent.verticalCenter; text: sp.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
        Rectangle {
            width: 150; height: 36; radius: 10; color: theme.field
            IconButton { anchors { left: parent.left; verticalCenter: parent.verticalCenter } theme: app.latteTheme; glyph: "minus"; enabledState: sp.value > sp.min; onClicked: sp.stepped(Math.max(sp.min, sp.value - sp.step)) }
            Text { anchors.centerIn: parent; text: (sp.step < 1 ? sp.value.toFixed(2) : Math.round(sp.value)) + sp.unit; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
            IconButton { anchors { right: parent.right; verticalCenter: parent.verticalCenter } theme: app.latteTheme; glyph: "plus"; enabledState: sp.value < sp.max; onClicked: sp.stepped(Math.min(sp.max, sp.value + sp.step)) }
        }
    }
    // textové pole; Enter alebo strata fokusu = uložiť
    component Field: Rectangle {
        id: fld
        property string text; property string placeholder; property bool secret: false; property bool multiline: false
        signal committed(string t)
        signal edited(string t)          // každá zmena (pre tlačidlá vedľa poľa)
        width: 420; height: multiline ? 110 : 38; radius: 10; color: theme.field
        border { color: inp.activeFocus ? theme.primary : "transparent"; width: 1 }
        TextEdit {
            id: inp
            visible: fld.multiline
            anchors { fill: parent; margins: 10 }
            wrapMode: TextEdit.Wrap; text: fld.text; color: theme.fg; selectionColor: theme.primary
            font { family: theme.fontUi; pixelSize: 13 }
            onActiveFocusChanged: if (!activeFocus && fld.multiline) fld.committed(text)
        }
        TextInput {
            id: one
            visible: !fld.multiline
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter; clip: true
            text: fld.text; color: theme.fg; selectionColor: theme.primary
            echoMode: fld.secret ? TextInput.Password : TextInput.Normal
            font { family: theme.fontUi; pixelSize: 13 }
            onAccepted: { fld.committed(text); focus = false; }
            onTextChanged: fld.edited(text)
            onActiveFocusChanged: if (!activeFocus) fld.committed(text)
        }
        Text {
            x: 12; y: fld.multiline ? 10 : (parent.height - height) / 2
            visible: (fld.multiline ? inp.text : one.text) === ""; text: fld.placeholder; color: theme.fgDim
            font { family: theme.fontUi; pixelSize: 13 }
        }
    }

    NastavDalsie { id: dalsie; app: app; theme: theme }

    // stránky, ktoré vlastní iný manažér (main_setting_v2 §57: stav + odkaz, nie druhá implementácia)
    readonly property var managed: ({
        aplikacie: ["Aplikácie", "Nainštalované aplikácie, zdroj, veľkosť, odinštalovanie.", ["latte-app", "aplikacie", "nainstalovane"]],
        instalacia: ["Aplikácie", "Objavovať: Flathub (bez hesla, v izolácii) a Fedora. „Bude to fungovať?“ pre stiahnuté súbory.", ["latte-app", "aplikacie", "objavovat"]],
        aktualizacie: ["Aplikácie", "Systém (dnf) aj Flatpak aplikácie na jednom mieste, „Aktualizovať všetko“.", ["latte-app", "aplikacie", "aktualizacie"]],
        sukromie: ["Aplikácie", "NET pre každú aplikáciu: internet áno/nie. Flatpak cez jeho izoláciu, ostatné aplikácie bežia bez siete (bubblewrap). Windows hry cez Proton prídu s hernou vrstvou.", ["latte-app", "aplikacie", "opravnenia"]],
        obrazovky: ["Správca zariadení", "Rozlíšenie a mierka s potvrdením do 15 s (inak sa zmena vráti). Uloží sa do ~/.config/latteos/monitors.lua.", ["latte-app", "zariadenia", "obrazovky"]],
        zvuk: ["Správca zariadení", "Výstup a vstup, hlasitosť, konektory (čo je zapojené do ktorého jacku), konfigurácia karty (stereo, 5.1…) a hlasitosť aplikácií.", ["latte-app", "zariadenia", "zvuk"]],
        siet: ["Správca zariadení", "Pripojenia, Wi-Fi v okolí, VPN a tunely, SSH server, firewall (zóny, služby, porty, presmerovania) a adresy.", ["latte-app", "zariadenia", "siet"]],
        bluetooth: ["Správca zariadení", "Zapnutie, hľadanie a párovanie zariadení, pripojenie a zabudnutie.", ["latte-app", "zariadenia", "bluetooth"]],
        napajanie: ["Správca zariadení", "Batéria, adaptér a režim napájania (Úsporný · Vyvážený · Výkon) a herný režim.", ["latte-app", "zariadenia", "napajanie"]],
        disky: ["Správca zariadení", "Disky, USB kľúče a karty: stav SMART, oddiely, bezpečné odpojenie. Pripojené sa ukážu aj v Súboroch.", ["latte-app", "zariadenia", "disky"]],
        tlac: ["Správca zariadení", "Tlačiarne a skenery: stav, ovládač a rad úloh. Novú sieťovú tlačiareň Fedora zvyčajne nájde sama (IPP Everywhere).", ["latte-app", "zariadenia", "tlac"]],
        spustanie: ["Monitor", "Čo sa spúšťa po prihlásení: autostart, služby tvojho účtu, časovače. Vypnutie jedným klikom.", ["latte-app", "monitor", "autorun"]]
    })
    function page(k) {
        if (managed[k]) return pManaged;
        if (dalsie.pages[k]) return dalsie.pages[k];
        return ({ domov: pDomov, ai: pAi, subory: pSubory, ulozisko: pUlozisko, vykon: pVykon, diagnostika: pDiag,
                  prihlasovanie: pGreeter, motiv: pMotiv, pozadie: pozadieTab === "online" ? pTapetyOnline : pPozadie, tapetyonline: pTapetyOnline, okna: pOkna, lista: pLista, efekty: pEfekty,
                  start: pStart, cas: pCas, o: pO, klavesnica: pKlavesy, oznamenia: pOznamenia, pristupnost: pPristupnost,
                  uzamknutie: pUzamknutie, pokrocile: pPokrocile, schranka: pSchranka, mojucet: pUcet, jazyk: pJazyk, zalohy: pZalohy, pouzivatelia: pPouzivatelia, synchronizacia: pCloud })[k] || pPlan;
    }

    // ── stránky ──────────────────────────────────────────────────────────────────
    Component {
        id: pDomov
        Column {
            spacing: 18
            Flow {
                width: parent.width; spacing: 12
                Repeater {
                    model: [
                        ["system", "start", "LatteOS", (app.mode.mode || "?").toUpperCase() + " · pády " + app.crashCount + " / 2", "shield"],
                        ["hardver", "vykon", "Hardvér", (app.mode.renderer || "?") + " · stupeň " + (app.mode.tier || "?"), "cpu"],
                        ["data", "ulozisko", "Dáta", (app.storage.split("\n").find(l => l.startsWith("/ ")) || "/ ?").trim().split(/\s+/).slice(3, 5).join(" voľné · ") + " obsadené", "database"],
                        ["softver", "ai", "AI", app.ai.ok === "1" ? (app.ai.model || "pripravené") : "nenastavené", "sparkles"],
                        ["prostredie", "motiv", "Prostredie", theme.themeName + " · " + app.modeName(app.modePref), "palette"],
                        ["ucet", "prihlasovanie", "Účet", app.user + " · prihlásenie " + app.greeter, "user"],
                        ["hardver", "siet", "Sieť", app.netState || "…", "wifi"],
                        ["data", "zalohy", "Zálohy", app.backup.last ? "posledná " + app.backup.last.slice(0, 10) : (app.backup.target ? "zatiaľ žiadna" : "nenastavené"), "history"],
                        ["data", "synchronizacia", "Cloud", app.clouds.length ? app.clouds.filter(c => c.mounted).length + " z " + app.clouds.length + " pripojených" : "žiadny účet", "cloud"]
                    ]
                    Card {
                        required property var modelData
                        width: 250; glyph: modelData[4]; title: modelData[2]; sub: modelData[3]
                        onClicked: app.go(modelData[1])
                    }
                }
            }
            Heading { text: app.warnings.length ? "UPOZORNENIA · " + app.warnings.length : "UPOZORNENIA"; visible: true }
            Text { visible: app.warnings.length === 0; text: "● Všetko v poriadku"; color: theme.primary; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
            Repeater {
                model: app.warnings
                Rectangle {
                    required property var modelData
                    width: Math.min(parent.width, 640); height: 52; radius: 12
                    color: wm.containsMouse ? theme.hover : Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.10)
                    border { color: Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.45); width: 1 }
                    Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; name: parent.modelData[0]; size: 20; color: theme.error }
                    Column {
                        x: 46; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "! " + parent.parent.modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                        Text { text: parent.parent.modelData[2]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                    }
                    Glyph { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } name: "chevron-right"; size: 16; color: theme.fgDim }
                    MouseArea { id: wm; anchors.fill: parent; hoverEnabled: true; onClicked: app.go(parent.modelData[3]) }
                }
            }
            Heading { text: "NEDÁVNO POUŽITÉ" }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: app.history.filter((k, i, a) => k !== "domov" && a.lastIndexOf(k) === i).slice(-5).reverse()
                    Button { required property string modelData; label: (app.allPages.find(p => p.key === modelData) || {}).label || modelData; onClicked: app.go(modelData) }
                }
            }
        }
    }
    Component {
        id: pAi
        Column {
            spacing: 14
            Heading { text: "KDE BEŽÍ AI" }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: [["lokalne", "Tento počítač", "Ollama, malý model; bez internetu", "device-desktop"],
                            ["domaci", "Domáci server", "LM Studio, llama.cpp, Ollama v sieti alebo cez SSH", "server"],
                            ["web", "Prihlásenie v prehliadači", "Claude, ChatGPT, Perplexity, Copilot s tvojím účtom, bez kľúča", "world"],
                            ["cloud", "Veľké AI (cloud)", "Claude, ChatGPT, Gemini, Mistral — s API kľúčom", "cloud"],
                            ["ziadna", "Bez AI", "LatteOS AI nikde neponúka (Text Bar, Super+I)", "robot-off"]]
                    Card {
                        required property var modelData
                        width: 250; glyph: modelData[3]; title: modelData[1]; sub: modelData[2]; selected: app.ai.provider === modelData[0]
                        onClicked: app.aiSet("provider", modelData[0])
                    }
                }
            }
            // webová AI s prihlásením
            Column {
                visible: app.ai.provider === "web"; spacing: 10; width: parent.width
                Heading { text: "KTORÁ WEBOVÁ AI" }
                Segments {
                    options: [["claude", "Claude"], ["chatgpt", "ChatGPT"], ["perplexity", "Perplexity"], ["copilot", "Copilot"]]
                    value: ((app.ai.model || "Claude").toLowerCase())
                    onPicked: (v) => app.aiSet("web", v)
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                       text: "Ako widget v mobile: otázka z Text Baru sa otvorí na stránke AI v prehliadači, kde si prihlásený (Firefox si prihlásenie pamätá). LatteOS nepotrebuje žiadny kľúč a nevidí tvoj účet." }
            }
            // domáci server
            Column {
                visible: app.ai.provider === "domaci"; spacing: 10; width: parent.width
                Heading { text: "ADRESA SERVERA (OpenAI API)" }
                Field { text: (app.ai.target || "").split(" cez ssh ")[0]; placeholder: "http://192.168.56.1:1234/v1"; onCommitted: (t) => { if (t !== "" && t !== (app.ai.target || "").split(" cez ssh ")[0]) app.aiSet("url", t); } }
                Heading { text: "SSH PRÍSTUP (voliteľné)" }
                Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                       text: "Ak server nie je otvorený do siete: zadaj pouzivatel@server. LatteOS otvorí SSH tunel na port z adresy (prihlásenie kľúčom, ssh-copy-id)." }
                Field { text: (app.ai.target || "").split(" cez ssh ")[1] || ""; placeholder: "pouzivatel@domaci-server"; onCommitted: (t) => { if (t !== ((app.ai.target || "").split(" cez ssh ")[1] || "")) app.aiSet("ssh", t); } }
            }
            // cloud
            Column {
                visible: app.ai.provider === "cloud"; spacing: 10; width: parent.width
                Heading { text: "SLUŽBA" }
                Segments {
                    options: [["anthropic", "Claude"], ["openai", "ChatGPT"], ["gemini", "Gemini"], ["mistral", "Mistral"]]
                    value: app.ai.target || ""
                    onPicked: (v) => app.aiSet("cloud", v)
                }
                Heading { text: "API KĽÚČ" }
                Field {
                    secret: true; placeholder: "vlož kľúč a stlač Enter (uloží sa s právami 0600)"
                    onCommitted: (t) => { if (t !== "") { app.run(["latte-ai", "key", app.ai.target || "anthropic", t], "Kľúč uložený"); text = ""; aiRefresh.restart(); } }
                }
            }
            Heading { text: "MODEL"; visible: app.ai.provider !== "cloud" }
            Flow {
                visible: app.ai.provider !== "cloud"
                width: parent.width; spacing: 8
                Card { width: 220; height: 58; title: "Automaticky"; sub: "načítaný na serveri"; selected: false; onClicked: app.aiSet("model", "") }
                Repeater {
                    model: app.aiModels
                    Card {
                        required property var modelData
                        width: 220; height: 58; title: modelData.id.split("/").pop(); sub: modelData.state === "loaded" ? "● načítaný" : (modelData.state === "not-loaded" ? "načíta sa pri otázke" : modelData.state)
                        selected: app.ai.model === modelData.id
                        onClicked: app.aiSet("model", modelData.id)
                    }
                }
            }
            Row {
                spacing: 10
                Button { label: "Vyskúšať"; glyph: "sparkles"; primaryStyle: true; onClicked: { app.aiAnswer = "Pýtam sa…"; aiAsk.running = true; } }
                Button { label: "Obnoviť"; glyph: "refresh"; onClicked: aiRefresh.restart() }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; visible: app.aiAnswer !== ""; text: app.aiAnswer; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
        }
    }
    Component {
        id: pSubory
        Column {
            spacing: 12
            Button { label: "Otvoriť Súbory"; glyph: "folder"; primaryStyle: true; onClicked: app.run(["latte-app", "subory"]) }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                text: "Farebné štítky: pravý klik na priečinok (v zozname aj v Obľúbených) › Farba. Štítok je viditeľný všade v Súboroch a nemení samotný priečinok."
            }
            Heading { text: "ŤAHANIE MYŠOU (REŽIM FORKLIFT)"; topPadding: 6 }
            Segments {
                options: [["", "Ako Windows"], ["copy", "Vždy kopírovať"], ["ask", "Vždy sa opýtať"]]
                value: app.suboryTahanie
                onPicked: (v) => { app.suboryTahanie = v; app.writePref("subory-tahanie", v, "Ťahanie súborov: " + (v || "ako Windows")); }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                text: "Ako Windows: na tom istom disku sa súbor presunie, na iný disk skopíruje. Ctrl = kopírovať, Shift = presunúť, Alt = odkaz. Ťahanie pravým (alebo stredným) tlačidlom vždy ukáže ponuku Kopírovať sem · Presunúť sem · Vytvoriť odkaz. Režim Total Commander kopíruje s dialógom F5."
            }
        }
    }
    Component {
        id: pUlozisko
        Column {
            spacing: 8
            Repeater {
                model: app.storage.split("\n").filter(l => l.trim() !== "")
                Rectangle {
                    required property string modelData
                    readonly property var f: modelData.trim().split(/\s+/)
                    width: Math.min(parent.width, 560); height: 54; radius: 12; color: theme.field
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        spacing: 6
                        Text { text: f[0] + "   ·   " + f[3] + " voľné z " + f[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                        Rectangle {
                            width: parent.width; height: 4; radius: 2; color: theme.line
                            Rectangle { width: parent.width * (parseInt(f[4]) || 0) / 100; height: 4; radius: 2; color: (parseInt(f[4]) || 0) > 90 ? theme.error : theme.primary }
                        }
                    }
                }
            }
            Item { width: 1; height: 6 }
            Rozsirene {
                id: ulRz
                hint: "disky a oddiely, stav SMART, bezpečné odpojenie (bývalé Úložné zariadenia)"
                open: app.ulRozsirene
                onOpenChanged: app.ulRozsirene = open
                Loader {
                    active: ulRz.open; width: parent.width; height: item ? item.naturalHeight : 0
                    sourceComponent: SpravcaZariadeni { theme: app.th; compact: false; embedded: true; only: "disky"; onOpenWindow: (a) => app.run(a) }
                }
            }
        }
    }
    Component {
        id: pSchranka
        Column {
            spacing: 12
            Component.onCompleted: kapsaCnt.running = true
            Heading { text: "HISTÓRIA SCHRÁNKY" }
            Segments {
                options: [["", "Zapnutá (Win + V)"], ["off", "Vypnutá"]]
                value: app.kapsaHist
                onPicked: (v) => { app.kapsaHist = v; app.writePref("kapsa-historia", v, v === "off" ? "História schránky vypnutá — nové kopírovanie sa neukladá" : "História schránky zapnutá"); }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Kapsa si pamätá texty aj obrázky, ktoré skopíruješ (Ctrl + C). Otvára sa klávesmi Win + V alebo z ostrova Kapsy na lište; klik na položku ju vloží späť do schránky." }
            Heading { text: "NAJVIAC POLOŽIEK"; topPadding: 6 }
            Segments {
                enabled: app.kapsaHist !== "off"; opacity: enabled ? 1 : 0.5
                options: [["50", "50"], ["", "200"], ["750", "750"], ["2000", "2000"]]
                value: app.kapsaMax
                onPicked: (v) => { app.kapsaMax = v; app.writePref("kapsa-max", v, "Kapsa si pamätá najviac " + (v || "200") + " položiek (staršie sa zmažú pri ďalšom kopírovaní)"); }
            }
            Heading { text: "VYMAZAŤ ÚDAJE SCHRÁNKY"; topPadding: 6 }
            Row {
                spacing: 12
                Button { label: "Vymazať históriu"; glyph: "trash"
                         onClicked: { app.run(["cliphist", "wipe"], "História schránky vymazaná"); app.kapsaCount = 0; } }
                Text { anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                       text: app.kapsaCount < 0 ? "" : "V histórii je " + app.kapsaCount + " položiek" }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Zmena zapnutia a počtu platí hneď pre ďalšie kopírovanie. Heslá zo správcu hesiel radšej vkladaj priamo (automatické vypĺňanie), nie cez schránku." }
        }
    }
    Component {
        id: pPokrocile
        Column {
            spacing: 10
            Component.onCompleted: advProc.running = true
            Heading { text: "PREDVOLENÝ TERMINÁL" }
            Segments {
                options: (app.terminals.length ? app.terminals : ["foot"]).map(t => [t, t])
                value: app.terminal
                onPicked: (v) => { app.terminal = v; app.writePref("terminal", v === "foot" ? "" : v, "Terminál: " + v + " (Win+Enter, Ctrl+Alt+T, ponuka Win+X)"); }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Otvára sa klávesmi Win + Enter a Ctrl + Alt + T a z ponuky Win + X (latte-terminal). Dialógy so správcovskými právami používajú foot." }

            Heading { text: "PREMENNÉ PROSTREDIA"; topPadding: 10 }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Pre celý tvoj účet (systemd environment.d). Platia po odhlásení a prihlásení. Súbor: " + app.envFile.replace(app.home, "~") }
            Repeater {
                model: app.envLines
                Rectangle {
                    required property string modelData
                    required property int index
                    width: parent.width; height: 38; radius: 10; color: theme.field
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; elide: Text.ElideRight; text: parent.modelData
                           color: theme.fg; font { family: theme.fontMono; pixelSize: 12 } }
                    Rectangle { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } width: 26; height: 26; radius: 8
                                color: em.containsMouse ? theme.hover : "transparent"
                                Glyph { anchors.centerIn: parent; name: "x"; size: 14; color: theme.fgDim }
                                MouseArea { id: em; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { const i = parent.parent.index; app.saveEnv(app.envLines.filter((_, k) => k !== i)); } } }
                }
            }
            Rectangle {
                width: parent.width; height: 38; radius: 10; color: theme.field; border { width: envIn.activeFocus ? 1 : 0; color: theme.primary }
                TextInput {
                    id: envIn
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter; clip: true
                    color: theme.fg; font { family: theme.fontMono; pixelSize: 12 } selectByMouse: true
                    Keys.onReturnPressed: {
                        const t = text.trim();
                        if (!/^[A-Za-z_][A-Za-z0-9_]*=.*$/.test(t)) { app.status = "Zápis: NÁZOV=hodnota (napr. MANGOHUD=1)"; return; }
                        const k = t.split("=")[0];
                        app.saveEnv(app.envLines.filter(l => l.split("=")[0] !== k).concat([t])); text = "";
                    }
                    Text { visible: !envIn.text && !envIn.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Pridať: NÁZOV=hodnota a Enter (napr. MANGOHUD=1)"
                           color: theme.fgDim; font: envIn.font }
                }
            }

            Heading { text: "VIRTUÁLNA PAMÄŤ (SWAP A ZRAM)"; topPadding: 10 }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontMono; pixelSize: 12 }
                   text: app.memInfo || "Bez swapu." }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Fedora používa zram: stlačená časť RAM namiesto pomalého disku. Veľkosť určuje /etc/systemd/zram-generator.conf (zmena platí po reštarte)." }
            Button { label: "Upraviť zram (správca)"; glyph: "settings"; onClicked: app.run(["foot", "-T", "zram", "-e", "sudoedit", "/etc/systemd/zram-generator.conf"]) }

            Heading { text: "ZDROJE APLIKÁCIÍ A VÝVOJ"; topPadding: 10 }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontMono; pixelSize: 12 }
                   text: app.remotes ? "Flatpak: " + app.remotes : "Flatpak: žiadny zdroj" }
            Flow {
                width: parent.width; spacing: 8
                Button { label: "SSH server a firewall"; glyph: "terminal"; onClicked: app.go("siet") }
                Button { label: "Súkromie a NET"; glyph: "shield"; onClicked: app.go("sukromie") }
                Button { label: "Štart a režim (SAFE)"; glyph: "refresh"; onClicked: app.go("start") }
            }
        }
    }
    Component {
        id: pVykon
        Flow {
            spacing: 10
            Repeater {
                model: [["auto", "Automaticky", "Podľa hardvéru pri štarte"], ["plny", "Plný", "Sklo, blur, žiara, animácie 120 Hz"],
                        ["standard", "Štandard", "Menší blur, plné animácie"], ["usporny", "Úsporný", "Bez blur a tieňov, krátke animácie"],
                        ["minimalny", "Minimálny", "Bez priehľadnosti a animácií"], ["softver", "Softvér", "VM a slabé PC, bez efektov"]]
                Card {
                    required property var modelData
                    title: modelData[1]; sub: modelData[2]; selected: app.tierChoice === modelData[0]
                    onClicked: app.setTier(modelData[0])
                }
            }
        }
    }
    Component {
        id: pDiag
        Column {
            spacing: 14
            Row {
                spacing: 12
                Text { anchors.verticalCenter: parent.verticalCenter; text: app.crashCount + " z 2 pádov (pri 2 naštartuje SAFE)"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                Button { label: "Vynulovať"; glyph: "refresh"; onClicked: app.run(["latte-boot", "reset"], "Počítadlo vynulované") }
            }
            Heading { text: "POSLEDNÝ PÁD" }
            Rectangle {
                width: parent.width; height: Math.max(80, log.implicitHeight + 28); radius: 12; color: theme.field
                Text {
                    id: log
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                    text: app.crashLog || "Žiadny zaznamenaný pád. ☕"; color: theme.fgDim
                    font { family: theme.fontMono; pixelSize: 11 }
                }
            }
            Button { visible: app.crashLog !== ""; label: "Vymazať záznam"; glyph: "trash"; onClicked: app.run(["rm", "-f", "/var/lib/latteos/greeter/last-crash.log"], "Záznam pádu vymazaný") }
        }
    }
    Component {
        id: pGreeter
        Column {
            spacing: 14
            Heading { text: "POZADIE" }
            Flow {
                width: parent.width; spacing: 10
                Rectangle {
                    width: 180; height: 102; radius: 12; color: app.greeterConf.color
                    border { color: app.greeterConf.background === "" ? theme.primary : "transparent"; width: 2 }
                    Text { anchors.centerIn: parent; text: "Iba farba"; color: "#F3EBDD"; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: app.setGreeter("background", "") }
                }
                Repeater {
                    model: app.wallpapers
                    Rectangle {
                        required property string modelData
                        width: 180; height: 102; radius: 12; clip: true; color: theme.field
                        border { color: app.greeterConf.background === modelData ? theme.primary : "transparent"; width: 2 }
                        Image { anchors { fill: parent; margins: 2 } source: "file://" + parent.modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize { width: 360; height: 204 } }
                        MouseArea { anchors.fill: parent; onClicked: app.setGreeter("background", parent.modelData) }
                    }
                }
            }
            Heading { text: "FARBA" }
            Row {
                spacing: 10
                Repeater {
                    model: ["#1B1410", "#101418", "#141A12", "#1A1020", "#2A2A2E", "#0E0E0E"]
                    Rectangle {
                        required property string modelData
                        width: 38; height: 38; radius: 19; color: modelData
                        border { color: app.greeterConf.color.toLowerCase() === modelData.toLowerCase() ? theme.primary : theme.line; width: 2 }
                        MouseArea { anchors.fill: parent; onClicked: app.setGreeter("color", parent.modelData) }
                    }
                }
            }
            Stepper { label: "Stmavenie obrázka"; value: parseFloat(app.greeterConf.dim) || 0; step: 0.05; min: 0; max: 0.85; unit: ""
                      onStepped: (v) => app.setGreeter("dim", v.toFixed(2)) }
            Heading { text: "ĽAVÝ PANEL" }
            Segments {
                options: [["log", "Log pádu"], ["pocasie", "Počasie"], ["rss", "Novinky (RSS)"], ["text", "Vlastný text"], ["none", "Nič"]]
                value: app.greeterConf.panel
                onPicked: (v) => {
                    app.setGreeter("panel", v);
                    if (v === "pocasie") {   // poloha z Nastavení › Dátum, čas a poloha
                        const lat = app.location.latitude || "48.74", lon = app.location.longitude || "19.15";
                        app.setGreeter("lat", lat); app.setGreeter("lon", lon);
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Vývojárska verzia: log posledného pádu. Počasie berie polohu z Dátum, čas a poloha (Open-Meteo, bez účtu)." }
            Column {
                visible: app.greeterConf.panel === "rss"; spacing: 8; width: parent.width
                Flow {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [["https://www.aktuality.sk/rss/", "Aktuality.sk"], ["https://spravy.stvr.sk/feed/", "Správy STVR"], ["https://www.root.cz/rss/clanky/", "Root.cz"], ["https://www.phoronix.com/rss.php", "Phoronix"]]
                        Card { required property var modelData; width: 170; height: 48; title: modelData[1]; sub: ""; selected: app.greeterConf.rss_url === modelData[0]
                               onClicked: { app.setGreeter("rss_url", modelData[0]); app.setGreeter("panel_title", modelData[1]); } }
                    }
                }
                Field { text: app.greeterConf.rss_url; placeholder: "vlastný RSS odkaz"; onCommitted: (t) => { if (t !== "" && t !== app.greeterConf.rss_url) app.setGreeter("rss_url", t); } }
            }
            Column {
                visible: app.greeterConf.panel === "text"; spacing: 8
                Field { text: app.greeterConf.panel_title; placeholder: "Nadpis (napr. Dnes)"; onCommitted: (t) => { if (t !== app.greeterConf.panel_title) app.setGreeter("panel_title", t); } }
                Field { multiline: true; text: app.greeterConf.panel_text; placeholder: "Text na obrazovke prihlásenia"; onCommitted: (t) => { if (t !== app.greeterConf.panel_text) app.setGreeter("panel_text", t); } }
            }
            Heading { text: "TYP" }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Aktuálne: " + ({ latte: "LatteOS (grafická)", tui: "textová (tuigreet)", noctalia: "Noctalia Greeter" })[app.greeter]
                      + ". Zmena vyžaduje administrátora: v /etc/latteos/boot.toml riadok greeter = \"latte\" alebo \"tui\"."
                color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
            }
        }
    }
    Component {
        id: pMotiv
        Column {
            spacing: 14
            Heading { text: "SVETLÁ / TMAVÁ VERZIA" }
            Segments {
                options: [["tema", "Podľa témy"], ["dark", "Tmavá"], ["light", "Svetlá"], ["auto", "Automaticky (slnko)"]]
                value: app.modePref
                onPicked: (v) => { app.run(["latte-theme", "mode", v], "Režim: " + app.modeName(v)); app.modePref = v; }
            }
            Text { visible: app.modePref === "auto"; width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Cez deň svetlá, po západe slnka tmavá. Poloha: Systém › Dátum, čas a poloha." }
            Heading { text: "TÉMA" }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.themes
                    Card {
                        required property var modelData
                        title: modelData.name; sub: modelData.desc; selected: theme.themeId === modelData.id
                        onClicked: app.run(["latte-theme", "set", modelData.id], "Téma: " + modelData.name)
                    }
                }
            }
        }
    }
    // ── Pozadie (ako Windows › Prispôsobenie › Pozadie; backend latte-tapety, obrázky = tapeta Noctalie) ──────────
    // náhľad tapety v zozname (obrázok, video s náhľadom, farba)
    component Thumb: Rectangle {
        id: th
        property string src: ""                // obrázok alebo náhľad videa
        property string name: ""
        property bool video: false
        property bool active: false
        property bool fav: false
        property real progress: -2              // sťahovanie 0–100 (-2 = nie)
        property int w: 164
        signal clicked()
        signal menu(real x, real y)
        width: w; height: Math.round(w * 9 / 16); radius: 10; clip: true; color: theme.field
        border { color: active ? theme.primary : (thm.containsMouse ? theme.outline : "transparent"); width: active ? 2.5 : 1 }
        Image { anchors { fill: parent; margins: th.active ? 3 : 1 } source: th.src ? (th.src.startsWith("http") ? th.src : "file://" + th.src) : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; sourceSize { width: 360; height: 204 } }
        Glyph { anchors.centerIn: parent; visible: !th.src; name: th.video ? "movie" : "photo"; size: 26; color: theme.fgDim }
        Rectangle { visible: th.video; anchors { left: parent.left; bottom: parent.bottom; margins: 6 } width: vtl.implicitWidth + 12; height: 18; radius: 6; color: Qt.rgba(0, 0, 0, 0.6)
                    Text { id: vtl; anchors.centerIn: parent; text: "▶ živá"; color: "white"; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } } }
        Text { visible: th.fav; anchors { right: parent.right; top: parent.top; margins: 6 } text: "★"; color: "#F2C14E"; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5); font.pixelSize: 15 }
        Rectangle { visible: th.progress > -2; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 6; color: Qt.rgba(0, 0, 0, 0.45)
                    Rectangle { width: parent.width * Math.max(0.03, th.progress / 100); height: parent.height; color: theme.primary } }
        Rectangle { visible: thm.containsMouse && th.name !== ""; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 22; color: Qt.rgba(0, 0, 0, 0.55)
                    Text { anchors { fill: parent; leftMargin: 8; rightMargin: 8 } verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: th.name; color: "white"; font { family: theme.fontUi; pixelSize: 11 } } }
        MouseArea { id: thm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                    onClicked: (m) => { if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); th.menu(q.x, q.y); } else th.clicked(); } }
    }
    // prepínač s popisom
    component Toggle: Row {
        id: tg
        property bool on: false
        property string label
        signal toggled()
        spacing: 10
        Rectangle {
            width: 46; height: 26; radius: 13; anchors.verticalCenter: parent.verticalCenter
            color: tg.on ? theme.primary : theme.field; border { color: theme.line; width: 1 }
            Rectangle { width: 20; height: 20; radius: 10; y: 3; x: tg.on ? 23 : 3; color: tg.on ? theme.fgOnPrimary : theme.fgDim }
            MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: tg.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
    }
    // riadok „Pretiahni sem… / Prehľadávať“ (ako Windows „Výber fotografie“), prijme aj pretiahnutie zo Súborov
    component PickRow: Rectangle {
        id: pr
        property string label
        property string hint: "alebo sem pretiahni súbor zo Súborov"
        property string button: "Prehľadávať…"
        signal browse()
        signal dropped(var paths)
        width: parent ? Math.min(parent.width, 760) : 600; height: 58; radius: 12
        color: prDrop.containsDrag ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.16) : theme.field
        border { color: prDrop.containsDrag ? theme.primary : "transparent"; width: 1.5 }
        Column { anchors { left: parent.left; leftMargin: 16; right: prBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter } spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: pr.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
            Text { width: parent.width; elide: Text.ElideRight; text: prDrop.containsDrag ? "Pusti — nastaví sa hneď" : pr.hint; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } } }
        Button { id: prBtn; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } label: pr.button; glyph: "folder-open"; onClicked: pr.browse() }
        DropArea { id: prDrop; anchors.fill: parent; keys: ["text/uri-list"]
                   onDropped: (d) => { if (d.hasUrls) { pr.dropped(app.dropPaths(d.urls)); d.accept(Qt.CopyAction); } } }
    }
    function setBackupTarget(t) { if (t !== app.backup.target) { run(["latte-backup", "set-target", t], "Cieľ zálohy: " + t); backupProc.running = true; } }
    function setBarFile(f) { barScene = "file:" + f; writePref("bar-scene", barScene, "Textúra L: " + f.split("/").pop()); }
    function dropPaths(urls) { return urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))); }
    // dialóg výberu (latte-vyber = zenity s farbami témy); výsledok dostane callback
    property var pickCb: null
    Cmd { id: picker; onDone: (out) => { const p = out.split("\n").filter(x => x !== ""); if (p.length && app.pickCb) app.pickCb(p); } }
    function browse(args, cb) { if (picker.running) return; pickCb = cb; picker.command = ["latte-vyber"].concat(args); picker.running = true; }

    // stav tapiet (spoločný pre Pozadie a Tapety online; obnovuje sa, kým je jedna z nich otvorená)
    property var tp: ({ nastavenia: {}, vystupy: {}, staticke: {}, nedavne: [], rezim: "crop", gpu: false })
    property var tpLib: []
    property var tpOuts: []
    property string tpTarget: "*"
    readonly property bool tpVisible: section === "pozadie" || section === "tapetyonline"
    Cmd { id: tpStav; command: ["latte-tapety", "stav"]; onDone: (o) => { try { app.tp = JSON.parse(o); } catch (e) {} } }
    Cmd { id: tpLibP; command: ["latte-tapety", "kniznica"]; onDone: (o) => { try { app.tpLib = JSON.parse(o); } catch (e) {} app.tpThumbNext(); } }
    Cmd { id: tpOutP; command: ["latte-tapety", "vystupy"]; onDone: (o) => { try { app.tpOuts = JSON.parse(o); } catch (e) {} } }
    onTpVisibleChanged: if (tpVisible) { tpStav.running = true; tpLibP.running = true; tpOutP.running = true; }
    Timer { interval: 5000; repeat: true; running: app.tpVisible; onTriggered: if (!tpStav.running) tpStav.running = true }
    // príkazy latte-tapety po jednom (rad), po každom sa obnoví stav
    property var tpQueue: []
    Cmd { id: tpAct; property string msg: ""
          onDone: (o) => { const t = o.trim(); app.status = t.startsWith("E ") ? "⚠ " + t.slice(2) : (tpAct.msg || "Hotovo");
                           tpStav.running = true; if (app.tpQueue.length) { const n = app.tpQueue[0]; app.tpQueue = app.tpQueue.slice(1); app.tpRun(n[0], n[1]); } } }
    function tpRun(args, msg) {
        if (tpAct.running) { tpQueue = tpQueue.concat([[args, msg]]); return; }
        tpAct.msg = msg || ""; tpAct.command = ["latte-tapety"].concat(args); tpAct.running = true;
        if (msg) status = msg + "…";
    }
    function tpOut() { return tpTarget === "*" ? [] : ["--vystup", tpTarget]; }
    function tpUse(path) { tpRun(["pouzi", path].concat(tpOut()), "Pozadie: " + path.split("/").pop()); }
    // náhľady videí (ffmpeg) po jednom
    Cmd { id: tpThumb; property string path: ""
          onDone: (o) => { const t = o.trim(); const l = app.tpLib.slice(); const i = l.findIndex(x => x.path === tpThumb.path);
                           if (i >= 0) { l[i] = Object.assign({}, l[i], { thumb: t, noThumb: true }); app.tpLib = l; } app.tpThumbNext(); } }
    function tpThumbNext() {
        if (tpThumb.running) return;
        const x = tpLib.find(i => i.video && !i.thumb && !i.noThumb);
        if (!x) return;
        tpThumb.path = x.path; tpThumb.command = ["latte-tapety", "nahlad", x.path]; tpThumb.running = true;
    }
    function tpThumbOf(p) { const x = tpLib.find(i => i.path === p); return x ? (x.thumb || (x.video ? "" : p)) : (/\.(mp4|webm|mkv|mov|avi)$/i.test(p) ? "" : p); }
    function tpIsFav(p) { return ((tp.nastavenia || {}).oblubene || []).indexOf(p) >= 0; }
    function tpMenu(x, y, path, name, video) {
        const items = [{ glyph: "photo", label: "Nastaviť na všetky obrazovky", action: () => app.tpRun(["pouzi", path], "Pozadie: " + name) }];
        if (tpOuts.length > 1) for (const o of tpOuts) items.push({ glyph: "device-desktop", label: "Nastaviť na " + o.name + (o.popis ? " (" + o.popis + ")" : ""), action: () => app.tpRun(["pouzi", path, "--vystup", o.name], o.name + ": " + name) });
        items.push({ separator: true });
        if (!video) items.push({ glyph: "login", label: "Aj na prihlasovaciu obrazovku", action: () => app.setGreeter("background", path) });
        items.push({ glyph: "star", label: tpIsFav(path) ? "Odobrať z obľúbených" : "Pridať medzi obľúbené", action: () => app.tpRun(["oblubena", path, tpIsFav(path) ? "off" : "on"], "") });
        items.push({ glyph: "palette", label: "Farby témy z tejto tapety", action: () => app.tpRun(["farby", path], "Farby témy podľa " + name) });
        items.push({ glyph: "folder", label: "Ukázať v Súboroch", action: () => app.run(["latte-app", "subory", path.substring(0, path.lastIndexOf("/"))]) });
        items.push({ glyph: "clipboard", label: "Kopírovať cestu", action: () => app.run(["wl-copy", "--", path], "Cesta skopírovaná") });
        ctx.open(x, y, items, name);
    }
    // sťahovanie z katalógov (na úrovni aplikácie, aby pokračovalo aj po odchode zo stránky)
    property var tpDownloads: ({})          // url → percento
    Component {
        id: tpDlComp
        Process {
            id: dl
            property string url: ""
            stdout: SplitParser { onRead: (l) => {
                const m = l.match(/^P (-?\d+)/); if (m) { const d = Object.assign({}, app.tpDownloads); d[dl.url] = parseInt(m[1]); app.tpDownloads = d; }
                if (l.startsWith("OK ")) app.status = "Stiahnuté do knižnice: " + l.slice(3).split("/").pop();
                if (l.startsWith("E ")) app.status = "⚠ Sťahovanie zlyhalo: " + l.slice(2);
            } }
            onExited: { const d = Object.assign({}, app.tpDownloads); delete d[dl.url]; app.tpDownloads = d; tpLibP.running = true; destroy(); }
        }
    }
    function tpDownload(it) {
        if (tpDownloads[it.url] !== undefined) return;
        const d = Object.assign({}, tpDownloads); d[it.url] = 0; tpDownloads = d;
        const p = tpDlComp.createObject(app, { url: it.url }); p.command = ["latte-tapety", "stiahni", it.url, it.title]; p.running = true;
        status = "Sťahujem " + it.title + "…";
    }

    Component {
        id: pPozadie
        Column {
            id: pz
            spacing: 14
            readonly property var n: app.tp.nastavenia || {}
            property string pick: ""                                   // zvolený druh (pred prvou zmenou = uložený)
            readonly property string typ: pick || n.typ || "obrazok"
            readonly property string mode: app.tp.rezim || "crop"
            readonly property bool soft: !app.tp.gpu
            readonly property var images: app.wallpapers.map(p => ({ path: p, name: p.split("/").pop().replace(/\.[^.]*$/, ""), video: false, system: true }))
                                          .concat(app.tpLib.filter(x => !x.video))
            readonly property var lives: app.tpLib.filter(x => x.video)
            property bool allImages: false
            // aktuálna tapeta pre obrazovku (živá má prednosť)
            function wallOf(name) {
                const v = (app.tp.vystupy || {})[name] || (app.tp.vystupy || {})["*"];
                if (v) return { path: v.subor, video: true };
                if (app.tp.ziva_gif) return { path: app.tp.ziva_gif, video: false };
                return { path: (app.tp.staticke || {})[name] || (app.tp.staticke || {})["*"] || "", video: false };
            }
            readonly property string current: wallOf(app.tpTarget === "*" ? ((app.tpOuts[0] || {}).name || "") : app.tpTarget).path

            // ── náhľad obrazoviek (klik = vybrať obrazovku, pretiahnutie = nastaviť) ──
            Rectangle {
                id: prev
                width: Math.min(parent.width, 760); height: 250; radius: 14
                color: prevDrop.containsDrag ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.14) : theme.field
                border { color: prevDrop.containsDrag ? theme.primary : "transparent"; width: 1.5 }
                readonly property var outs: app.tpOuts.length ? app.tpOuts : [{ name: "", width: 1920, height: 1080, x: 0, y: 0 }]
                readonly property real minX: Math.min.apply(null, outs.map(o => o.x))
                readonly property real minY: Math.min.apply(null, outs.map(o => o.y))
                readonly property real spanW: Math.max(1, Math.max.apply(null, outs.map(o => o.x + o.width)) - minX)
                readonly property real spanH: Math.max(1, Math.max.apply(null, outs.map(o => o.y + o.height)) - minY)
                readonly property real k: Math.min((width - 60) / spanW, (height - 70) / spanH)
                Item {
                    id: desk
                    width: prev.spanW * prev.k; height: prev.spanH * prev.k
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                    Repeater {
                        model: prev.outs
                        Item {
                            id: mon
                            required property var modelData
                            readonly property var w: pz.wallOf(modelData.name)
                            readonly property bool sel: app.tpTarget === "*" || app.tpTarget === modelData.name
                            x: (modelData.x - prev.minX) * prev.k; y: (modelData.y - prev.minY) * prev.k
                            width: modelData.width * prev.k; height: modelData.height * prev.k
                            Rectangle {       // rám monitora
                                anchors.fill: parent; anchors.margins: 2; radius: 8; color: "#111"
                                border { color: mon.sel && prev.outs.length > 1 ? theme.primary : Qt.rgba(1, 1, 1, 0.18); width: mon.sel && prev.outs.length > 1 ? 3 : 2 }
                                Item {
                                    anchors { fill: parent; margins: 6 }
                                    clip: true
                                    Rectangle { anchors.fill: parent; color: pz.typ === "farba" ? (pz.n.farba || "#3B2A20") : (app.tp.okraje || "#000000") }
                                    Image {
                                        visible: pz.typ !== "farba"
                                        // Cez viac obrazoviek: jeden obrázok cez celú plochu (každý monitor ukáže svoj výrez)
                                        x: pz.mode === "span" ? -(mon.modelData.x - prev.minX) * prev.k : 0
                                        y: pz.mode === "span" ? -(mon.modelData.y - prev.minY) * prev.k : 0
                                        width: pz.mode === "span" ? prev.spanW * prev.k - 12 : parent.width
                                        height: pz.mode === "span" ? prev.spanH * prev.k - 12 : parent.height
                                        source: mon.w.path ? "file://" + (mon.w.video ? app.tpThumbOf(mon.w.path) : mon.w.path) : ""
                                        asynchronous: true
                                        fillMode: ({ crop: Image.PreserveAspectCrop, fit: Image.PreserveAspectFit, stretch: Image.Stretch, repeat: Image.Tile,
                                                     center: Image.Pad, span: Image.PreserveAspectCrop })[pz.mode] ?? Image.PreserveAspectCrop
                                        // dlaždica a centrovanie: obrázok v skutočnej veľkosti zmenšenej ako obrazovka
                                        sourceSize.width: (pz.mode === "repeat" || pz.mode === "center") ? Math.max(24, 1600 * prev.k) : 640
                                        sourceSize.height: (pz.mode === "repeat" || pz.mode === "center") ? Math.max(14, 900 * prev.k) : 360
                                    }
                                    Rectangle { visible: mon.w.video; anchors { left: parent.left; bottom: parent.bottom; margins: 5 } width: pvl.implicitWidth + 10; height: 16; radius: 5; color: Qt.rgba(0, 0, 0, 0.6)
                                                Text { id: pvl; anchors.centerIn: parent; text: "▶ živá"; color: "white"; font { family: theme.fontUi; pixelSize: 9; weight: Font.Bold } } }
                                }
                            }
                            Text { anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                                   text: (prev.outs.length > 1 ? (prev.outs.indexOf(mon.modelData) + 1) + " · " : "") + (mon.modelData.name || "") + (mon.modelData.width ? "  " + mon.modelData.width + " × " + mon.modelData.height : "")
                                   color: mon.sel ? theme.fg : theme.fgDim; font { family: theme.fontUi; pixelSize: 11; weight: mon.sel ? Font.Bold : Font.Normal } }
                            MouseArea { anchors.fill: parent; enabled: prev.outs.length > 1; cursorShape: Qt.PointingHandCursor
                                        onClicked: app.tpTarget = app.tpTarget === mon.modelData.name ? "*" : mon.modelData.name }
                        }
                    }
                }
                Text { anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
                       text: prevDrop.containsDrag ? "Pusti — obrázok a video sa nastavia, priečinok spustí prezentáciu"
                                                   : "Pretiahni sem obrázok, video alebo priečinok" + (prev.outs.length > 1 ? " · klik na obrazovku ju vyberie" : "")
                       color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                DropArea { id: prevDrop; anchors.fill: parent; keys: ["text/uri-list"]
                           onDropped: (d) => { if (d.hasUrls) { app.tpUse(app.dropPaths(d.urls)[0]); d.accept(Qt.CopyAction); } } }
            }
            // viac obrazoviek: pre ktorú obrazovku (ako Windows „Nastaviť pre monitor 1/2“)
            Segments {
                visible: app.tpOuts.length > 1
                options: [["*", "Všetky obrazovky"]].concat(app.tpOuts.map((o, i) => [o.name, (i + 1) + " · " + o.name + (o.popis ? " (" + o.popis + ")" : "")]))
                value: app.tpTarget
                onPicked: (v) => app.tpTarget = v
            }

            // ── druh pozadia ──
            Heading { text: "PRISPÔSOBENIE POZADIA" }
            Segments {
                options: [["obrazok", "Obrázok"], ["farba", "Plná farba"], ["prezentacia", "Prezentácia"], ["ziva", "Živá tapeta"]]
                value: pz.typ
                onPicked: (v) => {
                    pz.pick = v;
                    if (v === "farba") app.tpRun(["farba", pz.n.farba || "#3B2A20"].concat(app.tpOut()), "Plná farba");
                    else if (v === "prezentacia") app.tpRun(["prezentacia", pz.n.prezentacia_priecinok || ""].concat(app.tpOut()), "Prezentácia");
                    else if (v === "obrazok" && pz.n.typ !== "obrazok" && (app.tp.nedavne || []).length) app.tpRun(["pouzi", app.tp.nedavne[0]].concat(app.tpOut()), "Obrázok");
                    else app.tpRun(["typ", v], "");
                }
            }

            // Obrázok
            Column {
                visible: pz.typ === "obrazok"
                width: parent.width; spacing: 10
                Heading { text: "NEDÁVNE OBRÁZKY"; visible: (app.tp.nedavne || []).length > 0; font.pixelSize: 11 }
                Flow {
                    width: parent.width; spacing: 10; visible: (app.tp.nedavne || []).length > 0
                    Repeater { model: (app.tp.nedavne || []).slice(0, 5)
                        Thumb { required property string modelData; src: modelData; name: modelData.split("/").pop(); active: pz.current === modelData; fav: app.tpIsFav(modelData)
                                onClicked: app.tpUse(modelData); onMenu: (x, y) => app.tpMenu(x, y, modelData, name, false) } }
                }
                PickRow { label: "Vybrať fotografiu"; button: "Prehľadávať fotografie"
                          onBrowse: app.browse(["--typ", "obrazok", "--nazov", "Vybrať tapetu", "--start", app.home + "/Obrázky"], (p) => app.tpUse(p[0]))
                          onDropped: (p) => app.tpUse(p[0]) }
                Heading { text: "TAPETY LATTEOS A KNIŽNICA · " + pz.images.length; font.pixelSize: 11 }
                Flow {
                    width: parent.width; spacing: 10
                    Repeater { model: pz.allImages ? pz.images : pz.images.slice(0, 12)
                        Thumb { required property var modelData; src: modelData.thumb || modelData.path; name: modelData.name; active: pz.current === modelData.path; fav: app.tpIsFav(modelData.path)
                                onClicked: app.tpUse(modelData.path); onMenu: (x, y) => app.tpMenu(x, y, modelData.path, modelData.name, false) } }
                }
                Button { visible: pz.images.length > 12; label: pz.allImages ? "Menej" : "Zobraziť všetky (" + pz.images.length + ")"; glyph: pz.allImages ? "chevron-up" : "layout-grid"; onClicked: pz.allImages = !pz.allImages }
            }

            // Plná farba
            Column {
                visible: pz.typ === "farba"
                width: parent.width; spacing: 10
                Heading { text: "VYBERTE FARBU POZADIA"; font.pixelSize: 11 }
                Grid {
                    columns: 12; spacing: 8
                    Repeater {
                        model: ["#3B2A20", "#6F4E37", "#C8A27A", "#1B1410", "#FFB900", "#FF8C00", "#F7630C", "#CA5010", "#DA3B01", "#EF6950", "#D13438", "#FF4343",
                                "#E74856", "#E81123", "#EA005E", "#C30052", "#E3008C", "#BF0077", "#C239B3", "#9A0089", "#0078D7", "#0063B1", "#8E8CD8", "#6B69D6",
                                "#8764B8", "#744DA9", "#B146C2", "#881798", "#0099BC", "#2D7D9A", "#00B7C3", "#038387", "#00B294", "#018574", "#00CC6A", "#10893E",
                                "#7A7574", "#5D5A58", "#68768A", "#515C6B", "#567C73", "#486860", "#498205", "#107C10", "#767676", "#4C4A48", "#69797E", "#4A5459"]
                        Rectangle {
                            required property string modelData
                            width: 38; height: 38; radius: 8; color: modelData
                            border { color: (pz.n.farba || "").toUpperCase() === modelData ? theme.fg : "transparent"; width: 2.5 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.tpRun(["farba", modelData].concat(app.tpOut()), "Farba " + modelData) }
                        }
                    }
                }
                Row {
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Vlastná farba"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                    Field { width: 140; placeholder: "#RRGGBB"; text: pz.n.farba || ""
                            onCommitted: (t) => { const c = t.trim().startsWith("#") ? t.trim() : "#" + t.trim(); if (/^#[0-9a-fA-F]{6}$/.test(c) && c.toUpperCase() !== (pz.n.farba || "").toUpperCase()) app.tpRun(["farba", c].concat(app.tpOut()), "Farba " + c); } }
                }
            }

            // Prezentácia
            Column {
                visible: pz.typ === "prezentacia"
                width: parent.width; spacing: 10
                PickRow { label: "Obrázky z: " + (pz.n.prezentacia_priecinok ? pz.n.prezentacia_priecinok.replace(app.home, "~") : "celej knižnice tapiet")
                          hint: "Iný priečinok vyber tlačidlom alebo ho sem pretiahni zo Súborov"; button: "Prehľadávať priečinok"
                          onBrowse: app.browse(["--priecinok", "--nazov", "Priečinok pre prezentáciu", "--start", app.home + "/Obrázky"], (p) => app.tpRun(["prezentacia", p[0]].concat(app.tpOut()), "Prezentácia z " + p[0].split("/").pop()))
                          onDropped: (p) => app.tpUse(p[0]) }
                Button { visible: !!pz.n.prezentacia_priecinok; label: "Použiť celú knižnicu tapiet"; glyph: "books"; onClicked: app.tpRun(["prezentacia", ""].concat(app.tpOut()), "Prezentácia z knižnice") }
                Heading { text: "MENIŤ OBRÁZOK KAŽDÝCH"; font.pixelSize: 11 }
                Segments { options: [["1", "1 minútu"], ["10", "10 minút"], ["30", "30 minút"], ["60", "1 hodinu"], ["360", "6 hodín"], ["1440", "1 deň"]]
                           value: String(pz.n.rotacia || 30); onPicked: (v) => app.tpRun(["nastavenie", "rotacia", v], "Prezentácia: každých " + v + " min") }
                Segments { options: [["postupne", "Postupne"], ["nahodne", "Náhodné poradie"]]; value: pz.n.rotacia_poradie || "postupne"
                           onPicked: (v) => app.tpRun(["nastavenie", "rotacia_poradie", v], v === "nahodne" ? "Náhodné poradie" : "Postupne") }
                Toggle { visible: !pz.n.prezentacia_priecinok; on: !!pz.n.len_oblubene; label: "Iba obľúbené ★ (pravý klik na tapetu › Pridať medzi obľúbené)"
                         onToggled: app.tpRun(["nastavenie", "len_oblubene", pz.n.len_oblubene ? "false" : "true"], "") }
                Row { spacing: 10
                    Button { label: "Predošlý"; glyph: "chevron-left"; onClicked: app.tpRun(["predosla"].concat(app.tpOut()), "Predošlý obrázok") }
                    Button { label: "Ďalší obrázok"; glyph: "chevron-right"; onClicked: app.tpRun(["dalsia"].concat(app.tpOut()), "Ďalší obrázok") } }
            }

            // Živá tapeta
            Column {
                visible: pz.typ === "ziva"
                width: parent.width; spacing: 10
                Text { visible: pz.soft; width: Math.min(parent.width, 760); wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                       text: "Tento počítač kreslí bez grafickej akcelerácie: animovaný GIF alebo WebP pôjde hneď, video (MP4, WebM) sa uloží a spustí sa samo na počítači s GPU." }
                PickRow { label: "Vybrať video alebo animáciu"; button: "Prehľadávať videá"
                          onBrowse: app.browse(["--typ", "video", "--nazov", "Vybrať živú tapetu", "--start", app.home + "/Videá"], (p) => app.tpUse(p[0]))
                          onDropped: (p) => app.tpUse(p[0]) }
                Flow {
                    width: parent.width; spacing: 10
                    Repeater { model: pz.lives
                        Thumb { required property var modelData; src: modelData.thumb || ""; video: true; name: modelData.name; active: pz.current === modelData.path; fav: app.tpIsFav(modelData.path)
                                onClicked: app.tpUse(modelData.path); onMenu: (x, y) => app.tpMenu(x, y, modelData.path, modelData.name, true) } }
                    Rectangle { visible: pz.lives.length === 0; width: 164; height: 92; radius: 10; color: theme.field
                                Text { anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; text: "Živé tapety stiahneš\nv Tapety online"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.go("tapetyonline") } }
                }
                Row { spacing: 10
                    Button { label: "Pauza / pokračovať"; glyph: "player-pause"; onClicked: app.tpRun(["pauza"], "Pauza") }
                    Button { label: "Ďalšia"; glyph: "chevron-right"; onClicked: app.tpRun(["dalsia"].concat(app.tpOut()), "Ďalšia živá tapeta") }
                    Button { label: "Vypnúť živú tapetu"; glyph: "x"; onClicked: { app.tpRun(["stop"], "Živá tapeta vypnutá"); if (app.tp.ziva_gif) app.setLive(""); } } }
                Heading { text: "AUTOMATICKÁ PAUZA (0 % CPU A GPU)"; font.pixelSize: 11 }
                Segments { options: [["max", "Pri maximalizovanom okne"], ["full", "Iba pri celej obrazovke (hry)"], ["skryta", "Keď je zakrytá"], ["off", "Nikdy"]]
                           value: pz.n.auto_pauza || "max"; onPicked: (v) => app.tpRun(["nastavenie", "auto_pauza", v], "Uložené") }
                Toggle { on: pz.n.bateria !== false; label: "Na batérii pozastaviť"; onToggled: app.tpRun(["nastavenie", "bateria", pz.n.bateria !== false ? "false" : "true"], "Uložené") }
                Heading { text: "ZVUK TAPETY"; font.pixelSize: 11 }
                Segments { options: [["0", "Bez zvuku"], ["20", "Potichu"], ["50", "Stredne"], ["80", "Nahlas"]]; value: String(pz.n.ticho ? 0 : (pz.n.zvuk || 0))
                           onPicked: (v) => app.tpRun(["hlasitost", v], "Zvuk tapety") }
                Heading { text: "DEKÓDOVANIE VIDEA"; font.pixelSize: 11 }
                Segments { options: [["auto-safe", "Automaticky"], ["vaapi", "VA-API (Intel, AMD)"], ["nvdec", "NVDEC (NVIDIA)"], ["no", "Procesorom"]]
                           value: pz.n.hwdec || "auto-safe"; onPicked: (v) => app.tpRun(["nastavenie", "hwdec", v], "Uložené") }
            }

            // ── prispôsobenie obrázka (Windows: Vyplniť … Cez viac obrazoviek) ──
            Heading { visible: pz.typ !== "farba"; text: "PRISPÔSOBENIE OBRÁZKA" }
            Segments {
                visible: pz.typ !== "farba"
                options: [["crop", "Vyplniť"], ["fit", "Prispôsobiť"], ["stretch", "Roztiahnuť"], ["repeat", "Dlaždica"], ["center", "Centrovať"], ["span", "Cez viac obrazoviek"]]
                value: pz.mode
                onPicked: (v) => app.tpRun(["rezim", v], ({ crop: "Vyplniť", fit: "Prispôsobiť", stretch: "Roztiahnuť", repeat: "Dlaždica", center: "Centrovať", span: "Cez viac obrazoviek" })[v])
            }
            Text { visible: pz.typ !== "farba"; width: Math.min(parent.width, 760); wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: ({ crop: "Obrázok vyplní obrazovku, presah sa oreže.", fit: "Celý obrázok je vidieť, voľné okraje majú farbu nižšie.", stretch: "Obrázok sa roztiahne na obrazovku (môže sa zdeformovať).",
                            repeat: "Obrázok v pôvodnej veľkosti sa opakuje ako dlaždice.", center: "Obrázok v pôvodnej veľkosti v strede, okolo farba nižšie.",
                            span: "Jeden obrázok cez všetky obrazovky, ako jedna veľká plocha." + (app.tpOuts.length < 2 ? " Pri jednej obrazovke je to ako Vyplniť." : "") })[pz.mode]
                         + (pz.typ === "ziva" ? " Video pozná Vyplniť, Prispôsobiť a Roztiahnuť." : "") }
            Row {
                visible: pz.typ !== "farba" && (pz.mode === "fit" || pz.mode === "center")
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Farba okrajov"; color: theme.fg; rightPadding: 6; font { family: theme.fontUi; pixelSize: 13 } }
                Repeater {
                    model: ["#000000", "#1B1410", "#3B2A20", "#6F4E37", "#C8A27A", "#F5EDE2", "#2F5D8A", "#3E7C59"]
                    Rectangle {
                        required property string modelData
                        width: 30; height: 30; radius: 15; color: modelData
                        border { color: (app.tp.okraje || "").toUpperCase() === modelData ? theme.primary : theme.line; width: 2 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { app.shellSet("wallpaper.fill_color", modelData, "Farba okrajov " + modelData); tpRefresh.restart(); } }
                    }
                }
                Timer { id: tpRefresh; interval: 600; onTriggered: tpStav.running = true }
            }

            // ── ďalšie ──
            Heading { text: "ĎALŠIE" }
            Toggle { on: app.wsWallpaper; label: "Každá plocha má inú tapetu (poradie tapiet LatteOS)"
                     onToggled: { app.wsWallpaper = !app.wsWallpaper; app.writePref("wallpaper-per-workspace", app.wsWallpaper ? "1" : "", app.wsWallpaper ? "Tapeta podľa plochy: zapnuté" : "Tapeta podľa plochy: vypnuté"); } }
            Toggle { on: app.deskIcons !== "off"; label: "Ikony na ploche (Kôš a súbory z ~/Plocha)"
                     onToggled: {
                         const on = app.deskIcons === "off";
                         app.deskIcons = on ? "" : "off";
                         app.writePref("desktop-icons", on ? "" : "off", on ? "Ikony na ploche zapnuté" : "Ikony na ploche vypnuté");
                         if (on) app.run(["sh", "-c", "pgrep -f 'apps/[p]locha.qml' >/dev/null || setsid latte-app plocha >/dev/null 2>&1 &"]);
                     } }
            Toggle { on: !!pz.n.farby; label: "Farby témy podľa tapety (inak farby témy LatteOS)"
                     onToggled: app.tpRun(["nastavenie", "farby", pz.n.farby ? "false" : "true"], pz.n.farby ? "Farby podľa témy" : "Farby podľa tapety") }
            Heading { text: "PRIEČINKY KNIŽNICE TAPIET"; font.pixelSize: 11 }
            Repeater {
                model: pz.n.adresare || []
                Row {
                    required property string modelData
                    spacing: 8
                    Glyph { anchors.verticalCenter: parent.verticalCenter; name: "folder"; size: 16; color: theme.primary }
                    Text { width: 380; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle; text: modelData.replace(app.home, "~"); color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                    IconButton { theme: app.latteTheme; glyph: "folder-open"; tip: "Otvoriť v Súboroch"; onClicked: app.run(["latte-app", "subory", modelData]) }
                    IconButton { theme: app.latteTheme; glyph: "x"; tip: "Odobrať z knižnice (súbory ostanú)"; onClicked: { app.tpRun(["adresar", "odober", modelData], "Priečinok odobratý"); tpLibP.running = true; } }
                }
            }
            PickRow { label: "Pridať priečinok do knižnice"; button: "Prehľadávať priečinok"; hint: "alebo sem pretiahni priečinok zo Súborov"
                      onBrowse: app.browse(["--priecinok", "--nazov", "Priečinok s tapetami"], (p) => { app.tpRun(["adresar", "pridaj", p[0]], "Priečinok pridaný"); tpLibP.running = true; })
                      onDropped: (p) => { app.tpRun(["adresar", "pridaj", p[0]], "Priečinok pridaný"); tpLibP.running = true; } }
        }
    }

    // ── Tapety online (katalógy z Aury) ──────────────────────────────────────────
    property string olSrc: "motionbgs"
    property string olCat: "all"
    property string olQuery: ""
    property string olRes: "hd"
    property string olSort: "toplist"
    property int olPage: 1
    property var olItems: []
    property string olErr: ""
    Cmd { id: olProc; onDone: (o) => { try { const d = JSON.parse(o); app.olItems = app.olPage > 1 ? app.olItems.concat(d.items) : d.items; app.olErr = d.error; } catch (e) { app.olErr = "katalóg sa nedá načítať"; } } }
    function olLoad(more) {
        olPage = more ? olPage + 1 : 1;
        if (!more) olItems = [];
        olProc.command = ["latte-tapety", "online", olSrc, "--strana", String(olPage), "--rozlisenie", olRes, "--triedenie", olSort]
                         .concat(olQuery ? ["--hladaj", olQuery] : []).concat(olCat !== "all" ? ["--kategoria", olCat] : []);
        olProc.running = true;
    }
    onSectionChanged: if (section === "pozadie" && pozadieTab === "online" && olItems.length === 0 && !olProc.running) olLoad(false)
    onPozadieTabChanged: if (section === "pozadie" && pozadieTab === "online" && olItems.length === 0 && !olProc.running) olLoad(false)
    readonly property var olCats: ({
        motionbgs: [["all", "Všetko"], ["anime", "Anime"], ["nature", "Príroda"], ["games", "Hry"], ["space", "Vesmír"], ["fantasy", "Fantasy"],
                    ["car", "Autá"], ["superhero", "Superhrdinovia"], ["technology", "Technológie"]],
        wallhaven: [["111", "Všetko"], ["100", "Všeobecné"], ["010", "Anime"], ["110", "Všeobecné + anime"]],
        bing: [], minimal: [] })
    Component {
        id: pTapetyOnline
        Column {
            spacing: 12
            Segments { options: [["motionbgs", "MotionBGS · živé"], ["wallhaven", "Wallhaven · 4K"], ["bing", "Bing · denná fotka"], ["minimal", "Minimalistické"]]
                       value: app.olSrc; onPicked: (v) => { app.olSrc = v; app.olCat = v === "wallhaven" ? "111" : "all"; app.olLoad(false); } }
            Row {
                spacing: 10
                Field { width: 360; placeholder: "Hľadať v katalógu (Enter)"; text: app.olQuery; visible: app.olSrc !== "bing"
                        onCommitted: (t) => { if (t.trim() !== app.olQuery) { app.olQuery = t.trim(); app.olLoad(false); } } }
                Segments { width: 420; visible: app.olSrc === "motionbgs" || app.olSrc === "wallhaven"
                           options: app.olSrc === "motionbgs" ? [["hd", "1080p"], ["4k", "4K"]] : [["all", "Všetky"], ["2k", "2K"], ["4k", "4K"], ["ultrawide", "Ultrawide"]]
                           value: app.olRes; onPicked: (v) => { app.olRes = v; app.olLoad(false); } }
            }
            Segments { visible: app.olSrc === "wallhaven"; options: [["toplist", "Najlepšie"], ["hot", "Populárne"], ["random", "Náhodne"]]
                       value: app.olSort; onPicked: (v) => { app.olSort = v; app.olLoad(false); } }
            Segments { visible: (app.olCats[app.olSrc] || []).length > 0; options: app.olCats[app.olSrc] || []
                       value: app.olCat; onPicked: (v) => { app.olCat = v; app.olLoad(false); } }
            Text { visible: app.olErr !== ""; text: "⚠ " + app.olErr; color: theme.error; font { family: theme.fontUi; pixelSize: 12 } }
            Text { visible: olProc.running && app.olItems.length === 0; text: "Načítavam katalóg…"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
            Flow {
                width: parent.width; spacing: 12
                Repeater {
                    model: app.olItems
                    Column {
                        required property var modelData
                        spacing: 4
                        Thumb { w: 220; src: modelData.thumb; video: modelData.video; name: modelData.title
                                progress: app.tpDownloads[modelData.url] !== undefined ? app.tpDownloads[modelData.url] : -2
                                onClicked: app.tpDownload(modelData)
                                onMenu: (x, y) => ctx.open(x, y, [
                                    { glyph: "download", label: "Stiahnuť do knižnice", action: () => app.tpDownload(modelData) },
                                    { glyph: "external-link", label: "Otvoriť v prehliadači", action: () => app.run(["xdg-open", modelData.url]) }
                                ], modelData.title) }
                        Text { width: 220; elide: Text.ElideRight; text: modelData.res + (modelData.author ? " · " + modelData.author : "") + (modelData.date ? " · " + modelData.date : "")
                               color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 } }
                    }
                }
            }
            Button { visible: app.olItems.length > 0 && app.olSrc !== "bing"; label: olProc.running ? "Načítavam…" : "Načítať ďalšie"; glyph: "refresh"
                     onClicked: if (!olProc.running) app.olLoad(true) }
            Text { width: Math.min(parent.width, 760); wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Klik stiahne tapetu do ~/.local/share/latteos/tapety. Nastavíš ju v Pozadí (Obrázok alebo Živá tapeta). Živé videá hrajú iba s grafickou akceleráciou." }
        }
    }
    Component {
        id: pOkna
        Column {
          spacing: 14
          Flow {
            width: parent.width
            spacing: 10
            Repeater {
                model: [["paska", "Nekonečná páska", "Okná v stĺpcoch vedľa seba, páska sa posúva"],
                        ["dlazdice", "Dlaždice", "Okná sa delia o obrazovku"],
                        ["plavajuce", "Plávajúce okná", "Voľné okná ako vo Windows"]]
                Card {
                    required property var modelData
                    width: 240; title: modelData[1]; sub: modelData[2]; selected: app.windowMode === modelData[0]
                    onClicked: { app.run(["hyprctl", "eval", "require(\"latte.windows\").apply(\"" + modelData[0] + "\", true)"], modelData[1]); app.windowMode = modelData[0]; }
                }
            }
        }
          Heading { text: "MULTITASKING (plávajúce okná, ako Windows 11)"; topPadding: 6 }
          Segments {
              options: [["", "Prichytávať okná k okrajom"], ["off", "Neprichytávať"]]
              value: app.snapOff
              onPicked: (v) => { app.snapOff = v; app.writePref("bez-prichytenia", v === "off" ? "1" : "", v === "off" ? "Prichytávanie vypnuté" : "Okno pritiahnuté k okraju sa prichytí (polovica, štvrtina, celá obrazovka)"); }
          }
          Segments {
              enabled: app.snapOff !== "off"; opacity: enabled ? 1 : 0.5
              options: [["", "Lišta rozložení (horný okraj a podržanie nad □)"], ["off", "Bez lišty rozložení"]]
              value: app.snapBarOff
              onPicked: (v) => { app.snapBarOff = v; app.writePref("bez-listy-rozlozeni", v === "off" ? "1" : "", v === "off" ? "Lišta rozložení vypnutá" : "Lišta rozložení zapnutá"); }
          }
          Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                 text: "Okno pritiahnuté k ľavému alebo pravému okraju zaberie polovicu, k rohu štvrtinu, k hornému okraju celú obrazovku; odtiahnutie vráti pôvodnú veľkosť. Win + šípky robia to isté z klávesnice. V páske a dlaždiciach okná rozkladá systém sám." }
        }
    }
    Component {
        id: pLista
        Column {
            spacing: 12
            Stepper { label: "Hrúbka lišty"; value: parseInt(app.bar.thickness) || 56; step: 4; min: 40; max: 72
                      onStepped: (v) => app.shellSet("bar.main.thickness", v, "Hrúbka lišty " + v) }
            Stepper { label: "Odsadenie od okrajov (šírka)"; value: parseInt(app.bar.margin_ends) || 12; step: 24; min: 0; max: 480
                      onStepped: (v) => app.shellSet("bar.main.margin_ends", v, "Odsadenie od okrajov " + v) }
            Stepper { label: "Odsadenie od spodku"; value: parseInt(app.bar.margin_edge) || 10; step: 2; min: 0; max: 40
                      onStepped: (v) => app.shellSet("bar.main.margin_edge", v, "Odsadenie od spodku " + v) }
            Stepper { label: "Medzera medzi ostrovmi"; value: parseInt(app.bar.widget_spacing) || 6; step: 2; min: 4; max: 32
                      onStepped: (v) => app.shellSet("bar.main.widget_spacing", v, "Medzera " + v) }
            Heading { text: "OKNÁ Z LIŠTY V TVARE L · ANIMOVANÁ TEXTÚRA" }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "App Manager (vľavo) a Zariadenia (vpravo) vyrastajú z ostrova na lište: ostrov je päta písmena L, nad ním pás s textúrou a okno. Textúra sa kreslí na dlaždici aj v páse naraz, bez švu." }
            // náhľad: presne ako na lište — skutočné rozmery okna L (kmeň 660 × 50, medzera 10, ostrov 100 × 43),
            // rovnaký zdroj GIF (snímky, ohnisko, priblíženie) ako dlaždica a okno, iba zmenšené
            Item {
                id: lPrev
                width: Math.min(parent.width, 560); height: 103 * k + 24
                readonly property real k: (width - 24) / 660
                property real t: 0
                Timer { interval: 125; repeat: true; running: lPrev.visible && app.barAnim !== "vypnuty"; onTriggered: lPrev.t += 0.125 }
                GifZdroj { id: prevGif; spec: app.barScene; playing: lPrev.visible && app.barAnim !== "vypnuty" }
                Rectangle { anchors.fill: parent; radius: 12; color: theme.field }
                Item {
                    x: 12; y: 12; width: 660; height: 103
                    transform: Scale { xScale: lPrev.k; yScale: lPrev.k }
                    Item {
                        width: 660; height: 50
                        Scena { anchors.fill: parent; colors: app.latteTheme; spec: app.barScene; time: lPrev.t; motion: app.barAnim === "vypnuty" ? "vypnute" : "vzdy"
                                canvasW: 660; canvasH: 103; radii: [16, 16, 16, 0]
                                image: prevGif.image; frame: prevGif.frame; frameDir: prevGif.frameDir; frameCount: prevGif.frameCount; ohnisko: prevGif.ohnisko; anchorX: 50; anchorY: 103 - 21.5 }
                        Rectangle { anchors.fill: parent; radius: 16; gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(app.latteTheme.surface.r, app.latteTheme.surface.g, app.latteTheme.surface.b, 0.05) }
                            GradientStop { position: 1; color: Qt.rgba(app.latteTheme.surface.r, app.latteTheme.surface.g, app.latteTheme.surface.b, app.barDim) } } }
                        Text { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "22 aplikácií   App Manager ›"
                               color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                    }
                    Item {
                        y: 50; width: 100; height: 53
                        Scena { anchors.fill: parent; colors: app.latteTheme; spec: app.barScene; time: lPrev.t; motion: app.barAnim === "vypnuty" ? "vypnute" : "vzdy"
                                oy: 50; canvasW: 660; canvasH: 103; radii: [0, 0, 16, 16]
                                image: prevGif.image; frame: prevGif.frame; frameDir: prevGif.frameDir; frameCount: prevGif.frameCount; ohnisko: prevGif.ohnisko; anchorX: 50; anchorY: 103 - 21.5 }
                        Rectangle { x: 35; y: 10 + 6.5; width: 30; height: 30; radius: 10; visible: !app.barScene.startsWith("file:")
                                    color: Qt.rgba(app.latteTheme.surfaceVariant.r, app.latteTheme.surfaceVariant.g, app.latteTheme.surfaceVariant.b, 0.85)
                                    Glyph { anchors.centerIn: parent; name: "apps"; size: 18; color: app.latteTheme.primary } }
                    }
                    // GIF / obrázok: bez ikony, iba rám okolo celého L (ako LPopup.framed)
                    Canvas {
                        width: 660; height: 103; visible: app.barScene.startsWith("file:")
                        onVisibleChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d"), h = 1, P = Math.PI; c.reset();
                            c.strokeStyle = app.latteTheme.primary; c.lineWidth = 2;
                            c.beginPath(); c.moveTo(h, 16); c.arc(16, 16, 16 - h, P, 1.5 * P); c.lineTo(644, h); c.arc(644, 16, 16 - h, 1.5 * P, 2 * P);
                            c.lineTo(660 - h, 34); c.arc(644, 34, 16 - h, 0, 0.5 * P); c.lineTo(110, 50 - h); c.quadraticCurveTo(100 - h, 50 - h, 100 - h, 60);
                            c.lineTo(100 - h, 87); c.arc(84, 87, 16 - h, 0, 0.5 * P); c.lineTo(16, 103 - h); c.arc(16, 87, 16 - h, 0.5 * P, P); c.closePath(); c.stroke();
                        }
                    }
                    Rectangle { x: 106; y: 60; width: 225; height: 43; radius: 16; color: theme.hover
                                Text { anchors.centerIn: parent; text: "05:35  ·  pi 25. 9."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } } }
                }
            }
            Segments {
                options: [["para", "Para"], ["matrix", "Matrix"], ["gears", "Ozubené kolesá"], ["glow", "Pomalé svetlo"], ["solid", "Jedna farba"], ["file", "Obrázok / GIF"]]
                value: app.barScene.split(":")[0]
                onPicked: (v) => {
                    const s = v === "solid" ? "solid:" + (app.barScene.startsWith("solid:") ? app.barScene.slice(6) : String(app.latteTheme.primary))
                            : v === "file" ? "file:" + (app.barScene.startsWith("file:") ? app.barScene.slice(5) : "") : v;
                    app.barScene = s;
                    if (v !== "file" || s !== "file:") app.writePref("bar-scene", s, "Textúra L: " + v);
                }
            }
            Segments {
                visible: /^file:.*\.(gif|webp)$/i.test(app.barScene)
                options: [["", "Priblížiť na pohyb (ostrov ukáže, kde sa GIF hýbe)"], ["off", "Celý obrázok bez priblíženia"]]
                value: app.barZoom
                onPicked: (v) => { app.barZoom = v; app.writePref("bar-priblizenie", v, v === "off" ? "GIF: celý obrázok" : "GIF: priblížiť na pohyb"); }
            }
            Row {
                visible: app.barScene.startsWith("solid:")
                spacing: 8
                Repeater {
                    model: [String(app.latteTheme.primary), "#6F4E37", "#C8A27A", "#3E7C59", "#2F5D8A", "#7A3E8C", "#A33B3B", "#222222"]
                    Rectangle {
                        required property string modelData
                        width: 32; height: 32; radius: 16; color: modelData
                        border { color: app.barScene === "solid:" + modelData ? theme.fg : "transparent"; width: 2 }
                        MouseArea { anchors.fill: parent; onClicked: { app.barScene = "solid:" + modelData; app.writePref("bar-scene", app.barScene, "Farba L: " + modelData); } }
                    }
                }
                Field { width: 130; placeholder: "#RRGGBB"; text: app.barScene.startsWith("solid:") ? app.barScene.slice(6) : ""
                        onCommitted: (t) => { if (/^#[0-9a-fA-F]{6}$/.test(t.trim())) { app.barScene = "solid:" + t.trim(); app.writePref("bar-scene", app.barScene, "Farba L: " + t.trim()); } } }
            }
            Column {
                visible: app.barScene.startsWith("file:")
                spacing: 6
                PickRow { label: app.barScene.length > 5 ? "Textúra: " + app.barScene.slice(5).split("/").pop() : "Vybrať obrázok alebo GIF (GIF, WebP, PNG, JPG)"; button: "Prehľadávať"
                          onBrowse: app.browse(["--typ", "obrazok", "--nazov", "Obrázok pre textúru L", "--start", app.home + "/Obrázky"], (p) => app.setBarFile(p[0]))
                          onDropped: (p) => app.setBarFile(p[0]) }
                Text { color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: "Obrázok vyplní celý pás L (orezaný na šírku). Dlaždica na lište ukáže ten istý obraz bez ikony, iba s rámom; pri otvorení okna sa rám roztiahne na celé L." }
            }
            Heading { text: "Pravé L (Zariadenia)"; font.pixelSize: 11 }
            Segments {
                options: [["", "Rovnaká ako vľavo"], ["para", "Para"], ["matrix", "Matrix"], ["gears", "Ozubené kolesá"], ["glow", "Pomalé svetlo"]]
                value: app.barSceneRight
                onPicked: (v) => { app.barSceneRight = v; app.writePref("bar-scene-vpravo", v, "Textúra pravého L: " + (v || "ako vľavo")); }
            }
            Stepper { label: "Stlmenie textúry pod textom"; value: Math.round(app.barDim * 100); step: 10; min: 0; max: 90; unit: " %"
                      onStepped: (v) => { app.barDim = v / 100; app.writePref("bar-stlmenie", (v / 100).toFixed(2), "Stlmenie " + v + " %"); } }
            Heading { text: "POHYB TEXTÚRY (dlaždica aj L)"; font.pixelSize: 11 }
            Segments {
                options: [["", "Podľa výkonu"], ["vzdy", "Vždy v pohybe"], ["kurzor", "Pod kurzorom"], ["vypnuty", "Bez pohybu"]]
                value: app.barAnim
                onPicked: (v) => { app.barAnim = v; app.writePref("bar-anim", v, "Pohyb textúry: " + (v || "podľa výkonu")); }
            }
            Heading { text: "SYSTÉMOVÉ MENU (šálka)" }
            Segments {
                options: [["", "Rýchly stupeň a režim okien"], ["off", "Iba účet, Nastavenia, Monitor, napájanie"]]
                value: app.cupQuick
                onPicked: (v) => { app.cupQuick = v; app.writePref("cup-quick", v, v === "off" ? "Šálka bez rýchlych volieb" : "Šálka s rýchlymi voľbami"); }
            }
            Heading { text: "MASKOT" }
            Segments {
                // rovnaké postavy ako plugin latteos/cat (common.luau M.names); staré voľby macka/zrnko = Latte mačka
                options: [["homebrew", "Homebrew"], ["drak", "Kávový drak"], ["ktulu", "Ktulu"], ["robot", "Robot turista"], ["maid", "Maid"],
                          ["kapybara", "Kapybara"], ["latte", "Latte mačka"], ["mokka", "Mokka"], ["tien", "Tieň"], ["liska", "Líška"],
                          ["myval", "Mýval"], ["svetluska", "Svetluška"], ["cdrak", "Dráčik"], ["ziadny", "Žiadny"]]
                value: ({ macka: "latte", zrnko: "latte", void: "cdrak" })[app.mascot] || app.mascot
                // výber postavy maskota zároveň zapne, ak bol vypnutý (inak by zmizol z lišty aj s ponukou, ktorá ho zapína)
                onPicked: (v) => { app.mascot = v; app.writePref("mascot", v, "Maskot: " + v);
                                   if (v !== "ziadny" && app.mascotMode === "off") { app.mascotMode = "slot"; app.writePref("mascot-mode", "slot", "Maskot je späť na lište"); } }
            }
            Segments {
                visible: app.mascot !== "ziadny"
                options: [["off", "Vypnutý"], ["slot", "Ostrov na lište"], ["world", "Výbehy po lište a oknách"], ["chaos", "Chaos po celej ploche"]]
                value: app.mascotMode || (app.mascotEscape === "off" ? "slot" : "world")
                onPicked: (v) => { app.mascotMode = v; app.writePref("mascot-mode", v, v === "off" ? "Maskot je skrytý" : "Maskot: " + ({ slot: "ostrov", world: "výbehy", chaos: "chaos" })[v]); }
            }
            Segments {
                visible: app.mascot !== "ziadny"
                options: [["", "Uteká, keď sa nudí alebo si preč"], ["off", "Zostáva na lište"]]
                value: app.mascotEscape
                onPicked: (v) => { app.mascotEscape = v; app.writePref("mascot-escape", v, v === "off" ? "Maskot zostáva na lište" : "Maskot môže utiecť"); }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Maskot ťuká labkami do rytmu hudby, žmurká a v noci či pri Nerušiť spí. Keď si 5 minút preč alebo sa nudí, odíde na prechádzku a vráti sa s tebou (klik ho zavolá). Ktulu občas vystrčí chápadlá z lišty. Pohyb stojí trochu CPU, preto je vo VM väčšinou iba pri hudbe." }
            Row {
                spacing: 10
                Button { label: "Predvolené LatteOS"; glyph: "refresh"
                         onClicked: app.run(["sh", "-c", "for k in thickness margin_ends margin_edge widget_spacing; do latte-shellset unset bar.main.$k; done"], "Lišta: predvolené") }
                Button { label: "Ďalšie voľby lišty (Noctalia)"; glyph: "settings"; onClicked: app.run(["noctalia", "msg", "settings-open"]) }
            }
        }
    }
    Component {
        id: pEfekty
        Column {
            spacing: 14
            Heading { text: "ŽIVÁ TAPETA (pohyblivá textúra nad tapetou, pod oknami)" }
            Segments {
                options: [["", "Vypnutá"], ["tema", "Podľa témy"], ["para", "Para"], ["salka", "Para zo šálky"], ["bublinky", "Bublinky"], ["sneh", "Sneh"], ["iskry", "Iskry"], ["trblietky", "Trblietky"], ["prach", "Prach"]]
                value: app.liveWp.startsWith("video:") ? "" : app.liveWp
                onPicked: (v) => app.setLive(v)
            }
            Heading { text: "VIDEO ALEBO ANIMÁCIA AKO TAPETA (ako X Live Wallpaper)" }
            PickRow { label: app.liveWp.startsWith("video:") ? "Hrá: " + app.liveWp.slice(6).split("/").pop() : "Vybrať video alebo animáciu"; button: "Prehľadávať videá"
                      onBrowse: app.browse(["--typ", "video", "--nazov", "Vybrať živú tapetu", "--start", app.home + "/Videá"], (p) => app.tpRun(["pouzi", p[0]], "Živá tapeta: " + p[0].split("/").pop()))
                      onDropped: (p) => app.tpRun(["pouzi", p[0]], "Živá tapeta: " + p[0].split("/").pop()) }
            Row {
                spacing: 10
                Button { label: "Živé tapety v Pozadí"; glyph: "photo"; onClicked: app.go("pozadie") }
                Button { visible: app.liveWp.startsWith("video:"); label: "Vypnúť video"; glyph: "x"; onClicked: app.setLive("") }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Bez zvuku, v slučke, pri hre a okne na celú obrazovku stojí. V Súboroch: pravý klik na video › Nastaviť ako živú tapetu. "
                         + ((app.mode.tier === "softver" || app.mode.tier === "minimalny") ? "Video (MP4, WebM) potrebuje grafickú akceleráciu — v stupni Softvér pôjde iba animovaný GIF alebo WebP." : "MP4, WebM, MKV, GIF aj WebP.") }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Podľa témy: Latte = para, Mráz = para zo šálky na tapete, Jantár = bublinky, kovy = iskry, drahokamy = trblietky, kameň = prach. "
                         + "V hernom režime stojí. Stojí asi 2 % jedného jadra" + ((app.mode.tier === "softver" || app.mode.tier === "minimalny") ? " — vo VM so softvérovým kreslením ju odporúčame nechať vypnutú." : ".") }
            Heading { text: "SKLO POD PANELMI" }
            Toggle { on: app.skloPref; label: "Matné sklo v oknách z lišty (rozmazaná tapeta, funguje aj bez GPU)"
                     onToggled: { app.skloPref = !app.skloPref; app.writePref("sklo", app.skloPref ? "" : "off", app.skloPref ? "Sklo zapnuté" : "Sklo vypnuté"); } }
            Heading { text: "EFEKTY OKIEN" }
            Button { label: "Stupeň výkonu"; glyph: "bolt"; primaryStyle: true; onClicked: app.go("vykon") }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                   text: "Sklo, tiene a žiaru okien riadi stupeň výkonu. Herný režim (Zariadenia na lište) ich vypne dočasne. Materiály tém ako shadery (mráz na skle, kovový lesk) prídu s GPU na reálnom HW." }
        }
    }
    Component {
        id: pStart
        Column {
            spacing: 14
            Heading { text: "ĎALŠÍ ŠTART" }
            Row {
                spacing: 10
                Card { title: "NORMAL"; sub: "Hyprland + Noctalia (odporúčané)"; selected: !app.forceSafe
                       onClicked: app.run(["latte-boot", "reset"], "Ďalší štart: NORMAL") }
                Card { title: "SAFE"; sub: "labwc bez GPU, iba nabudúce"; selected: app.forceSafe
                       onClicked: app.run(["latte-boot", "force-safe"], "Ďalší štart: SAFE") }
            }
            Heading { text: "POČÍTADLO PÁDOV" }
            Row {
                spacing: 12
                Text { anchors.verticalCenter: parent.verticalCenter; text: app.crashCount + " z 2 pádov (pri 2 naštartuje SAFE)"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                Button { label: "Diagnostika"; glyph: "stethoscope"; onClicked: app.go("diagnostika") }
            }
        }
    }
    Component {
        id: pCas
        Column {
            spacing: 14
            Heading { text: "POLOHA (VÝCHOD A ZÁPAD SLNKA)" }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: [["Bratislava", 48.15, 17.11], ["Banská Bystrica", 48.74, 19.15], ["Košice", 48.72, 21.26], ["Žilina", 49.22, 18.74],
                            ["Praha", 50.08, 14.43], ["Brno", 49.20, 16.61], ["Viedeň", 48.21, 16.37], ["Budapešť", 47.50, 19.04], ["Londýn", 51.51, -0.13]]
                    Card {
                        required property var modelData
                        width: 150; height: 52; title: modelData[0]; sub: modelData[1] + ", " + modelData[2]
                        selected: Math.abs((parseFloat(app.location.latitude) || 48.74) - modelData[1]) < 0.01 && Math.abs((parseFloat(app.location.longitude) || 19.15) - modelData[2]) < 0.01
                        onClicked: {
                            app.run(["sh", "-c", "latte-shellset set location.latitude \"$1\" && latte-shellset set location.longitude \"$2\"", "sh", String(modelData[1]), String(modelData[2])], "Poloha: " + modelData[0]);
                            // počasie na obrazovke prihlásenia pre to isté mesto
                            app.setGreeter("place", modelData[0]); app.setGreeter("lat", String(modelData[1])); app.setGreeter("lon", String(modelData[2]));
                            app.status = "Poloha: " + modelData[0];
                        }
                    }
                }
            }
            Heading { text: "ĎALŠIE ČASOVÉ PÁSMA V PANELI ČAS" }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: [["Europe/London", "Londýn"], ["America/New_York", "New York"], ["America/Los_Angeles", "Los Angeles"], ["Asia/Tokyo", "Tokio"],
                            ["Asia/Shanghai", "Peking"], ["Asia/Kolkata", "Dillí"], ["Australia/Sydney", "Sydney"], ["Europe/Moscow", "Moskva"], ["UTC", "UTC"]]
                    Card {
                        required property var modelData
                        width: 150; height: 52; title: modelData[1]; sub: modelData[0]; selected: app.clockZones.indexOf(modelData[0]) >= 0
                        onClicked: app.toggleZone(modelData[0])
                    }
                }
            }
        }
    }
    Component {
        id: pO
        Column {
            spacing: 6
            Row {
                spacing: 14; bottomPadding: 10
                Image { source: "file:///usr/share/latteos/noctalia/icons/latte-cup.png"; width: 56; height: 56 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "LatteOS"; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 26; weight: Font.DemiBold } }
                    Text { text: "vývojárska verzia · gamerdistro"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                }
            }
            Repeater {
                model: app.about.split("\n").filter(l => l.includes("|"))
                Row {
                    required property string modelData
                    spacing: 12
                    Text { width: 130; text: modelData.split("|")[0]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                    Text { text: modelData.split("|")[1] || "—"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                }
            }
        }
    }
    Component {
        id: pCloud
        Column {
            id: cloudPage
            spacing: 12
            readonly property var types: ({ drive: "Google Drive", onedrive: "OneDrive", dropbox: "Dropbox", webdav: "Nextcloud / WebDAV", s3: "S3", sftp: "SFTP (domáci server)", pcloud: "pCloud", mega: "MEGA", box: "Box", protondrive: "Proton Drive", alias: "priečinok" })
            Text { visible: app.clouds.length === 0; width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                   text: "Zatiaľ žiadny účet. Klikni Pridať účet — otvorí sa sprievodca rclone (n = nový, potom vyber službu a prihlás sa v prehliadači)." }
            Repeater {
                model: app.clouds
                Rectangle {
                    required property var modelData
                    width: Math.min(parent.width, 680); height: 64; radius: 12; color: theme.field
                    Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "cloud"; size: 24; color: modelData.mounted ? theme.primary : theme.fgDim }
                    Column {
                        x: 50; anchors.verticalCenter: parent.verticalCenter
                        Text { text: parent.parent.modelData.name; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        Text { text: (cloudPage.types[parent.parent.modelData.type] || parent.parent.modelData.type) + " · " + (parent.parent.modelData.mounted ? "● pripojené v ~/Cloud/" + parent.parent.modelData.name : "○ odpojené")
                               color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Button { visible: parent.parent.modelData.mounted; label: "Otvoriť"; glyph: "folder"; onClicked: app.run(["latte-app", "subory", app.home + "/Cloud/" + parent.parent.modelData.name]) }
                        Button { label: parent.parent.modelData.mounted ? "Odpojiť" : "Pripojiť"; glyph: "cloud"; primaryStyle: !parent.parent.modelData.mounted
                                 onClicked: { app.run(["latte-cloud", parent.parent.modelData.mounted ? "unmount" : "mount", parent.parent.modelData.name]); cloudRefresh.restart(); } }
                        Button { label: parent.parent.modelData.auto ? "Po prihlásení: áno" : "Po prihlásení: nie"
                                 onClicked: { app.run(["latte-cloud", "auto", parent.parent.modelData.name, parent.parent.modelData.auto ? "off" : "on"]); cloudRefresh.restart(); } }
                    }
                }
            }
            Row {
                spacing: 10
                Button { label: "Pridať účet"; glyph: "plus"; primaryStyle: true; onClicked: { app.run(["latte-cloud", "add"]); cloudRefresh.interval = 20000; cloudRefresh.restart(); } }
                Button { label: "Obnoviť"; glyph: "refresh"; onClicked: cloudProc.running = true }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Tip: domáci server cez SSH pridáš ako typ sftp. Pripojené účty sú aj v Súboroch v sekcii Cloud." }
        }
    }
    Component {
        id: pPouzivatelia
        Column {
            spacing: 12
            Repeater {
                model: app.accounts
                Rectangle {
                    required property var modelData
                    width: Math.min(parent.width, 620); height: 64; radius: 12; color: theme.field
                    Rectangle {
                        id: av; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 42; height: 42; radius: 11; color: theme.primary; clip: true
                        Text { anchors.centerIn: parent; visible: ai.status !== Image.Ready; text: parent.parent.modelData.name.charAt(0).toUpperCase(); color: theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 18; weight: Font.Bold } }
                        Image { id: ai; anchors.fill: parent; smooth: false; fillMode: Image.PreserveAspectCrop; source: "file:///var/lib/latteos/greeter/avatars/" + parent.parent.modelData.name + ".png" }
                    }
                    Column {
                        anchors { left: av.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        Text { text: (parent.parent.modelData.full || parent.parent.modelData.name) + (parent.parent.modelData.me ? "  (ty)" : ""); color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        Text { text: parent.parent.modelData.name + " · " + (parent.parent.modelData.admin ? "správca" : "bežný účet"); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                    Button {
                        visible: !parent.modelData.me
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        label: "Odstrániť"; glyph: "trash"; danger: true
                        onClicked: app.term("echo 'Odstrániť účet " + parent.modelData.name + " aj s domovom? (Ctrl+C = nie)'; read x; sudo userdel -r " + parent.modelData.name, "Odstránenie účtu v termináli")
                    }
                }
            }
            Heading { text: "PRIDAŤ ÚČET" }
            Row {
                spacing: 10
                Field { width: 260; placeholder: "prihlasovacie meno (malé písmená)"; onEdited: (t) => app.newUser = t.trim().toLowerCase() }
                Button {
                    label: "Pridať"; glyph: "plus"; primaryStyle: true
                    onClicked: {
                        if (!/^[a-z_][a-z0-9_-]{0,30}$/.test(app.newUser)) { app.status = "Meno: malé písmená, číslice, - a _ (napr. anna)"; return; }
                        app.term("sudo useradd -m '" + app.newUser + "' && sudo passwd '" + app.newUser + "'", "Nový účet " + app.newUser + " v termináli");
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Nový účet je bežný (bez práv správcu), domov má súkromný. Pridanie a odstránenie vyžaduje heslo správcu. Rodičovskú kontrolu pripravujeme." }
        }
    }
    Component {
        id: pZalohy
        Column {
            spacing: 14
            Heading { text: "KAM ZÁLOHOVAŤ" }
            Text { visible: app.backupDrives.length === 0; width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                   text: "Pripoj USB disk (objaví sa tu), alebo vyber priečinok nižšie." }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.backupDrives
                    Card {
                        required property var modelData
                        width: 240; glyph: "usb"; title: modelData[0].split("/").pop(); sub: modelData[1] + " voľné"; selected: app.backup.target === modelData[0]
                        onClicked: { app.run(["latte-backup", "set-target", modelData[0]], "Cieľ zálohy: " + modelData[0]); backupRefresh.restart(); }
                    }
                }
            }
            PickRow { label: app.backup.target ? "Cieľ: " + app.backup.target.replace(app.home, "~") : "Iný priečinok (sieťový disk, druhý disk…)"; button: "Prehľadávať priečinok"
                      hint: "alebo sem pretiahni priečinok zo Súborov"
                      onBrowse: app.browse(["--priecinok", "--nazov", "Kam zálohovať", "--start", "/run/media/" + app.user], (p) => app.setBackupTarget(p[0]))
                      onDropped: (p) => app.setBackupTarget(p[0]) }
            Timer { id: backupRefresh; interval: 500; onTriggered: backupProc.running = true }
            Row {
                spacing: 10
                Button { label: app.backupPct >= 0 ? "Zálohujem… " + app.backupPct + " %" : "Zálohovať teraz"; glyph: "history"; primaryStyle: true
                         onClicked: if (app.backupPct < 0 && app.backup.target) { app.backupPct = 0; backupRun.running = true; } }
                Button { label: app.backup.schedule === "on" ? "Denne: zapnuté" : "Denne: vypnuté"; glyph: "clock"
                         onClicked: { app.run(["latte-backup", "schedule", app.backup.schedule === "on" ? "off" : "on"], "Denná záloha " + (app.backup.schedule === "on" ? "vypnutá" : "zapnutá")); backupRefresh.restart(); } }
            }
            Rectangle { visible: app.backupPct >= 0; width: parent.width; height: 6; radius: 3; color: theme.field
                        Rectangle { width: parent.width * app.backupPct / 100; height: 6; radius: 3; color: theme.primary } }
            Heading { text: "ZÁLOHY (obnova: otvor zálohu v Súboroch a skopíruj súbor späť, F5)" }
            Text { visible: app.backupList.length === 0; text: "Zatiaľ žiadne."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
            Repeater {
                model: app.backupList.slice(0, 10)
                Rectangle {
                    required property string modelData
                    width: Math.min(parent.width, 560); height: 44; radius: 10; color: theme.field
                    Text { x: 14; anchors.verticalCenter: parent.verticalCenter
                           text: modelData.replace(/^(\d{4})-(\d\d)-(\d\d)_(\d\d)(\d\d)(\d\d)?$/, (m, y, mo, d, h, mi) => parseInt(d) + ". " + parseInt(mo) + ". " + y + "  " + h + ":" + mi)
                           color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                    Button { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } label: "Otvoriť"; glyph: "folder"
                             onClicked: app.run(["latte-app", "subory", app.backup.target + "/LatteOS-zaloha-" + app.user + "/" + parent.modelData]) }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Nezálohuje sa: vyrovnávacia pamäť, kôš, Steam a Flatpak aplikácie (dajú sa stiahnuť znova). Ponecháva sa 14 najnovších záloh." }
        }
    }
    Component {
        id: pJazyk
        Column {
            spacing: 14
            readonly property var langs: [["sk_SK.UTF-8", "Slovenčina", "sk"], ["cs_CZ.UTF-8", "Čeština", "cs"], ["en_US.UTF-8", "English (US)", "en"],
                                          ["en_GB.UTF-8", "English (UK)", "en"], ["de_DE.UTF-8", "Deutsch", "de"], ["hu_HU.UTF-8", "Magyar", "hu"], ["pl_PL.UTF-8", "Polski", "pl"]]
            Heading { text: "JAZYK" }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: parent.parent.langs
                    Card {
                        required property var modelData
                        readonly property bool installed: app.hasLocale(modelData[0])
                        width: 190; height: 62; title: modelData[1]; sub: installed ? modelData[0] : "treba doinštalovať (klikni)"
                        selected: (app.localeConf.LANG || "sk_SK.UTF-8") === modelData[0]
                        onClicked: {
                            if (!installed) { app.run(["latte-app", "instalator", "--nazov=Jazyk_" + modelData[1].replace(/ /g, "_"), "install", "glibc-langpack-" + modelData[2]], "Inštalácia jazyka"); return; }
                            app.setLocale("LANG", modelData[0] === "sk_SK.UTF-8" ? "" : modelData[0]);
                        }
                    }
                }
            }
            Heading { text: "FORMÁTY (dátum, čas, čísla, meny)" }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: [["", "Podľa jazyka"], ["sk_SK.UTF-8", "Slovensko · 24. 9. 2026 · 1 234,50 €"], ["cs_CZ.UTF-8", "Česko · 24. 09. 2026 · 1 234,50 Kč"],
                            ["en_GB.UTF-8", "UK · 24/09/2026 · £1,234.50"], ["en_US.UTF-8", "USA · 9/24/2026 · $1,234.50"]]
                    Card {
                        required property var modelData
                        width: 290; height: 56; title: modelData[1]; sub: modelData[0] && !app.hasLocale(modelData[0]) ? "treba doinštalovať jazyk" : ""
                        selected: (app.localeConf.LC_TIME || "") === modelData[0]
                        onClicked: { for (const k of ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_PAPER", "LC_MEASUREMENT"]) app.setLocale(k, modelData[0]); }
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Zmena platí po odhlásení a prihlásení. Jazyk celého systému (aj obrazovky prihlásenia) mení správca: localectl set-locale." }
        }
    }
    Component {
        id: pUcet
        Column {
            spacing: 14
            Row {
                spacing: 16
                Rectangle {
                    width: 84; height: 84; radius: 20; color: theme.primary; clip: true
                    Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: app.user.charAt(0).toUpperCase(); color: theme.fgOnPrimary; font { family: theme.fontDisplay; pixelSize: 40; weight: Font.Bold } }
                    Image { id: face; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; cache: false; smooth: false
                            source: "file:///var/lib/latteos/greeter/avatars/" + app.user + ".png?" + app.avatarRev }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    Text { text: app.fullName || app.user; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 24; weight: Font.DemiBold } }
                    Text { text: "používateľ " + app.user; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                }
            }
            Heading { text: "OBRÁZOK ÚČTU (ukáže sa aj pri prihlásení)" }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.avatarChoices
                    Rectangle {
                        required property string modelData
                        width: 72; height: 72; radius: 16; color: theme.field; clip: true
                        border { color: am2.containsMouse ? theme.primary : "transparent"; width: 2 }
                        Image { anchors { fill: parent; margins: modelData.indexOf("/mascots/") >= 0 ? 8 : 0 } source: "file://" + parent.modelData
                                fillMode: modelData.indexOf("/mascots/") >= 0 ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                                smooth: modelData.indexOf("/mascots/") < 0; asynchronous: true; sourceSize { width: 144; height: 144 } }
                        MouseArea { id: am2; anchors.fill: parent; hoverEnabled: true; onClicked: app.setAvatar(parent.modelData) }
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Na výber sú maskoti LatteOS a posledné obrázky z priečinka Obrázky." }
            Row {
                spacing: 10
                Button { label: "Bez obrázka"; glyph: "x"; onClicked: app.setAvatar("") }
                Button { label: "Zmeniť heslo"; glyph: "lock"; onClicked: app.run(["foot", "-e", "passwd"], "Zmena hesla v termináli") }
            }
        }
    }
    Component {
        id: pUzamknutie
        Column {
            spacing: 14
            Heading { text: "ZAMKNÚŤ OBRAZOVKU PO" }
            Segments {
                options: [["0", "Nikdy"], ["5", "5 min"], ["10", "10 min"], ["15", "15 min"], ["30", "30 min"]]
                value: String(app.idleMin(app.idle.lock))
                onPicked: (v) => app.setIdle("lock", "lock", parseInt(v), v === "0" ? "Automatické zamknutie vypnuté" : "Zamknúť po " + v + " min")
            }
            Heading { text: "VYPNÚŤ OBRAZOVKU PO" }
            Segments {
                options: [["0", "Nikdy"], ["5", "5 min"], ["10", "10 min"], ["20", "20 min"], ["60", "1 h"]]
                value: String(app.idleMin(app.idle.screen))
                onPicked: (v) => app.setIdle("screen-off", "screen_off", parseInt(v), v === "0" ? "Obrazovka sa nevypína" : "Vypnúť obrazovku po " + v + " min")
            }
            Heading { text: "USPAŤ PO (pred uspaním zamkne)" }
            Segments {
                options: [["0", "Nikdy"], ["30", "30 min"], ["60", "1 h"], ["120", "2 h"]]
                value: String(app.idleMin(app.idle.suspend))
                onPicked: (v) => app.setIdle("lock-and-suspend", "lock_and_suspend", parseInt(v), v === "0" ? "Uspávanie vypnuté" : "Uspať po " + v + " min")
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Vo VM uspanie nemusí fungovať. Počas hry na celú obrazovku a pri prehrávaní videa sa nečinnosť nepočíta (aplikácia to hlási sama)." }
            Button { label: "Zamknúť teraz (Super+L)"; glyph: "lock"; onClicked: app.run(["noctalia", "msg", "session", "lock"]) }
        }
    }
    Component {
        id: pPristupnost
        Column {
            spacing: 14
            Heading { text: "VEĽKOSŤ ROZHRANIA (lišta, panely)" }
            Segments {
                options: [["1", "100 %"], ["1.15", "115 %"], ["1.3", "130 %"], ["1.5", "150 %"]]
                value: String(parseFloat(app.access.ui_scale) || 1)
                onPicked: (v) => app.shellSet("accessibility.ui_scale", v === "1" ? null : parseFloat(v), "Mierka rozhrania " + Math.round(parseFloat(v) * 100) + " %")
            }
            Heading { text: "KONTRAST" }
            Segments {
                options: [["false", "Bežný"], ["true", "Vysoký kontrast"]]
                value: app.access.high_contrast === "true" ? "true" : "false"
                onPicked: (v) => app.shellSet("accessibility.high_contrast", v === "true" ? true : null, v === "true" ? "Vysoký kontrast zapnutý" : "Bežný kontrast")
            }
            Heading { text: "POHYB" }
            Segments {
                options: [["false", "Animácie podľa výkonu"], ["true", "Bez animácií"]]
                value: app.noAnim ? "true" : "false"
                onPicked: (v) => app.setNoAnim(v === "true")
            }
            Heading { text: "KURZOR" }
            Segments {
                options: [["24", "Bežný"], ["32", "Väčší"], ["48", "Veľký"], ["64", "Najväčší"]]
                value: app.cursorSize
                onPicked: (v) => { app.writePref("cursor-size", v === "24" ? "" : v, "Kurzor " + v + " px"); app.cursorSize = v; app.run(["hyprctl", "setcursor", "default", v]); }
            }
            Heading { text: "LUPA" }
            Segments {
                options: [["1", "Vypnutá"], ["1.5", "150 %"], ["2", "200 %"], ["3", "300 %"], ["4", "400 %"]]
                value: app.zoomPick
                onPicked: (v) => { app.zoomPick = v; app.run(["hyprctl", "eval", "latte.keys.zoomTo(" + v + ")"], v === "1" ? "Lupa vypnutá" : "Lupa " + Math.round(parseFloat(v) * 100) + " %"); }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Ako vo Windows: Win + Plus zväčší okolie kurzora, Win + Mínus zmenší, Win + Esc lupu vypne. Obraz ide za kurzorom." }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Veľkosť písma v aplikáciách a čítačku obrazovky pripravujeme. Zmeny lišty a panelov platia hneď, kurzor v nových oknách po prihlásení." }
        }
    }
    Component {
        id: pOznamenia
        Column {
            spacing: 14
            Row {
                spacing: 10
                Rectangle {
                    width: 46; height: 26; radius: 13; anchors.verticalCenter: parent.verticalCenter
                    color: app.dnd ? theme.primary : theme.field; border { color: theme.line; width: 1 }
                    Rectangle { width: 20; height: 20; radius: 10; y: 3; x: app.dnd ? 23 : 3; color: app.dnd ? theme.fgOnPrimary : theme.fgDim }
                    MouseArea { anchors.fill: parent; onClicked: { app.dnd = !app.dnd; app.run(["noctalia", "msg", "notification-dnd-set", app.dnd ? "on" : "off"], app.dnd ? "Nerušiť zapnuté" : "Nerušiť vypnuté"); } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Nerušiť (oznámenia sa ukladajú do histórie, neukazujú sa)"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
            }
            Heading { text: "KDE SA UKAZUJÚ" }
            Segments {
                options: [["top_right", "Vpravo hore"], ["top_center", "Hore v strede"], ["top_left", "Vľavo hore"], ["bottom_right", "Vpravo dole"], ["bottom_left", "Vľavo dole"]]
                value: app.notif.position || "top_right"
                onPicked: (v) => app.shellSet("notification.position", v, "Oznámenia: " + v)
            }
            Stepper { label: "Najviac naraz (0 = bez limitu)"; value: parseInt(app.notif.max_visible) || 0; step: 1; min: 0; max: 10; unit: ""
                      onStepped: (v) => app.shellSet("notification.max_visible", v, "Najviac naraz: " + v) }
            Heading { text: "OBSAH" }
            Segments {
                options: [["true", "Ukázať názov aplikácie"], ["false", "Bez názvu"]]
                value: app.notif.show_app_name === "false" ? "false" : "true"
                onPicked: (v) => app.shellSet("notification.show_app_name", v === "true", "Názov aplikácie: " + (v === "true" ? "áno" : "nie"))
            }
            Segments {
                options: [["true", "Tlačidlá akcií"], ["false", "Bez tlačidiel"]]
                value: app.notif.show_actions === "false" ? "false" : "true"
                onPicked: (v) => app.shellSet("notification.show_actions", v === "true", "Akcie v oznámení: " + (v === "true" ? "áno" : "nie"))
            }
            Heading { text: "Z MOBILU" }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Oznámenia z telefónu cez KDE Connect (Android, iPhone obmedzene): panel Čas na lište › Oznámenia. Pravidlá podľa aplikácie pripravujeme." }
            Button { label: "Otestovať oznámenie"; glyph: "bell"; onClicked: app.run(["notify-send", "-a", "LatteOS", "Skúšobné oznámenie", "Takto vyzerá oznámenie LatteOS ☕"]) }
        }
    }
    Component {
        id: pKlavesy
        Column {
            spacing: 10
            Heading { text: "PROFIL OVLÁDANIA" }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Skratky, fokus okien a stredné tlačidlo myši podľa toho, na čo si zvyknutý. Myšou ide všetko rovnako v každom profile. Platí hneď." }
            Segments {
                options: [["windows", "Windows 7–11"], ["linux", "Linux (GNOME, KDE, tiling)"], ["mac", "macOS"]]
                value: app.ctrlProfile
                onPicked: (v) => { app.ctrlProfile = v; app.writePrefReload("profil-ovladania", v === "windows" ? "" : v, "Profil ovládania: " + v); }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                   text: app.ctrlProfile === "windows" ? "Okno sa aktivuje kliknutím, stredný klik nevkladá text, samotný kláves Win otvorí Štart (App Manager). Klávesnice bez Win: Ctrl + Esc."
                       : app.ctrlProfile === "linux" ? "Okno sa aktivuje už prejdením myšou, stredný klik vloží označený text, Super + ťahanie presúva okná."
                       : "Kláves Cmd je kláves Win (Super). Okno sa aktivuje kliknutím. Cmd + C / V v aplikáciách príde s premapovaním klávesov." }
            Heading { text: "NUM LOCK PO ŠTARTE"; topPadding: 8 }
            Segments {
                options: [["", "Podľa počítača (stolný zapnutý)"], ["on", "Zapnutý"], ["off", "Vypnutý"]]
                value: app.numlockPref
                onPicked: (v) => { app.numlockPref = v; app.writePrefReload("numlock", v, "Num Lock: " + (v || "podľa počítača")); }
            }
            Heading { text: "SKRATKY PROFILU"; topPadding: 8 }
            Repeater {
                model: app.shortcutSets[app.ctrlProfile] || []
                Row {
                    required property var modelData
                    spacing: 16
                    Rectangle { width: 240; height: 30; radius: 8; color: theme.field
                                Text { anchors.centerIn: parent; text: modelData[0]; color: theme.fg; font { family: theme.fontMono; pixelSize: 12; weight: Font.Bold } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                }
            }
            Text { topPadding: 6; width: parent.width; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                   text: "Vo všetkých profiloch: hlasitosť, jas a prehrávanie hudby na multimediálnych klávesoch, Herňa (Win + G), Súbory (Win + E), gestá 3 a 4 prstami. V hernom režime samotný Win nič neotvorí.\nVlastné skratky: ~/.config/latteos/hyprland.lua (načíta sa na konci a môže prepísať čokoľvek)." }
        }
    }
    Component {
        id: pManaged
        Column {
            spacing: 12
            readonly property var m: app.managed[app.section] || ["", "", []]
            Text { width: parent.width; wrapMode: Text.WordWrap; text: parent.m[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
            readonly property bool dev: m[0] === "Správca zariadení"
            readonly property bool emb: dev || m[0] === "Aplikácie" || m[0] === "Monitor"      // obsah priamo na stránke
            // stránky hardvéru: ten istý komponent ako Správca zariadení (jedna implementácia, nie odkaz)
            Loader {
                active: parent.dev; visible: active; width: parent.width; height: item ? item.naturalHeight : 0
                sourceComponent: SpravcaZariadeni {
                    theme: app.th; compact: false; embedded: true
                    only: app.managed[app.section][2][2]
                    tab: app.section === "siet" ? "siete" : "zariadenia"
                    onOpenWindow: (a) => app.run(a)
                }
            }
            // Softvér: ten istý App Manager (common/AppManager.qml) priamo na stránke, s vlastným rolovaním
            Loader {
                active: parent.m[0] === "Aplikácie"; visible: active
                width: parent.width; height: Math.max(560, content.height - 150)
                sourceComponent: AppManager {
                    theme: app.th; embedded: true
                    args: [app.managed[app.section][2][2]]
                }
            }
            Loader {
                active: parent.m[0] === "Monitor"; visible: active
                width: parent.width; height: Math.max(560, content.height - 150)
                sourceComponent: MonitorView { theme: app.th; embedded: true; args: app.managed[app.section][2][2] }
            }
            Button { label: "Otvoriť " + parent.m[0]; glyph: parent.m[0] === "Monitor" ? "activity" : (parent.m[0] === "Aplikácie" ? "apps" : "cpu"); primaryStyle: !parent.emb; onClicked: app.run(parent.m[2]) }
            Text { visible: !parent.emb; text: "Nastavenia ukazujú stav a odkaz; operácie vlastní " + parent.m[0] + " (jedna implementácia)."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
        }
    }
    Component {
        id: pPlan
        Column {
            spacing: 10
            Repeater {
                model: app.plans[app.section] || []
                Row {
                    required property string modelData
                    spacing: 10
                    Text { text: "○"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                    Text { text: modelData; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                }
            }
            Text { topPadding: 8; text: "Spravuje: " + app.current.owner + " · ROADMAP.md"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
        }
    }
}
