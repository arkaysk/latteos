// LatteOS — Inšpektor siete ako samostatné okno (to isté je v Správcovi zariadení › Siete). Podľa ESET Network Inspector:
// radar s týmto počítačom a routerom, zariadenia pripojené teraz a v minulosti, identifikácia (meno, druh), zoznam.
// Spúšťa sa: latte-app inspektor [zoznam]
import QtQuick
import Quickshell
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }
    readonly property var th: theme
    FloatingWindow {
        title: "Inšpektor siete — LatteOS"
        implicitWidth: 1040; implicitHeight: 720
        color: theme.surface
        onClosed: Qt.quit()
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: insp.selKey = ""
            HeaderBar {
                id: header
                theme: theme
                anchors { left: parent.left; right: parent.right; top: parent.top }
                title: "Inšpektor siete"
                netVisible: false
                searchPlaceholder: "Nájsť zariadenie (meno, IP, výrobca)"
                onSearchSubmitted: (t) => { const q = t.toLowerCase(); const d = (insp.net.devices || []).find(x => (insp.label(x) + " " + x.ip + " " + x.vendor).toLowerCase().includes(q));
                                            if (d) insp.selKey = d.key; }
                onCloseRequested: Qt.quit()
            }
            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 22 }
                contentHeight: insp.implicitHeight + 20; clip: true; boundsBehavior: Flickable.StopAtBounds
                InspektorSiete {
                    id: insp
                    theme: app.th; compact: false; fill: view === "radar"
                    width: parent.width; height: view === "radar" ? flick.height - 10 : implicitHeight
                    view: (Quickshell.env("LATTE_APP_ARGS") || "").trim() === "zoznam" ? "zoznam" : "radar"
                    onOpenWindow: (a) => Quickshell.execDetached(a)
                }
            }
        }
    }
}
