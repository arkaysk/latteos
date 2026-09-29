// LatteOS — Správca zariadení (Device Manager) ako samostatné okno. Obsah je spoločný s oknom v tvare L z pravého rohu
// lišty a so stránkami Nastavení (common/SpravcaZariadeni.qml): karty Zariadenia / Siete, dlaždice kategórií podľa
// dôležitosti, zariadenia so stavom, opravou a vlastnosťami ako vo Windows a softvér ovládačov (zvuk: konektory
// a kanály, obrazovka: rozlíšenie s potvrdením do 15 s, Wi-Fi, Bluetooth, disky…). Backend: latte-devices.
// Spúšťa sa: latte-app zariadenia [skupina|siete]
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }
    readonly property string arg: (Quickshell.env("LATTE_APP_ARGS") || "").trim()
    Process { id: det }

    FloatingWindow {
        id: win
        title: "Správca zariadení — LatteOS"
        implicitWidth: 1100; implicitHeight: 780
        color: theme.surface
        onClosed: Qt.quit()                  // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        onVisibleChanged: if (!visible) dmv.revert()

        Item {
            anchors.fill: parent
            focus: true
            Keys.onReturnPressed: dmv.keep()
            Keys.onEscapePressed: { if (dmv.countdown > 0) dmv.revert(); else if (dmv.group !== "") dmv.group = ""; }
            HeaderBar {
                id: header
                theme: theme
                anchors { left: parent.left; right: parent.right; top: parent.top }
                title: dmv.tab === "siete" ? "Siete" : (dmv.curGroup ? dmv.curGroup.title : "Správca zariadení")
                canBack: dmv.group !== ""
                onBack: dmv.group = ""
                netVisible: false
                onCloseRequested: { dmv.revert(); Qt.quit(); }
            }
            SpravcaZariadeni {
                id: dmv
                theme: theme
                compact: false
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 20 }
                tab: app.arg === "siete" ? "siete" : "zariadenia"
                Component.onCompleted: if (app.arg && app.arg !== "siete" && app.arg !== "vsetko") group = app.arg
                onOpenWindow: (a) => { det.command = a; det.startDetached(); }
            }
        }
    }
}
