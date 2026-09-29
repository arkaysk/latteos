// LatteOS — znak NET pre cudzie okná (zadanie 24. 9.: „NET nezobrazený, kým aplikácia nepristúpi k internetu“).
// Aplikácie LatteOS majú NET vo vlastnej hlavičke (HeaderBar). Pre ostatné okná kreslí tento proces malý znak
// nad aktívnym oknom: v titulku kompozitora (hyprbars) naľavo od – □ ✕, pri oknách s vlastnou hlavičkou
// (GTK, Firefox, Electron…) ako prilepený jazýček nad horným okrajom okna. Znak sa ukáže, až keď proces
// okna alebo jeho potomkovia majú spojenie mimo lo (latte-net used PID); vypnutý NET ostáva viditeľný.
// Klik prepne NET aplikácie (latte-net on/off podľa triedy okna — platí hneď cez latte-netd).
// Spúšťa: latte-app netznak (hyprland.lua pri štarte).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "common"

ShellRoot {
    id: nz
    LatteTheme { id: theme }

    // triedy okien s vlastnou hlavičkou: jediný zdroj je latte/bars.lua (Lua vzor → JS regex)
    property var ownRe: /^org\.quickshell$/
    FileView {
        path: "/usr/share/latteos/hypr/latte/bars.lua"; printErrors: false
        onLoaded: {
            const m = text().match(/B\.own_titlebar = ([\s\S]*?)\n\s*\n/);
            if (!m) return;
            const src = (m[1].match(/"([^"]*)"/g) || []).map(s => s.slice(1, -1)).join("").replace(/%(\W)/g, "\\$1");
            try { nz.ownRe = new RegExp(src); } catch (e) {}
        }
    }

    property var win: null              // aktívne okno z hyprctl
    property var mon: ({ x: 0, y: 0 })
    property var used: ({})             // adresa okna → aplikácia už použila sieť (zostáva)
    property var off: ({})              // trieda → NET vypnutý
    readonly property string cls: win ? (win["class"] || "") : ""
    readonly property bool own: cls !== "" && ownRe.test(cls)
    readonly property bool isLatte: cls === "org.quickshell"
    readonly property bool netUsed: win ? used[win.address] === true : false
    readonly property bool netOff: off[cls] === true
    readonly property bool shown: win !== null && !isLatte && win.fullscreen !== 2 && (netUsed || netOff)

    Process {
        id: q
        command: ["sh", "-c", "hyprctl -j activewindow; echo '@@'; hyprctl -j monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("@@");
                let w = null, ms = [];
                try { w = JSON.parse(parts[0]); } catch (e) {}
                try { ms = JSON.parse(parts[1]); } catch (e) {}
                if (!w || !w.address || !w.mapped || w.hidden || (w.workspace && w.workspace.id < 0)) { nz.win = null; return; }
                const m = ms.find(x => x.id === w.monitor) || ms[0];
                if (m) nz.mon = { x: m.x, y: m.y };
                const changed = !nz.win || nz.win.address !== w.address;
                nz.win = w;
                if (changed) { nz.checkNet(); nz.checkOff(); }
            }
        }
    }
    // udalosti Hyprlandu nižšie pokrývajú zmenu okna; polling je iba záloha na zmenu veľkosti okna — častý (1 s) iba vtedy,
    // keď je znak vidieť (optimalizácia 26. 9.: predtým každú sekundu sh + 2× hyprctl)
    Timer { interval: nz.shown ? 1000 : 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!q.running) q.running = true }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (/^(activewindowv2|movewindowv2|changefloatingmode|fullscreen|workspacev2|closewindow|openwindow)$/.test(ev.name) && !q.running) q.running = true;
        }
    }

    // sieť: raz za 3 s pre aktívne okno, kým ju nepoužije
    Process {
        id: probe
        property string addr: ""
        stdout: StdioCollector {
            onStreamFinished: if (this.text.trim() === "1" && probe.addr !== "") { const u = Object.assign({}, nz.used); u[probe.addr] = true; nz.used = u; }
        }
    }
    function checkNet() {
        if (!win || isLatte || netUsed || probe.running || !(win.pid > 0)) return;
        probe.addr = win.address;
        probe.command = ["latte-net", "used", String(win.pid)];
        probe.running = true;
    }
    Timer { interval: 5000; repeat: true; running: nz.win !== null && !nz.netUsed && !nz.isLatte; onTriggered: nz.checkNet() }

    Process {
        id: status
        property string c: ""
        stdout: StdioCollector { onStreamFinished: { const o = Object.assign({}, nz.off); o[status.c] = this.text.trim() === "off"; nz.off = o; } }
    }
    function checkOff() {
        if (cls === "" || isLatte || status.running) return;
        status.c = cls; status.command = ["latte-net", "status", cls]; status.running = true;
    }
    Process {
        id: toggle
        property bool turnOff: false
        onExited: (code) => {
            if (code === 0) { const o = Object.assign({}, nz.off); o[nz.cls] = turnOff; nz.off = o; }   // znak sa prefarbí hneď
            nz.checkOff();
            tell.command = code === 0
                ? ["notify-send", "-a", "LatteOS", "-i", turnOff ? "network-offline" : "network-wired",
                   (turnOff ? "Internet zablokovaný: " : "Internet povolený: ") + nz.cls,
                   turnOff ? "Platí hneď, otvorené spojenia sa ukončili." : "Platí hneď, aplikácia sa môže znova pripojiť."]
                : ["notify-send", "-a", "LatteOS", "-u", "critical", "NET sa nedá prepnúť: " + nz.cls, "Aplikácia sa nenašla medzi spúšťačmi (.desktop)."];
            tell.running = true;
        }
    }
    Process { id: tell }

    // poloha znaku (logické súradnice monitora)
    readonly property int pillW: 58
    readonly property int pillH: 20
    readonly property bool outside: own && win !== null && (win.at[1] - mon.y) >= pillH + 4       // jazýček nad oknom, ak je miesto
    // hyprbars: okraj 12 + tri tlačidlá 17 px s medzerou 8 → ~79 px sprava, znak ešte 10 px vľavo
    readonly property int px: win ? (own ? win.at[0] + win.size[0] - pillW - 16 : win.at[0] + win.size[0] - 89 - pillW) - mon.x : 0
    readonly property int py: win ? (own ? (outside ? win.at[1] - pillH : win.at[1] + 2) : win.at[1] - 25) - mon.y : 0      // titulok hyprbars (30 px) leží nad geometriou okna

    PanelWindow {
        visible: nz.shown
        anchors { top: true; left: true }
        margins { left: Math.max(0, nz.px); top: Math.max(0, nz.py) }
        implicitWidth: nz.pillW; implicitHeight: nz.pillH
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "latte-netznak"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: nz.outside ? 0 : height / 2
            topLeftRadius: 9; topRightRadius: 9
            bottomLeftRadius: nz.outside ? 0 : height / 2; bottomRightRadius: nz.outside ? 0 : height / 2
            color: ma.containsMouse ? theme.hover : theme.surfaceVariant
            border { color: nz.netOff ? theme.netOffColor : Qt.rgba(theme.netOnColor.r, theme.netOnColor.g, theme.netOnColor.b, 0.6); width: 1 }
            Row {
                anchors.centerIn: parent; spacing: 5
                Rectangle {         // zapnutý: zelené plné koliesko; vypnutý: červené prázdne
                    width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                    color: nz.netOff ? "transparent" : theme.netOnColor
                    border { color: nz.netOff ? theme.netOffColor : theme.netOnColor; width: nz.netOff ? 1.5 : 0 }
                }
                Text { text: "NET"; color: theme.fg; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
            }
            MouseArea {
                id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    toggle.turnOff = !nz.netOff;
                    toggle.command = ["latte-net", toggle.turnOff ? "off" : "on", nz.cls];
                    toggle.running = true;
                }
            }
        }
    }
}
