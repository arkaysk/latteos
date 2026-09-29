// TileOverlay — textúra ostrova na lište pre GIF / obrázok (zadanie 25. 9.): Noctalia v dlaždici kreslí iba svoje textúry
// (para, matrix, farba), preto GIF nad ostrov dokreslí táto vrstva. Ukazuje presne ten výsek spoločného plátna, ktorý
// je v okne v tvare L pätou, takže po otvorení okna obraz plynule pokračuje do kmeňa. Bez ikony v strede (zadanie
// 25. 9. večer): ostrov je iba pekne orámovaný a ten istý rám pri otvorení okna prejde plynulo na celý tvar L (LPopup).
// Kliknutia prepúšťa (prázdna maska) na dlaždicu Noctalie pod ňou. GIF je jeden (image) a zdieľa ho aj LPopup.
//   hrá: pohyb „vždy“ (bar-anim) alebo keď je okno otvorené; v hernom režime stojí a vrstva sa skryje.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: to
    required property var theme
    property var foot: ({ x: 12, y: 896, w: 100, h: 42 })
    property string spec: "para"
    property string motion: "vzdy"          // vzdy | vypnute (z bar-anim)
    property bool popupOpen: false
    property bool mirror: false
    property real footRadius: 16
    // spoločné plátno okna L (rovnaké čísla ako LPopup: ox/oy výseku päty, rozmer plátna)
    property real canvasW: 660
    property real canvasH: 100
    property real ox: 0
    property real oy: 50
    readonly property bool isFile: spec.startsWith("file:")
    // spoločný zdroj GIF (snímky, ohnisko pohybu, voľba priblíženia) — ten istý aj v náhľade Nastavení
    GifZdroj { id: zdroj; spec: to.spec; playing: !to.game && (to.motion === "vzdy" || to.popupOpen) }
    readonly property alias image: zdroj.image
    readonly property alias frameDir: zdroj.frameDir
    readonly property alias frameCount: zdroj.frameCount
    readonly property alias frame: zdroj.frame
    readonly property alias ohnisko: zdroj.ohnisko
    property bool game: false
    FileView { path: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/latteos/game-mode"
               printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: to.game = text().trim() === "1"; onLoadFailed: to.game = false }

    PanelWindow {
        visible: to.isFile && !to.game && to.foot.w > 0
        anchors { top: true; left: true }
        margins { left: to.foot.x; top: to.foot.y }
        implicitWidth: to.foot.w; implicitHeight: to.foot.h
        exclusionMode: ExclusionMode.Ignore
        // nad lištou vždy: v rovnakej úrovni (Top) by záležalo na poradí štartu — po prihlásení vznikla skôr ako lišta
        // Noctalie a lišta ju prekryla (26. 9. ráno GIF v koreni zmizol)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "latte-dlazdica"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}                      // kliknutie prejde na dlaždicu Noctalie
        color: "transparent"
        Scena {
            anchors.fill: parent
            colors: to.theme; spec: to.spec; image: zdroj.image; frame: zdroj.frame; mirror: to.mirror; frameDir: to.frameDir; frameCount: to.frameCount
            radii: [to.footRadius, to.footRadius, to.footRadius, to.footRadius]
            ox: to.ox; oy: to.oy; canvasW: to.canvasW; canvasH: to.canvasH
            ohnisko: to.ohnisko; anchorX: to.ox + to.foot.w / 2; anchorY: to.canvasH - to.foot.h / 2
        }
        // rám ostrova: rovnaká farba a hrúbka ako obrys okna L (LPopup.frameColor/frameWidth), jemný svetlý lem dnu
        Rectangle {
            anchors.fill: parent; radius: to.footRadius; color: "transparent"
            border { width: 1.5; color: to.theme.primary }
        }
        Rectangle {
            anchors { fill: parent; margins: 1.5 } radius: to.footRadius - 1.5; color: "transparent"
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.10) }
        }
    }
}
