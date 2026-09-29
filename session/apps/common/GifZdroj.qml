// GifZdroj — jeden zdroj GIF / WebP textúry pre okná L, dlaždicu na lište aj náhľad v Nastaveniach (rovnaký obraz všade).
//   image     skrytý AnimatedImage (určuje aktuálny snímok a časovanie)
//   frameDir  snímky ako PNG (latte-tapety snimky) — Canvas by z AnimatedImage kreslil stále prvý snímok
//   ohnisko   kde sa v animácii niečo hýbe (podiel šírky/výšky); ostrov na lište ho ukáže. Vypnuté voľbou
//             „celý obrázok“ (~/.config/latteos/bar-priblizenie = off) → obraz sa iba vyplní a vycentruje.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: gz
    property string spec: ""
    property bool playing: true
    readonly property bool isFile: spec.startsWith("file:")
    readonly property alias image: gif
    property string frameDir: ""
    property int frameCount: 0
    property var focusRaw: null
    property bool zoom: true
    readonly property var ohnisko: zoom ? focusRaw : null
    visible: false

    FileView { path: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/latteos/bar-priblizenie"
               printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: gz.zoom = text().trim() !== "off"; onLoadFailed: gz.zoom = true }
    // Optimalizácia (26. 9.): každá snímka stojí kompozitor celé prekreslenie obrazovky (pri softvérovom kreslení
    // ~7 % CPU za snímku/s). GIF preto nehrá vlastným tempom (napr. 20 snímok/s), ale krokuje časovač najviac
    // 8 snímok/s bez GPU (24 s GPU) a preskakuje snímky tak, aby animácia bežala rovnakou rýchlosťou.
    readonly property bool gpu: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    readonly property int maxFps: gpu ? 24 : 8
    property int frame: 0                      // aktuálny snímok (Scena kreslí PNG snímok s týmto číslom)
    property int delay: 100                    // ms na snímku podľa GIF (latte-tapety snimky)
    readonly property int step: Math.max(1, Math.ceil(1000 / maxFps / Math.max(1, delay)))
    readonly property int tickMs: step * Math.max(1, delay)      // presne pôvodné tempo animácie
    AnimatedImage {
        id: gif
        visible: false
        source: gz.isFile ? "file://" + gz.spec.slice(5) : ""
        playing: false                         // iba rozmer a záložné kreslenie; snímky počíta „frame“ nižšie
        cache: false; asynchronous: true
    }
    // okno na celú obrazovku (film, hra) zakrýva lištu → GIF stojí (udalosť z IPC Hyprlandu, žiadny polling)
    CelaObrazovka { id: cela }
    readonly property bool fullscreen: cela.active                    // maximalizované okno GIF nezastaví
    // pokoj: obrazovka je zamknutá (hook Noctalie session_locked) → GIF stojí
    property bool pokoj: false
    FileView { path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos/pokoj"; printErrors: false; watchChanges: true
               onFileChanged: reload(); onLoaded: gz.pokoj = true; onLoadFailed: gz.pokoj = false }
    Timer { interval: 5000; repeat: true; running: gz.pokoj; onTriggered: pokojCheck.running = true }   // zmazanie súboru inotify nenahlási vždy
    Process { id: pokojCheck; command: ["test", "-e", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos/pokoj"]; onExited: (c) => gz.pokoj = c === 0 }
    Timer {
        interval: gz.tickMs; repeat: true
        running: gif.status === AnimatedImage.Ready && gz.isFile && gz.playing && !gz.pokoj && !gz.fullscreen && gif.frameCount > 1
        onTriggered: gz.frame = (gz.frame + gz.step) % gif.frameCount
    }
    // priamo zo spec (v onSpecChanged ešte nemusia byť prepočítané odvodené vlastnosti)
    function loadFrames() {
        frameDir = ""; frameCount = 0; focusRaw = null;
        if (/^file:.*\.(gif|webp)$/i.test(spec)) { frames.running = false; frames.command = ["latte-tapety", "snimky", spec.slice(5)]; frames.running = true; }
    }
    onSpecChanged: loadFrames()
    Component.onCompleted: loadFrames()
    Process {
        id: frames
        stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(this.text); gz.frameCount = j.count; gz.focusRaw = j.focus || null; gz.frameDir = j.dir; gz.delay = j.delay || 100; } catch (e) {} } }
    }
}
