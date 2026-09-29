// LatteOS — systémové ponuky ako vo Windows (alfatest 1). Beží na pozadí (rýchle otvorenie), otvára ich latte-ponuka:
//   zabezpecenie   Ctrl+Alt+Del: Zamknúť, Odhlásiť sa, Zmeniť heslo, Správca úloh; vpravo dole napájanie; Zrušiť
//   vypnut         Alt+F4 na prázdnej ploche: „Čo má počítač urobiť?“ s výberom a OK / Zrušiť
//   win-x          Win+X a pravý klik na dlaždicu aplikácií (ako pravý klik na Štart)
//   projekcia      Win+P: Iba obrazovka PC · Duplikovať · Rozšíriť · Iba druhá obrazovka (vpravo dole ako Windows)
//   rozlozenia     podržanie myši nad □ (Windows 11): malá ponuka rozložení pod kurzorom, zmizne po odchode myši
//   okno X Y ADR   pravý klik na titulok okna (hyprbars) a Alt+Medzerník: Obnoviť, Minimalizovať, Maximalizovať,
//                  rozloženia, navrchu, na plochu, Zavrieť
// Klik mimo alebo Esc ponuku zavrie. Nič sa nevypne bez potvrdenia (vypnutie / reštart cez dialóg alebo druhé kliknutie).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "common"

