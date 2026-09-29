// LatteOS — Barista, sprievodca prvým spustením (radar: „Barista ako meno sprievodcu“).
// Ukáže sa raz po prvom prihlásení (hyprland.lua, ak chýba ~/.config/latteos/barista-done), dá sa spustiť
// aj ručne: latte-app barista. Každá voľba používa tie isté nástroje ako Nastavenia (latte-theme, Lua modul,
// latte-ai, latte-apps), takže sa dá neskôr zmeniť v Nastaveniach.
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }

    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos"
    property int step: Math.max(0, Math.min(6, parseInt(Quickshell.env("LATTE_APP_ARGS") || "0") || 0))   // latte-app barista <krok>
    readonly property var steps: ["Vitaj", "Vzhľad", "Okná", "Lišta", "AI", "Aplikácie", "Hotovo"]
    property var themes: []
    property string themeId: theme.themeId
    property string modePref: "tema"
    property string windowMode: "paska"
    property string ctrlProfile: "windows"   // profil ovládania (latte/skratky.lua), zmena platí hneď
    property string mascot: "macka"
    property string aiChoice: "domaci"
    property string aiState: ""
    property var picks: ({ "org.mozilla.firefox": true, "org.videolan.VLC": true })
    property string status: ""

    readonly property var apps: [["org.mozilla.firefox", "Firefox", "prehliadač"], ["org.videolan.VLC", "VLC", "video a hudba"],
                                 ["org.libreoffice.LibreOffice", "LibreOffice", "kancelária"], ["com.valvesoftware.Steam", "Steam", "hry"],
                                 ["com.discordapp.Discord", "Discord", "hlas a chat"], ["org.gimp.GIMP", "GIMP", "fotky"],
                                 ["io.github.alainm23.planify", "Planify", "úlohy a plánovač"], ["com.obsproject.Studio", "OBS Studio", "nahrávanie"]]

    Process {
        id: scan; running: true
        command: ["sh", "-c", "for f in /usr/share/latteos/themes/*.theme; do printf '%s|%s|%s\\n' \"$(basename $f .theme)\" \"$(sed -n 's/^name = //p' $f)\" \"$(sed -n 's/^desc = //p' $f)\"; done"]
        stdout: StdioCollector { onStreamFinished: app.themes = this.text.split("\n").filter(l => l).map(l => { const p = l.split("|"); return { id: p[0], name: p[1], desc: p[2] }; }) }
    }
    Process {
        id: aiProc; command: ["latte-ai", "status"]
        stdout: StdioCollector { onStreamFinished: { const ok = /ok=1/.test(this.text); const m = (this.text.match(/model=(.*)/) || [, ""])[1]; app.aiState = ok ? "✓ Domáci server odpovedá" + (m ? " (" + m + ")" : "") : "× Domáci server teraz neodpovedá — nastavíš neskôr"; } }
    }
    FileView { id: doneFile; path: app.cfg + "/barista-done"; printErrors: false }
    FileView { path: app.cfg + "/profil-ovladania"; printErrors: false
               onLoaded: app.ctrlProfile = (["linux", "mac"].indexOf(text().trim()) >= 0) ? text().trim() : "windows" }
    Process { id: runner }
    function run(cmd) { runner.command = cmd; runner.running = true; }
    // inštalácia vybraných aplikácií priamo v Baristovi (krok Hotovo), jedna po druhej, so stavom každej
    property var instState: ({})          // id → "caka" | "bezi" | "ok" | "chyba"
    property var queue: []
    property bool installing: false
    Process {
        id: installer
        onExited: (code) => {
            const s = Object.assign({}, app.instState); s[app.queue[0]] = code === 0 ? "ok" : "chyba"; app.instState = s;
            app.queue = app.queue.slice(1); app.nextInstall();
        }
    }
    function startInstalls() {
        if (installing) return;
        const ids = Object.keys(picks).filter(k => picks[k]);
        const s = {}; for (const i of ids) s[i] = "caka"; instState = s;
        queue = ids; installing = ids.length > 0; nextInstall();
    }
    function nextInstall() {
        if (queue.length === 0) { installing = false; status = Object.keys(instState).length ? "Aplikácie sú nainštalované — nájdeš ich v Text Bare a v App Manageri." : ""; return; }
        const s = Object.assign({}, instState); s[queue[0]] = "bezi"; instState = s;
        installer.command = ["latte-apps", "install", "flatpak", queue[0]]; installer.running = true;
    }
    function finish() {
        // zvyšok (ak ešte beží) dokončí proces na pozadí s oznámením po každej aplikácii
        if (queue.length > 1 || (queue.length === 1 && !installer.running)) {
            const rest = installer.running ? queue.slice(1) : queue;
            const bg = Qt.createQmlObject('import Quickshell.Io; Process {}', app);
            bg.command = ["sh", "-c", "for id in \"$@\"; do latte-apps install flatpak \"$id\" >/dev/null 2>&1 && notify-send -a Barista 'Nainštalované' \"$id\" || notify-send -a Barista 'Inštalácia zlyhala' \"$id\"; done", "sh"].concat(rest);
            bg.startDetached();
        }
        doneFile.setText(new Date().toISOString() + "\n");      // Barista sa už sám neukáže
        Qt.callLater(Qt.quit);
    }

    FloatingWindow {

        onClosed: app.finish()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: "Barista — LatteOS"
        implicitWidth: 980; implicitHeight: 680
        color: theme.surface

        // ľavý pás krokov
        Rectangle {
            id: rail
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 230; color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.18 : 0.04)
            Column {
                x: 22; y: 26; spacing: 6
                Row {
                    spacing: 10; bottomPadding: 18
                    Image { source: "file:///usr/share/latteos/noctalia/icons/latte-cup.png"; width: 34; height: 34 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Barista"; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 24; weight: Font.DemiBold } }
                }
                Repeater {
                    model: app.steps
                    Row {
                        required property string modelData
                        required property int index
                        spacing: 10
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: index < app.step ? theme.primary : (index === app.step ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.25) : theme.field)
                            border { color: index === app.step ? theme.primary : "transparent"; width: 1.5 }
                            Text { anchors.centerIn: parent; text: index < app.step ? "✓" : (index + 1); color: index < app.step ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; color: index === app.step ? theme.fg : theme.fgDim
                               font { family: theme.fontUi; pixelSize: 14; weight: index === app.step ? Font.Bold : Font.Normal } }
                    }
                }
            }
        }

        component Choice: Rectangle {
            id: ch
            property string title; property string sub; property bool on: false; property string glyph: ""
            signal picked()
            width: 250; height: 84; radius: 14
            color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (cm.containsMouse ? theme.hover : theme.field)
            border { color: on ? theme.primary : "transparent"; width: 1.5 }
            Glyph { visible: ch.glyph !== ""; x: 16; anchors.verticalCenter: parent.verticalCenter; name: ch.glyph || "point"; size: 26; color: theme.primary }
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: ch.glyph !== "" ? 54 : 16; rightMargin: 12 }
                spacing: 3
                Text { width: parent.width; elide: Text.ElideRight; text: ch.title; color: theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: ch.sub; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
            }
            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: ch.picked() }
        }
        component H: Text { color: theme.fg; font { family: theme.fontDisplay; pixelSize: 30; weight: Font.DemiBold } }
        component P: Text { width: parent ? parent.width : 600; wrapMode: Text.WordWrap; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } }

        Item {
            anchors { left: rail.right; right: parent.right; top: parent.top; bottom: nav.top; margins: 34 }
            Loader {
                anchors.fill: parent
                sourceComponent: [sWelcome, sLook, sWindows, sBar, sAi, sApps, sDone][app.step]
            }
        }

        Row {
            id: nav
            anchors { right: parent.right; bottom: parent.bottom; margins: 26 }
            spacing: 10
            component NavBtn: Rectangle {
                id: nb
                property string label; property bool primaryStyle: false
                signal clicked()
                width: nt.implicitWidth + 34; height: 42; radius: 12
                color: primaryStyle ? theme.primary : (nm.containsMouse ? theme.hover : theme.field)
                Text { id: nt; anchors.centerIn: parent; text: nb.label; color: nb.primaryStyle ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; onClicked: nb.clicked() }
            }
            NavBtn { visible: app.step === 0; label: "Preskočiť"; onClicked: { app.picks = {}; app.finish(); } }
            NavBtn { visible: app.step > 0; label: "Späť"; onClicked: app.step-- }
            NavBtn { label: app.step === app.steps.length - 1 ? "Začať používať LatteOS" : "Ďalej"; primaryStyle: true
                     onClicked: { if (app.step === app.steps.length - 1) app.finish(); else { app.step++; if (app.step === 4) aiProc.running = true; if (app.step === 6) app.startInstalls(); } } }
        }
        Text { anchors { left: rail.right; bottom: parent.bottom; margins: 30; leftMargin: 34 } text: app.status; color: theme.primary; font { family: theme.fontUi; pixelSize: 12 } }
    }

    // ── kroky ────────────────────────────────────────────────────────────────────
    Component {
        id: sWelcome
        Column {
            spacing: 16
            H { text: "Vitaj v LatteOS ☕" }
            P { text: "Za minútu si nastavíme vzhľad, okná, lištu, AI a aplikácie. Všetko sa dá neskôr zmeniť v Nastaveniach (šálka na lište › Nastavenia) — nič tu nie je natrvalo." }
            P { text: "Tip: Super+Medzerník otvorí Text Bar. Píš čokoľvek — aplikáciu, nastavenie, súbor, otázku pre AI." }
        }
    }
    Component {
        id: sLook
        Column {
            spacing: 14
            H { text: "Vzhľad" }
            P { text: "Téma prefarbí lištu, panely, okná aj aplikácie. Klikni a hneď uvidíš výsledok." }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.themes
                    Choice {
                        required property var modelData
                        width: 172; height: 62; title: modelData.name; sub: modelData.desc; on: app.themeId === modelData.id
                        onPicked: { app.themeId = modelData.id; app.run(["latte-theme", "set", modelData.id]); }
                    }
                }
            }
            Row {
                spacing: 10
                Repeater {
                    model: [["tema", "Podľa témy"], ["dark", "Tmavá"], ["light", "Svetlá"], ["auto", "Podľa slnka"]]
                    Choice { required property var modelData; width: 150; height: 52; title: modelData[1]; sub: ""; on: app.modePref === modelData[0]
                             onPicked: { app.modePref = modelData[0]; app.run(["latte-theme", "mode", modelData[0]]); } }
                }
            }
        }
    }
    Component {
        id: sWindows
        Column {
            spacing: 14
            H { text: "Ovládanie a okná" }
            P { text: "Odkiaľ prichádzaš? Klávesové skratky a správanie myši sa prispôsobia. Zmeníš to v Nastaveniach › Klávesnica a skratky." }
            Row {
                spacing: 12
                Repeater {
                    model: [["windows", "Windows", "Alt+Tab, Alt+F4, Ctrl+Alt+Del, Win = Štart", "app-window"],
                            ["linux", "Linux", "Super+Enter, Super+Q, fokus za myšou", "terminal-2"],
                            ["mac", "macOS", "Cmd+Medzerník, Cmd+Tab, Cmd+Q (Cmd = Win)", "keyboard"]]
                    Choice { required property var modelData; width: 230; height: 110; title: modelData[1]; sub: modelData[2]; glyph: modelData[3]; on: app.ctrlProfile === modelData[0]
                             onPicked: { app.ctrlProfile = modelData[0];
                                         app.run(["sh", "-c", "mkdir -p \"$1\" && if [ \"$2\" = windows ]; then rm -f \"$1/profil-ovladania\"; else printf '%s\\n' \"$2\" > \"$1/profil-ovladania\"; fi; hyprctl reload",
                                                  "sh", app.cfg, modelData[0]]); } }
                }
            }
            P { text: "Ako sa majú ukladať okná? Režim prepneš kedykoľvek ikonou na lište; Win+Z ponúkne rozloženie okna." }
            Row {
                spacing: 12
                Repeater {
                    model: [["paska", "Nekonečná páska", "Okná v stĺpcoch vedľa seba, páska sa posúva. Srdce LatteOS.", "layout-columns"],
                            ["dlazdice", "Dlaždice", "Okná sa delia o obrazovku, nič sa neprekrýva.", "layout-grid"],
                            ["plavajuce", "Plávajúce", "Voľné okná ako vo Windows.", "app-window"]]
                    Choice { required property var modelData; width: 230; height: 110; title: modelData[1]; sub: modelData[2]; glyph: modelData[3]; on: app.windowMode === modelData[0]
                             onPicked: { app.windowMode = modelData[0]; app.run(["hyprctl", "eval", "require(\"latte.windows\").apply(\"" + modelData[0] + "\", false)"]); } }
                }
            }
        }
    }
    Component {
        id: sBar
        Column {
            spacing: 14
            H { text: "Lišta a maskot" }
            P { text: "Na lište vpravo sedí maskot. Keď hrá hudba, ťuká labkami do rytmu; v noci spí. Vyber si svojho (alebo žiadneho)." }
            Row {
                spacing: 12
                Repeater {
                    model: [["macka", "Latte mačka"], ["mokka", "Mokka"], ["zrnko", "Zrnko"], ["ziadny", "Žiadny"]]
                    Rectangle {
                        required property var modelData
                        width: 150; height: 150; radius: 16
                        color: app.mascot === modelData[0] ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : theme.field
                        border { color: app.mascot === modelData[0] ? theme.primary : "transparent"; width: 1.5 }
                        Image { visible: parent.modelData[0] !== "ziadny"; anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                                width: 88; height: 72; smooth: false; fillMode: Image.PreserveAspectFit
                                source: parent.modelData[0] !== "ziadny" ? "file:///usr/share/latteos/noctalia/plugins/cat/mascots/" + parent.modelData[0] + "-sedi.png" : "" }
                        Text { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 } text: parent.modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        MouseArea { anchors.fill: parent; onClicked: { app.mascot = parent.modelData[0]; app.run(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/mascot\"", "sh", app.cfg, parent.modelData[0]]); } }
                    }
                }
            }
            P { text: "Vľavo je dlaždica aplikácií (klik = spúšťač, pravý klik = App Manager), v strede Text Bar, vedľa času kalendár a oznámenia, vpravo Kapsa (schránka)." }
        }
    }
    Component {
        id: sAi
        Column {
            spacing: 14
            H { text: "AI" }
            P { text: "Text Bar (/ai) a panel Super+I sa pýtajú AI. Kde má bežať?" }
            Flow {
                width: parent.width; spacing: 12
                Repeater {
                    model: [["domaci", "Domáci server", "LM Studio alebo Ollama na inom PC v sieti", "server"],
                            ["lokalne", "Tento počítač", "Malý model v Ollame, bez internetu", "device-desktop"],
                            ["web", "Prihlásenie v prehliadači", "Claude, ChatGPT… s tvojím účtom, bez API kľúča", "world"],
                            ["cloud", "Veľké AI cez API", "Claude, ChatGPT, Gemini (kľúč v Nastaveniach)", "cloud"],
                            ["ziadna", "Bez AI", "LatteOS AI nikde neponúka ani nezobrazí", "robot-off"]]
                    Choice { required property var modelData; width: 240; height: 100; title: modelData[1]; sub: modelData[2]; glyph: modelData[3]; on: app.aiChoice === modelData[0]
                             onPicked: { app.aiChoice = modelData[0]; app.run(["latte-ai", "set", "provider", modelData[0]]); } }
                }
            }
            P { text: app.aiChoice === "domaci" ? (app.aiState || "Zisťujem domáci server…")
                    : app.aiChoice === "ziadna" ? "AI bude vypnutá: Text Bar nemá režim AI a panel Super+I nič neponúka. Zapneš ju kedykoľvek v Nastaveniach."
                    : app.aiChoice === "web" ? "Otázka z Text Baru sa otvorí na stránke AI (predvolene Claude), kde si prihlásený. Zmeníš pravým klikom na Text Bar."
                    : "Podrobnosti nastavíš v Nastaveniach › Softvér › AI." }
        }
    }
    Component {
        id: sApps
        Column {
            spacing: 14
            H { text: "Aplikácie" }
            P { text: "Označ, čo chceš mať hneď. Inštalujú sa z Flathubu pre tvoj účet (bez hesla, v izolácii) na pozadí. Ďalšie nájdeš v App Manageri." }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.apps
                    Choice {
                        required property var modelData
                        width: 200; height: 62; title: (app.picks[modelData[0]] ? "✓ " : "") + modelData[1]; sub: modelData[2]; on: !!app.picks[modelData[0]]
                        onPicked: { const p = Object.assign({}, app.picks); p[modelData[0]] = !p[modelData[0]]; app.picks = p; }
                    }
                }
            }
        }
    }
    Component {
        id: sDone
        Column {
            spacing: 12
            H { text: app.installing ? "Chystám ti aplikácie…" : "Hotovo, dobrú chuť ☕" }
            Repeater {
                model: Object.keys(app.instState)
                Row {
                    required property string modelData
                    spacing: 10
                    readonly property string st: app.instState[modelData]
                    Text { width: 24; text: ({ caka: "○", bezi: "◐", ok: "✓", chyba: "×" })[parent.st]; color: parent.st === "chyba" ? theme.error : theme.primary; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                    Text { text: ((app.apps.find(a => a[0] === modelData) || [, modelData])[1]) + "  ·  " + ({ caka: "čaká", bezi: "inštalujem z Flathubu…", ok: "nainštalované", chyba: "nepodarilo sa (skús v App Manageri)" })[parent.st]
                           color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                }
            }
            P { text: "Pár skratiek na začiatok:" }
            Repeater {
                model: [["Super + Medzerník", "Text Bar: hľadaj, spúšťaj, pýtaj sa"], ["Super + Tab", "Prehľad pásky"], ["Super + Z", "Rozloženie okna"],
                        ["Super + I", "AI rozhovor"], ["Super + G", "Herňa"], ["Super + E", "Súbory"], ["Ctrl + Shift + Esc", "Monitor"]]
                Row {
                    required property var modelData
                    spacing: 14
                    Rectangle { width: 180; height: 30; radius: 8; color: theme.field
                                Text { anchors.centerIn: parent; text: modelData[0]; color: theme.fg; font { family: theme.fontMono; pixelSize: 12; weight: Font.Bold } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                }
            }
            P { text: "Všetky skratky: Nastavenia › Systém › Klávesnica a skratky. Sprievodcu spustíš znova: Text Bar › Barista." }
        }
    }
}
