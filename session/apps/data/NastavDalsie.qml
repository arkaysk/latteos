// Ďalšie stránky Nastavení (25. 9.: „oproti Windows či Linuxu nekompletné“), podľa kanonického stromu
// old/main_setting_v2.md §58 a toho, čo majú Windows 11 / GNOME / KDE:
//   Softvér › Predvolené aplikácie        (latte-apps defaults — xdg-mime, ~/.config/mimeapps.list)
//   Hardvér › Hry a herný režim           (herný režim, knižnica z Herne, MangoHud/GameMode/Gamescope, ovládače)
//   Hardvér › Myš, touchpad a ovládače    (Hyprland input; uloží ~/.config/latteos/vstup.lua, načíta ho hyprland.lua)
//   Účet › Heslo a zabezpečenie           (heslo, odtlačok prsta, SSH kľúče, kľúčenka)
//   Prostredie › Písmo a mierka           (písmo aplikácií a kódu, veľkosť textu, vyhladzovanie — gsettings)
//   Systém › Bezpečnosť                   (firewall, SELinux, Secure Boot, šifrovanie, SSH, aktualizácie — prehľad ako Zabezpečenie Windows)
//   Systém › Zdieľanie                     (SSH, KDE Connect, vzdialená plocha, zdieľanie obrazovky)
// Operácie s rootom idú cez terminál so sudo (ako Používatelia), nič sa nespúšťa potajomky.
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Item {
    id: dd
    required property var app
    required property var theme
    readonly property var t: theme
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos"

    readonly property var pages: ({ predvolene: pPredvolene, hry: pHry, vstup: pVstup, heslo: pHeslo, pismo: pPismo, bezpecnost: pBezpecnost, zdielanie: pZdielanie })
    readonly property var intros: ({
        predvolene: "Ktorá aplikácia otvorí odkaz, priečinok, obrázok, video alebo hudbu. Zmena platí hneď pre všetky typy súborov v skupine.",
        hry: "Herný režim, knižnica hier a nástroje, ktoré hrám pomáhajú. Hry sa spúšťajú z Herne (Super+G).",
        vstup: "Rýchlosť a správanie myši a touchpadu platí hneď. Herné ovládače sa ukážu po pripojení.",
        heslo: "Heslo účtu, odtlačok prsta a kľúče, ktorými sa prihlasuješ.",
        pismo: "Písmo a veľkosť textu v aplikáciách. Mierka celého rozhrania je v Prístupnosti, mierka obrazovky v Obrazovkách.",
        bezpecnost: "Prehľad ochrany počítača na jednom mieste. Každá položka hovorí, čo znamená a čo s ňou urobiť.",
        zdielanie: "Čo z tvojho počítača je dostupné z iných zariadení v sieti."
    })
    readonly property var stored: ({
        predvolene: "~/.config/mimeapps.list (xdg-mime)", hry: "~/.local/state/latteos/game-mode\nlatte-games",
        vstup: "~/.config/latteos/vstup.json\n~/.config/latteos/vstup.lua (načíta hyprland.lua)",
        heslo: "/etc/shadow (passwd)\n~/.ssh/", pismo: "gsettings org.gnome.desktop.interface",
        bezpecnost: "firewalld · SELinux · mokutil · lsblk", zdielanie: "sshd.service · KDE Connect · xdg-desktop-portal"
    })
    function stateText(k) {
        if (k === "predvolene") { const w = defaults.find(d => d.key === "web"); return w ? "Prehliadač: " + (w.currentName || "nenastavený") : "—"; }
        if (k === "hry") return "Herný režim " + (game ? "zapnutý" : "vypnutý") + (gamesCount >= 0 ? "\n" + gamesCount + " hier v knižnici" : "");
        if (k === "vstup") return "Rýchlosť " + inp.sensitivity.toFixed(1) + " · " + (inp.accel_profile === "flat" ? "bez zrýchlenia" : "so zrýchlením") + (inp.left_handed ? " · ľavák" : "");
        if (k === "pismo") return font.ui + "\nText " + Math.round(font.scale * 100) + " %";
        if (k === "bezpecnost") { const bad = secItems().filter(i => i.level === "bad").length, warn = secItems().filter(i => i.level === "warn").length;
                                  return bad ? bad + " vyžaduje pozornosť" : (warn ? warn + " odporúčanie" : "Všetko v poriadku"); }
        if (k === "zdielanie") return "SSH: " + (sec.ssh_active === "active" ? "zapnuté" : "vypnuté");
        if (k === "heslo") return sshKeys.length + " SSH " + (sshKeys.length === 1 ? "kľúč" : "kľúče") + (fprint ? " · čítačka odtlačkov" : "");
        return "—";
    }
    function opened(k) {
        if (k === "predvolene") defProc.running = true;
        if (k === "hry") { gameProc.running = true; toolsProc.running = true; padsProc.running = true; }
        if (k === "vstup") padsProc.running = true;
        if (k === "bezpecnost" || k === "zdielanie" || k === "heslo") secProc.running = true;
        if (k === "pismo") fontProc.running = true;
    }

    // ── spoločné ovládacie prvky (rovnaký vzhľad ako v nastavenia.qml) ───────────────────
    component Heading: Text { color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.8 } }
    component Note: Text { width: parent ? parent.width : 400; wrapMode: Text.WordWrap; color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 12 } }
    component Btn: Rectangle {
        id: b
        property string label; property string glyph: ""; property bool primaryStyle: false; property bool small: false
        signal clicked()
        width: br.implicitWidth + (small ? 20 : 28); height: small ? 30 : 36; radius: 10
        color: primaryStyle ? dd.t.primary : (bm.containsMouse ? dd.t.hover : dd.t.field)
        Row { id: br; anchors.centerIn: parent; spacing: 7
            Glyph { visible: b.glyph !== ""; name: b.glyph || "x"; size: b.small ? 14 : 16; color: b.primaryStyle ? dd.t.fgOnPrimary : dd.t.fg; anchors.verticalCenter: parent.verticalCenter }
            Text { text: b.label; color: b.primaryStyle ? dd.t.fgOnPrimary : dd.t.fg; font { family: dd.t.fontUi; pixelSize: b.small ? 12 : 13; weight: Font.Bold } } }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component Seg: Row {
        id: sg
        property var options: []      // [[hodnota, text]]
        property var value
        signal picked(var v)
        spacing: 6
        Repeater {
            model: sg.options
            Rectangle {
                required property var modelData
                readonly property bool on: sg.value === modelData[0]
                width: stx.implicitWidth + 26; height: 34; radius: 10
                color: on ? Qt.rgba(dd.t.primary.r, dd.t.primary.g, dd.t.primary.b, 0.18) : (sgm.containsMouse ? dd.t.hover : dd.t.field)
                border { color: on ? dd.t.primary : "transparent"; width: 1.5 }
                Text { id: stx; anchors.centerIn: parent; text: modelData[1]; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 13; weight: on ? Font.Bold : Font.Medium } }
                MouseArea { id: sgm; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked(modelData[0]) }
            }
        }
    }
    component Switch: Row {
        id: sw
        property string label; property string sub: ""; property bool checked: false
        signal toggled(bool v)
        spacing: 12
        width: parent ? parent.width : 400
        Rectangle {
            width: 46; height: 26; radius: 13; anchors.verticalCenter: parent.verticalCenter
            color: sw.checked ? dd.t.primary : dd.t.field; border { color: dd.t.line; width: 1 }
            Rectangle { width: 20; height: 20; radius: 10; y: 3; x: sw.checked ? 23 : 3; color: sw.checked ? dd.t.fgOnPrimary : dd.t.fgDim
                        Behavior on x { NumberAnimation { duration: 140 } } }
            MouseArea { anchors.fill: parent; onClicked: sw.toggled(!sw.checked) }
        }
        Column {
            width: sw.width - 58; anchors.verticalCenter: parent.verticalCenter
            Text { text: sw.label; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 13 } }
            Text { visible: sw.sub !== ""; width: parent.width; wrapMode: Text.WordWrap; text: sw.sub; color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 11 } }
        }
    }
    // stavový riadok: ikona · názov · stav slovom (nie iba farba) · vysvetlenie · akcia
    component StatusRow: Rectangle {
        id: sr
        property string glyph; property string title; property string state; property string level: "ok"   // ok | warn | bad | info
        property string sub: ""; property string action: ""
        signal act()
        width: parent ? parent.width : 500; height: Math.max(62, src.implicitHeight + 20); radius: 12; color: dd.t.field
        readonly property color lc: level === "bad" ? dd.t.error : (level === "warn" ? "#E0A84F" : (level === "ok" ? dd.t.primary : dd.t.fgDim))
        Rectangle { width: 4; height: parent.height - 20; radius: 2; x: 8; anchors.verticalCenter: parent.verticalCenter; color: sr.lc }
        Glyph { x: 22; anchors.verticalCenter: parent.verticalCenter; name: sr.glyph; size: 20; color: sr.lc }
        Column {
            id: src
            x: 56; width: parent.width - 56 - (sa.visible ? sa.width + 24 : 14); anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Row { spacing: 8
                Text { text: sr.title; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 14; weight: Font.Bold } }
                Text { text: (sr.level === "bad" ? "✕ " : sr.level === "warn" ? "! " : sr.level === "ok" ? "✓ " : "· ") + sr.state; color: sr.lc; font { family: dd.t.fontUi; pixelSize: 12; weight: Font.DemiBold } } }
            Text { visible: sr.sub !== ""; width: parent.width; wrapMode: Text.WordWrap; text: sr.sub; color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 12 } }
        }
        Btn { id: sa; visible: sr.action !== ""; small: true; label: sr.action; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } onClicked: sr.act() }
    }
    component Q: Process {
        id: q
        signal done(string out)
        stdout: StdioCollector { onStreamFinished: q.done(this.text) }
    }

    // ── Predvolené aplikácie ───────────────────────────────────────────────────────
    property var defaults: []
    property string defOpen: ""
    Q { id: defProc; command: ["latte-apps", "defaults"]; onDone: (o) => { try { dd.defaults = JSON.parse(o); } catch (e) {} } }
    Q { id: defSet; onDone: defProc.running = true }
    Component {
        id: pPredvolene
        Column {
            spacing: 8
            Repeater {
                model: dd.defaults
                Rectangle {
                    id: drow
                    required property var modelData
                    readonly property bool open: dd.defOpen === modelData.key
                    width: parent.width; radius: 12; color: dd.t.field
                    height: 58 + (open ? optFlow.implicitHeight + 12 : 0)
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    clip: true
                    Item {
                        width: parent.width; height: 58
                        Glyph { x: 16; anchors.verticalCenter: parent.verticalCenter; name: drow.modelData.glyph; size: 20; color: dd.t.primary }
                        Column { x: 50; anchors.verticalCenter: parent.verticalCenter
                            Text { text: drow.modelData.title; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 14; weight: Font.Bold } }
                            Text { text: drow.modelData.types + (drow.modelData.types === 1 ? " typ" : drow.modelData.types < 5 ? " typy" : " typov"); color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 11 } } }
                        Row {
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Image { width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter; sourceSize { width: 44; height: 44 }
                                    visible: source != ""; source: { const o = drow.modelData.options.find(x => x.id === drow.modelData.current); return o && o.icon ? Quickshell.iconPath(o.icon, true) : ""; } }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.currentName || (drow.modelData.options.length ? "nenastavené" : "žiadna aplikácia")
                                   color: drow.modelData.currentName ? dd.t.fg : dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 13 } }
                            Glyph { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right"; size: 14; color: dd.t.fgDim; rotation: drow.open ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160 } } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: dd.defOpen = drow.open ? "" : drow.modelData.key }
                    }
                    Flow {
                        id: optFlow
                        x: 50; y: 58; width: parent.width - 64; spacing: 6
                        Repeater {
                            model: drow.modelData.options
                            Rectangle {
                                required property var modelData
                                readonly property bool cur: modelData.id === drow.modelData.current
                                width: orow.implicitWidth + 22; height: 34; radius: 10
                                color: cur ? Qt.rgba(dd.t.primary.r, dd.t.primary.g, dd.t.primary.b, 0.2) : (om.containsMouse ? dd.t.hover : dd.t.surface)
                                border { color: cur ? dd.t.primary : "transparent"; width: 1.5 }
                                Row { id: orow; anchors.centerIn: parent; spacing: 7
                                    Image { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter; visible: source != ""; sourceSize { width: 36; height: 36 }
                                            source: parent.parent.modelData.icon ? Quickshell.iconPath(parent.parent.modelData.icon, true) : "" }
                                    Text { text: parent.parent.modelData.name; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 12; weight: parent.parent.cur ? Font.Bold : Font.Normal } } }
                                MouseArea { id: om; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { defSet.command = ["latte-apps", "default", drow.modelData.key, parent.modelData.id]; defSet.running = true;
                                                         dd.app.status = drow.modelData.title + ": " + parent.modelData.name; dd.defOpen = ""; } }
                            }
                        }
                        Btn { small: true; glyph: "download"; label: drow.modelData.options.length ? "Ďalšie v App Manageri" : "Nájsť aplikáciu v App Manageri"
                              onClicked: dd.app.run(["latte-app", "aplikacie", "objavovat"]) }
                    }
                }
            }
            Note { topPadding: 6; text: "Jednotlivý typ súboru zmeníš v Súboroch: pravý klik › Otvoriť v › Vždy otvárať v." }
        }
    }

    // ── Hry a herný režim ──────────────────────────────────────────────────────────
    property bool game: false
    property int gamesCount: -1
    property var tools: ({})
    property var pads: []
    FileView { path: (Quickshell.env("XDG_STATE_HOME") || (dd.home + "/.local/state")) + "/latteos/game-mode"; printErrors: false; watchChanges: true
               onFileChanged: reload(); onLoaded: dd.game = text().trim() === "1"; onLoadFailed: dd.game = false }
    Q { id: gameProc; command: ["latte-games", "list"]; onDone: (o) => { try { dd.gamesCount = JSON.parse(o).length; } catch (e) { dd.gamesCount = 0; } } }
    Q { id: toolsProc
        command: ["sh", "-c", "for x in steam mangohud gamemoded gamescope; do command -v $x >/dev/null && echo $x=1 || echo $x=0; done; "
                  + "flatpak info com.valvesoftware.Steam >/dev/null 2>&1 && echo steamflat=1; flatpak info net.davidotek.pupgui2 >/dev/null 2>&1 && echo protonup=1; "
                  + "ls -d ~/.steam/root/compatibilitytools.d/GE-Proton* ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d/GE-Proton* 2>/dev/null | wc -l | sed 's/^/ge=/'"]
        onDone: (o) => { const m = {}; for (const l of o.split("\n")) { const p = l.split("="); if (p.length === 2) m[p[0]] = p[1].trim(); } dd.tools = m; } }
    Q { id: padsProc
        command: ["sh", "-c", "awk '/^N: Name=/{n=substr($0,10)} /^H: Handlers=/{ if ($0 ~ /js[0-9]/) print n }' /proc/bus/input/devices | tr -d '\"' | sort -u"]
        onDone: (o) => dd.pads = o.split("\n").filter(l => l.trim() !== "" && !/mouse|touchpad|keyboard|integration/i.test(l)) }
    function install(name, pkg) { app.run(["latte-app", "instalator", "--nazov=" + name.replace(/ /g, "_"), "install", pkg], "Inštalácia: " + name); }
    Component {
        id: pHry
        Column {
            spacing: 12
            Switch {
                label: "Herný režim"; checked: dd.game
                sub: "Bez efektov, medzier a animácií; oznámenia počkajú. Herňa ho zapne sama pri spustení hry a po hre vráti."
                onToggled: (v) => { dd.game = v; dd.app.run(["hyprctl", "eval", "latte.game(" + v + ")"], "Herný režim " + (v ? "zapnutý" : "vypnutý")); }
            }
            Row { spacing: 8
                Btn { primaryStyle: true; glyph: "device-gamepad-2"; label: "Otvoriť Herňu" + (dd.gamesCount >= 0 ? " · " + dd.gamesCount + " hier" : ""); onClicked: dd.app.run(["noctalia", "msg", "panel-toggle", "latteos/games:panel"]) }
                Btn { glyph: "activity"; label: "Výkon a grafika"; onClicked: dd.app.go("vykon") } }
            Heading { topPadding: 8; text: "NÁSTROJE PRE HRY" }
            StatusRow { glyph: "brand-steam"; title: "Steam"; level: dd.tools.steam === "1" || dd.tools.steamflat === "1" ? "ok" : "info"
                        state: dd.tools.steam === "1" ? "nainštalovaný" : (dd.tools.steamflat === "1" ? "nainštalovaný (Flatpak)" : "nie je")
                        sub: "Knižnica hier, Proton pre hry z Windows."
                        action: dd.tools.steam === "1" || dd.tools.steamflat === "1" ? "" : "Nainštalovať"; onAct: dd.app.run(["latte-app", "aplikacie", "detail", "com.valvesoftware.Steam"]) }
            StatusRow { glyph: "bolt"; title: "GameMode"; level: dd.tools.gamemoded === "1" ? "ok" : "info"; state: dd.tools.gamemoded === "1" ? "nainštalovaný" : "nie je"
                        sub: "Počas hry prepne procesor na výkon a zvýši prioritu hry (Feral). Herňa ho použije, keď je k dispozícii."
                        action: dd.tools.gamemoded === "1" ? "" : "Nainštalovať"; onAct: dd.install("GameMode", "gamemode") }
            StatusRow { glyph: "activity"; title: "MangoHud"; level: dd.tools.mangohud === "1" ? "ok" : "info"; state: dd.tools.mangohud === "1" ? "nainštalovaný" : "nie je"
                        sub: "Prekrytie v hre: FPS, teploty, záťaž CPU a GPU. V Steame: vlastnosti hry › mangohud %command%."
                        action: dd.tools.mangohud === "1" ? "" : "Nainštalovať"; onAct: dd.install("MangoHud", "mangohud") }
            StatusRow { glyph: "device-desktop"; title: "Gamescope"; level: dd.tools.gamescope === "1" ? "ok" : "info"; state: dd.tools.gamescope === "1" ? "nainštalovaný" : "nie je"
                        sub: "Hra v samostatnom kompozitore: obmedzenie FPS, zväčšenie (FSR), HDR a VRR. Plne na reálnom HW."
                        action: dd.tools.gamescope === "1" ? "" : "Nainštalovať"; onAct: dd.install("Gamescope", "gamescope") }
            StatusRow { glyph: "download"; title: "Proton-GE"; level: parseInt(dd.tools.ge || "0") > 0 ? "ok" : "info"
                        state: parseInt(dd.tools.ge || "0") > 0 ? dd.tools.ge + " verzie" : "nie je"
                        sub: "Upravený Proton s kodekmi a opravami pre viac hier. Spravuje ho ProtonUp-Qt."
                        action: dd.tools.protonup === "1" ? "ProtonUp-Qt" : "Nainštalovať ProtonUp-Qt"; onAct: dd.app.run(["latte-app", "aplikacie", "detail", "net.davidotek.pupgui2"]) }
            Heading { topPadding: 8; text: "HERNÉ OVLÁDAČE" }
            Repeater { model: dd.pads
                StatusRow { required property string modelData; glyph: "device-gamepad"; title: modelData; level: "ok"; state: "pripojený"; sub: "" } }
            Note { visible: dd.pads.length === 0; text: "Žiadny herný ovládač nie je pripojený. Xbox, PlayStation a Switch ovládače fungujú cez USB aj Bluetooth; Steam Input ich preloží pre každú hru." }
            Note { text: "Obmedzenie FPS, HDR a VRR budú v Zariadeniach na lište na reálnom HW (gamescope)." }
        }
    }

    // ── Myš, touchpad a ovládače ────────────────────────────────────────────────────
    property var inp: ({ sensitivity: 0, accel_profile: "adaptive", left_handed: false, natural_scroll: false, scroll_factor: 1,
                         tp_natural_scroll: true, tap_to_click: true, disable_while_typing: true, tp_scroll_factor: 1,
                         repeat_delay: 600, repeat_rate: 25, b275: "", b276: "", b277: "", b278: "" })
    // ďalšie tlačidlá myši → akcia systému ("" = nechať aplikáciám, napr. Späť / Dopredu v prehliadači a Súboroch)
    readonly property var mouseActions: [["", "V aplikáciách (predvolené)"], ["noctalia msg panel-toggle latteos/overview:panel", "Prehľad okien"],
        ["latte-spustac prepni", "Štart (App Manager)"], ["hyprctl eval 'latte.keys.show_desktop()'", "Plocha"],
        ["noctalia msg screenshot-region", "Výstrižok"], ["noctalia msg panel-toggle latteos/kapsa:panel", "Kapsa"],
        ["noctalia msg mic-mute", "Stlmiť mikrofón"], ["noctalia msg media play-pause", "Hudba: prehrať / pauza"]]
    FileView { id: inpFile; path: dd.cfg + "/vstup.json"; printErrors: false
               onLoaded: { try { dd.inp = Object.assign({}, dd.inp, JSON.parse(text())); } catch (e) {} } }
    Process { id: inpApply }
    function setInput(key, v) {
        const o = Object.assign({}, inp); o[key] = v; inp = o;
        const b = (x) => x ? "true" : "false";
        const lua = "hl.config({ input = { sensitivity = " + o.sensitivity.toFixed(2) + ", accel_profile = \"" + o.accel_profile + "\", left_handed = " + b(o.left_handed)
                  + ", natural_scroll = " + b(o.natural_scroll) + ", scroll_factor = " + o.scroll_factor.toFixed(2)
                  + ", touchpad = { natural_scroll = " + b(o.tp_natural_scroll) + ", tap_to_click = " + b(o.tap_to_click)
                  + ", disable_while_typing = " + b(o.disable_while_typing) + ", scroll_factor = " + o.tp_scroll_factor.toFixed(2) + " }"
                  + ", repeat_delay = " + Math.round(o.repeat_delay) + ", repeat_rate = " + Math.round(o.repeat_rate) + " } })"
                  // tlačidlá myši: najprv zrušiť staré priradenie (hyprctl eval sa volá pri každej zmene)
                  + ["275", "276", "277", "278"].map(k => " pcall(hl.unbind, \"mouse:" + k + "\")"
                        + (o["b" + k] ? " hl.bind(\"mouse:" + k + "\", hl.dsp.exec_cmd(\"" + o["b" + k].replace(/"/g, "\\\"") + "\"))" : "")).join("");
        inpFile.setText(JSON.stringify(o));
        inpApply.command = ["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' '-- LatteOS: Nastavenia › Myš a touchpad (vygenerované, neupravovať ručne)' \"$2\" > \"$1/vstup.lua\" && hyprctl eval \"$2\" >/dev/null", "sh", dd.cfg, lua];
        inpApply.running = true;
        app.status = "Myš a touchpad: uložené";
    }
    component Slide: Row {
        id: sl
        property string label; property real from: 0; property real to: 1; property real value: 0; property real step: 0.1; property string fmt: ""
        signal changed(real v)
        spacing: 12
        Text { width: 220; anchors.verticalCenter: parent.verticalCenter; text: sl.label; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 13 } }
        Item {
            width: 260; height: 28
            readonly property real frac: (((sm.pressed ? sm.v : sl.value) - sl.from) / (sl.to - sl.from))
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: dd.t.field }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * parent.frac; height: 6; radius: 3; color: dd.t.primary }
            Rectangle { x: (parent.width - 18) * parent.frac; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: dd.t.fg; border { color: dd.t.primary; width: 2 } }
            MouseArea { id: sm; anchors.fill: parent; property real v: 0
                function at(x) { const r = sl.from + Math.max(0, Math.min(1, x / width)) * (sl.to - sl.from); return Math.round(r / sl.step) * sl.step; }
                onPressed: (m) => v = at(m.x); onPositionChanged: (m) => v = at(m.x); onReleased: sl.changed(v) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: sl.fmt || sl.value.toFixed(1); color: dd.t.fgDim; font { family: dd.t.fontUi; pixelSize: 12 } }
    }
    Component {
        id: pVstup
        Column {
            spacing: 12
            Heading { text: "MYŠ" }
            Slide { label: "Rýchlosť ukazovateľa"; from: -1; to: 1; step: 0.1; value: dd.inp.sensitivity
                    fmt: dd.inp.sensitivity === 0 ? "predvolená" : (dd.inp.sensitivity > 0 ? "+" : "") + dd.inp.sensitivity.toFixed(1); onChanged: (v) => dd.setInput("sensitivity", v) }
            Seg { options: [["adaptive", "So zrýchlením"], ["flat", "Bez zrýchlenia (hry)"]]; value: dd.inp.accel_profile; onPicked: (v) => dd.setInput("accel_profile", v) }
            Switch { label: "Pre ľavákov"; sub: "Vymení ľavé a pravé tlačidlo."; checked: dd.inp.left_handed; onToggled: (v) => dd.setInput("left_handed", v) }
            Switch { label: "Prirodzené rolovanie kolieskom"; sub: "Obsah sa posúva rovnakým smerom ako prsty (ako na mobile)."; checked: dd.inp.natural_scroll; onToggled: (v) => dd.setInput("natural_scroll", v) }
            Slide { label: "Rýchlosť rolovania"; from: 0.2; to: 3; step: 0.1; value: dd.inp.scroll_factor; fmt: dd.inp.scroll_factor.toFixed(1) + "×"; onChanged: (v) => dd.setInput("scroll_factor", v) }
            Heading { topPadding: 8; text: "TLAČIDLÁ MYŠI" }
            Note { text: "Bočné tlačidlá robia predvolene Späť a Dopredu v prehliadači, Súboroch, Nastaveniach a App Manageri (ako vo Windows). Môžeš im priradiť akciu systému; herné myši majú ďalšie tlačidlá (6, 7)." }
            Repeater {
                model: [["b275", "Bočné tlačidlo Späť"], ["b276", "Bočné tlačidlo Dopredu"], ["b277", "Tlačidlo 6"], ["b278", "Tlačidlo 7"]]
                Column {
                    required property var modelData
                    width: parent.width; spacing: 6
                    Text { text: modelData[1]; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: dd.mouseActions
                            Rectangle {
                                required property var modelData
                                readonly property string key: parent.parent.modelData[0]
                                readonly property bool on: (dd.inp[key] || "") === modelData[0]
                                width: mbt.implicitWidth + 22; height: 30; radius: 9
                                color: on ? Qt.rgba(dd.t.primary.r, dd.t.primary.g, dd.t.primary.b, 0.18) : (mbm.containsMouse ? dd.t.hover : dd.t.field)
                                border { color: on ? dd.t.primary : "transparent"; width: 1.5 }
                                Text { id: mbt; anchors.centerIn: parent; text: modelData[1]; color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 12; weight: on ? Font.Bold : Font.Medium } }
                                MouseArea { id: mbm; anchors.fill: parent; hoverEnabled: true; onClicked: dd.setInput(key, modelData[0]) }
                            }
                        }
                    }
                }
            }
            Note { text: "DPI, profily v pamäti myši a podsvietenie herných myší (Logitech, Razer, SteelSeries…) nastavíš aplikáciou Piper." }
            Btn { glyph: "mouse"; label: "Piper — nastavenie hernej myši"; onClicked: dd.app.run(["latte-app", "aplikacie", "detail", "org.freedesktop.Piper"]) }
            Heading { topPadding: 8; text: "KLÁVESNICA" }
            Slide { label: "Oneskorenie opakovania"; from: 200; to: 1000; step: 50; value: dd.inp.repeat_delay; fmt: Math.round(dd.inp.repeat_delay) + " ms"; onChanged: (v) => dd.setInput("repeat_delay", v) }
            Slide { label: "Rýchlosť opakovania"; from: 10; to: 50; step: 1; value: dd.inp.repeat_rate; fmt: Math.round(dd.inp.repeat_rate) + " znakov/s"; onChanged: (v) => dd.setInput("repeat_rate", v) }
            Heading { topPadding: 8; text: "TOUCHPAD" }
            Switch { label: "Ťuknutie = klik"; checked: dd.inp.tap_to_click; onToggled: (v) => dd.setInput("tap_to_click", v) }
            Switch { label: "Vypnúť počas písania"; sub: "Dlaň na touchpade nepohne ukazovateľom."; checked: dd.inp.disable_while_typing; onToggled: (v) => dd.setInput("disable_while_typing", v) }
            Switch { label: "Prirodzené rolovanie dvoma prstami"; checked: dd.inp.tp_natural_scroll; onToggled: (v) => dd.setInput("tp_natural_scroll", v) }
            Slide { label: "Rýchlosť rolovania"; from: 0.2; to: 3; step: 0.1; value: dd.inp.tp_scroll_factor; fmt: dd.inp.tp_scroll_factor.toFixed(1) + "×"; onChanged: (v) => dd.setInput("tp_scroll_factor", v) }
            Note { text: "Gestá: tri prsty vľavo/vpravo prepnú plochu (páska), štyri prsty hore otvoria prehľad." }
            Heading { topPadding: 8; text: "HERNÉ OVLÁDAČE" }
            Repeater { model: dd.pads
                StatusRow { required property string modelData; glyph: "device-gamepad"; title: modelData; level: "ok"; state: "pripojený" } }
            Note { visible: dd.pads.length === 0; text: "Žiadny herný ovládač nie je pripojený." }
            Btn { glyph: "cpu"; label: "Vstupné zariadenia v Správcovi zariadení"; onClicked: dd.app.run(["latte-app", "zariadenia", "vstup"]) }
        }
    }

    // ── Bezpečnosť, Zdieľanie, Heslo (jedna sonda) ───────────────────────────────────
    property var sec: ({})
    property var sshKeys: []
    property bool fprint: false
    Q { id: secProc
        command: ["sh", "-c",
            "echo fw=$(systemctl is-active firewalld 2>/dev/null); echo fwzone=$(firewall-cmd --get-default-zone 2>/dev/null); "
          + "echo selinux=$(getenforce 2>/dev/null); echo sb=$(mokutil --sb-state 2>/dev/null | head -1); "
          + "echo crypt=$(lsblk -rno TYPE 2>/dev/null | grep -c crypt); "
          + "echo ssh_active=$(systemctl is-active sshd 2>/dev/null); echo ssh_enabled=$(systemctl is-enabled sshd 2>/dev/null); "
          + "echo auto=$( (systemctl is-enabled dnf5-automatic.timer || systemctl is-enabled dnf-automatic.timer) 2>/dev/null | grep -m1 -v not-found); "
          + "echo kdec=$(command -v kdeconnect-cli >/dev/null && echo 1); echo kdedev=$(kdeconnect-cli -a --id-only 2>/dev/null | wc -l); "
          + "echo vnc=$(command -v wayvnc >/dev/null && echo 1); echo portal=$(systemctl --user is-active xdg-desktop-portal-hyprland 2>/dev/null); "
          + "echo keyring=$(pgrep -x gnome-keyring-d >/dev/null && echo gnome || (pgrep -x kwalletd6 >/dev/null && echo kwallet)); "
          + "echo fprint=$(fprintd-list \"$USER\" 2>&1 | grep -v -i 'no devices' | grep -c -i 'fingerprints for user\\|device at'); "
          + "for k in ~/.ssh/*.pub; do [ -f \"$k\" ] && echo \"key=$(basename \"$k\")|$(cut -d' ' -f1 \"$k\")|$(cut -d' ' -f3- \"$k\")\"; done"]
        onDone: (o) => {
            const m = {}, keys = [];
            for (const l of o.split("\n")) { const i = l.indexOf("="); if (i < 0) continue; const k = l.slice(0, i), v = l.slice(i + 1).trim();
                if (k === "key") { const p = v.split("|"); keys.push({ file: p[0], type: p[1], comment: p[2] || "" }); } else m[k] = v; }
            dd.sec = m; dd.sshKeys = keys; dd.fprint = parseInt(m.fprint || "0") > 0;
        } }
    function secItems() {
        const s = sec, out = [];
        out.push({ glyph: "shield-check", title: "Firewall", level: s.fw === "active" ? "ok" : "bad", state: s.fw === "active" ? "zapnutý" + (s.fwzone ? " · zóna " + s.fwzone : "") : "vypnutý",
                   sub: s.fw === "active" ? "Prichádzajúce spojenia sú povolené iba pre služby zóny." : "Počítač prijme spojenia na všetky otvorené porty.",
                   action: s.fw === "active" ? "" : "Zapnúť", cmd: "sudo systemctl enable --now firewalld" });
        out.push({ glyph: "shield-lock", title: "SELinux", level: s.selinux === "Enforcing" ? "ok" : (s.selinux === "Permissive" ? "warn" : "bad"),
                   state: ({ Enforcing: "chráni (Enforcing)", Permissive: "iba zapisuje (Permissive)", Disabled: "vypnutý" })[s.selinux] || (s.selinux || "?"),
                   sub: "Obmedzuje, čo smú služby a aplikácie robiť, aj keď sú napadnuté.",
                   action: s.selinux === "Permissive" ? "Zapnúť ochranu" : "", cmd: "sudo setenforce 1 && sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" });
        const sbOn = (s.sb || "").includes("enabled");
        out.push({ glyph: "lock", title: "Secure Boot", level: sbOn ? "ok" : "warn", state: sbOn ? "zapnutý" : (s.sb ? "vypnutý" : "nedá sa zistiť"),
                   sub: sbOn ? "Firmvér spustí iba podpísaný zavádzač a jadro." : "Zapína sa v nastaveniach firmvéru (UEFI) počítača. Vo VM nie je potrebný.", action: "" });
        const cr = parseInt(s.crypt || "0") > 0;
        out.push({ glyph: "database", title: "Šifrovanie disku", level: cr ? "ok" : "warn", state: cr ? "zapnuté (LUKS)" : "vypnuté",
                   sub: cr ? "Pri krádeži počítača sa dáta bez hesla neprečítajú." : "Zapína sa pri inštalácii systému (LUKS). Pri stolnom PC doma je to odporúčanie, nie chyba.", action: "" });
        out.push({ glyph: "terminal-2", title: "Vzdialené prihlásenie (SSH)", level: s.ssh_active === "active" ? "warn" : "ok",
                   state: s.ssh_active === "active" ? "zapnuté" : "vypnuté",
                   sub: s.ssh_active === "active" ? "Do počítača sa dá prihlásiť zo siete heslom alebo kľúčom. Ak to nepotrebuješ, vypni." : "Zo siete sa do počítača prihlásiť nedá.",
                   action: s.ssh_active === "active" ? "Vypnúť" : "", cmd: "sudo systemctl disable --now sshd" });
        out.push({ glyph: "refresh", title: "Bezpečnostné aktualizácie", level: s.auto ? "ok" : "info", state: s.auto ? "automaticky" : "ručne (App Manager › Aktualizácie)",
                   sub: "App Manager ukáže dostupné aktualizácie; systém sa aktualizuje po tvojom potvrdení.", action: "Aktualizácie", go: "aktualizacie" });
        out.push({ glyph: "world", title: "Internet podľa aplikácií (NET)", level: "info", state: "App Manager", sub: "Ktorá aplikácia smie na internet; vypnutie platí hneď.", action: "Otvoriť", go: "sukromie" });
        out.push({ glyph: "lock", title: "Uzamknutie obrazovky", level: "info", state: "podľa Nečinnosti", sub: "Kedy sa obrazovka zamkne, keď odídeš.", action: "Nastaviť", go: "uzamknutie" });
        return out;
    }
    Component {
        id: pBezpecnost
        Column {
            spacing: 8
            Repeater {
                model: dd.secItems()
                StatusRow { required property var modelData; glyph: modelData.glyph; title: modelData.title; level: modelData.level; state: modelData.state; sub: modelData.sub
                            action: modelData.action; onAct: modelData.go ? dd.app.go(modelData.go) : dd.app.term(modelData.cmd, modelData.title + " v termináli") }
            }
            Row { spacing: 8; topPadding: 6
                Btn { glyph: "refresh"; label: "Skontrolovať znova"; onClicked: secProc.running = true }
                Btn { glyph: "stethoscope"; label: "Diagnostika a pády"; onClicked: dd.app.go("diagnostika") } }
        }
    }
    Component {
        id: pZdielanie
        Column {
            spacing: 8
            StatusRow { glyph: "terminal-2"; title: "Vzdialené prihlásenie (SSH)"; level: dd.sec.ssh_active === "active" ? "warn" : "info"
                        state: dd.sec.ssh_active === "active" ? "zapnuté" + (dd.sec.ssh_enabled === "enabled" ? " · aj po štarte" : "") : "vypnuté"
                        sub: "Príkazový riadok tohto počítača z iného zariadenia (ssh " + (Quickshell.env("USER") || "user") + "@<adresa>)."
                        action: dd.sec.ssh_active === "active" ? "Vypnúť" : "Zapnúť"
                        onAct: dd.app.term(dd.sec.ssh_active === "active" ? "sudo systemctl disable --now sshd" : "sudo systemctl enable --now sshd", "SSH v termináli") }
            StatusRow { glyph: "device-mobile"; title: "Mobil (KDE Connect)"; level: dd.sec.kdec === "1" ? (parseInt(dd.sec.kdedev || "0") > 0 ? "ok" : "info") : "info"
                        state: dd.sec.kdec === "1" ? (parseInt(dd.sec.kdedev || "0") > 0 ? dd.sec.kdedev + " spárované" : "nič nespárované") : "nie je nainštalované"
                        sub: "Oznámenia z mobilu, zdieľanie súborov a schránky, mobil ako diaľkové ovládanie."
                        action: dd.sec.kdec === "1" ? "Spárovať" : "Nainštalovať"
                        onAct: dd.sec.kdec === "1" ? dd.app.run(["kdeconnect-app"]) : dd.install("KDE Connect", "kde-connect") }
            StatusRow { glyph: "device-desktop"; title: "Vzdialená plocha"; level: "info"; state: dd.sec.vnc === "1" ? "wayvnc nainštalovaný" : "plán"
                        sub: "Ovládanie tohto počítača z iného (VNC/RDP) s potvrdením na obrazovke. Príde s ďalšou fázou." }
            StatusRow { glyph: "app-window"; title: "Zdieľanie obrazovky pre aplikácie"; level: dd.sec.portal === "active" ? "ok" : "warn"
                        state: dd.sec.portal === "active" ? "funguje" : "portál nebeží"
                        sub: "Discord, prehliadač a OBS si vyžiadajú okno alebo obrazovku; vždy sa ťa spýtajú." }
            StatusRow { glyph: "folder"; title: "Zdieľané priečinky v sieti"; level: "info"; state: "plán"; sub: "Priečinok pre ostatné počítače doma (Samba). Pripojiť cudzí priečinok vieš v Súboroch." }
        }
    }
    Component {
        id: pHeslo
        Column {
            spacing: 8
            StatusRow { glyph: "key"; title: "Heslo účtu"; level: "info"; state: Quickshell.env("USER") || ""; sub: "Heslo na prihlásenie, odomknutie a správcovské úkony (sudo)."
                        action: "Zmeniť heslo"; onAct: dd.app.term("passwd", "Zmena hesla v termináli") }
            StatusRow { glyph: "fingerprint"; title: "Odtlačok prsta"; level: dd.fprint ? "ok" : "info"; state: dd.fprint ? "čítačka nájdená" : "čítačka nenájdená"
                        sub: dd.fprint ? "Prihlásenie a sudo prstom (fprintd)." : "Na tomto počítači nie je čítačka odtlačkov."
                        action: dd.fprint ? "Pridať prst" : ""; onAct: dd.app.term("fprintd-enroll", "Pridanie odtlačku v termináli") }
            StatusRow { glyph: "shield-lock"; title: "Kľúčenka"; level: dd.sec.keyring ? "ok" : "info"; state: dd.sec.keyring ? (dd.sec.keyring === "gnome" ? "GNOME Keyring" : "KWallet") : "nebeží"
                        sub: "Uložené heslá aplikácií (Wi-Fi, prehliadač, e-mail) odomknuté prihlásením." }
            Heading { topPadding: 8; text: "SSH KĽÚČE" }
            Repeater { model: dd.sshKeys
                StatusRow { required property var modelData; glyph: "key"; title: modelData.file; level: "ok"; state: modelData.type.replace("ssh-", ""); sub: modelData.comment
                            action: "Kopírovať"; onAct: dd.app.run(["sh", "-c", "wl-copy < \"$HOME/.ssh/$1\"", "sh", modelData.file], "Verejný kľúč skopírovaný") } }
            Note { visible: dd.sshKeys.length === 0; text: "Žiadny SSH kľúč. Kľúčom sa prihlasuješ na servery a GitHub bez hesla." }
            Btn { glyph: "plus"; label: "Vytvoriť SSH kľúč"; onClicked: dd.app.term("ssh-keygen -t ed25519 -C \"$USER@$(hostname)\"", "Nový SSH kľúč v termináli") }
            Note { text: "Bezpečnostný kľúč (FIDO2/YubiKey) na prihlásenie: plán." }
        }
    }

    // ── Písmo a mierka ─────────────────────────────────────────────────────────────
    property var font: ({ ui: "Adwaita Sans 11", mono: "Adwaita Mono 11", scale: 1, aa: "grayscale", hint: "slight", families: [] })
    Q { id: fontProc
        command: ["sh", "-c", "g=org.gnome.desktop.interface; echo \"ui=$(gsettings get $g font-name)\"; echo \"mono=$(gsettings get $g monospace-font-name)\"; "
                  + "echo \"scale=$(gsettings get $g text-scaling-factor)\"; echo \"aa=$(gsettings get $g font-antialiasing)\"; echo \"hint=$(gsettings get $g font-hinting)\"; "
                  + "fc-list : family | cut -d, -f1 | sort -u | sed 's/^/fam=/'"]
        onDone: (o) => {
            const f = { families: [] };
            for (const l of o.split("\n")) { const i = l.indexOf("="); if (i < 0) continue; const k = l.slice(0, i), v = l.slice(i + 1).replace(/^'|'$/g, "");
                if (k === "fam") f.families.push(v); else f[k] = v; }
            f.scale = parseFloat(f.scale) || 1;
            dd.font = Object.assign({}, dd.font, f);
        } }
    function fontFamily(s) { return (s || "").replace(/\s+\d+(\.\d+)?$/, ""); }
    function fontSize(s) { const m = (s || "").match(/(\d+(\.\d+)?)$/); return m ? parseFloat(m[1]) : 11; }
    function gset(key, val, msg) { app.run(["gsettings", "set", "org.gnome.desktop.interface", key, val], msg); Qt.callLater(() => fontProc.running = true); }
    Component {
        id: pPismo
        Column {
            spacing: 12
            readonly property var uiFams: ["Adwaita Sans", "Inter", "Manrope", "Cantarell", "Noto Sans", "DejaVu Sans"].filter(f => dd.font.families.indexOf(f) >= 0)
            readonly property var monoFams: ["Adwaita Mono", "JetBrains Mono", "DejaVu Sans Mono", "Noto Sans Mono"].filter(f => dd.font.families.indexOf(f) >= 0)
            Heading { text: "PÍSMO APLIKÁCIÍ" }
            Seg { options: parent.uiFams.map(f => [f, f]); value: dd.fontFamily(dd.font.ui)
                  onPicked: (v) => dd.gset("font-name", v + " " + dd.fontSize(dd.font.ui), "Písmo: " + v) }
            Seg { options: [[10, "Malé"], [11, "Stredné"], [12, "Väčšie"], [13, "Veľké"]]; value: dd.fontSize(dd.font.ui)
                  onPicked: (v) => dd.gset("font-name", dd.fontFamily(dd.font.ui) + " " + v, "Veľkosť písma " + v) }
            Heading { topPadding: 6; text: "PÍSMO PRE KÓD A TERMINÁL" }
            Seg { options: parent.monoFams.map(f => [f, f]); value: dd.fontFamily(dd.font.mono)
                  onPicked: (v) => dd.gset("monospace-font-name", v + " " + dd.fontSize(dd.font.mono), "Písmo kódu: " + v) }
            Heading { topPadding: 6; text: "VEĽKOSŤ TEXTU" }
            Seg { options: [[0.9, "90 %"], [1, "100 %"], [1.1, "110 %"], [1.25, "125 %"], [1.5, "150 %"]]; value: Math.round(dd.font.scale * 100) / 100
                  onPicked: (v) => dd.gset("text-scaling-factor", String(v), "Veľkosť textu " + Math.round(v * 100) + " %") }
            Heading { topPadding: 6; text: "VYHLADZOVANIE" }
            Seg { options: [["grayscale", "Odtiene sivej"], ["rgba", "Subpixelové (LCD)"], ["none", "Vypnuté"]]; value: dd.font.aa
                  onPicked: (v) => dd.gset("font-antialiasing", v, "Vyhladzovanie: " + v) }
            Seg { options: [["none", "Bez hintingu"], ["slight", "Jemný"], ["medium", "Stredný"], ["full", "Plný"]]; value: dd.font.hint
                  onPicked: (v) => dd.gset("font-hinting", v, "Hinting: " + v) }
            Rectangle {
                width: parent.width; height: pv.implicitHeight + 28; radius: 12; color: dd.t.field
                Column { id: pv; x: 16; y: 14; width: parent.width - 32; spacing: 6
                    Text { text: "Príliš žltučký kôň úpäl ďábelské ódy."; color: dd.t.fg
                           font { family: dd.fontFamily(dd.font.ui); pointSize: dd.fontSize(dd.font.ui) * dd.font.scale } }
                    Text { text: "for (i = 0; i < 10; i++) { print(\"0O 1lI\"); }"; color: dd.t.fgDim
                           font { family: dd.fontFamily(dd.font.mono); pointSize: dd.fontSize(dd.font.mono) * dd.font.scale } } }
            }
            Note { text: "Platí pre aplikácie GTK a Qt (cez portál); niektoré aplikácie treba zavrieť a otvoriť. Rozhranie LatteOS používa vlastné písmo Manrope, jeho veľkosť mení Prístupnosť › Mierka." }
            Row { spacing: 8
                Btn { glyph: "accessible"; label: "Mierka rozhrania"; onClicked: dd.app.go("pristupnost") }
                Btn { glyph: "device-desktop"; label: "Mierka obrazovky"; onClicked: dd.app.go("obrazovky") } }

            // písma v systéme (Windows: Prispôsobenie › Písma): prehľad s ukážkou, inštalácia zo súboru pre tvoj účet
            Heading { topPadding: 10; text: "PÍSMA V SYSTÉME · " + dd.font.families.length }
            Rectangle {
                width: parent.width; height: 36; radius: 10; color: dd.t.field
                TextInput { id: fq; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter; clip: true
                            color: dd.t.fg; font { family: dd.t.fontUi; pixelSize: 13 } selectByMouse: true
                            Text { visible: !fq.text && !fq.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Hľadať písmo…"; color: dd.t.fgDim; font: fq.font } }
            }
            Flow {
                width: parent.width; spacing: 6
                Repeater {
                    model: dd.font.families.filter(f => !fq.text || f.toLowerCase().indexOf(fq.text.toLowerCase()) >= 0).slice(0, 40)
                    Rectangle {
                        required property string modelData
                        width: fl.implicitWidth + 24; height: 34; radius: 9; color: dd.t.field
                        Text { id: fl; anchors.centerIn: parent; text: parent.modelData; color: dd.t.fg; font { family: parent.modelData; pixelSize: 14 } }
                    }
                }
            }
            Note { visible: dd.font.families.length > 40 && !fq.text; text: "Zobrazených prvých 40 — napíš časť názvu." }
            Row { spacing: 8
                Btn { glyph: "download"; label: "Nainštalovať písmo zo súboru…"
                      onClicked: { app.run(["sh", "-c", "f=$(latte-vyber --nazov 'Písmo (.ttf, .otf)' --typ vsetko) || exit 0; [ -n \"$f\" ] || exit 0; "
                                        + "case \"$f\" in *.[tT][tT][fF]|*.[oO][tT][fF]|*.[tT][tT][cC]) d=\"$HOME/.local/share/fonts\"; mkdir -p \"$d\" && cp \"$f\" \"$d/\" && fc-cache -f \"$d\" "
                                        + "&& notify-send -a LatteOS 'Písmo nainštalované' \"$(basename \"$f\")\";; *) notify-send -a LatteOS 'Toto nie je písmo' 'Očakávam .ttf alebo .otf';; esac"],
                                       "Vyber súbor s písmom"); fontRe.restart(); } }
                Btn { glyph: "folder"; label: "Priečinok mojich písiem"
                      onClicked: app.run(["sh", "-c", "mkdir -p \"$HOME/.local/share/fonts\" && latte-app subory \"$HOME/.local/share/fonts\""]) } }
            Timer { id: fontRe; interval: 15000; onTriggered: fontProc.running = true }   // po výbere súboru znova načítať zoznam
            Note { text: "Písmo nainštalované sem platí iba pre tvoj účet. Stačí ho aj pretiahnuť do priečinka mojich písiem." }
        }
    }
}
