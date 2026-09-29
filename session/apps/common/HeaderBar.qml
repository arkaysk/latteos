// HeaderBar — hlavička okna aplikácie LatteOS (návrh V2): ‹ › · názov · [nástroje] · hľadanie · NET · okno.
// Nástroje aplikácie sa vkladajú ako deti (default property → tools).
import QtQuick
import Quickshell.Io
// NET: appId = názov .desktop súboru aplikácie (napr. latteos-subory); stav a prepnutie cez latte-net,
// platí od ďalšieho spustenia aplikácie (bubblewrap bez siete).

Rectangle {
    id: hb
    required property var theme
    property string title: ""
    property string crumbPath: ""          // cesta ako klikateľná adresa namiesto titulku (Súbory)
    signal crumbClicked(string path)
    property bool canBack: false
    property bool canForward: false
    property string searchPlaceholder: "Hľadať"
    property bool netVisible: true         // aplikácia môže NET úplne skryť (napr. editor bez siete)
    property bool netUsed: false           // NET sa ukáže, až keď aplikácia naozaj otvorí sieťové spojenie
    property bool netOn: true
    property bool windowControls: true     // false = vložené v inej aplikácii (Nastavenia): bez okenných tlačidiel a ťahania okna
    property string appId: ""
    Process { id: netStatus; running: hb.appId !== ""; command: ["latte-net", "status", hb.appId]
              stdout: StdioCollector { onStreamFinished: hb.netOn = this.text.trim() !== "off" } }
    Process { id: netSet }
    // má proces aplikácie (rodič tohto sh = qs) nadviazané TCP/UDP spojenie?
    Process {
        id: netProbe
        command: ["sh", "-c", "ss -Htunp 2>/dev/null | grep -q \"pid=$PPID,\" && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: if (this.text.trim() === "1") hb.netUsed = true }
    }
    Timer { interval: 5000; repeat: true; running: hb.netVisible && !hb.netUsed; triggeredOnStart: true; onTriggered: netProbe.running = true }
    Process { id: winCmd }
    function winAction(code) { winCmd.command = ["hyprctl", "eval", code]; winCmd.running = true; }
    // prázdne miesto hlavičky: ťahanie presunie okno (xdg_toplevel.move ako GTK/KDE), dvojklik = zväčšiť.
    // Leží pod ostatnými prvkami, tlačidlá a hľadanie majú prednosť. Super + myš je iba doplnok.
    MouseArea {
        enabled: hb.windowControls
        z: -1; anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point start
        onPressed: (m) => start = Qt.point(m.x, m.y)
        // pravý klik na hlavičku = ponuka okna ako vo Windows (Obnoviť, Minimalizovať, Maximalizovať, rozloženia, Zavrieť)
        onClicked: (m) => { if (m.button === Qt.RightButton) { const q = mapToItem(null, m.x, m.y); winCmd.command = ["latte-ponuka", "okno-rel", String(Math.round(q.x)), String(Math.round(q.y))]; winCmd.running = true; } }
        onPositionChanged: (m) => {
            if ((m.buttons & Qt.LeftButton) && Math.abs(m.x - start.x) + Math.abs(m.y - start.y) > 4 && hb.Window.window)
                hb.Window.window.startSystemMove();
        }
        onDoubleClicked: hb.winAction("latte.win.maximize()")
    }
    default property alias tools: toolRow.data
    signal back()
    signal forward()
    signal searchChanged(string text)
    signal searchSubmitted(string text)    // Enter v hľadaní
    signal closeRequested()
    signal netToggled(bool on)
    property alias searchText: search.text
    function focusSearch() { search.forceActiveFocus(); search.selectAll(); }   // Ctrl+F / F3 ako vo Windows

    height: 52
    color: "transparent"

    Row {
        id: left
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 4
        // Späť / Dopredu ako v prehliadači: šípka je vidieť iba vtedy, keď sa dá použiť (aplikácie bez
        // prechádzania ich nemajú vôbec); Alt+← / Alt+→ robia to isté
        Rectangle {
            visible: hb.canBack || hb.canForward
            width: navRow.implicitWidth + 4; height: 36; radius: 10; color: hb.theme.field
            Row {
                id: navRow
                anchors.centerIn: parent
                IconButton { visible: hb.canBack; theme: hb.theme; glyph: "chevron-left"; tip: "Späť (Alt+←)"; onClicked: hb.back() }
                IconButton { visible: hb.canForward; theme: hb.theme; glyph: "chevron-right"; tip: "Dopredu (Alt+→)"; onClicked: hb.forward() }
            }
        }
        Shortcut { sequence: "Alt+Left"; enabled: hb.canBack; onActivated: hb.back() }
        Shortcut { sequence: "Alt+Right"; enabled: hb.canForward; onActivated: hb.forward() }
        Row { id: toolRow; spacing: 2; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter }
    }

    Text {
        visible: hb.crumbPath === ""
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - left.width - right.width - 40)
        elide: Text.ElideMiddle
        text: hb.title; color: hb.theme.fg
        font { family: hb.theme.fontUi; pixelSize: 14; weight: Font.Bold }
    }
    // klikateľná adresa (Súbory): klik na časť cesty prejde do toho priečinka; pri dlhej ceste ostane viditeľný koniec
    Item {
        id: crumbBox
        visible: hb.crumbPath !== ""
        readonly property real avail: parent.width - left.width - right.width - 40
        width: Math.min(crumbs.implicitWidth, avail); height: 30
        anchors.centerIn: parent
        clip: true
        readonly property var parts: {
            const p = hb.crumbPath, out = [{ label: "/", path: "/" }];
            let acc = "";
            for (const seg of p.split("/").filter(x => x !== "")) { acc += "/" + seg; out.push({ label: seg, path: acc }); }
            return out;
        }
        Row {
            id: crumbs
            x: Math.min(0, crumbBox.width - implicitWidth)
            height: parent.height
            Repeater {
                model: crumbBox.parts
                Row {
                    required property var modelData
                    required property int index
                    height: crumbs.height
                    Text { visible: index > 1; anchors.verticalCenter: parent.verticalCenter; text: "/"; color: hb.theme.fgDim
                           font { family: hb.theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                    Rectangle {
                        readonly property bool last: index === crumbBox.parts.length - 1
                        width: ct.implicitWidth + 10; height: 26; radius: 7; anchors.verticalCenter: parent.verticalCenter
                        color: cm.containsMouse && !last ? hb.theme.hover : "transparent"
                        Text { id: ct; anchors.centerIn: parent; text: modelData.label; color: parent.last ? hb.theme.fg : hb.theme.fgDim
                               font { family: hb.theme.fontUi; pixelSize: 14; weight: parent.last ? Font.Bold : Font.DemiBold } }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.last ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: if (!parent.last) hb.crumbClicked(modelData.path) }
                    }
                }
            }
        }
    }

    Row {
        id: right
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 8
        Rectangle {
            width: 230; height: 36; radius: 10; color: hb.theme.field
            border { color: search.activeFocus ? hb.theme.primary : "transparent"; width: 1 }
            Glyph { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 15; color: hb.theme.fgDim }
            TextInput {
                id: search
                anchors { fill: parent; leftMargin: 32; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter; clip: true
                color: hb.theme.fg; selectionColor: hb.theme.primary
                font { family: hb.theme.fontUi; pixelSize: 13 }
                onTextChanged: hb.searchChanged(text)
                onAccepted: hb.searchSubmitted(text)
                Keys.onEscapePressed: { text = ""; focus = false }
            }
            Text {
                x: 32; anchors.verticalCenter: parent.verticalCenter; visible: search.text === ""
                text: hb.searchPlaceholder; color: hb.theme.fgDim
                font { family: hb.theme.fontUi; pixelSize: 13 }
            }
        }
        // NET: sieťový prístup aplikácie (bezpečnostný model F6), prepnutie platí hneď (latte-netd)
        Rectangle {
            visible: hb.netVisible && (hb.netUsed || !hb.netOn)      // vypnutý NET ostáva viditeľný, aby sa dal zapnúť
            width: netRow.implicitWidth + 16; height: 36; radius: 10
            color: hb.netOn ? Qt.rgba(hb.theme.netOnColor.r, hb.theme.netOnColor.g, hb.theme.netOnColor.b, 0.14) : hb.theme.field
            border { color: hb.netOn ? "transparent" : hb.theme.netOffColor; width: 1 }
            Row {
                id: netRow; anchors.centerIn: parent; spacing: 6
                Rectangle {         // zapnutý: zelené plné koliesko; vypnutý: červené prázdne
                    width: 9; height: 9; radius: 4.5; anchors.verticalCenter: parent.verticalCenter
                    color: hb.netOn ? hb.theme.netOnColor : "transparent"
                    border { color: hb.netOn ? hb.theme.netOnColor : hb.theme.netOffColor; width: hb.netOn ? 0 : 1.5 }
                }
                Text { text: "NET"; color: hb.theme.fg; font { family: hb.theme.fontUi; pixelSize: 12; weight: Font.ExtraBold } }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    hb.netOn = !hb.netOn; hb.netToggled(hb.netOn);
                    if (hb.appId !== "") { netSet.command = ["latte-net", hb.netOn ? "on" : "off", hb.appId]; netSet.running = true; }
                }
            }
        }
        // okenné tlačidlá ako v lište kompozitora (latte/bars.lua): minimalizovať, zväčšiť, zavrieť
        Row {
            visible: hb.windowControls
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            component WinBtn: Rectangle {
                id: wb
                property string icon; property color bg; property string tip
                signal clicked()
                width: 22; height: 22; radius: 11
                color: wm.containsMouse ? Qt.lighter(bg, 1.15) : bg
                Text { anchors.centerIn: parent; text: wb.icon; color: wb.bg === hb.theme.error ? "white" : hb.theme.fgOnPrimary; font { family: hb.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                MouseArea { id: wm; anchors.fill: parent; hoverEnabled: true; onClicked: wb.clicked() }
            }
            WinBtn { icon: "–"; bg: hb.theme.primary; tip: "Minimalizovať"; onClicked: hb.winAction("latte.win.minimize()") }
            WinBtn { icon: "□"; bg: hb.theme.primary; tip: "Zväčšiť"; onClicked: hb.winAction("latte.win.maximize()") }
            WinBtn { icon: "✕"; bg: hb.theme.error; tip: "Zavrieť"; onClicked: hb.closeRequested() }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: hb.theme.primary; opacity: 0.55 }
}
