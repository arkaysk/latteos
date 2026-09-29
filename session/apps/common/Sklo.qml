// Sklo — softvérové matné sklo pre panely LatteOS (ROADMAP F3): výrez rozmazanej tapety (latte-sklo → ~/.cache/latteos/
// sklo.png) presne pod panelom + tónovanie farbou témy. Bez shaderov a bez GPU (Canvas s orezaním na zaoblené rohy),
// takže funguje aj vo VM. Vypnutie: ~/.config/latteos/sklo = off (potom plná farba ako doteraz).
//   screenX/screenY = poloha ľavého horného rohu panelu na obrazovke, radii = [ľh, ph, pd, ľd], tint = krytie farby témy
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: sk
    required property var theme
    property real screenX: 0
    property real screenY: 0
    property var radii: [16, 16, 16, 16]
    property real tint: 0.78
    property bool on: true
    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string cache: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/latteos"
    property string src: ""
    property bool enabledPref: true

    FileView { path: (Quickshell.env("XDG_CONFIG_HOME") || (sk.home + "/.config")) + "/latteos/sklo"; printErrors: false; watchChanges: true
               onFileChanged: reload(); onLoaded: sk.enabledPref = text().trim() !== "off"; onLoadFailed: sk.enabledPref = true }
    // nová rozmazaná tapeta (latte-sklo zapíše sklo.json) → načítať znova
    FileView { path: sk.cache + "/sklo.json"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: { sk.src = "file://" + sk.cache + "/sklo.png?" + Qt.md5(text()); cv.loadImage(sk.src); } }
    Process { id: gen; command: ["latte-sklo"] }
    onVisibleChanged: if (visible && on && enabledPref && !gen.running) gen.running = true     // tapeta sa mohla zmeniť
    Component.onCompleted: if (on && enabledPref) gen.running = true
    readonly property bool active: on && enabledPref && src !== ""

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        readonly property real sig: sk.screenX + sk.screenY * 7 + width * 13 + height * 17 + (sk.active ? 1 : 0)
        onSigChanged: requestPaint()
        onImageLoaded: requestPaint()
        onPaint: {
            const c = getContext("2d"), w = width, h = height, R = sk.radii;
            c.reset();
            if (w < 1 || h < 1) return;
            c.beginPath();
            c.moveTo(R[0], 0); c.lineTo(w - R[1], 0); if (R[1]) c.arcTo(w, 0, w, R[1], R[1]);
            c.lineTo(w, h - R[2]); if (R[2]) c.arcTo(w, h, w - R[2], h, R[2]);
            c.lineTo(R[3], h); if (R[3]) c.arcTo(0, h, 0, h - R[3], R[3]);
            c.lineTo(0, R[0]); if (R[0]) c.arcTo(0, 0, R[0], 0, R[0]);
            c.closePath(); c.clip();
            const t = sk.theme.surface;
            if (sk.active && isImageLoaded(sk.src)) {
                c.drawImage(sk.src, sk.screenX, sk.screenY, w, h, 0, 0, w, h);
                c.fillStyle = Qt.rgba(t.r, t.g, t.b, sk.tint);
            } else c.fillStyle = t;
            c.fillRect(0, 0, w, h);
        }
    }
}
