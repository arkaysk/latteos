// LatteOS — obrazovka prihlásenia (Quickshell + greetd), vzhľad latteGoo (29. 9. 2026): káva na tapete —
// hodiny hore, prihlásenie ako kvapka v strede (účty sú guľaté kvapky na jej hrane), mláka kávy pri spodnom okraji,
// z ktorej vystupujú kvapky Reštartovať a Vypnúť. Všetko myšou; klávesnica iba na heslo.
// Spúšťa ju latte-greeter pod labwc s pixmanom a Qt software backendom: žiadne GL, žiadne GPU — kvapky kreslí
// Canvas (statické tvary, prekreslia sa iba pri zmene).
// Texty po anglicky cez i18n.tr() (apps/common/I18n.qml, preklady /usr/share/latteos/i18n/<jazyk>.json),
// relácie zo súborov /usr/share/latteos/sessions/*.desktop a potom /usr/share/wayland-sessions/*.desktop (iné
// nainštalované prostredia na pokusy; rovnaký názov súboru iba raz, Hidden/NoDisplay nie) — Name, Comment a ich [jazyk].
//
// Vstupy (premenné prostredia z latte-greeter):
//   LATTE_MODE (normal|safe), LATTE_RENDERER, LATTE_REASON — z /run/latteos (latte-boot select)
//   LATTE_GREETER_TEST=1 — náhľad bez greetd (tlačidlo Prihlásiť iba ukáže stav)
// Súbory (skupina latte smie zapisovať z Nastavení, greeter iba číta):
//   /var/lib/latteos/greeter/greeter.conf    background, color, dim, panel (log|text|rss|pocasie|none), panel_title,
//                                            panel_text, rss_url, lat, lon, place
//   /var/lib/latteos/greeter/last-crash.log  prvý log z posledného pádu (píše latte-session)
//   /var/lib/greetd/latte-recent             posledné dva prihlásené účty (píše greeter)
//   /var/lib/greetd/latte-last-session       naposledy zvolená relácia (súbor .desktop, píše greeter)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd


