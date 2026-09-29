// LatteOS — Aplikácie (App Manager) ako samostatné okno. Obsah je spoločný s Nastaveniami › Softvér (common/AppManager.qml).
// Backend: latte-apps. Spúšťa sa: latte-app aplikacie [objavovat|aktualizacie|nainstalovane|opravnenia|check SÚBOR|hladat …|detail ID]
import QtQuick
import Quickshell
import "common"

ShellRoot {
    id: shell
    LatteTheme { id: theme }
    readonly property var th: theme

    FloatingWindow {
        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: "Aplikácie — LatteOS"
        implicitWidth: 1220; implicitHeight: 780
        color: theme.surface
        AppManager {
            anchors.fill: parent
            theme: shell.th
            args: (Quickshell.env("LATTE_APP_ARGS") || "").trim().split(" ")
            onCloseRequested: Qt.quit()
        }
    }
}
