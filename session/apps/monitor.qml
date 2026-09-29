// LatteOS — Monitor ako samostatné okno (Ctrl+Shift+Esc). Obsah je spoločný s Nastaveniami › Spúšťanie a na pozadí
// (common/MonitorView.qml). Spúšťa sa: latte-app monitor [prehlad|procesy|autorun|telemetria|hardver|senzory|pohoda|strom]
import QtQuick
import Quickshell
import "common"

ShellRoot {
    id: shell
    LatteTheme { id: theme }
    readonly property var th: theme
    FloatingWindow {
        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: "Monitor — LatteOS"
        implicitWidth: 1220; implicitHeight: 760
        color: theme.surface
        MonitorView {
            anchors.fill: parent
            theme: shell.th
            args: (Quickshell.env("LATTE_APP_ARGS") || "").trim()
            onCloseRequested: Qt.quit()
        }
    }
}
