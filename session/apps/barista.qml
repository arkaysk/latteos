// LatteOS — Barista, sprievodca prvým spustením (radar: „Barista ako meno sprievodcu“).
// Texty po anglicky cez i18n.tr() (common/I18n.qml, preklady /usr/share/latteos/i18n/<jazyk>.json).
// Krok „Hrnček a káva“: téma LatteOS je hrnček (materiál okien), kvapky v ploche Kvapky sú káva v ňom
// (~/.config/latteos/kava) — „Akú si dáte kávu a do čoho?“.
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
    I18n { id: i18n }

    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos"
    property int step: Math.max(0, Math.min(6, parseInt(Quickshell.env("LATTE_APP_ARGS") || "0") || 0))   // latte-app barista <krok>
    readonly property var steps: [i18n.tr("Welcome"), i18n.tr("Cup & coffee"), i18n.tr("Windows"), i18n.tr("Bar"), i18n.tr("AI"), i18n.tr("Apps"), i18n.tr("Done")]
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
    property string kava: "espresso"
    // káva: pomer vody a mlieka ako v kvapkách (session/kvapky/kvapka.luau)
    readonly property var kavy: [["espresso", "Espresso", 0, 0], ["ristretto", "Ristretto", 0, 0], ["lungo", "Lungo", 0.35, 0],
                                 ["americano", "Americano", 0.7, 0], ["macchiato", "Macchiato", 0, 0.25], ["cortado", "Cortado", 0, 0.4],
                                 ["flatwhite", "Flat white", 0.05, 0.5], ["cappuccino", "Cappuccino", 0, 0.55], ["latte", "Latte", 0, 0.85],
                                 ["cierna-s-mliekom", "Black with milk", 0.4, 0.3]]
    function coffeeColor(v, m) {
        const mix = (a, b, t) => a + (b - a) * t;
        const base = [mix(0x1c, 0x4a, v), mix(0x0f, 0x24, v), mix(0x09, 0x10, v)];
        const mm = m * m;
        return Qt.rgba(mix(base[0], 0xc9, mm) / 255, mix(base[1], 0xa4, mm) / 255, mix(base[2], 0x7a, mm) / 255, 1 - 0.42 * v * (1 - m));
    }
    function kavaOf(id) { return app.kavy.find(k => k[0] === id) || app.kavy[0]; }
    // hrnček podľa materiálu témy
    function cupColor(t) {
        const m = (t && t.material) || "", a = "#" + ((t && t.accent) || "E4B283");
        if (m === "kov") return Qt.tint("#a3acb4", Qt.rgba(Qt.color(a).r, Qt.color(a).g, Qt.color(a).b, 0.55));   // hliník, striebro, zlato
        return ({ sklo: Qt.rgba(1, 1, 1, 0.22), jantar: "#d99a3c", mraz: "#cfe8f5", fazety: "#f3dde6", kamen: "#8a8177" })[m] || a;
    }

    readonly property var apps: [["org.mozilla.firefox", "Firefox", "browser"], ["org.videolan.VLC", "VLC", "video and music"],
                                 ["org.libreoffice.LibreOffice", "LibreOffice", "office"], ["com.valvesoftware.Steam", "Steam", "games"],
                                 ["com.discordapp.Discord", "Discord", "voice and chat"], ["org.gimp.GIMP", "GIMP", "photos"],
                                 ["io.github.alainm23.planify", "Planify", "tasks and planner"], ["com.obsproject.Studio", "OBS Studio", "recording"]]

    Process {
        id: scan; running: true
        command: ["sh", "-c", "for f in /usr/share/latteos/themes/*.theme; do printf '%s|%s|%s|%s|%s\\n' \"$(basename $f .theme)\" \"$(sed -n 's/^name = //p' $f)\" \"$(sed -n 's/^desc = //p' $f)\" \"$(sed -n 's/^material = //p' $f)\" \"$(sed -n 's/^border_active = //p' $f)\"; done"]
        stdout: StdioCollector { onStreamFinished: app.themes = this.text.split("\n").filter(l => l).map(l => { const p = l.split("|"); return { id: p[0], name: p[1], desc: p[2], material: p[3], accent: p[4] }; }) }
    }
    Process {
        id: aiProc; command: ["latte-ai", "status"]
        stdout: StdioCollector { onStreamFinished: { const ok = /ok=1/.test(this.text); const m = (this.text.match(/model=(.*)/) || [, ""])[1]; app.aiState = ok ? "✓ " + i18n.tr("The home server answers") + (m ? " (" + m + ")" : "") : "× " + i18n.tr("The home server does not answer right now — set it up later"); } }
    }
    FileView { id: doneFile; path: app.cfg + "/barista-done"; printErrors: false }
    FileView { path: app.cfg + "/kava"; printErrors: false; onLoaded: { const k = text().trim(); if (app.kavy.find(x => x[0] === k)) app.kava = k; } }
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
        if (queue.length === 0) { installing = false; status = Object.keys(instState).length ? i18n.tr("The apps are installed — find them in the Text Bar and in the App Manager.") : ""; return; }
        const s = Object.assign({}, instState); s[queue[0]] = "bezi"; instState = s;
        installer.command = ["latte-apps", "install", "flatpak", queue[0]]; installer.running = true;
    }
    function finish() {
        // zvyšok (ak ešte beží) dokončí proces na pozadí s oznámením po každej aplikácii
        if (queue.length > 1 || (queue.length === 1 && !installer.running)) {
            const rest = installer.running ? queue.slice(1) : queue;
            const bg = Qt.createQmlObject('import Quickshell.Io; Process {}', app);
            bg.command = ["sh", "-c", "ok=\"$1\"; bad=\"$2\"; shift 2; for id in \"$@\"; do latte-apps install flatpak \"$id\" >/dev/null 2>&1 && notify-send -a Barista \"$ok\" \"$id\" || notify-send -a Barista \"$bad\" \"$id\"; done", "sh", i18n.tr("Installed"), i18n.tr("Installation failed")].concat(rest);
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
                sourceComponent: [sWelcome, sCup, sWindows, sBar, sAi, sApps, sDone][app.step]
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
            NavBtn { visible: app.step === 0; label: i18n.tr("Skip"); onClicked: { app.picks = {}; app.finish(); } }
            NavBtn { visible: app.step > 0; label: i18n.tr("Back"); onClicked: app.step-- }
            NavBtn { label: app.step === app.steps.length - 1 ? i18n.tr("Start using LatteOS") : i18n.tr("Next"); primaryStyle: true
                     onClicked: { if (app.step === app.steps.length - 1) app.finish(); else { app.step++; if (app.step === 4) aiProc.running = true; if (app.step === 6) app.startInstalls(); } } }
        }
        Text { anchors { left: rail.right; bottom: parent.bottom; margins: 30; leftMargin: 34 } text: app.status; color: theme.primary; font { family: theme.fontUi; pixelSize: 12 } }
    }

    // ── kroky ────────────────────────────────────────────────────────────────────
    Component {
        id: sWelcome
        Column {
            spacing: 16
            H { text: i18n.tr("Welcome to LatteOS ☕") }
            P { text: i18n.tr("In a minute we will set up your cup and coffee, windows, bar, AI and apps. Everything can be changed later in Settings — nothing here is permanent.") }
            P { text: i18n.tr("Everything works with the mouse; the keyboard only makes it faster. Tip: the Windows key (Super) + Space opens the Text Bar — type anything: an app, a setting, a file, a question for AI.") }
        }
    }
    // hrnček (téma = materiál okien) a káva (kvapky); náhľad: zvolený hrnček so zvolenou kávou
    component Cup: Item {
        id: cup
        property color body: "#f3ebdd"
        property color coffee: "#1c0f09"
        property real milk: 0
        property bool glass: false
        width: 96; height: 84
        Rectangle {     // ucho
            x: cup.width - 30; y: 18; width: 30; height: 36; radius: 15; color: "transparent"
            border { color: cup.body; width: 7 }
        }
        Rectangle {     // telo hrnčeka
            x: 6; y: 12; width: cup.width - 30; height: cup.height - 16; radius: 18; color: cup.body
            border { color: Qt.darker(cup.body, cup.glass ? 1.0 : 1.25); width: cup.glass ? 2 : 1 }
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                        height: 16; radius: 8; color: cup.coffee }
            Rectangle { visible: cup.milk > 0.2; anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                        width: (parent.width - 24) * Math.min(1, cup.milk + 0.2); height: 10; radius: 5; color: "#f3ebdd"; opacity: 0.55 + 0.4 * cup.milk }
        }
    }
    Component {
        id: sCup
        Column {
            spacing: 8
            H { text: i18n.tr("What coffee will you have, and in what?") }
            P { text: i18n.tr("The cup is the look of your windows and panels. The coffee is the colour of the liquid drops on the Drops desktop. Click and you see it at once.") }
            Row {
                spacing: 18
                Cup {
                    readonly property var t: app.themes.find(x => x.id === app.themeId) || null
                    readonly property var k: app.kavaOf(app.kava)
                    anchors.verticalCenter: parent.verticalCenter
                    scale: 1.05
                    body: app.cupColor(t); glass: !!t && t.material === "sklo"
                    coffee: app.coffeeColor(k[2], k[3]); milk: k[3]
                }
                Column {
                    spacing: 2; anchors.verticalCenter: parent.verticalCenter
                    Text { text: app.kavaOf(app.kava)[1] === "Black with milk" ? i18n.tr("Black with milk") : app.kavaOf(app.kava)[1]
                           color: theme.fg; font { family: theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold } }
                    Text { text: i18n.tr("in the cup “{name}”", { name: (app.themes.find(x => x.id === app.themeId) || { name: app.themeId }).name })
                           color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                }
            }
            Text { text: i18n.tr("IN WHAT"); color: theme.primary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: app.themes
                    Rectangle {
                        required property var modelData
                        width: 150; height: 44; radius: 12
                        color: app.themeId === modelData.id ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (tm.containsMouse ? theme.hover : theme.field)
                        border { color: app.themeId === modelData.id ? theme.primary : "transparent"; width: 1.5 }
                        Cup { x: 6; anchors.verticalCenter: parent.verticalCenter; scale: 0.36; transformOrigin: Item.Left
                              body: app.cupColor(parent.modelData); glass: parent.modelData.material === "sklo"; coffee: app.coffeeColor(app.kavaOf(app.kava)[2], app.kavaOf(app.kava)[3]); milk: app.kavaOf(app.kava)[3] }
                        Text { anchors { left: parent.left; leftMargin: 52; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                               text: parent.modelData.name; elide: Text.ElideRight; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { app.themeId = parent.modelData.id; app.run(["latte-theme", "set", parent.modelData.id]); } }
                    }
                }
            }
            Text { text: i18n.tr("WHAT COFFEE"); color: theme.primary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: app.kavy
                    Rectangle {
                        required property var modelData
                        width: 118; height: 34; radius: 17
                        color: app.kava === modelData[0] ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : (km.containsMouse ? theme.hover : theme.field)
                        border { color: app.kava === modelData[0] ? theme.primary : "transparent"; width: 1.5 }
                        Rectangle { x: 7; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11
                                    color: app.coffeeColor(parent.modelData[2], parent.modelData[3]); border { color: Qt.rgba(1, 1, 1, 0.25); width: 1 } }
                        Text { anchors { left: parent.left; leftMargin: 38; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                               text: parent.modelData[0] === "cierna-s-mliekom" ? i18n.tr("Black with milk") : parent.modelData[1]
                               elide: Text.ElideRight; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                        MouseArea { id: km; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { app.kava = parent.modelData[0];
                                                 app.run(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/kava\"", "sh", app.cfg, parent.modelData[0]]); } }
                    }
                }
            }
            Row {
                spacing: 10
                Repeater {
                    model: [["tema", "By theme"], ["dark", "Dark"], ["light", "Light"], ["auto", "By the sun"]]
                    Choice { required property var modelData; width: 128; height: 36; title: i18n.tr(modelData[1]); sub: ""; on: app.modePref === modelData[0]
                             onPicked: { app.modePref = modelData[0]; app.run(["latte-theme", "mode", modelData[0]]); } }
                }
            }
        }
    }
    Component {
        id: sWindows
        Column {
            spacing: 14
            H { text: i18n.tr("Controls and windows") }
            P { text: i18n.tr("Where are you coming from? Keyboard shortcuts and mouse behaviour adapt. Change it in Settings › Keyboard and shortcuts.") }
            Row {
                spacing: 12
                Repeater {
                    model: [["windows", "Windows", "Alt+Tab, Alt+F4, Ctrl+Alt+Del, Win = Start", "app-window"],
                            ["linux", "Linux", "Super+Enter, Super+Q, focus follows the mouse", "terminal-2"],
                            ["mac", "macOS", "Cmd+Space, Cmd+Tab, Cmd+Q (Cmd = Win)", "keyboard"]]
                    Choice { required property var modelData; width: 230; height: 110; title: modelData[1]; sub: i18n.tr(modelData[2]); glyph: modelData[3]; on: app.ctrlProfile === modelData[0]
                             onPicked: { app.ctrlProfile = modelData[0];
                                         app.run(["sh", "-c", "mkdir -p \"$1\" && if [ \"$2\" = windows ]; then rm -f \"$1/profil-ovladania\"; else printf '%s\\n' \"$2\" > \"$1/profil-ovladania\"; fi; hyprctl reload",
                                                  "sh", app.cfg, modelData[0]]); } }
                }
            }
            P { text: i18n.tr("How should windows be arranged? Switch the mode any time with a click on the bar; Win+Z offers a window layout.") }
            Row {
                spacing: 12
                Repeater {
                    model: [["paska", "Endless strip", "Windows in columns side by side, the strip scrolls. The heart of LatteOS.", "layout-columns"],
                            ["dlazdice", "Tiles", "Windows share the screen, nothing overlaps.", "layout-grid"],
                            ["plavajuce", "Floating", "Free windows like in Windows.", "app-window"]]
                    Choice { required property var modelData; width: 230; height: 110; title: i18n.tr(modelData[1]); sub: i18n.tr(modelData[2]); glyph: modelData[3]; on: app.windowMode === modelData[0]
                             onPicked: { app.windowMode = modelData[0]; app.run(["hyprctl", "eval", "require(\"latte.windows\").apply(\"" + modelData[0] + "\", false)"]); } }
                }
            }
        }
    }
    Component {
        id: sBar
        Column {
            spacing: 14
            H { text: i18n.tr("Bar and mascot") }
            P { text: i18n.tr("A mascot sits on the right of the bar. When music plays it taps along; at night it sleeps. Pick yours (or none).") }
            Row {
                spacing: 12
                Repeater {
                    model: [["macka", "Latte cat"], ["mokka", "Mokka"], ["zrnko", "Bean"], ["ziadny", "None"]]
                    Rectangle {
                        required property var modelData
                        width: 150; height: 150; radius: 16
                        color: app.mascot === modelData[0] ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18) : theme.field
                        border { color: app.mascot === modelData[0] ? theme.primary : "transparent"; width: 1.5 }
                        Image { visible: parent.modelData[0] !== "ziadny"; anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                                width: 88; height: 72; smooth: false; fillMode: Image.PreserveAspectFit
                                source: parent.modelData[0] !== "ziadny" ? "file:///usr/share/latteos/noctalia/plugins/cat/mascots/" + parent.modelData[0] + "-sedi.png" : "" }
                        Text { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 } text: i18n.tr(parent.modelData[1]); color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        MouseArea { anchors.fill: parent; onClicked: { app.mascot = parent.modelData[0]; app.run(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/mascot\"", "sh", app.cfg, parent.modelData[0]]); } }
                    }
                }
            }
            P { text: i18n.tr("On the left is the apps tile (click = launcher, right click = App Manager), in the middle the Text Bar, next to the time the calendar and notifications, on the right Kapsa (clipboard).") }
        }
    }
    Component {
        id: sAi
        Column {
            spacing: 14
            H { text: i18n.tr("AI") }
            P { text: i18n.tr("The Text Bar (/ai) and the Super+I panel ask an AI. Where should it run?") }
            Flow {
                width: parent.width; spacing: 12
                Repeater {
                    model: [["domaci", "Home server", "LM Studio or Ollama on another PC in the network", "server"],
                            ["lokalne", "This computer", "A small model in Ollama, without internet", "device-desktop"],
                            ["web", "Sign in in the browser", "Claude, ChatGPT… with your account, no API key", "world"],
                            ["cloud", "Big AI over an API", "Claude, ChatGPT, Gemini (key in Settings)", "cloud"],
                            ["ziadna", "No AI", "LatteOS never offers or shows AI", "robot-off"]]
                    Choice { required property var modelData; width: 240; height: 100; title: i18n.tr(modelData[1]); sub: i18n.tr(modelData[2]); glyph: modelData[3]; on: app.aiChoice === modelData[0]
                             onPicked: { app.aiChoice = modelData[0]; app.run(["latte-ai", "set", "provider", modelData[0]]); } }
                }
            }
            P { text: app.aiChoice === "domaci" ? (app.aiState || i18n.tr("Checking the home server…"))
                    : app.aiChoice === "ziadna" ? i18n.tr("AI will be off: the Text Bar has no AI mode and the Super+I panel offers nothing. Turn it on any time in Settings.")
                    : app.aiChoice === "web" ? i18n.tr("A question from the Text Bar opens on the AI page (Claude by default) where you are signed in. Change it with a right click on the Text Bar.")
                    : i18n.tr("Set the details in Settings › Software › AI.") }
        }
    }
    Component {
        id: sApps
        Column {
            spacing: 14
            H { text: i18n.tr("Apps") }
            P { text: i18n.tr("Mark what you want right away. They install from Flathub for your account (no password, sandboxed) in the background. More in the App Manager.") }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: app.apps
                    Choice {
                        required property var modelData
                        width: 200; height: 62; title: (app.picks[modelData[0]] ? "✓ " : "") + modelData[1]; sub: i18n.tr(modelData[2]); on: !!app.picks[modelData[0]]
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
            H { text: app.installing ? i18n.tr("Getting your apps ready…") : i18n.tr("Done — enjoy your coffee ☕") }
            Repeater {
                model: Object.keys(app.instState)
                Row {
                    required property string modelData
                    spacing: 10
                    readonly property string st: app.instState[modelData]
                    Text { width: 24; text: ({ caka: "○", bezi: "◐", ok: "✓", chyba: "×" })[parent.st]; color: parent.st === "chyba" ? theme.error : theme.primary; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                    Text { text: ((app.apps.find(a => a[0] === modelData) || [, modelData])[1]) + "  ·  " + i18n.tr(({ caka: "waiting", bezi: "installing from Flathub…", ok: "installed", chyba: "failed (try in the App Manager)" })[parent.st])
                           color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                }
            }
            P { text: i18n.tr("Everything works with the mouse. A few shortcuts to go faster:") }
            Repeater {
                model: [["Super + Space", "Text Bar: search, launch, ask"], ["Super + Tab", "Strip overview"], ["Super + Z", "Window layout"],
                        ["Super + I", "AI chat"], ["Super + G", "Game room"], ["Super + E", "Files"], ["Ctrl + Shift + Esc", "Monitor"]]
                Row {
                    required property var modelData
                    spacing: 14
                    Rectangle { width: 180; height: 30; radius: 8; color: theme.field
                                Text { anchors.centerIn: parent; text: modelData[0]; color: theme.fg; font { family: theme.fontMono; pixelSize: 12; weight: Font.Bold } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: i18n.tr(modelData[1]); color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } }
                }
            }
            P { text: i18n.tr("All shortcuts: Settings › System › Keyboard and shortcuts. Run this guide again: Text Bar › Barista.") }
        }
    }
}
