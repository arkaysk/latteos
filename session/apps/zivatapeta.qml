// LatteOS — živá tapeta: pokojné pohyblivé textúry podľa materiálu témy nad tapetou, pod oknami.
// Vrstva Background nad tapetou Noctalie, priehľadná a neklikateľná (klik prejde na plochu). Jeden časovač hýbe desiatkami malých
// prvkov (žiadne shadery — beží aj pri softvérovom kreslení, stojí však CPU; vo VM je predvolene vypnutá).
// Scéna: ~/.config/latteos/live-wallpaper = tema | para | salka | bublinky | sneh | iskry | trblietky | prach
//        alebo video:/cesta/k/súboru (mp4, webm, mkv, animovaný gif/webp) — ako X Live Wallpaper, bez zvuku, v slučke
// „salka“: para stúpa zo šálky (loga LatteOS) na aktuálnej tapete (poloha z tapety, výplň crop); téma Mráz ju
// má ako svoju textúru. V hernom režime (~/.local/state/latteos/game-mode) a pri okne na celú obrazovku stojí.
// Spúšťa: latte-app zivatapeta (hyprland.lua pri štarte).
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "common"

ShellRoot {
    id: live
    LatteTheme { id: theme }

    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos"
    readonly property string state: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/latteos"
    property string pref: Quickshell.env("LATTE_APP_ARGS") || ""
    property string material: "sklo"
    property bool game: false
    readonly property var byMaterial: ({ sklo: "para", jantar: "bublinky", mraz: "salka", kov: "iskry", fazety: "trblietky", kamen: "prach" })
    readonly property string video: pref.startsWith("video:") ? pref.slice(6) : ""
    readonly property bool animated: /\.(gif|webp)$/i.test(video)
    // video (VideoOutput) potrebuje grafickú akceleráciu; pri softvérovom kreslení (stupeň Softvér/SAFE) iba GIF/WebP
    readonly property bool softGfx: Quickshell.env("QT_QUICK_BACKEND") === "software"
    readonly property bool videoBlocked: video !== "" && !animated && softGfx
    Process { id: tellNoVideo; command: ["notify-send", "-a", "LatteOS", "-i", "video-display", "Živá tapeta: video nejde",
                                         "Video potrebuje grafickú akceleráciu (v stupni Softvér, napr. vo VM, ju nemáš). Animovaný GIF alebo WebP funguje."] }
    onVideoBlockedChanged: if (videoBlocked) tellNoVideo.running = true
    Component.onCompleted: if (videoBlocked) tellNoVideo.running = true
    readonly property string scene: video !== "" ? "" : ((pref === "" || pref === "tema") ? (byMaterial[material] || "") : pref)
    property bool fullscreen: false
    readonly property bool running: (scene !== "" || video !== "") && !game && !fullscreen
    // šálky na tapetách LatteOS (súradnice v obrázku): logo = horná hrana šálky z loga, odkiaľ stúpa para
    // šálky na tapetách LatteOS (súradnice v obrázku): logo = horná hrana šálky z loga, cup = skutočná šálka;
    // ak je logo po orezaní (výplň crop) príliš hore, para stúpa zo skutočnej šálky
    readonly property var cups: ({
        "latteos-wallpaper1.jpg": { w: 1264, h: 843, logo: [1068, 96, 60], cup: [640, 415, 120] },
        "latteos-wallpaper2.jpg": { w: 1264, h: 843, logo: [1070, 108, 60], cup: [622, 427, 110] },
        "latteos-wallpaper3.jpg": { w: 1264, h: 843, logo: [1068, 96, 60], cup: [625, 415, 150] },
        "latteos-wallpaper4.jpg": { w: 1326, h: 800, logo: [1142, 72, 60], cup: [650, 390, 110] }
    })
    Process {
        id: fsProbe
        command: ["sh", "-c", "hyprctl -j activewindow 2>/dev/null | grep -q '\"fullscreen\": 2' && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: live.fullscreen = this.text.trim() === "1" }
    }
    Timer { interval: 2000; repeat: true; running: live.scene !== "" || live.video !== ""; triggeredOnStart: true; onTriggered: if (!fsProbe.running) fsProbe.running = true }

    FileView { path: live.cfg + "/live-wallpaper"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: if (Quickshell.env("LATTE_APP_ARGS") === "") live.pref = text().trim() || "tema"
               onLoadFailed: if (Quickshell.env("LATTE_APP_ARGS") === "") Qt.quit() }       // vypnuté → skončiť
    FileView { path: "/usr/share/latteos/themes/" + theme.themeId + ".theme"; printErrors: false
               onLoaded: { const m = text().match(/^material = (\w+)/m); live.material = m ? m[1] : ""; } }
    FileView { path: live.state + "/game-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: live.game = text().trim() === "1"; onLoadFailed: live.game = false }

    // parametre scén: počet, smer (vy < 0 = hore), veľkosť, tvar, trvanie života v krokoch
    readonly property var scenes: ({
        para:      { n: 22, vx: 0.15, vy: -0.9, size: [30, 90], round: true,  alpha: 0.05, life: 420, spawn: "bottom", wobble: 0.6, color: "fg" },
        bublinky:  { n: 26, vx: 0.0,  vy: -0.7, size: [6, 22],   round: true,  alpha: 0.35, life: 400, spawn: "bottom", wobble: 0.4, ring: true, color: "primary" },
        sneh:      { n: 40, vx: 0.2,  vy: 0.8,  size: [3, 8],    round: true,  alpha: 0.55, life: 700, spawn: "top",    wobble: 0.8, color: "fg" },
        iskry:     { n: 6,  vx: 3.5,  vy: 0.0,  size: [180, 320], round: false, alpha: 0.06, life: 260, spawn: "left",   wobble: 0.0, streak: true, color: "fg" },
        trblietky: { n: 30, vx: 0.0,  vy: 0.0,  size: [3, 7],    round: true,  alpha: 0.8,  life: 90,  spawn: "any",    wobble: 0.0, twinkle: true, color: "primary" },
        prach:     { n: 30, vx: 0.12, vy: -0.05, size: [2, 5],   round: true,  alpha: 0.35, life: 900, spawn: "any",    wobble: 0.3, color: "fg" },
        salka:     { n: 16, vx: 0.08, vy: -0.55, size: [10, 30], round: true, alpha: 0.30, life: 200, spawn: "cup",    wobble: 0.55, color: "steam", grow: true }
    })

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // vrstva Background nad tapetou Noctalie (ikony plochy vo vrstve Bottom sú vždy nad ňou); keď Noctalia
            // otvorí svoju tapetu znova (reštart shellu), vrstva sa prevesí navrch (znovu namapuje)
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "latte-live-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}                       // klik prejde na plochu pod ňou
            visible: (live.scene !== "" || live.video !== "") && !remap
            property bool remap: false
            Connections {
                target: Hyprland
                function onRawEvent(ev) { if (ev.name === "openlayer" && String(ev.data).startsWith("noctalia-wallpaper")) { win.remap = true; remapT.restart(); } }
            }
            Timer { id: remapT; interval: 400; onTriggered: win.remap = false }

            // video alebo animácia ako tapeta (pod textúrami); zvuk vypnutý, v slučke, stojí pri hre a celej obrazovke
            Loader {
                anchors.fill: parent
                active: live.video !== "" && !live.videoBlocked
                sourceComponent: live.animated ? animComp : videoComp
            }
            Component {
                id: animComp
                AnimatedImage { source: "file://" + live.video; fillMode: Image.PreserveAspectCrop; playing: live.running; cache: false }
            }
            Component {
                id: videoComp
                Item {
                    MediaPlayer {
                        id: mp
                        source: "file://" + live.video
                        loops: MediaPlayer.Infinite
                        videoOutput: vo
                        Component.onCompleted: if (live.running) play()
                    }
                    Connections { target: live; function onRunningChanged() { if (live.running) mp.play(); else mp.pause(); } }
                    VideoOutput { id: vo; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                }
            }

            // šálka na tapete tejto obrazovky → bod na obrazovke (výplň crop = zväčšiť a vycentrovať)
            property var cup: null
            Process {
                id: wpGet
                command: ["noctalia", "msg", "wallpaper-get", win.modelData.name]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const c = live.cups[this.text.trim().split("/").pop()];
                        if (!c) { win.cup = null; return; }
                        const sc = Math.max(win.width / c.w, win.height / c.h);
                        const map = (pt) => ({ x: (win.width - c.w * sc) / 2 + pt[0] * sc, y: (win.height - c.h * sc) / 2 + pt[1] * sc, spread: pt[2] * sc });
                        const logo = map(c.logo);
                        win.cup = logo.y >= 80 ? logo : map(c.cup);
                    }
                }
            }
            Timer { interval: 10000; repeat: true; running: live.scene === "salka"; triggeredOnStart: true; onTriggered: if (win.width > 0) wpGet.running = true }

            property var parts: []
            property int frame: 0             // polia v JS objektoch nie sú sledované → väzby závisia od frame
            readonly property var sp: live.scenes[live.scene] || live.scenes.para
            function spawn(p, fresh) {
                const s = sp, w = win.width, h = win.height;
                p.size = s.size[0] + Math.random() * (s.size[1] - s.size[0]);
                // prvé rozmiestnenie po celej obrazovke, ďalšie zrodenie na okraji, odkiaľ scéna prichádza
                if (s.spawn === "cup") {             // para zo šálky; bez známej šálky zdola ako „para“
                    const c = win.cup || { x: w * 0.5, y: h + 20, spread: w * 0.4 };
                    p.x = c.x + (Math.random() - 0.5) * c.spread - p.size / 2;
                    p.y = c.y - p.size / 2;
                    p.age = fresh ? Math.floor(Math.random() * s.life) : 0;
                    if (fresh) p.y -= p.age * Math.abs(s.vy) * 0.8;
                    p.base = p.size;
                    p.seed = Math.random() * 6.28;
                    return p;
                }
                p.x = (s.spawn === "left" && !fresh) ? -p.size : Math.random() * w;
                p.y = fresh || s.spawn === "any" || s.spawn === "left" ? Math.random() * h : (s.spawn === "bottom" ? h + p.size : -p.size);
                p.age = fresh ? Math.floor(Math.random() * s.life) : 0;
                p.seed = Math.random() * 6.28;
                return p;
            }
            function reset() { const a = []; for (let i = 0; i < sp.n; i++) a.push(spawn({}, true)); parts = a; }
            // rozmiestniť až keď okno pozná veľkosť (pri vytvorení je 0 × 0)
            onWidthChanged: if (width > 0 && height > 0) reset()
            onHeightChanged: if (width > 0 && height > 0) reset()
            onSpChanged: if (width > 0 && height > 0) reset()
            onCupChanged: if (live.scene === "salka" && width > 0) reset()

            Timer {
                interval: 50; repeat: true; running: live.running && win.visible     // 20 obr/s, v hernom režime stojí
                onTriggered: {
                    const s = win.sp, a = win.parts;
                    for (const p of a) {
                        p.age++;
                        if (s.grow) p.size = p.base * (1 + p.age / s.life * 1.6);      // obláčik sa pri stúpaní rozplýva
                        p.x += s.vx * (1 + p.size / 60) + Math.sin(p.age / 30 + p.seed) * s.wobble;
                        p.y += s.vy * (1 + p.size / 80);
                        const out = (s.vy < 0 && p.y < -p.size * 2) || (s.vy > 0 && p.y > win.height + p.size * 2)
                                 || (s.vx > 1 && p.x > win.width + p.size) || p.age > s.life;
                        if (out) win.spawn(p, false);
                    }
                    win.frame++;
                }
            }
            Repeater {
                model: win.parts.length
                Rectangle {
                    required property int index
                    readonly property var p: (win.frame, win.parts[index]) || { x: 0, y: 0, size: 0, age: 0, seed: 0 }
                    readonly property var s: win.sp
                    x: (win.frame, p.x); y: (win.frame, p.y)
                    width: (win.frame, p.size); height: s.streak ? 2 : (win.frame, p.size)
                    radius: s.round ? height / 2 : 1
                    rotation: s.streak ? -12 : 0
                    color: s.ring ? "transparent" : (s.color === "primary" ? theme.primary : (s.color === "steam" ? "#FFFFFF" : theme.fg))
                    border { width: s.ring ? 1.5 : 0; color: theme.primary }
                    // mäkký nástup a doznenie; trblietky blikajú
                    opacity: (win.frame, s.alpha) * (s.twinkle ? Math.max(0, Math.sin(p.age / s.life * 3.14159))
                                                  : Math.min(1, p.age / 30, (s.life - p.age) / 40))
                }
            }
        }
    }
}
