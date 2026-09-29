// LatteOS — Inštalátor: grafická inštalácia a aktualizácia systémových balíkov (namiesto terminálu).
// Použitie: latte-app instalator install <balík…> | remove <balík…> | upgrade | latteos
//   latteos = aktualizovať súčasti LatteOS: git pull v repozitári inštalácie + setup/f1/install-session.sh
//             (heslo ide do dočasného askpass v $XDG_RUNTIME_DIR s právami 0600/0700, po skončení sa zmaže)
//           (voliteľne prvý argument „--nazov=Pekný názov“ pre nadpis)
// Heslo správcu sa zadá v okne a ide iba cez stdin do sudo (-S), nikam sa neukladá. Priebeh z výstupu dnf.
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }

    readonly property var args: (Quickshell.env("LATTE_APP_ARGS") || "").trim().split(/\s+/).filter(a => a !== "")
    readonly property string title: (args.find(a => a.startsWith("--nazov=")) || "").slice(8).replace(/_/g, " ")
    readonly property var rest: args.filter(a => !a.startsWith("--nazov="))
    readonly property string action: rest[0] || "install"
    readonly property var pkgs: rest.slice(1).filter(p => /^[A-Za-z0-9._+-]+$/.test(p) || /^\/[^\s]+\.rpm$/.test(p))     // mená balíkov alebo cesta k .rpm
    // stav: info → heslo → beží → hotovo | chyba
    property string phase: "info"
    property string stepText: ""
    property real progress: 0
    property string log: ""
    property bool showLog: false
    property string sizeInfo: ""
    property string error: ""
    property bool quitWhenDone: false
    Process { id: tell }

    readonly property string heading: title || (action === "latteos" ? "Aktualizácia súčastí LatteOS" : action === "upgrade" ? "Aktualizácia systému" : (action === "remove" ? "Odstránenie" : "Inštalácia") + " · " + pkgs.join(", "))

    // veľkosť a zoznam z dnf (bez práv správcu, z cache)
    Process {
        id: infoProc; running: app.action === "install" && app.pkgs.length > 0
        command: ["sh", "-c", "LC_ALL=C dnf -q --cacheonly info \"$@\" 2>/dev/null | awk -F': ' '/^(Name|Size|Summary)/{print $1\"|\"$2}'", "sh"].concat(app.pkgs)
        stdout: StdioCollector {
            onStreamFinished: {
                const sizes = this.text.split("\n").filter(l => l.startsWith("Size")).map(l => l.split("|")[1]);
                const sum = this.text.split("\n").filter(l => l.startsWith("Summary")).map(l => l.split("|")[1]);
                app.sizeInfo = (sum[0] || "") + (sizes.length ? "  ·  veľkosť " + sizes.join(" + ") : "");
            }
        }
    }

    Process {
        id: dnf
        stdinEnabled: true                 // pred spustením zapnuté (write), po hesle sa zatvorí
        stdout: SplitParser { onRead: (l) => app.parse(l) }
        stderr: SplitParser { onRead: (l) => app.parse(l) }
        onExited: (code) => {
            if (code === 0) { app.phase = "hotovo"; app.progress = 1; app.stepText = "Hotovo"; }
            else {
                app.phase = "chyba";
                app.error = /incorrect password|nesprávne heslo|Sorry, try again|3 incorrect/i.test(app.log) ? "Nesprávne heslo správcu." : "Nepodarilo sa (kód " + code + "). Pozri Podrobnosti.";
            }
            if (app.quitWhenDone) {
                tell.command = ["notify-send", "-a", "LatteOS", "Inštalátor · " + app.heading, code === 0 ? "Hotovo" : app.error];
                tell.startDetached();
                Qt.quit();
            }
        }
    }
    function parse(l) {
        log += l + "\n";
        const m = l.match(/\[\s*(\d+)\s*\/\s*(\d+)\]\s*(.*)/);        // dnf5: [ 3/10] Installing balík
        if (m) {
            const n = parseInt(m[1]), tot = Math.max(1, parseInt(m[2]));
            progress = 0.1 + 0.9 * n / tot;
            const what = m[3];
            stepText = /Downloading|Sťahuje/i.test(what) ? "Sťahujem " + what.replace(/^\S+\s+/, "") : (/Install|Upgrad|Inštal|Aktual/i.test(what) ? "Inštalujem " + what.replace(/^\S+\s+/, "").split(" ")[0] : what);
        } else if (action === "latteos" && /^== /.test(l)) {          // kroky install-session.sh (~17)
            stepText = l.slice(3); progress = Math.min(0.97, progress + 0.055);
        } else if (/Downloading|Sťahovanie|Repositories loaded|Načítavanie/i.test(l)) { stepText = "Príprava a sťahovanie…"; progress = Math.max(progress, 0.05); }
        else if (/Nothing to do|Nie je čo robiť/i.test(l)) stepText = "Už je nainštalované / nie je čo robiť";
    }
    function start(pw) {
        phase = "bezi"; progress = 0.02; stepText = "Overujem heslo…"; log = "";
        if (action === "latteos") {
            // git pull ako používateľ, inštalácia s sudo -A (install-session.sh to podporuje); heslo iba cez stdin do súboru 0600
            dnf.command = ["sh", "-c",
                'umask 077; d="${XDG_RUNTIME_DIR:-/tmp}"; f=$(mktemp -p "$d" latteos-heslo.XXXXXX); a="$f.sh"; trap \'rm -f "$f" "$a"\' EXIT; '
                + 'IFS= read -r pw; printf "%s\\n" "$pw" > "$f"; unset pw; printf "#!/bin/sh\\ncat %s\\n" "$f" > "$a"; chmod 700 "$a"; '
                + 'export SUDO_ASKPASS="$a"; sudo -A -v || { echo "Sorry, try again."; exit 3; }; '
                + 'src=$(sed -n "s/^source=//p" /usr/share/latteos/VERSION); [ -d "$src/.git" ] || { echo "repozitár nenájdený"; exit 4; }; '
                + 'cd "$src" && git pull --ff-only && ./setup/f1/install-session.sh', "sh"];
            dnf.running = true;
            dnf.write(pw + "\n");
            dnf.stdinEnabled = false;
            return;
        }
        const cmd = action === "upgrade" ? ["upgrade", "-y"] : [action, "-y"].concat(pkgs);
        dnf.command = ["sudo", "-S", "-p", "", "dnf"].concat(cmd);
        dnf.running = true;
        dnf.write(pw + "\n");
        dnf.stdinEnabled = false;          // zatvoriť stdin: pri zlom hesle sudo skončí hneď, nečaká na ďalší pokus
    }

    FloatingWindow {

        onClosed: if (app.phase === "bezi") app.quitWhenDone = true; else Qt.quit()   // dnf sa neprerušuje: dobehne, oznámi, skončí
        title: "Inštalátor — LatteOS"
        implicitWidth: 620; implicitHeight: app.showLog ? 620 : 360
        color: theme.surface

        Column {
            anchors { fill: parent; margins: 28 }
            spacing: 14
            Row {
                spacing: 14
                Rectangle {
                    width: 56; height: 56; radius: 16; color: Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.16)
                    Glyph { anchors.centerIn: parent; name: app.action === "remove" ? "trash" : (app.action === "upgrade" || app.action === "latteos" ? "refresh" : "package"); size: 30; color: theme.primary }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; width: 480
                    Text { width: parent.width; elide: Text.ElideRight; text: app.heading; color: theme.fg; font { family: theme.fontDisplay; pixelSize: 21; weight: Font.DemiBold } }
                    Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                           text: app.sizeInfo || (app.action === "latteos" ? "Lišta, aplikácie a nastavenia LatteOS z repozitára" : app.action === "upgrade" ? "Systém a aplikácie z Fedory" : app.pkgs.join(" ")); color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                }
            }

            // heslo
            Column {
                visible: app.phase === "info" || app.phase === "chyba"
                width: parent.width; spacing: 8
                Text { width: parent.width; wrapMode: Text.WordWrap; color: app.phase === "chyba" ? theme.error : theme.fgDim; font { family: theme.fontUi; pixelSize: 13 }
                       text: app.phase === "chyba" ? app.error : "Systémové zmeny vyžadujú heslo správcu (tvoje heslo, ak si správca)." }
                Row {
                    spacing: 10
                    Rectangle {
                        width: 360; height: 42; radius: 10; color: theme.field; border { color: pw.activeFocus ? theme.primary : "transparent"; width: 1 }
                        TextInput {
                            id: pw
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password; passwordCharacter: "•"
                            color: theme.fg; font { family: theme.fontUi; pixelSize: 14 }
                            focus: true; Component.onCompleted: forceActiveFocus()
                            onAccepted: if (text !== "") { app.start(text); text = ""; }
                        }
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; visible: pw.text === ""; text: "Heslo správcu"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } }
                    }
                    Rectangle {
                        width: bt.implicitWidth + 30; height: 42; radius: 10; color: theme.primary
                        Text { id: bt; anchors.centerIn: parent; text: app.action === "remove" ? "Odstrániť" : (app.action === "upgrade" || app.action === "latteos" ? "Aktualizovať" : "Inštalovať"); color: theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        MouseArea { anchors.fill: parent; onClicked: if (pw.text !== "") { app.start(pw.text); pw.text = ""; } }
                    }
                }
            }

            // priebeh
            Column {
                visible: app.phase === "bezi" || app.phase === "hotovo"
                width: parent.width; spacing: 8
                Text { text: app.phase === "hotovo" ? "✓ Hotovo" : app.stepText; color: app.phase === "hotovo" ? theme.primary : theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                Rectangle {
                    width: parent.width; height: 8; radius: 4; color: theme.field
                    Rectangle { width: parent.width * app.progress; height: 8; radius: 4; color: theme.primary
                                Behavior on width { NumberAnimation { duration: theme.animMs * 2 } } }
                }
                Text { text: Math.round(app.progress * 100) + " %"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
            }

            Row {
                spacing: 10
                Rectangle {
                    width: lt.implicitWidth + 24; height: 34; radius: 10; color: lm.containsMouse ? theme.hover : theme.field
                    Text { id: lt; anchors.centerIn: parent; text: app.showLog ? "Skryť podrobnosti" : "Podrobnosti"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true; onClicked: app.showLog = !app.showLog }
                }
                Rectangle {
                    visible: app.phase === "hotovo" || app.phase === "info" || app.phase === "chyba"
                    width: ct.implicitWidth + 24; height: 34; radius: 10; color: app.phase === "hotovo" ? theme.primary : (cm.containsMouse ? theme.hover : theme.field)
                    Text { id: ct; anchors.centerIn: parent; text: app.phase === "hotovo" ? "Zavrieť" : "Zrušiť"; color: app.phase === "hotovo" ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: Qt.quit() }
                }
            }
            Rectangle {
                visible: app.showLog
                width: parent.width; height: 240; radius: 10; color: theme.field
                Flickable {
                    id: lf; anchors { fill: parent; margins: 10 }
                    ScrollHint { flick: lf; colors: theme }
                    contentHeight: lg.implicitHeight; clip: true
                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                    Text { id: lg; width: parent.width; wrapMode: Text.WrapAnywhere; text: app.log || "(zatiaľ nič)"; color: theme.fgDim; font { family: theme.fontMono; pixelSize: 11 } }
                }
            }
        }
    }
}