ShellRoot {
    id: root
    I18n { id: i18n }

    // ── paleta Latte (session/noctalia/palettes/Latte.json) ──────────────────────
    readonly property color cBg: "#1B1410"
    readonly property color cCoffee: "#1c0f09"
    readonly property color cGlass: Qt.rgba(28 / 255, 16 / 255, 10 / 255, 0.92)
    readonly property color cField: Qt.rgba(0, 0, 0, 0.30)
    readonly property color cOutline: Qt.rgba(243 / 255, 235 / 255, 221 / 255, 0.14)
    readonly property color cText: "#F3EBDD"
    readonly property color cDim: "#CDBCA6"
    readonly property color cAccent: "#E4B283"
    readonly property color cOnAccent: "#1E1712"
    readonly property color cError: "#E07A5F"
    readonly property string fUi: "Manrope"
    readonly property string fDisplay: "Fraunces"

    readonly property string mode: Quickshell.env("LATTE_MODE") || "safe"
    readonly property string renderer: Quickshell.env("LATTE_RENDERER") || "pixman"
    readonly property string reason: Quickshell.env("LATTE_REASON") || ""
    readonly property bool testMode: Quickshell.env("LATTE_GREETER_TEST") === "1"
    // jazyk dátumu podľa LANG („sk_SK.UTF-8“ → sk_SK)
    readonly property string localeName: (Quickshell.env("LATTE_LANG") || Quickshell.env("LANG") || "en_US").split(".")[0]
    function dateText(d) {
        const loc = Qt.locale(root.localeName);
        return loc.toString(d, root.localeName.startsWith("sk") || root.localeName.startsWith("cs") ? "dddd d. MMMM" : "dddd, MMMM d");
    }

    // ── relácie: súbory .desktop (poradie: LatteOS GOO, Marea, Noctalia, Serpantinum, potom ostatné) ──
    property var sessions: [{ file: "latteos", name: "LatteOS GOO", comment: "", cmd: ["/usr/bin/latte-session"] }]
    property int sessionIndex: 0
    property string lastSession: ""
    Process {
        id: sessProc; running: true
        command: ["sh", "-c", "lang=\"${1%%.*}\"; short=\"${lang%%_*}\"; seen=' '; "
                  + "for f in /usr/share/latteos/sessions/*.desktop /usr/share/wayland-sessions/*.desktop; do [ -f \"$f\" ] || continue; "
                  + "b=\"$(basename \"$f\" .desktop)\"; case \"$seen\" in *\" $b \"*) continue;; esac; seen=\"$seen$b \"; "
                  // holý Hyprland nemá lištu ani cestu von myšou (iba Super+M) a gamescope-session-steam je LatteOS Hra
                  // bez poistiek (návrat na plochu) — v zozname LatteOS nie sú
                  + "case \"$b\" in hyprland|hyprland-uwsm|gamescope-session-steam) continue;; esac; "
                  + "grep -qiE '^(Hidden|NoDisplay)=true' \"$f\" && continue; "
                  + "awk -v L=\"$lang\" -v S=\"$short\" -v F=\"$(basename \"$f\" .desktop)\" -F= '"
                  + "$1==\"Name\"{n=$2} $1==\"Name[\"S\"]\"||$1==\"Name[\"L\"]\"{nl=$2} $1==\"Comment\"{c=$2} $1==\"Comment[\"S\"]\"||$1==\"Comment[\"L\"]\"{cl=$2} "
                  + "$1==\"Exec\"{e=substr($0,6)} END{print F\"\\t\"(nl?nl:n)\"\\t\"(cl?cl:c)\"\\t\"e}' \"$f\"; done", "sh", root.localeName]
        stdout: StdioCollector {
            onStreamFinished: {
                const order = ["latteos", "marea-wm", "marea-hyprland", "latteos-noctalia", "serpantinum"];
                const list = this.text.split("\n").filter(l => l.trim() !== "").map(l => {
                    const p = l.split("\t");
                    // polia Exec ako %U/%f (spec .desktop) greetd nepozná
                    return { file: p[0], name: p[1], comment: p[2] || "", cmd: (p[3] || "/usr/bin/latte-session").trim().split(/\s+/).filter(a => !/^%[a-zA-Z]$/.test(a)) };
                });
                list.sort((a, b) => { const ia = order.indexOf(a.file), ib = order.indexOf(b.file);
                                      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.name.localeCompare(b.name); });
                if (list.length > 0) root.sessions = list;
                root.pickSession();
            }
        }
    }
    FileView { path: "/var/lib/greetd/latte-last-session"; printErrors: false; onLoaded: { root.lastSession = text().trim(); root.pickSession(); } }
    // SAFE pri štarte: LatteOS GOO (latte-session ho v núdzovom režime spustí ako SAFE); inak naposledy zvolená
    // relácia; inak LatteOS GOO
    function pickSession() {
        const find = (f) => sessions.findIndex(s => s.file === f);
        let i = mode === "safe" ? find("latteos") : find(lastSession);
        sessionIndex = i >= 0 ? i : 0;
    }
    property bool sessionsOpen: false

    property string status: ""
    property bool statusError: false
    property bool busy: false
    // Caps Lock / Num Lock: LED klávesnice (/sys/class/leds, číta každý) + odhad z písaných znakov
    property bool capsLed: false
    property bool numLed: true
    property bool hasNumLed: false
    property int capsGuess: -1              // -1 nevie, 0 vypnutý, 1 zapnutý (podľa posledného písmena)
    property bool numpadDead: false         // kláves numerickej klávesnice nenapísal číslicu → Num Lock vypnutý
    readonly property bool capsOn: capsGuess === -1 ? capsLed : capsGuess === 1
    readonly property bool numOff: numpadDead || (hasNumLed && !numLed && numpadUsed)
    property bool numpadUsed: false
    property bool showPass: false
    // test bez klávesnice (setup/f1/headless.sh): LATTE_GREETER_TEST_LOCKS=1 ukáže obe upozornenia
    // LATTE_GREETER_TEST_SESSIONS=1 ukáže rozliaty zoznam relácií
    Component.onCompleted: {
        if (testMode && Quickshell.env("LATTE_GREETER_TEST_LOCKS") === "1") { capsGuess = 1; numpadDead = true; showPass = true; }
        if (testMode && Quickshell.env("LATTE_GREETER_TEST_SESSIONS") === "1") sessionsOpen = true;
    }
    Process {
        id: ledProc
        command: ["sh", "-c", "c=0; n=; for f in /sys/class/leds/*::capslock/brightness; do [ -r \"$f\" ] && [ \"$(cat \"$f\")\" != 0 ] && c=1; done; for f in /sys/class/leds/*::numlock/brightness; do [ -r \"$f\" ] && { [ \"$(cat \"$f\")\" != 0 ] && n=1 || n=${n:-0}; }; done; echo \"$c ${n:--}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(" ");
                const caps = f[0] === "1";
                if (caps !== root.capsLed) root.capsGuess = -1;        // LED sa zmenila → veriť LED
                root.capsLed = caps;
                root.hasNumLed = f[1] !== "-"; root.numLed = f[1] === "1";
            }
        }
    }
    Timer { interval: 500; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!ledProc.running) ledProc.running = true }
    function keyHint(ev) {
        const t = ev.text || "";
        if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {       // písmeno
            const shift = (ev.modifiers & Qt.ShiftModifier) !== 0;
            const upper = t === t.toUpperCase();
            root.capsGuess = (upper !== shift) ? 1 : 0;
        }
        if (ev.modifiers & Qt.KeypadModifier) {
            root.numpadUsed = true;
            root.numpadDead = !/^[0-9.,]$/.test(t) && [Qt.Key_Enter, Qt.Key_Plus, Qt.Key_Minus, Qt.Key_Asterisk, Qt.Key_Slash].indexOf(ev.key) < 0;
        }
        if (ev.key === Qt.Key_CapsLock) root.capsGuess = root.capsGuess === -1 ? (root.capsLed ? 0 : 1) : 1 - root.capsGuess;
        if (ev.key === Qt.Key_NumLock) root.numpadDead = false;
    }

    // ── vzhľad z Nastavení › Účet › Prihlasovanie ──────────────────────────────
    property var conf: ({ background: "/usr/share/backgrounds/latteos/latteos-wallpaper1.jpg", color: "#1B1410",
                          dim: "0.55", panel: "log", panel_title: "", panel_text: "",
                          rss_url: "https://www.aktuality.sk/rss/", lat: "48.74", lon: "19.15", place: "Banská Bystrica" })
    property string crashLog: ""
    FileView {
        path: Quickshell.env("LATTE_GREETER_CONF") || "/var/lib/latteos/greeter/greeter.conf"   // premenná iba pre testy
        printErrors: false
        onLoaded: {
            const c = Object.assign({}, root.conf);
            for (const l of text().split("\n")) { const r = l.match(/^\s*(\w+)\s*=\s*"(.*)"\s*$/); if (r) c[r[1]] = r[2].replace(/\\n/g, "\n"); }
            root.conf = c;
        }
    }
    FileView {
        path: "/var/lib/latteos/greeter/last-crash.log"
        printErrors: false
        onLoaded: root.crashLog = text().trim()
    }
    readonly property bool panelVisible: conf.panel === "text" ? conf.panel_text !== "" : (conf.panel === "log" || conf.panel === "rss" || conf.panel === "pocasie")

    // ── novinky (RSS) a počasie (Open-Meteo, bez kľúča) pre ľavý panel ─────────
    property var news: []
    property var weather: null
    property string netNote: ""
    Process {
        id: rssProc
        command: ["curl", "-s", "-m", "6", "-A", "LatteOS greeter", root.conf.rss_url]
        stdout: StdioCollector {
            onStreamFinished: {
                const items = [];
                const re = /<item[\s\S]*?<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/g;
                let m; while ((m = re.exec(this.text)) && items.length < 8) items.push(m[1].replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#039;|&apos;/g, "'").trim());
                root.news = items; root.netNote = items.length ? "" : i18n.tr("Could not load the news (no network?)");
            }
        }
    }
    Process {
        id: weatherProc
        command: ["curl", "-s", "-m", "6", "https://api.open-meteo.com/v1/forecast?latitude=" + root.conf.lat + "&longitude=" + root.conf.lon
                  + "&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=4"]
        stdout: StdioCollector { onStreamFinished: { try { root.weather = JSON.parse(this.text); root.netNote = ""; } catch (e) { root.netNote = i18n.tr("Could not load the weather (no network?)"); } } }
    }
    function wmo(c) {
        if (c === 0) return [i18n.tr("Clear"), "☀"]; if (c <= 2) return [i18n.tr("Partly cloudy"), "⛅"]; if (c === 3) return [i18n.tr("Overcast"), "☁"];
        if (c <= 48) return [i18n.tr("Fog"), "🌫"]; if (c <= 57) return [i18n.tr("Drizzle"), "🌦"]; if (c <= 67) return [i18n.tr("Rain"), "🌧"];
        if (c <= 77) return [i18n.tr("Snow"), "❄"]; if (c <= 82) return [i18n.tr("Showers"), "🌦"]; if (c <= 86) return [i18n.tr("Snow showers"), "🌨"]; return [i18n.tr("Thunderstorm"), "⛈"];
    }
    onConfChanged: { if (conf.panel === "rss") rssProc.running = true; if (conf.panel === "pocasie") weatherProc.running = true; }
    Timer { interval: 900000; repeat: true; running: root.conf.panel === "rss" || root.conf.panel === "pocasie"
            onTriggered: { if (root.conf.panel === "rss") rssProc.running = true; else weatherProc.running = true; } }

    // ── používatelia: prvý bežný účet z /etc/passwd, alebo naposledy prihlásený ───
    property string lastUser: ""
    property var users: []
    property var recent: []          // posledné dva prihlásené účty (najnovší prvý)
    property var fullNames: ({})
    property string user: ""         // vybraný účet
    property bool otherUser: false   // „Iný účet“: meno sa píše

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            const list = [], names = {};
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const uid = parseInt(f[2]);
                if (f.length > 6 && uid >= 1000 && uid < 60000 && !f[6].endsWith("nologin")) {
                    list.push(f[0]);
                    names[f[0]] = (f[4] || "").split(",")[0] || f[0];
                }
            }
            root.users = list;
            root.fullNames = names;
            if (root.user === "") root.user = root.defaultUser();
        }
    }
    FileView {
        id: lastUserFile
        path: "/var/lib/greetd/latte-last-user"
        printErrors: false
        onLoaded: { root.lastUser = text().trim(); root.user = root.defaultUser(); }
    }
    FileView {
        path: "/var/lib/greetd/latte-recent"
        printErrors: false
        onLoaded: { root.recent = text().split("\n").map(x => x.trim()).filter(x => x !== "").slice(0, 2); root.user = root.defaultUser(); }
    }
    readonly property var recentUsers: {
        const r = recent.filter(u => users.indexOf(u) >= 0);
        if (r.length === 0 && lastUser !== "" && users.indexOf(lastUser) >= 0) r.push(lastUser);
        if (r.length === 0 && users.length > 0) r.push(users[0]);
        return r.slice(0, 2);
    }

    function defaultUser() {
        if (recentUsers.length > 0) return recentUsers[0];
        return users.length > 0 ? users[0] : "";
    }

    // ── greetd ────────────────────────────────────────────────────────────────
    property string pendingPassword: ""

    function login(name, password) {
        if (name === "") { setStatus(i18n.tr("Enter the user name."), true); return; }
        if (testMode || !Greetd.available) {
            setStatus(i18n.tr("Preview: greetd is not running, no login ({session}).", { session: sessions[sessionIndex].name }), false);
            return;
        }
        busy = true;
        pendingPassword = password;
        setStatus(i18n.tr("Checking…"), false);
        Greetd.createSession(name);
    }

    function setStatus(text, isError) { status = text; statusError = isError; }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.pendingPassword);
                root.pendingPassword = "";
            } else if (message !== "") {
                root.setStatus(message, error);
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.pendingPassword = "";
            root.setStatus(i18n.tr("Wrong password or user name."), true);
            Greetd.cancelSession();
            passwordFocus.start();
        }
        function onReadyToLaunch() {
            root.setStatus(i18n.tr("Starting {session}…", { session: root.sessions[root.sessionIndex].name }), false);
            saveUser.running = true;
            Greetd.launch(root.sessions[root.sessionIndex].cmd);
        }
        function onError(error) {
            root.busy = false;
            root.setStatus("greetd: " + error, true);
        }
    }

    Process {
        id: saveUser
        command: ["sh", "-c", "printf '%s\\n' \"$1\" > /var/lib/greetd/latte-last-user; printf '%s\\n' \"$2\" > /var/lib/greetd/latte-last-session; { printf '%s\\n' \"$1\"; grep -vx \"$1\" /var/lib/greetd/latte-recent 2>/dev/null | head -1; } > /var/lib/greetd/latte-recent.new && mv -f /var/lib/greetd/latte-recent.new /var/lib/greetd/latte-recent", "sh", Greetd.user, root.sessions[root.sessionIndex].file]
    }
    Process { id: reboot; command: ["systemctl", "reboot"] }
    Process { id: poweroff; command: ["systemctl", "poweroff"] }

    Timer { id: passwordFocus; interval: 50; onTriggered: root.focusPassword() }
    signal focusPassword()

    // ── kvapka: kruh, ktorý sa plynulo zlieva s rovnou hranou (konkávne prechody) ──
    // edgeY: hrana (y), dir: -1 kvapka nad hranou (vyrastá hore), 1 pod ňou; fil: veľkosť prechodu
    function gooBlob(c, cx, cy, r, edgeY, dir, fil) {
        c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.fill();
        const d = Math.abs(cy - edgeY);
        if (d > r + fil * 0.6) return;                   // príliš ďaleko: bez mosta
        const w = Math.sqrt(Math.max(0, r * r - Math.pow(Math.min(d, r * 0.95), 2))) + fil;
        c.beginPath();
        c.moveTo(cx - w - fil, edgeY);
        c.quadraticCurveTo(cx - w * 0.55, edgeY, cx - r * 0.8, cy + dir * r * 0.55);
        c.lineTo(cx + r * 0.8, cy + dir * r * 0.55);
        c.quadraticCurveTo(cx + w * 0.55, edgeY, cx + w + fil, edgeY);
        c.closePath(); c.fill();
    }

    // ── obrazovka (na každom monitore) ────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "latte-greeter"
            color: root.conf.color || root.cBg

            Image {
                anchors.fill: parent
                visible: root.conf.background !== ""
                source: root.conf.background !== "" ? "file://" + root.conf.background : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: false          // pixman/software: lacnejšie škálovanie
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0.07, 0.05, 0.04, parseFloat(root.conf.dim) || 0) }
            // klik mimo ponuky relácií ju zavrie
            MouseArea { anchors.fill: parent; enabled: root.sessionsOpen; onClicked: root.sessionsOpen = false }

            // ── mláka kávy pri spodnom okraji: z nej vystupujú kvapky Reštartovať a Vypnúť ──
            readonly property real puddleTop: height - 26
            Canvas {
                id: puddle
                anchors.fill: parent
                onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d"); c.reset();
                    const W = width, Y = win.puddleTop;
                    c.fillStyle = root.cCoffee; c.globalAlpha = 0.94;
                    // vlnitá hladina celou šírkou
                    c.beginPath(); c.moveTo(0, height); c.lineTo(0, Y + 8);
                    for (let x = 0; x <= W; x += 40) c.lineTo(x, Y + 5 * Math.sin(x / 170) + 3 * Math.sin(x / 61));
                    c.lineTo(W, height); c.closePath(); c.fill();
                    // kvapky napájania vpravo (Reštartovať, Vypnúť)
                    root.gooBlob(c, W - 150, Y - 30, 25, Y + 4, 1, 18);
                    root.gooBlob(c, W - 76, Y - 34, 29, Y + 4, 1, 20);
                }
            }
            Repeater {
                model: [{ x: -150, y: -30, r: 25, label: i18n.tr("Restart"), glyph: "⟳", proc: reboot },
                        { x: -76, y: -34, r: 29, label: i18n.tr("Shut down"), glyph: "⏻", proc: poweroff }]
                Item {
                    required property var modelData
                    x: win.width + modelData.x - modelData.r; y: win.puddleTop + modelData.y - modelData.r
                    width: modelData.r * 2; height: modelData.r * 2
                    Text { anchors.centerIn: parent; text: parent.modelData.glyph; color: pm.containsMouse ? root.cAccent : root.cText
                           font { family: root.fUi; pixelSize: parent.modelData.r * 0.9; weight: Font.Bold } }
                    Text { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 6 } visible: pm.containsMouse
                           text: parent.modelData.label; color: root.cText; font { family: root.fUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: parent.modelData.proc.running = true }
                }
            }
            // režim a dôvod (vľavo dole, v mláke)
            Text {
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.bottom; verticalCenterOffset: -12 }
                width: win.width * 0.5; elide: Text.ElideRight
                color: root.cDim; opacity: 0.9
                font { family: root.fUi; pixelSize: 12 }
                text: i18n.tr("Mode {mode}", { mode: root.mode.toUpperCase() }) + " · " + root.renderer + (root.reason !== "" ? " — " + root.reason : "")
            }

            // ── ľavý panel: posledný pád (vývojárska verzia), novinky, počasie alebo text ──
            Rectangle {
                id: sidePanel
                visible: root.panelVisible && win.width >= 1100
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 28; bottomMargin: 84 }
                width: Math.min(500, win.width * 0.28)
                radius: 26; color: root.cGlass; border { color: root.cOutline; width: 1 }
                clip: true
                readonly property bool isLog: root.conf.panel === "log"
                readonly property bool isFeed: root.conf.panel === "rss" || root.conf.panel === "pocasie"
                Column {
                    anchors { fill: parent; margins: 22 }
                    spacing: 10
                    Text {
                        text: sidePanel.isLog ? i18n.tr("Last crash") : (root.conf.panel === "rss" ? (root.conf.panel_title || i18n.tr("News")) : (root.conf.panel === "pocasie" ? i18n.tr("Weather") + " · " + root.conf.place : (root.conf.panel_title || i18n.tr("Message"))))
                        color: root.cText; font { family: root.fDisplay; pixelSize: 21; weight: Font.DemiBold }
                    }
                    Text {
                        visible: sidePanel.isLog || sidePanel.isFeed
                        text: sidePanel.isFeed ? (root.conf.panel === "rss" ? root.conf.rss_url.replace(/^https?:\/\//, "").split("/")[0] : i18n.tr("Open-Meteo · updated every 15 min")) : root.crashLog === "" ? i18n.tr("No crash recorded. ☕") : i18n.tr("Developer build · /var/lib/latteos/greeter/last-crash.log")
                        color: root.cDim; font { family: root.fUi; pixelSize: 12 }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.cOutline }
                    Repeater {
                        model: root.conf.panel === "rss" ? root.news : []
                        Text { required property string modelData; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                               text: "•  " + modelData; color: root.cText; font { family: root.fUi; pixelSize: 14 } }
                    }
                    Column {
                        visible: root.conf.panel === "pocasie" && !!root.weather && !!root.weather.current
                        width: parent.width; spacing: 10
                        Row {
                            spacing: 14
                            Text { text: root.weather && root.weather.current ? root.wmo(root.weather.current.weather_code)[1] : ""; color: root.cAccent; font { pixelSize: 52 } }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: root.weather && root.weather.current ? Math.round(root.weather.current.temperature_2m) + " °C" : ""; color: root.cText; font { family: root.fDisplay; pixelSize: 38; weight: Font.DemiBold } }
                                Text { text: root.weather && root.weather.current ? root.wmo(root.weather.current.weather_code)[0] + " · " + i18n.tr("wind {v} km/h", { v: Math.round(root.weather.current.wind_speed_10m) }) : ""; color: root.cDim; font { family: root.fUi; pixelSize: 13 } }
                            }
                        }
                        Repeater {
                            model: root.weather && root.weather.daily ? root.weather.daily.time.slice(1) : []
                            Row {
                                required property string modelData
                                required property int index
                                spacing: 12
                                readonly property int i: index + 1
                                Text { width: 90; text: Qt.locale(root.localeName).toString(new Date(modelData + "T12:00:00"), "dddd"); color: root.cDim; font { family: root.fUi; pixelSize: 14 } }
                                Text { width: 30; text: root.wmo(root.weather.daily.weather_code[i])[1]; color: root.cAccent; font { pixelSize: 16 } }
                                Text { text: Math.round(root.weather.daily.temperature_2m_min[i]) + "° / " + Math.round(root.weather.daily.temperature_2m_max[i]) + "°"; color: root.cText; font { family: root.fUi; pixelSize: 14 } }
                            }
                        }
                    }
                    Text { visible: sidePanel.isFeed && root.netNote !== ""; width: parent.width; wrapMode: Text.WordWrap; text: root.netNote; color: root.cDim; font { family: root.fUi; pixelSize: 13 } }
                    Text {
                        visible: !sidePanel.isFeed
                        width: parent.width
                        height: sidePanel.height - 110
                        wrapMode: sidePanel.isLog ? Text.WrapAnywhere : Text.WordWrap
                        elide: Text.ElideRight
                        text: sidePanel.isLog ? root.crashLog : root.conf.panel_text
                        color: sidePanel.isLog ? root.cDim : root.cText
                        font { family: sidePanel.isLog ? "monospace" : root.fUi; pixelSize: sidePanel.isLog ? 11 : 14 }
                        textFormat: Text.PlainText
                    }
                }
            }

            // ── hodiny a dátum ──
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.08
                spacing: 0
                Text {
                    id: clock
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.cText
                    font { family: root.fDisplay; pixelSize: Math.min(win.height * 0.12, 116); weight: Font.Bold }
                    text: Qt.formatTime(new Date(), "HH:mm")
                }
                Text {
                    id: date
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.cDim
                    font { family: root.fUi; pixelSize: 18; weight: Font.DemiBold }
                    text: root.dateText(new Date())
                }
                Timer {
                    interval: 10000; running: true; repeat: true
                    onTriggered: { clock.text = Qt.formatTime(new Date(), "HH:mm"); date.text = root.dateText(new Date()); }
                }
            }

            // ── prihlásenie: kvapka v strede, účty sú guľaté kvapky na jej hornej hrane ──
            Item {
                id: drop
                width: Math.min(440, win.width - 32)
                height: edgeTop + 40 + body.height + 24
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: win.height * 0.07
                readonly property real edgeTop: 56            // hrana karty (pod kvapkami účtov)
                readonly property var avatars: root.otherUser ? [] : root.recentUsers
                readonly property real avR: 38

                Canvas {
                    id: dropShape
                    anchors.fill: parent
                    property var deps: [drop.width, drop.height, drop.avatars.length, root.user, root.otherUser]
                    onDepsChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        c.fillStyle = root.cGlass;
                        const t = drop.edgeTop, w = width, h = height, r = 34;
                        c.beginPath(); c.roundedRect(0, t, w, h - t, r, r); c.fill();
                        // kvapky účtov na hornej hrane (vybraný je väčší a vyšší)
                        const n = drop.avatars.length;
                        for (let i = 0; i < n; i++) {
                            const sel = drop.avatars[i] === root.user;
                            const cx = n === 1 ? w / 2 : w / 2 + (i === 0 ? -62 : 62);
                            const rr = sel ? drop.avR : drop.avR * 0.78;
                            root.gooBlob(c, cx, t - (sel ? 6 : -2), rr, t + 2, -1, 22);
                        }
                        // „Iný účet“: malá kvapka vpravo hore
                        root.gooBlob(c, w - 40, t - 2, 16, t + 2, -1, 12);
                    }
                }
                // obrázky / písmená účtov v kvapkách
                Repeater {
                    model: drop.avatars
                    Item {
                        required property string modelData
                        required property int index
                        readonly property bool sel: modelData === root.user
                        readonly property real rr: sel ? drop.avR : drop.avR * 0.78
                        readonly property real cx: drop.avatars.length === 1 ? drop.width / 2 : drop.width / 2 + (index === 0 ? -62 : 62)
                        x: cx - rr + 6; y: drop.edgeTop - (sel ? 6 : -2) - rr + 6
                        width: (rr - 6) * 2; height: width
                        Rectangle {
                            anchors.fill: parent; radius: width / 2; color: parent.sel ? root.cAccent : Qt.rgba(228 / 255, 178 / 255, 131 / 255, 0.35); clip: true
                            Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: modelData.charAt(0).toUpperCase(); color: root.cOnAccent
                                   font { family: root.fUi; pixelSize: parent.width * 0.42; weight: Font.ExtraBold } }
                            // obrázok účtu z Nastavení › Účet › Môj účet (/var/lib/latteos/greeter/avatars/<meno>.png)
                            Image { id: pic; anchors.fill: parent; source: "file:///var/lib/latteos/greeter/avatars/" + modelData + ".png"
                                    fillMode: Image.PreserveAspectCrop; smooth: false; asynchronous: true; sourceSize { width: 96; height: 96 } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.user = modelData; root.otherUser = false; root.focusPassword(); } }
                    }
                }
                // „Iný účet“
                Item {
                    x: drop.width - 56; y: drop.edgeTop - 18; width: 32; height: 32
                    Text { anchors.centerIn: parent; text: root.otherUser ? "×" : "+"; color: om.containsMouse ? root.cAccent : root.cText
                           font { family: root.fUi; pixelSize: 20; weight: Font.Bold } }
                    MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.otherUser = !root.otherUser; if (!root.otherUser) root.user = root.defaultUser(); else root.user = "";
                                             root.focusPassword(); } }
                }

                Column {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: drop.edgeTop + 40; leftMargin: 28; rightMargin: 28 }
                    spacing: 12

                    // meno vybraného účtu (alebo pole pre iný účet)
                    Text {
                        visible: !root.otherUser
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fullNames[root.user] || root.user || i18n.tr("No user")
                        color: root.cText; font { family: root.fDisplay; pixelSize: 24; weight: Font.DemiBold }
                    }
                    Rectangle {
                        visible: root.otherUser
                        width: parent.width; height: 46; radius: 23; color: root.cField
                        border { color: userInput.activeFocus ? root.cAccent : "transparent"; width: 1 }
                        TextInput {
                            id: userInput
                            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.cText; selectionColor: root.cAccent
                            font { family: root.fUi; pixelSize: 15 }
                            onTextChanged: if (root.otherUser) root.user = text.trim()
                            KeyNavigation.tab: passInput
                            onAccepted: passInput.forceActiveFocus()
                        }
                        Text { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                               visible: userInput.text === ""; text: i18n.tr("User name"); color: root.cDim; font { family: root.fUi; pixelSize: 15 } }
                    }

                    // heslo + oko + kvapka prihlásenia (→)
                    Item {
                        width: parent.width; height: 50
                        Rectangle {
                            id: passBox
                            anchors { left: parent.left; right: goBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            height: 46; radius: 23; color: root.cField
                            border { color: passInput.activeFocus ? root.cAccent : "transparent"; width: 1 }
                            TextInput {
                                id: passInput
                                anchors { fill: parent; leftMargin: 18; rightMargin: 46 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.cText; selectionColor: root.cAccent
                                echoMode: root.showPass ? TextInput.Normal : TextInput.Password; passwordCharacter: "•"
                                font { family: root.fUi; pixelSize: 15 }
                                focus: true
                                Keys.onPressed: (ev) => root.keyHint(ev)
                                enabled: !root.busy
                                KeyNavigation.tab: root.otherUser ? userInput : passInput
                                onAccepted: { root.login(root.user.trim(), text); text = ""; }
                                Component.onCompleted: forceActiveFocus()
                                Connections { target: root; function onFocusPassword() { passInput.forceActiveFocus(); } }
                            }
                            Text { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                   visible: passInput.text === ""; text: i18n.tr("Password"); color: root.cDim; font { family: root.fUi; pixelSize: 15 } }
                            // ukázať / skryť heslo (oko)
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                width: 34; height: 32; radius: 16
                                color: eyeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                Canvas {
                                    id: eye
                                    anchors.centerIn: parent; width: 22; height: 16
                                    property bool open: root.showPass
                                    onOpenChanged: requestPaint()
                                    onPaint: {
                                        const c = getContext("2d"); c.reset();
                                        c.strokeStyle = root.cDim; c.lineWidth = 1.6;
                                        c.beginPath(); c.moveTo(1, 8); c.quadraticCurveTo(11, -3, 21, 8); c.quadraticCurveTo(11, 19, 1, 8); c.stroke();
                                        c.beginPath(); c.arc(11, 8, 3, 0, Math.PI * 2); c.stroke();
                                        if (!open) { c.beginPath(); c.moveTo(3, 15); c.lineTo(19, 1); c.stroke(); }
                                    }
                                }
                                MouseArea { id: eyeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { root.showPass = !root.showPass; passInput.forceActiveFocus(); } }
                            }
                        }
                        // prihlásiť: okrúhla kvapka so šípkou
                        Rectangle {
                            id: goBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 50; height: 50; radius: 25
                            color: root.busy ? Qt.darker(root.cAccent, 1.4) : (gm.containsMouse ? Qt.lighter(root.cAccent, 1.08) : root.cAccent)
                            Text { anchors.centerIn: parent; text: root.busy ? "…" : "→"; color: root.cOnAccent; font { family: root.fUi; pixelSize: 22; weight: Font.ExtraBold } }
                            MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; enabled: !root.busy; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.login(root.user.trim(), passInput.text); passInput.text = ""; } }
                        }
                    }
                    // upozornenia pri hesle: Caps Lock zapnutý, Num Lock vypnutý
                    Row {
                        visible: root.capsOn || root.numOff
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Repeater {
                            model: (root.capsOn ? [["⇪", i18n.tr("Caps Lock is on")]] : []).concat(root.numOff ? [["⇭", i18n.tr("Num Lock is off")]] : [])
                            Rectangle {
                                required property var modelData
                                width: wr.implicitWidth + 22; height: 28; radius: 14
                                color: Qt.rgba(228 / 255, 178 / 255, 131 / 255, 0.18); border { color: root.cAccent; width: 1 }
                                Row {
                                    id: wr; anchors.centerIn: parent; spacing: 6
                                    Text { text: modelData[0]; color: root.cAccent; font { family: root.fUi; pixelSize: 14; weight: Font.Bold } }
                                    Text { text: modelData[1]; color: root.cText; font { family: root.fUi; pixelSize: 12; weight: Font.DemiBold } }
                                }
                            }
                        }
                    }
                    // relácia: jedna kvapka „LatteOS ▾“, klik rozleje zoznam
                    Rectangle {
                        id: sessPill
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, sl.implicitWidth + 44); height: 36; radius: 18
                        color: sm.containsMouse || root.sessionsOpen ? Qt.rgba(1, 1, 1, 0.08) : root.cField
                        Row {
                            id: sl; anchors.centerIn: parent; spacing: 8
                            Text { text: root.sessions[root.sessionIndex] ? root.sessions[root.sessionIndex].name : ""; color: root.cText; font { family: root.fUi; pixelSize: 13; weight: Font.Bold } }
                            Text { text: root.sessionsOpen ? "▴" : "▾"; color: root.cAccent; font { family: root.fUi; pixelSize: 13; weight: Font.Bold } }
                        }
                        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sessionsOpen = !root.sessionsOpen }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        visible: root.status !== ""
                        text: root.status
                        color: root.statusError ? root.cError : root.cDim
                        font { family: root.fUi; pixelSize: 13; weight: Font.Medium }
                    }
                    Item { width: 1; height: 2 }
                }
            }

            // ── zoznam relácií: vyteká pod kvapkou prihlásenia ──
            Rectangle {
                visible: root.sessionsOpen
                anchors { horizontalCenter: drop.horizontalCenter; top: drop.bottom; topMargin: -14 }
                // po spodok obrazovky; viac relácií (iné nainštalované prostredia) sa roluje kolieskom
                width: drop.width - 40; radius: 22
                height: Math.min(sessCol.implicitHeight + 16, parent.height - (drop.y + drop.height - 14) - 24)
                color: root.cGlass; border { color: root.cOutline; width: 1 }
                Flickable {
                    anchors { fill: parent; margins: 8 }
                    clip: true
                    contentHeight: sessCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: sessCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.sessions
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: sessCol.width; height: 52; radius: 16
                            color: root.sessionIndex === index ? Qt.rgba(228 / 255, 178 / 255, 131 / 255, 0.18) : (rm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                            Column {
                                anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: root.cText; font { family: root.fUi; pixelSize: 13; weight: Font.Bold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.comment; color: root.cDim; font { family: root.fUi; pixelSize: 11 } }
                            }
                            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.sessionIndex = index; root.sessionsOpen = false; root.focusPassword(); } }
                        }
                    }
                }
                }
            }
        }
    }
}