ShellRoot {
    id: pn
    LatteTheme { id: theme }

    property string kind: ""                 // "" = zavreté
    property real atX: 0
    property real atY: 0
    property string addr: ""
    property var win: null                   // stav okna z hyprctl (floating, fullscreen, pinned, workspace)
    property string user: Quickshell.env("USER") || ""
    property string choice: "shutdown"       // dialóg Vypnúť
    property string confirm: ""              // napájanie v Ctrl+Alt+Del: druhé kliknutie potvrdí
    property bool rel: false                 // atX/atY sú v súradniciach okna (vlastná hlavička aplikácie)
    readonly property bool anim: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0

    IpcHandler {
        target: "ponuka"
        function zabezpecenie(): void { pn.show("zabezpecenie", 0, 0, ""); }
        function vypnut(): void { pn.show("vypnut", 0, 0, ""); }
        function winx(x: int, y: int): void { pn.show("win-x", x, y, ""); }
        function okno(x: int, y: int, address: string): void { pn.show("okno", x, y, address); }
        function oknoRel(x: int, y: int): void { pn.rel = true; pn.show("okno", x, y, ""); }
        function rozlozenia(x: int, y: int, address: string): void { pn.flyAddr = address; pn.flyAt = Qt.point(x, y); pn.flyOn = true; flyLeave.restart(); }
        function zavri(): void { pn.kind = ""; }
        function projekcia(): void { monProc.running = true; }
    }
    function show(k, x, y, a) {
        confirm = ""; choice = "shutdown"; atX = x; atY = y; addr = a; win = null;
        if (k === "okno") { clients.running = true; return; }       // ponuka až so stavom okna
        kind = k;
    }
    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const l = JSON.parse(this.text);
                    let w = l.find(c => c.address === pn.addr);
                    if (!w) { const act = l.filter(c => c.focusHistoryID === 0); w = act[0]; }
                    if (!w) return;
                    pn.addr = w.address; pn.win = w;
                    if (pn.rel) { pn.atX += w.at[0]; pn.atY += w.at[1]; pn.rel = false; }
                    else if (!pn.atX && !pn.atY) { pn.atX = w.at[0] + 8; pn.atY = w.at[1] + 30; }   // Alt+Medzerník: pod titulok
                    pn.kind = "okno";
                    menu.open(pn.atX, pn.atY, pn.windowItems(), "");
                } catch (e) {}
            }
        }
    }
    // ── rozloženia nad □ (Windows 11): vlastná malá vrstva pri kurzore, bez fokusu klávesnice; klik mimo ide aplikáciám
    property bool flyOn: false
    property point flyAt: Qt.point(0, 0)
    property string flyAddr: ""
    readonly property var flyGroups: [
        [["lava", 0, 0, 0.5, 1], ["prava", 0.5, 0, 0.5, 1]],
        [["l23", 0, 0, 2/3, 1], ["p13", 2/3, 0, 1/3, 1]],
        [["l13", 0, 0, 1/3, 1], ["p23", 1/3, 0, 2/3, 1]],
        [["lh", 0, 0, 0.5, 0.5], ["ph", 0.5, 0, 0.5, 0.5], ["ld", 0, 0.5, 0.5, 0.5], ["pd", 0.5, 0.5, 0.5, 0.5]]]
    Timer { id: flyLeave; interval: 2500; onTriggered: if (!flyHover.hovered) pn.flyOn = false }
    PanelWindow {
        visible: pn.flyOn
        anchors { top: true; left: true }
        margins { left: Math.max(0, pn.flyAt.x - 250); top: pn.flyAt.y + 6 }
        implicitWidth: 2 * 104 + 10 + 24; implicitHeight: 2 * 56 + 10 + 24
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "latte-rozlozenia"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: 14
            color: theme.surface; border { color: theme.outline; width: 1 }
            HoverHandler { id: flyHover; onHoveredChanged: if (!hovered) flyLeave.restart() }
            Grid {
                x: 12; y: 12; columns: 2; spacing: 10
                Repeater {
                    model: pn.flyGroups
                    Item {
                        required property var modelData
                        width: 104; height: 56
                        Repeater {
                            model: parent.modelData
                            Rectangle {
                                required property var modelData
                                x: modelData[1] * 104 + 2; y: modelData[2] * 56 + 2; width: modelData[3] * 104 - 4; height: modelData[4] * 56 - 4; radius: 6
                                color: cm2.containsMouse ? theme.primary : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.14)
                                border { color: cm2.containsMouse ? theme.primary : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.25); width: 1 }
                                MouseArea { id: cm2; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { pn.flyOn = false; pn.hyprEval("latte.okno.rozlozenie('" + pn.flyAddr + "','" + parent.modelData[0] + "')"); } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Win+P: monitory (hyprctl monitors all), prvý = obrazovka PC (interný eDP alebo prvý v zozname) ─────────
    property var mons: []
    property string projMode: ""
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const l = JSON.parse(this.text);
                    l.sort((a, b) => (/^eDP/.test(b.name) ? 1 : 0) - (/^eDP/.test(a.name) ? 1 : 0) || a.id - b.id);
                    pn.mons = l;
                    const on = l.filter(m => !m.disabled);
                    pn.projMode = l.length < 2 ? "pc" : (on.length === 1 ? (on[0].name === l[0].name ? "pc" : "druha")
                                 : (on.some(m => m.mirrorOf && m.mirrorOf !== "none") ? "duplikovat" : "rozsirit"));
                } catch (e) { pn.mons = []; }
                pn.kind = "projekcia";
            }
        }
    }
    function project(mode) {
        const l = mons; if (l.length < 2) { kind = ""; return; }
        const pc = l[0].name, others = l.slice(1).map(m => m.name);
        const mon = (o, extra) => "hl.monitor({ output = \"" + o + "\", mode = \"preferred\", position = \"auto-right\", scale = 1" + (extra || "") + " }) ";
        let lua = "";
        if (mode === "pc") lua = mon(pc) + others.map(o => "hl.monitor({ output = \"" + o + "\", disabled = true }) ").join("");
        else if (mode === "druha") lua = others.map(o => mon(o)).join("") + "hl.monitor({ output = \"" + pc + "\", disabled = true }) ";
        else if (mode === "duplikovat") lua = mon(pc) + others.map(o => mon(o, ", mirror = \"" + pc + "\"")).join("");
        else lua = mon(pc) + others.map(o => mon(o)).join("");
        projMode = mode; kind = "";
        hyprEval(lua);
    }
    function sh(cmd) { runner.command = ["sh", "-c", cmd]; runner.startDetached(); }
    Process { id: runner }
    function hyprEval(lua) { runner.command = ["hyprctl", "eval", lua]; runner.startDetached(); }
    function session(a) { kind = ""; sh("noctalia msg session " + a); }

    // ── položky ─────────────────────────────────────────────────────────────────
    function winxItems() {
        const app = (n) => () => { pn.kind = ""; pn.sh("latte-app " + n); };
        return [
            { glyph: "apps", label: "Nainštalované aplikácie", action: app("aplikacie") },
            { glyph: "battery", label: "Možnosti napájania", action: app("nastavenia napajanie") },
            { glyph: "shield", label: "Systém", action: app("nastavenia system") },
            { glyph: "cpu", label: "Správca zariadení", action: app("zariadenia") },
            { glyph: "network", label: "Sieťové pripojenia", action: app("zariadenia siete") },
            { glyph: "database", label: "Disky", action: app("zariadenia disky") },
            { separator: true },
            { glyph: "terminal", label: "Terminál", action: () => { pn.kind = ""; pn.sh("latte-terminal"); } },
            { glyph: "terminal-2", label: "Terminál (správca)", action: () => { pn.kind = ""; pn.sh("latte-terminal sudo -i"); } },
            { glyph: "activity", label: "Správca úloh", hint: "Ctrl+Shift+Esc", action: app("monitor") },
            { glyph: "settings", label: "Nastavenia", hint: "Win+I", action: app("nastavenia") },
            { glyph: "folder", label: "Prieskumník súborov", hint: "Win+E", action: app("subory") },
            { glyph: "search", label: "Hľadať", hint: "Win+S", action: () => { pn.kind = ""; pn.sh("noctalia msg panel-open launcher"); } },
            { glyph: "player-play", label: "Spustiť", hint: "Win+R", action: () => { pn.kind = ""; pn.sh("noctalia msg panel-open launcher"); } },
            { separator: true },
            { glyph: "power", label: "Vypnúť alebo odhlásiť sa", sub: [
                { glyph: "logout", label: "Odhlásiť sa", action: () => pn.session("logout") },
                { glyph: "moon", label: "Uspať", action: () => pn.session("suspend") },
                { glyph: "power", label: "Vypnúť", action: () => pn.session("shutdown") },
                { glyph: "refresh", label: "Reštartovať", action: () => pn.session("reboot") }] },
            { glyph: "device-desktop", label: "Pracovná plocha", hint: "Win+D", action: () => { pn.kind = ""; pn.hyprEval("latte.keys.show_desktop()"); } },
        ];
    }
    function windowItems() {
        const w = pn.win || {}, a = pn.addr, max = w.fullscreen === 1, full = w.fullscreen === 2;
        const q = (lua) => () => { pn.kind = ""; pn.hyprEval(lua); };
        const lay = (z, label, glyph) => ({ glyph: glyph, label: label, action: q("latte.okno.rozlozenie('" + a + "','" + z + "')") });
        const desks = [];
        for (let i = 1; i <= 4; i++) desks.push({ label: "Plocha " + i, checked: w.workspace && w.workspace.id === i, action: q("latte.okno.na_plochu('" + a + "'," + i + ")") });
        desks.push({ glyph: "plus", label: "Nová plocha", action: q("latte.okno.na_plochu('" + a + "',0)") });
        return [
            { glyph: "arrows-minimize", label: "Obnoviť", enabled: max || full || !!w.latteSnapped, action: q("latte.okno.obnovit('" + a + "')") },
            { glyph: "minus", label: "Minimalizovať", action: q("latte.okno.minimalizovat('" + a + "')") },
            { glyph: "square", label: "Maximalizovať", enabled: !max, action: q("latte.okno.maximalizovat('" + a + "')") },
            { glyph: "layout-grid", label: "Rozloženie", sub: [
                lay("lava", "Ľavá polovica", "layout-sidebar"), lay("prava", "Pravá polovica", "layout-sidebar-right"),
                lay("lh", "Vľavo hore", "layout-grid"), lay("ph", "Vpravo hore", "layout-grid"),
                lay("ld", "Vľavo dole", "layout-grid"), lay("pd", "Vpravo dole", "layout-grid"),
                lay("l23", "Dve tretiny vľavo", "layout-columns"), lay("p13", "Tretina vpravo", "layout-columns"),
                lay("stred", "Na stred", "focus-centered")] },
            { label: "Vždy navrchu (na všetkých plochách)", checked: !!w.pinned, action: q("latte.okno.navrchu('" + a + "')") },
            { glyph: "stack-2", label: "Presunúť na plochu", sub: desks },
            { separator: true },
            { glyph: "x", label: "Zavrieť", hint: "Alt+F4", danger: true, action: q("latte.okno.zavriet('" + a + "')") },
        ];
    }
    // Win+X: nad dlaždicou aplikácií (lišta 56 px + okraj 10 px), ako ponuka nad tlačidlom Štart
    onKindChanged: if (kind === "win-x") { if (atY >= 9000) menu.openAbove(atX, layer.height - 72, winxItems(), ""); else menu.open(atX, atY, winxItems(), ""); }

    PanelWindow {
        id: layer
        visible: pn.kind !== ""
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "latte-ponuka"
        WlrLayershell.keyboardFocus: pn.kind !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: pn.kind === "zabezpecenie" ? Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.94)
             : pn.kind === "vypnut" ? Qt.rgba(0, 0, 0, 0.35) : "transparent"

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: pn.kind = ""
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: if (pn.kind !== "zabezpecenie") pn.kind = "" }

            // ── Ctrl+Alt+Del ──────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: pn.kind === "zabezpecenie"
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: pn.user; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } bottomPadding: 14 }
                    Repeater {
                        model: [
                            { t: "Zamknúť", a: () => pn.session("lock") },
                            { t: "Odhlásiť sa", a: () => pn.session("logout") },
                            { t: "Zmeniť heslo", a: () => { pn.kind = ""; pn.sh("latte-app nastavenia heslo"); } },
                            { t: "Správca úloh", a: () => { pn.kind = ""; pn.sh("latte-app monitor"); } }]
                        Rectangle {
                            required property var modelData
                            width: 300; height: 44; radius: 10
                            color: bm.containsMouse || activeFocus ? theme.hover : "transparent"
                            Text { anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                                   text: parent.modelData.t; color: theme.fg; font { family: theme.fontUi; pixelSize: 18; weight: Font.DemiBold } }
                            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: parent.modelData.a() }
                        }
                    }
                    Item { width: 1; height: 24 }
                    Rectangle {
                        width: 120; height: 40; radius: 10; color: cm.containsMouse ? theme.hover : theme.field
                        border { color: theme.outline; width: 1 }
                        Text { anchors.centerIn: parent; text: "Zrušiť"; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: pn.kind = "" }
                    }
                }
                // napájanie vpravo dole (druhé kliknutie potvrdí)
                Row {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
                    spacing: 8
                    Repeater {
                        model: [{ id: "suspend", g: "moon", t: "Uspať" }, { id: "reboot", g: "refresh", t: "Reštartovať" }, { id: "shutdown", g: "power", t: "Vypnúť" }]
                        Rectangle {
                            required property var modelData
                            readonly property bool armed: pn.confirm === modelData.id
                            width: row.implicitWidth + 24; height: 40; radius: 10
                            color: armed ? theme.error : (pm.containsMouse ? theme.hover : "transparent")
                            Row { id: row; anchors.centerIn: parent; spacing: 8
                                  Glyph { name: parent.parent.modelData.g; size: 18; color: parent.parent.armed ? "white" : theme.fg; anchors.verticalCenter: parent.verticalCenter }
                                  Text { text: parent.parent.armed ? "Naozaj? Klikni znova" : parent.parent.modelData.t; color: parent.parent.armed ? "white" : theme.fg
                                         font { family: theme.fontUi; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter } }
                            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { if (parent.armed) pn.session(parent.modelData.id); else pn.confirm = parent.modelData.id; } }
                        }
                    }
                }
            }

            // ── Alt+F4 na ploche: Vypnúť počítač ──────────────────────────────────
            Rectangle {
                visible: pn.kind === "vypnut"
                anchors.centerIn: parent
                width: 420; height: dcol.implicitHeight + 36; radius: 16
                color: theme.surface; border { color: theme.outline; width: 1 }
                MouseArea { anchors.fill: parent }                  // klik do dialógu ho nezavrie
                Keys.onReturnPressed: pn.session(pn.choice)
                Column {
                    id: dcol
                    x: 20; y: 18; width: parent.width - 40; spacing: 12
                    Row { spacing: 12
                          Glyph { name: "power"; size: 26; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                          Text { text: "Vypnúť LatteOS"; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold }
                                 anchors.verticalCenter: parent.verticalCenter } }
                    Text { text: "Čo má počítač urobiť?"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                    Column {
                        width: parent.width; spacing: 2
                        Repeater {
                            model: [{ id: "lock", t: "Zamknúť" }, { id: "logout", t: "Odhlásiť sa" }, { id: "suspend", t: "Uspať" },
                                    { id: "shutdown", t: "Vypnúť" }, { id: "reboot", t: "Reštartovať" }]
                            Rectangle {
                                required property var modelData
                                width: parent.width; height: 34; radius: 8
                                color: pn.choice === modelData.id ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.22) : (om.containsMouse ? theme.hover : "transparent")
                                Row { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } spacing: 10
                                      Rectangle { width: 14; height: 14; radius: 7; anchors.verticalCenter: parent.verticalCenter; color: "transparent"
                                                  border { color: theme.primary; width: 2 }
                                                  Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: theme.primary; visible: pn.choice === parent.parent.parent.modelData.id } }
                                      Text { text: parent.parent.modelData.t; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 } } }
                                MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; onClicked: pn.choice = parent.modelData.id
                                            onDoubleClicked: pn.session(parent.modelData.id) }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; spacing: 8
                        Repeater {
                            model: [{ t: "OK", ok: true }, { t: "Zrušiť", ok: false }]
                            Rectangle {
                                required property var modelData
                                width: 96; height: 36; radius: 10
                                color: modelData.ok ? theme.primary : (km.containsMouse ? theme.hover : theme.field)
                                Text { anchors.centerIn: parent; text: parent.modelData.t; color: parent.modelData.ok ? theme.fgOnPrimary : theme.fg
                                       font { family: theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                                MouseArea { id: km; anchors.fill: parent; hoverEnabled: true; onClicked: parent.modelData.ok ? pn.session(pn.choice) : pn.kind = "" }
                            }
                        }
                    }
                }
            }

            // ── Win+P ─────────────────────────────────────────────────────────────
            Rectangle {
                visible: pn.kind === "projekcia"
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 76 }
                width: 300; height: pcol.implicitHeight + 28; radius: 16
                color: theme.surface; border { color: theme.outline; width: 1 }
                MouseArea { anchors.fill: parent }
                Column {
                    id: pcol
                    x: 14; y: 14; width: parent.width - 28; spacing: 6
                    Text { text: "Premietanie"; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 18; weight: Font.DemiBold } bottomPadding: 4 }
                    Repeater {
                        model: [["pc", "Iba obrazovka PC", "device-laptop"], ["duplikovat", "Duplikovať", "copy"], ["rozsirit", "Rozšíriť", "columns-2"], ["druha", "Iba druhá obrazovka", "device-desktop"]]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: pn.projMode === modelData[0]
                            readonly property bool usable: pn.mons.length > 1 || modelData[0] === "pc"
                            width: parent.width; height: 44; radius: 10; opacity: usable ? 1 : 0.4
                            color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.20) : (prm.containsMouse && usable ? theme.hover : "transparent")
                            border { color: on ? theme.primary : "transparent"; width: 1.5 }
                            Row { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } spacing: 12
                                  Glyph { name: parent.parent.modelData[2]; size: 20; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                  Text { text: parent.parent.modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 14; weight: Font.DemiBold } anchors.verticalCenter: parent.verticalCenter } }
                            MouseArea { id: prm; anchors.fill: parent; hoverEnabled: true; onClicked: if (parent.usable) pn.project(parent.modelData[0]) }
                        }
                    }
                    Text { visible: pn.mons.length < 2; width: parent.width; wrapMode: Text.WordWrap; topPadding: 4
                           text: "Pripojená je iba jedna obrazovka."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    Text { width: parent.width; wrapMode: Text.WordWrap; topPadding: 2; text: "Rozloženie a rozlíšenie: Správca zariadení › Obrazovky"
                           color: theme.primary; font { family: theme.fontUi; pixelSize: 12; underline: plm.containsMouse }
                           MouseArea { id: plm; anchors.fill: parent; hoverEnabled: true; onClicked: { pn.kind = ""; pn.sh("latte-app zariadenia obrazovky"); } } }
                }
            }

            ContextMenu {
                id: menu
                theme: theme
                onVisibleChanged: if (!visible && (pn.kind === "win-x" || pn.kind === "okno")) pn.kind = ""
            }
        }
    }
}
