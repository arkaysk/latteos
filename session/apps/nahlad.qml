// LatteOS — živý náhľad okna nad oválom okien na lište (zadanie 24. 9., bod 3): keď myš podrží ikonu okna,
// widget latteos/okna zapíše jeho adresu do ~/.local/state/latteos/nahlad a tu sa nad kurzorom ukáže
// živý obraz okna (ScreencopyView cez Hyprland toplevel export) s názvom. Klik na náhľad prepne na okno.
// Pri softvérovom kreslení sa obraz obnovuje iba 4× za sekundu (šetrí CPU). Spúšťa: latte-app nahlad.
// Navyše náhľad prichytenia okna (alfatest 1, ako Windows): pri ťahaní okna k okraju ukáže priehľadný obdĺžnik
// cieľa (hore = celá obrazovka, bok = polovica, roh = štvrtina). Volá latte/prichytenie.lua cez IPC „prichytenie“.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "common"

ShellRoot {
    id: nh
    LatteTheme { id: theme }

    readonly property string state: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/latteos"
    readonly property bool cheap: ["softver", "safe", "minimalny"].includes(Quickshell.env("LATTE_TIER") || "softver")
    property string addr: ""
    property int cx: 0
    property var top: null                      // HyprlandToplevel
    property bool overPreview: false

    FileView {
        path: nh.state + "/nahlad"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: nh.want(text().trim())
        onLoadFailed: nh.want("")
    }
    // krátke oneskorenie: náhľad až po zastavení myši nad ikonou, zmiznutie až po odchode aj z náhľadu
    Timer { id: showT; interval: 350; onTriggered: { Hyprland.refreshToplevels(); pos.running = true; } }
    Timer { id: hideT; interval: 250; onTriggered: if (!nh.overPreview) nh.addr = "" }
    property string pending: ""
    function want(a) {
        pending = a.replace(/^0x/, "");
        if (pending !== "") { hideT.stop(); showT.restart(); } else { showT.stop(); hideT.restart(); }
    }
    Process {
        id: pos
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/(-?\d+),\s*(-?\d+)/);
                if (m) nh.cx = parseInt(m[1]);
                nh.addr = nh.pending;
            }
        }
    }
    onAddrChanged: top = addr === "" ? null : (Hyprland.toplevels.values.find(t => t.address === addr || t.address === "0x" + addr) || null)

    PanelWindow {
        id: win
        visible: nh.top !== null && nh.top.wayland !== null
        anchors { bottom: true; left: true }
        margins { bottom: 74; left: Math.max(8, nh.cx - width / 2) }
        implicitWidth: 300; implicitHeight: 210
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top               // pod panelmi Noctalie (ponuka okna ho prekryje)
        WlrLayershell.namespace: "latte-nahlad"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        Rectangle {
            anchors.fill: parent; radius: 16
            color: theme.surface; border { color: theme.outline; width: 1 }
            Column {
                anchors { fill: parent; margins: 10 }
                spacing: 8
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: nh.top ? nh.top.title : ""
                    color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                ScreencopyView {
                    id: shot
                    width: parent.width; height: parent.height - 26
                    captureSource: win.visible && nh.top ? nh.top.wayland : null
                    live: !nh.cheap
                    constraintSize: Qt.size(width, height)
                    Timer { interval: 250; repeat: true; running: nh.cheap && win.visible; onTriggered: shot.captureFrame() }
                    Text { anchors.centerIn: parent; visible: !shot.hasContent; text: "…"; color: theme.fgDim; font.pixelSize: 20 }
                }
            }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                onEntered: { nh.overPreview = true; hideT.stop(); }
                onExited: { nh.overPreview = false; hideT.restart(); }
                onClicked: { act.command = ["hyprctl", "eval", 'latte.win.activate("0x' + nh.addr + '")']; act.running = true; nh.addr = ""; }
            }
        }
    }
    Process { id: act }

    // ── náhľad prichytenia okna ─────────────────────────────────────────────────────
    property var snapRect: null                  // { x, y, w, h } v globálnych súradniciach, null = skryté
    // lišta rozložení (Windows 11) — rovnaké čísla ako P.BAR a P.GROUPS v latte/prichytenie.lua
    property bool barOn: false
    property point barAt: Qt.point(0, 0)
    property string barZone: ""
    readonly property var barGroups: [
        [["lava", 0, 0, 0.5, 1], ["prava", 0.5, 0, 0.5, 1]],
        [["l23", 0, 0, 2/3, 1], ["p13", 2/3, 0, 1/3, 1]],
        [["l13", 0, 0, 1/3, 1], ["p23", 1/3, 0, 2/3, 1]],
        [["lh", 0, 0, 0.5, 0.5], ["ph", 0.5, 0, 0.5, 0.5], ["ld", 0, 0.5, 0.5, 0.5], ["pd", 0.5, 0.5, 0.5, 0.5]]]
    IpcHandler {
        target: "prichytenie"
        function ukaz(x: int, y: int, w: int, h: int): void { nh.snapRect = { x: x, y: y, w: w, h: h }; }
        function skry(): void { nh.snapRect = null; }
        function lista(x: int, y: int, zone: string): void { nh.barAt = Qt.point(x, y); nh.barZone = zone === "-" ? "" : zone; nh.barOn = true; }
        function listaSkry(): void { nh.barOn = false; }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: sw
            required property var modelData
            screen: modelData
            readonly property var r: nh.snapRect
            readonly property bool here: !!r && r.x < modelData.x + modelData.width && r.x + r.w > modelData.x
                                         && r.y < modelData.y + modelData.height && r.y + r.h > modelData.y
            readonly property bool barHere: nh.barOn && nh.barAt.x >= modelData.x && nh.barAt.x < modelData.x + modelData.width
            visible: here || box.opacity > 0.01 || barHere
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "latte-prichytenie"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}                      // kliknutia a ťahanie idú ďalej
            color: "transparent"
            Rectangle {
                id: box
                // pri skrytí ostane na poslednom mieste a iba zmizne
                property var last: ({ x: 0, y: 0, w: 0, h: 0 })
                readonly property var g: sw.here ? sw.r : last
                onGChanged: if (sw.here) last = sw.r
                x: g.x - sw.modelData.x; y: g.y - sw.modelData.y; width: g.w; height: g.h
                radius: 14
                color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.18)
                border { color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.85); width: 2 }
                opacity: sw.here ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: nh.cheap ? 0 : 120 } }
                Behavior on x { enabled: !nh.cheap && sw.here; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !nh.cheap && sw.here; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !nh.cheap && sw.here; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !nh.cheap && sw.here; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            // lišta rozložení (Windows 11): skupiny s políčkami, políčko pod kurzorom zvýraznené
            Rectangle {
                visible: sw.barHere
                x: nh.barAt.x - sw.modelData.x; y: nh.barAt.y - sw.modelData.y
                width: 4 * 104 + 3 * 10 + 24; height: 80; radius: 18
                color: Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.96)
                border { color: theme.outline; width: 1 }
                Repeater {
                    model: nh.barGroups
                    Item {
                        required property var modelData
                        required property int index
                        x: 12 + index * (104 + 10); y: (80 - 56) / 2; width: 104; height: 56
                        Repeater {
                            model: parent.modelData
                            Rectangle {
                                required property var modelData
                                readonly property bool hot: nh.barZone === modelData[0]
                                x: modelData[1] * 104 + 2; y: modelData[2] * 56 + 2; width: modelData[3] * 104 - 4; height: modelData[4] * 56 - 4; radius: 6
                                color: hot ? theme.primary : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.14)
                                border { color: hot ? theme.primary : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.25); width: 1 }
                            }
                        }
                    }
                }
            }
        }
    }
}
