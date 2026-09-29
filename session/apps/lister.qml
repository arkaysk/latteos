// LatteOS — Lister (F3 v Súboroch, ako Lister v Total Commanderi): rýchly náhľad súboru v samostatnom okne.
//   text (automatické kódovanie UTF-8 / CP1250 / ISO-8859-2, dá sa prepnúť), hex (klávesa 3), obrázok, zalamovanie (W),
//   hľadanie (Ctrl+F, F3 ďalšie), veľké súbory po 256 kB (načíta ďalšie pri konci), N/P = ďalší/predošlý súbor v priečinku,
//   Esc zavrie. Dáta: latte-tc nahlad. Spúšťa sa: latte-app lister SÚBOR
//   Médiá (ako Lister v TC s pluginom): zvuk sa prehrá priamo (Medzerník = prehrať/pauza, ←/→ posun o 5 s),
//   video ukáže snímku (ffmpegthumbnailer) a technické údaje (ffprobe); prehrá ho predvolený prehrávač
//   (vo VM bez GPU sa video v okne neprehráva — softvérové skladanie videa zhodilo Hyprland).
import QtQuick
import Quickshell
import Quickshell.Io
import QtMultimedia
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }
    property string path: (Quickshell.env("LATTE_APP_ARGS") || "").trim().replace(/^file:\/\//, "")
    property string mode: "text"            // text | hex | obrazok | medium
    property string enc: ""
    property var data: null
    property string content: ""
    property int loaded: 0
    property bool wrap: true
    property string find: ""
    property int findPos: -1
    property var siblings: []
    readonly property string name: path.split("/").pop()
    readonly property bool isImage: /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i.test(path)
    readonly property bool isAudio: /\.(mp3|flac|ogg|oga|opus|wav|m4a|aac|wma|aiff?)$/i.test(path)
    readonly property bool isVideo: /\.(mp4|mkv|webm|avi|mov|m4v|wmv|flv|mpe?g|ts|3gp)$/i.test(path)
    readonly property bool isMedia: isAudio || isVideo
    property var info: null                 // ffprobe: { format, streams }
    property string thumb: ""
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos"
    Process {
        id: probe
        stdout: StdioCollector { onStreamFinished: { try { app.info = JSON.parse(this.text); } catch (e) { app.info = null; } } }
    }
    Process {
        id: thumbProc
        onExited: (code) => { if (code === 0) app.thumb = "file://" + app.runDir + "/lister-nahlad.png?" + Date.now(); }
    }
    function loadMedia() {
        info = null; thumb = ""; player.stop();
        probe.command = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path]; probe.running = true;
        if (isVideo) { thumbProc.command = ["sh", "-c", 'mkdir -p "$1" && ffmpegthumbnailer -i "$2" -o "$1/lister-nahlad.png" -s 960 -t 15%', "sh", runDir, path]; thumbProc.running = true; }
        if (isAudio) { player.source = "file://" + path; player.play(); }
    }
    function dur(sec) { sec = Math.round(sec || 0); const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), x = sec % 60;
                        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0"); }
    readonly property var facts: {
        if (!info) return [];
        const f = info.format || {}, out = [];
        const v = (info.streams || []).find(x => x.codec_type === "video" && !(x.disposition && x.disposition.attached_pic));
        const a = (info.streams || []).find(x => x.codec_type === "audio");
        const t = Object.assign({}, (a && a.tags) || {}, f.tags || {});          // Ogg/Opus majú tagy v stope
        if (t.title || t.TITLE) out.push(["Názov", t.title || t.TITLE]);
        if (t.artist || t.ARTIST) out.push(["Interpret", t.artist || t.ARTIST]);
        if (t.album || t.ALBUM) out.push(["Album", t.album || t.ALBUM]);
        out.push(["Dĺžka", dur(parseFloat(f.duration))]);
        if (v) out.push(["Video", (v.codec_name || "").toUpperCase() + " · " + v.width + "×" + v.height + (v.r_frame_rate ? " · " + Math.round(eval(v.r_frame_rate) * 100) / 100 + " fps" : "")]);
        if (a) out.push(["Zvuk", (a.codec_name || "").toUpperCase() + " · " + (a.sample_rate ? Math.round(a.sample_rate / 100) / 10 + " kHz" : "") + (a.channels ? " · " + (a.channels === 1 ? "mono" : a.channels === 2 ? "stereo" : a.channels + " kanálov") : "")]);
        if (f.bit_rate) out.push(["Dátový tok", Math.round(f.bit_rate / 1000) + " kb/s"]);
        out.push(["Kontajner", f.format_long_name || f.format_name || ""]);
        const subs = (info.streams || []).filter(x => x.codec_type === "subtitle").length;
        if (subs) out.push(["Titulky", subs + " stôp"]);
        return out;
    }
    MediaPlayer { id: player; audioOutput: AudioOutput { volume: 0.8 } }

    Process {
        id: load
        property bool append: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    app.data = d;
                    app.content = load.append ? app.content + (d.mode === "hex" ? "\n" : "") + d.text : d.text;
                    app.loaded = d.start + d.len;
                    if (!load.append && d.binary && app.mode === "text" && !app.enc) app.mode = "hex";
                } catch (e) { app.content = "Súbor sa nedá prečítať."; }
            }
        }
    }
    function reload(more) {
        if (isImage && mode !== "hex") { mode = "obrazok"; return; }
        if (isMedia && mode !== "hex" && mode !== "text") { mode = "medium"; loadMedia(); return; }
        if (mode === "obrazok" || mode === "medium") { mode = "text"; player.stop(); }
        load.append = !!more;
        load.command = ["latte-tc", "nahlad", path, "--od", String(more ? loaded : 0)].concat(mode === "hex" ? ["--hex"] : []).concat(enc ? ["--kodovanie", enc] : []);
        load.running = true;
    }
    Component.onCompleted: { if (isMedia) mode = "medium"; reload(false); sib.running = true; }
    Process {
        id: sib
        command: ["sh", "-c", 'ls -1Ap "$(dirname "$1")" | grep -v /$', "sh", app.path]
        stdout: StdioCollector { onStreamFinished: app.siblings = this.text.split("\n").filter(l => l !== "") }
    }
    function step(d) {
        const i = siblings.indexOf(name); if (i < 0 || !siblings.length) return;
        const n = siblings[(i + d + siblings.length) % siblings.length];
        path = path.substring(0, path.lastIndexOf("/") + 1) + n; mode = isImage ? "obrazok" : (isMedia ? "medium" : "text"); enc = ""; content = ""; reload(false);
    }
    function doFind(next) {
        if (!find) return;
        const low = content.toLowerCase(), q = find.toLowerCase();
        let i = low.indexOf(q, next ? findPos + 1 : 0); if (i < 0) i = low.indexOf(q);
        findPos = i;
        if (i >= 0) { txt.select(i, i + q.length); const r = txt.positionToRectangle(i); flick.contentY = Math.max(0, r.y - flick.height / 3); }
    }
    function human(b) { const u = ["B", "KB", "MB", "GB"]; let v = b || 0, i = 0; while (v >= 1024 && i < 3) { v /= 1024; i++; } return v.toFixed(i ? 1 : 0).replace(".", ",") + " " + u[i]; }

    FloatingWindow {
        onClosed: Qt.quit()
        title: app.name + " — Lister"
        implicitWidth: 1000; implicitHeight: 720
        color: theme.surface
        Item {
            id: root
            anchors.fill: parent; focus: true
            Keys.onPressed: (ev) => {
                const ctrl = ev.modifiers & Qt.ControlModifier; ev.accepted = true;
                if (findBox.visible && ev.key !== Qt.Key_F3 && ev.key !== Qt.Key_Escape) { ev.accepted = false; return; }
                if (ev.key === Qt.Key_Escape) { if (findBox.visible) findBox.visible = false; else Qt.quit(); }
                else if (ev.key === Qt.Key_F && ctrl) { findBox.visible = true; findIn.forceActiveFocus(); findIn.selectAll(); }
                else if (ev.key === Qt.Key_F3) app.doFind(true);
                else if (ev.key === Qt.Key_1) { app.mode = "text"; app.reload(false); }
                else if (ev.key === Qt.Key_3) { app.mode = "hex"; app.reload(false); }
                else if (app.mode === "medium" && ev.key === Qt.Key_Space && app.isAudio) { if (player.playbackState === MediaPlayer.PlayingState) player.pause(); else player.play(); }
                else if (app.mode === "medium" && ev.key === Qt.Key_Right) player.position = Math.min(player.duration, player.position + 5000);
                else if (app.mode === "medium" && ev.key === Qt.Key_Left) player.position = Math.max(0, player.position - 5000);
                else if (ev.key === Qt.Key_W) app.wrap = !app.wrap;
                else if (ev.key === Qt.Key_N) app.step(1);
                else if (ev.key === Qt.Key_P) app.step(-1);
                else if (ev.key === Qt.Key_Down) flick.contentY = Math.min(flick.contentHeight - flick.height, flick.contentY + 40);
                else if (ev.key === Qt.Key_Up) flick.contentY = Math.max(0, flick.contentY - 40);
                else if (ev.key === Qt.Key_PageDown || ev.key === Qt.Key_Space) flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + flick.height - 40);
                else if (ev.key === Qt.Key_PageUp) flick.contentY = Math.max(0, flick.contentY - flick.height + 40);
                else if (ev.key === Qt.Key_Home) flick.contentY = 0;
                else if (ev.key === Qt.Key_End) flick.contentY = Math.max(0, flick.contentHeight - flick.height);
                else ev.accepted = false;
            }
            HeaderBar {
                id: header
                theme: theme; appId: "latteos-subory"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                title: app.name
                onCloseRequested: Qt.quit()
            }
            Row {
                id: bar
                anchors { left: parent.left; top: header.bottom; margins: 10 }
                spacing: 6
                component Chip: Rectangle {
                    id: c
                    property string label; property bool on: false
                    signal clicked()
                    width: cl.implicitWidth + 20; height: 28; radius: 8
                    color: on ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.22) : (cm.containsMouse ? theme.hover : theme.field)
                    Text { id: cl; anchors.centerIn: parent; text: c.label; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: c.on ? Font.Bold : Font.Normal } }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: { c.clicked(); root.forceActiveFocus(); } }
                }
                Chip { label: "1 Text"; on: app.mode === "text"; onClicked: { app.mode = "text"; app.reload(false); } }
                Chip { label: "3 Hex"; on: app.mode === "hex"; onClicked: { app.mode = "hex"; app.reload(false); } }
                Chip { visible: app.isImage; label: "Obrázok"; on: app.mode === "obrazok"; onClicked: app.mode = "obrazok" }
                Chip { visible: app.isMedia; label: app.isAudio ? "Zvuk" : "Video"; on: app.mode === "medium"; onClicked: { app.mode = "medium"; app.loadMedia(); } }
                Chip { label: "W Zalamovať"; on: app.wrap; onClicked: app.wrap = !app.wrap }
                Item { width: 10; height: 1 }
                Repeater { model: ["", "utf-8", "cp1250", "iso-8859-2", "latin-1"]
                    Chip { required property string modelData; label: modelData || "auto"; on: app.enc === modelData; onClicked: { app.enc = modelData; app.mode = "text"; app.reload(false); } } }
                Item { width: 10; height: 1 }
                Chip { label: "Ctrl+F Hľadať"; onClicked: { findBox.visible = true; findIn.forceActiveFocus(); } }
                Chip { label: "Otvoriť v aplikácii"; onClicked: runner.running = true }
            }
            Process { id: runner; command: ["xdg-open", app.path] }
            Rectangle {
                id: findBox
                visible: false
                anchors { right: parent.right; top: header.bottom; margins: 10 }
                width: 320; height: 30; radius: 8; color: theme.field; border { color: theme.primary; width: 1 }
                z: 5
                TextInput { id: findIn; anchors { fill: parent; leftMargin: 10; rightMargin: 10 } verticalAlignment: TextInput.AlignVCenter; color: theme.fg
                            font { family: theme.fontUi; pixelSize: 13 }
                            onTextChanged: { app.find = text; app.doFind(false); }
                            Keys.onReturnPressed: (ev) => { ev.accepted = true; app.doFind(true); }
                            Keys.onEscapePressed: { findBox.visible = false; root.forceActiveFocus(); } }
            }
            Flickable {
                id: flick
                visible: app.mode !== "obrazok"
                anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: status.top; margins: 10 }
                contentWidth: app.wrap ? width : Math.max(width, txt.implicitWidth); contentHeight: txt.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollHint { flick: flick; colors: theme }
                onContentYChanged: if (app.data && app.data.more && !load.running && contentY > contentHeight - height * 2) app.reload(true)
                TextEdit {
                    id: txt
                    width: app.wrap ? flick.width - 14 : implicitWidth
                    readOnly: true; selectByMouse: true; textFormat: TextEdit.PlainText
                    wrapMode: app.wrap ? TextEdit.WrapAnywhere : TextEdit.NoWrap
                    text: app.content; color: theme.fg; selectionColor: theme.primary; selectedTextColor: theme.fgOnPrimary
                    font { family: theme.fontMono; pixelSize: 13 }
                }
            }
            Image {
                visible: app.mode === "obrazok"
                anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: status.top; margins: 10 }
                source: app.mode === "obrazok" ? "file://" + app.path : ""; fillMode: Image.PreserveAspectFit; asynchronous: true
            }
            // médium: snímka / obal, údaje, prehrávanie zvuku
            Item {
                visible: app.mode === "medium"
                anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: status.top; margins: 16 }
                Image {
                    id: mimg
                    anchors { left: parent.left; top: parent.top; bottom: ctl.top; bottomMargin: 12 }
                    width: parent.width * 0.6
                    source: app.thumb; fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                    Glyph { anchors.centerIn: parent; visible: !app.thumb; name: app.isAudio ? "music" : "movie"; size: 96; color: theme.fgDim }
                }
                Column {
                    anchors { left: mimg.right; leftMargin: 20; right: parent.right; top: parent.top }
                    spacing: 8
                    Repeater {
                        model: app.facts
                        Column {
                            required property var modelData
                            width: parent.width; spacing: 1
                            Text { text: modelData[0]; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11; weight: Font.Bold } }
                            Text { width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData[1]; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                        }
                    }
                }
                Row {
                    id: ctl
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 40; spacing: 12
                    Chip { visible: app.isAudio; anchors.verticalCenter: parent.verticalCenter
                           label: player.playbackState === MediaPlayer.PlayingState ? "Pauza (Medzerník)" : "Prehrať (Medzerník)"
                           onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                    Item {
                        visible: app.isAudio; width: parent.width - 360; height: 40
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: theme.field }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: player.duration ? parent.width * player.position / player.duration : 0; height: 6; radius: 3; color: theme.primary }
                        MouseArea { anchors.fill: parent; onClicked: (m) => { if (player.duration) player.position = player.duration * m.x / width; } }
                    }
                    Text { visible: app.isAudio; anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                           text: app.dur(player.position / 1000) + " / " + app.dur(player.duration / 1000) }
                    Chip { anchors.verticalCenter: parent.verticalCenter; label: app.isVideo ? "Prehrať v prehrávači" : "Otvoriť v prehrávači"
                           onClicked: { player.pause(); opener.command = ["xdg-open", app.path]; opener.startDetached(); } }
                }
            }
            Process { id: opener }
            Rectangle {
                id: status
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 28; color: "transparent"
                Rectangle { width: parent.width; height: 1; color: theme.line }
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: app.data ? app.human(app.data.size) + " · " + (app.data.mime || "") + (app.data.encoding && app.mode === "text" ? " · " + app.data.encoding : "")
                                        + (app.data.more ? " · načítané " + app.human(app.loaded) + " (pri konci ďalšie)" : "") : "" }
                Text { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } color: theme.fgDim; font { family: theme.fontUi; pixelSize: 11 }
                       text: "1 text · 3 hex · W zalamovanie · N/P ďalší/predošlý súbor · Ctrl+F hľadať · Esc zavrieť" }
            }
        }
    }
}
