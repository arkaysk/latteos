// LatteOS — výrez Kapsy (náčrt 24. 9.): jedna odložená vec v jamke kontajnera Kapsy na lište.
// Noctalia neprijíma súbory pretiahnuté z iných aplikácií, preto túto časť robí malá vrstva nad výrezom:
// pustený súbor sa uloží (~/.local/state/latteos/kapsa-vec), jeho ikona čiastočne zapadne do jamky
// a presahuje nad lištu. Klik = otvoriť, ťahanie = presunúť súbor ďalej (text/uri-list), pravý klik =
// vybrať z Kapsy. Nová vec posunie predošlú do histórie schránky (sloty Kapsy).
// Polohu výrezu zapisuje widget Kapsy (~/.local/state/latteos/kapsa-poloha: x y šírka výška).
// Pri celoobrazovkovom okne a v hernom režime je skrytá. Spúšťa: latte-app kapsavyrez (hyprland.lua).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "common"

ShellRoot {
    id: kv
    LatteTheme { id: theme }

    readonly property string state: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/latteos"
    property var pos: null                 // { x, y, w, h } výrezu v súradniciach monitora
    property string path: ""               // odložený súbor
    property string mime: ""
    property bool hidden
    property bool hovering: false
    readonly property int rise: 36         // o koľko ikona presahuje nad výrez

    FileView {
        path: kv.state + "/kapsa-poloha"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: {
            const p = text().trim().split(/\s+/).map(Number);
            kv.pos = p.length >= 4 && p.every(n => !isNaN(n)) ? { x: p[0], y: p[1], w: p[2], h: p[3] } : null;
        }
        onLoadFailed: kv.pos = null
    }
    FileView {
        id: vec
        path: kv.state + "/kapsa-vec"; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { kv.path = text().trim(); mimeProc.running = kv.path !== "" }
        onLoadFailed: kv.path = ""
    }
    Process {
        id: mimeProc
        command: ["file", "--mime-type", "-b", kv.path]
        stdout: StdioCollector { onStreamFinished: kv.mime = this.text.trim() }
    }
    Process { id: run }
    function sh(cmd, args) { run.command = ["sh", "-c", cmd, "sh"].concat(args || []); run.running = true; }

    function put(url) {
        const p = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
        if (p === "" || p === kv.path) return;
        // predošlá vec ide do histórie schránky (ako odkaz na súbor), nová sedí vo výreze
        sh('mkdir -p "$1"; [ -n "$3" ] && printf "file://%s\\n" "$3" | wl-copy -t text/uri-list; printf "%s\\n" "$2" > "$1/kapsa-vec"',
           [kv.state, p, kv.path]);
    }
    function clear() { sh('rm -f "$1/kapsa-vec"', [kv.state]); }

    // celá obrazovka / herný režim → skryť (optimalizácia 26. 9.: udalosti Hyprlandu a inotify namiesto sh + hyprctl
    // + grep + cat každé 2 s)
    property bool game: false
    FileView { path: kv.state + "/game-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: kv.game = text().trim() === "1"; onLoadFailed: kv.game = false }
    CelaObrazovka { id: cela }
    hidden: game || cela.active

    readonly property string iconName: {
        if (mime === "inode/directory") return "folder";
        if (mime === "") return "text-x-generic";
        return mime.replace("/", "-");
    }
    readonly property bool isImage: /^image\/(png|jpe?g|gif|webp|bmp|svg)/.test(mime)
    readonly property string fileName: path.split("/").pop()

    PanelWindow {
        visible: kv.pos !== null && !kv.hidden
        anchors { top: true; left: true }
        margins { left: kv.pos ? kv.pos.x - 8 : 0; top: kv.pos ? kv.pos.y - kv.rise : 0 }
        implicitWidth: kv.pos ? kv.pos.w + 16 : 60
        implicitHeight: kv.pos ? kv.pos.h + kv.rise : 56
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "latte-kapsa-vyrez"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        // vstup iba tam, kde niečo je: prázdna → jamka (cieľ pustenia), plná → ikona
        mask: Region { item: kv.path !== "" ? icon : hole }

        Item { id: hole; x: 8; y: kv.rise; width: kv.pos ? kv.pos.w : 44; height: kv.pos ? kv.pos.h : 26 }

        // zvýraznenie jamky pri ťahaní súboru nad ňou
        Rectangle {
            x: hole.x; y: hole.y; width: hole.width; height: hole.height; radius: 10
            color: drop.containsDrag ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.45) : "transparent"
            border { color: drop.containsDrag ? theme.primary : "transparent"; width: 2 }
        }

        Item {
            id: icon
            visible: kv.path !== ""
            width: 48; height: 52
            x: hole.x + (hole.width - width) / 2
            y: hole.y + hole.height - height - 3          // spodok ikony zapadne do jamky
            rotation: ma.pressed ? 0 : -8
            scale: kv.hovering ? 1.08 : 1
            Behavior on scale { NumberAnimation { duration: theme.animMs } }

            Image {
                anchors.fill: parent
                source: kv.isImage ? "file://" + kv.path : Quickshell.iconPath(kv.iconName, "text-x-generic")
                fillMode: kv.isImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit; asynchronous: true
                sourceSize { width: 80; height: 88 }
            }

            Drag.active: ma.drag.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
            Drag.mimeData: ({ "text/uri-list": "file://" + kv.path + "\r\n" })
            MouseArea {
                id: ma
                anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                drag.target: icon
                onEntered: kv.hovering = true
                onExited: kv.hovering = false
                onClicked: (m) => { if (m.button === Qt.RightButton) kv.clear(); else kv.sh('xdg-open "$1" >/dev/null 2>&1 &', [kv.path]); }
                onReleased: { icon.x = Qt.binding(() => hole.x + (hole.width - icon.width) / 2); icon.y = Qt.binding(() => hole.y + hole.height - icon.height - 3); }
            }
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (d) => { if (d.hasUrls && d.urls.length > 0) { kv.put(d.urls[0]); d.accept(Qt.CopyAction); } }
        }
    }
}
