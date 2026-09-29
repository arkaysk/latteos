// LatteOS — AI rozhovor ako okno (pripínačik 📌 vo vyskakovacom paneli AI). Ten istý rozhovor
// (~/.local/share/latteos/ai-rozhovor.json) ako panel Super+I a odpovede z Text Baru; odpoveď cez
// `latte-ai chat` (poskytovateľ podľa Nastavenia › Softvér › AI).
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }

    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || ((Quickshell.env("HOME") || "") + "/.local/share")) + "/latteos"
    readonly property string file: dataDir + "/ai-rozhovor.json"
    property var msgs: []
    property bool busy: false
    property string target: ""

    FileView {
        id: store
        path: app.file; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { const m = JSON.parse(text()); app.msgs = Array.isArray(m) ? m : []; } catch (e) { app.msgs = []; } }
        onLoadFailed: app.msgs = []
    }
    function save(list) {
        app.msgs = list.slice(-40);
        store.setText(JSON.stringify(app.msgs));
    }
    Process {
        running: true; command: ["latte-ai", "status"]
        stdout: StdioCollector { onStreamFinished: {
            const model = (this.text.match(/model=([^\n]*)/) || [])[1] || "";
            const tgt = (this.text.match(/target=([^\n]*)/) || [])[1] || "";
            app.target = (model ? model + " · " : "") + tgt;
        } }
    }
    Process {
        id: ask
        command: ["latte-ai", "chat", app.file]
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: (code) => {
            app.busy = false;
            const a = out.text.trim();
            app.save(app.msgs.concat([{ role: "assistant", content: code === 0 && a !== "" ? a : "⚠ AI neodpovedalo: " + (err.text.trim() || a || "?").slice(0, 300) }]));
        }
    }
    Process { id: runner }
    function run(cmd) { runner.command = cmd; runner.startDetached(); }
    // pravý klik na správu: kopírovať, uložiť do Heidelbergu, poslať znova
    function msgMenu(m, x, y) {
        const txt = String(m.content);
        const items = [
            { glyph: "copy", label: "Kopírovať správu", action: () => app.run(["wl-copy", "--", txt]) },
            { glyph: "file-text", label: "Uložiť do Heidelbergu", action: () => app.run(["sh", "-c", 'd="$HOME/Dokumenty"; mkdir -p "$d"; f="$d/AI $(date +%Y-%m-%d\\ %H-%M).md"; printf "%s\\n" "$1" > "$f"; latte-app heidelberg "$f"', "sh", txt]) }
        ];
        if (m.role === "user") items.push({ glyph: "refresh", label: "Poslať znova", enabled: !app.busy, action: () => app.send(txt) });
        items.push({ separator: true });
        items.push({ glyph: "trash", label: "Vymazať rozhovor", danger: true, action: () => app.save([]) });
        ctx.open(x, y, items, m.role === "user" ? "Tvoja správa" : "Odpoveď AI");
    }
    function send(t) {
        t = t.trim();
        if (t === "" || busy) return;
        save(msgs.concat([{ role: "user", content: t }]));
        busy = true;
        Qt.callLater(() => ask.running = true);       // až keď je otázka zapísaná v súbore
    }

    FloatingWindow {
        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: "AI — LatteOS"
        implicitWidth: 620; implicitHeight: 760
        color: theme.surface

        HeaderBar {
            id: header
            theme: theme
            appId: "latteos-aichat"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            title: "AI rozhovor"
            netVisible: false
            searchPlaceholder: "Hľadať v rozhovore"
            onCloseRequested: Qt.quit()
            IconButton { theme: theme; glyph: "plus"; tip: "Nový rozhovor"; onClicked: app.save([]) }
        }

        ListView {
            id: list
            ScrollHint { flick: list; colors: theme }
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: inputBox.top; margins: 16 }
            clip: true; spacing: 10
            model: app.msgs.filter(m => header.searchText === "" || String(m.content).toLowerCase().includes(header.searchText.toLowerCase()))
            onCountChanged: Qt.callLater(() => list.positionViewAtEnd())
            delegate: Item {
                required property var modelData
                readonly property bool mine: modelData.role === "user"
                width: list.width; height: bubble.height
                Rectangle {
                    id: bubble
                    anchors { right: mine ? parent.right : undefined; left: mine ? undefined : parent.left }
                    width: Math.min(list.width * 0.85, txt.implicitWidth + 28); height: txt.implicitHeight + who.height + 26
                    radius: 14; color: mine ? theme.primary : theme.surfaceVariant
                    Text { id: who; x: 14; y: 10; text: mine ? "Ty" : "AI"; color: mine ? theme.fgOnPrimary : theme.primary; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                    MouseArea {    // pravý klik na bublinu (ľavé tlačidlo ostáva výberu textu)
                        anchors.fill: parent; acceptedButtons: Qt.RightButton; z: 2
                        onClicked: (m) => { const q = mapToItem(null, m.x, m.y); app.msgMenu(modelData, q.x, q.y); }
                    }
                    TextEdit {
                        id: txt; x: 14; anchors { top: who.bottom; topMargin: 4 }
                        width: Math.min(list.width * 0.85 - 28, implicitWidth); readOnly: true; selectByMouse: true
                        wrapMode: Text.Wrap; textFormat: mine ? Text.PlainText : Text.MarkdownText
                        text: String(modelData.content)
                        color: mine ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                        Component.onCompleted: if (implicitWidth > list.width * 0.85 - 28) width = list.width * 0.85 - 28
                    }
                }
            }
            header: Text { width: list.width; bottomPadding: 8; text: app.target; color: theme.fgDim; elide: Text.ElideRight; font { family: theme.fontUi; pixelSize: 11 } }
            Text { anchors.centerIn: parent; visible: list.count === 0; text: "Opýtaj sa čokoľvek. Rozhovor si pamätá predošlé správy."; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
        }

        Rectangle {
            id: inputBox
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            height: 48; radius: 12; color: theme.field; border { color: input.activeFocus ? theme.primary : "transparent"; width: 1 }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: 14; rightMargin: 50 }
                verticalAlignment: TextInput.AlignVCenter; color: theme.fg; font { family: theme.fontUi; pixelSize: 14 }
                enabled: !app.busy; focus: true; Component.onCompleted: forceActiveFocus()
                onAccepted: { app.send(text); text = ""; }
            }
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; visible: input.text === ""
                   text: app.busy ? "AI premýšľa…" : "Napíš správu, Enter pošle"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } }
            IconButton { theme: theme; glyph: "arrow-up"; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                         onClicked: { app.send(input.text); input.text = ""; } }
        }
        ContextMenu { id: ctx; theme: theme; anchors.fill: parent }
    }
}
