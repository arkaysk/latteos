// Scena — animovaná textúra lišty a kmeňa L (stará verzia: latte_common/scenes.py, docs/lista-a-rohy.md, časť 4).
//   spec:  para · matrix · gears (ozubené kolesá) · glow (pomalé svetlo) · solid:#RRGGBB · file:/cesta (GIF, WebP, obrázok)
// Obraz je čistá funkcia času a polohy na spoločnom plátne (ox, oy = posun tohto výseku), takže päta v lište a kmeň
// nad ňou kreslia ten istý obraz vo fáze a bez švu. Pohyb pasívny a pokojný (cyklus 6–12 s), softvér ~8 obr/s, GPU 24.
// motion: vzdy · kurzor (iba keď awake) · vypnute (statický snímok).
// Všetko (aj GIF) sa kreslí do jedného Canvasu, orezané na tvar výseku (radii: zaoblené rohy, napr. päta = ostrov
// lišty), preto sedí s obrysom okna v tvare L. GIF môžu viaceré výseky zdieľať (image: spoločný AnimatedImage),
// takže päta, kmeň aj dlaždica na lište ukazujú ten istý snímok.
import QtQuick
import Quickshell

Item {
    id: sc
    required property var colors
    property string spec: "para"
    property string motion: "vzdy"
    property bool awake: true
    property real ox: 0                     // poloha výseku na spoločnom plátne
    property real oy: 0
    property real canvasW: width            // šírka celého plátna (kvôli rozloženiu stĺpcov / kolies)
    property real canvasH: height
    property real time: 0                   // spoločný čas (nastaví rodič, aby výseky boli vo fáze)
    property bool mirror: false             // pravý roh: zrkadlová geometria
    property var radii: [0, 0, 0, 0]        // orezanie výseku: tl, tr, br, bl
    property var image: null                // spoločný AnimatedImage (inak si výsek vytvorí vlastný)
    property int frame: -1                  // číslo snímku zo spoločného zdroja (GifZdroj.frame); -1 = podľa AnimatedImage
    onFrameChanged: if (kind === "file") cv.requestPaint()
    property string frameDir: ""            // snímky GIF ako PNG (latte-tapety snimky): Canvas kreslí aktuálny snímok
    property int frameCount: 0
    // ohnisko pohybu GIF (podiel šírky/výšky, z latte-tapety snimky) a bod plátna, kam má padnúť (stred ostrova na lište):
    // obraz sa zväčší a posunie, aby ostrov ukazoval práve pohyblivú časť; všetky výseky počítajú rovnako → bez švu
    property var ohnisko: null
    property real anchorX: canvasW / 2
    property real anchorY: canvasH / 2
    property color base: colors.surfaceVariant   // podklad pod textúrou
    property var dim: null                  // stlmenie pod textom [alfa vľavo, alfa vpravo] farbou dimColor, orezané s výsekom
    property color dimColor: colors.surface
    readonly property bool gpu: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    readonly property int fps: gpu ? 24 : 8
    readonly property bool moving: motion === "vzdy" || (motion === "kurzor" && awake)
    readonly property string kind: spec.indexOf(":") > 0 ? spec.slice(0, spec.indexOf(":")) : spec
    readonly property string arg: spec.indexOf(":") > 0 ? spec.slice(spec.indexOf(":") + 1) : ""
    readonly property var img: image || ownImg

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    AnimatedImage {
        id: ownImg
        visible: false
        source: !sc.image && sc.kind === "file" ? "file://" + sc.arg : ""
        playing: status === AnimatedImage.Ready && sc.moving && sc.kind === "file" && !sc.image; cache: false; asynchronous: true
    }
    Connections { target: sc.img; function onFrameChanged() { if (sc.kind === "file") cv.requestPaint(); }
                  function onStatusChanged() { cv.requestPaint(); } ignoreUnknownSignals: true }

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        property real t: sc.time
        onTChanged: if (sc.kind !== "file" && sc.kind !== "solid") requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onImageLoaded: requestPaint()
        function frameUrl(i) { return "file://" + sc.frameDir + "/" + ("00" + (i + 1)).slice(-3) + ".png"; }
        Connections { target: sc; function onFrameDirChanged() { if (sc.frameDir) for (let i = 0; i < sc.frameCount; i++) cv.loadImage(cv.frameUrl(i)); } }
        Component.onCompleted: if (sc.frameDir) for (let i = 0; i < sc.frameCount; i++) loadImage(frameUrl(i))
        Connections { target: sc; function onOhniskoChanged() { cv.requestPaint(); } function onAnchorXChanged() { cv.requestPaint(); }
                      function onSpecChanged() { cv.requestPaint(); } function onOxChanged() { cv.requestPaint(); }
                      function onOyChanged() { cv.requestPaint(); } function onRadiiChanged() { cv.requestPaint(); }
                      function onDimChanged() { cv.requestPaint(); } }
        onPaint: {
            const c = getContext("2d"); c.reset();
            const w = width, h = height, R = sc.radii || [0, 0, 0, 0];
            // tvar výseku (zaoblené rohy) → orezanie
            c.beginPath();
            c.moveTo(R[0], 0); c.lineTo(w - R[1], 0); if (R[1]) c.arcTo(w, 0, w, R[1], R[1]);
            c.lineTo(w, h - R[2]); if (R[2]) c.arcTo(w, h, w - R[2], h, R[2]);
            c.lineTo(R[3], h); if (R[3]) c.arcTo(0, h, 0, h - R[3], R[3]);
            c.lineTo(0, R[0]); if (R[0]) c.arcTo(0, 0, R[0], 0, R[0]);
            c.closePath();
            c.clip();
            paintScene(c, w, h);
            if (sc.dim && sc.dim.length === 2) {
                const g = c.createLinearGradient(0, 0, w, 0), d = sc.dimColor;
                g.addColorStop(0, Qt.rgba(d.r, d.g, d.b, sc.dim[0])); g.addColorStop(1, Qt.rgba(d.r, d.g, d.b, sc.dim[1]));
                c.fillStyle = g; c.fillRect(0, 0, w, h);
            }
        }
        function paintScene(c, w, h) {
            c.fillStyle = sc.kind === "solid" ? (sc.arg || sc.base) : sc.base;
            c.fillRect(0, 0, w, h);
            if (sc.kind === "solid") return;
            const W = sc.canvasW, H = sc.canvasH, ox = sc.ox, oy = sc.oy, t = sc.time, pc = sc.colors.primary;
            if (sc.kind === "file") {
                // obrázok / GIF vyplní celé spoločné plátno (orezanie na stred), výsek z neho ukáže svoju časť
                const im = sc.img;
                if (!im || im.status !== Image.Ready || !im.implicitWidth) return;
                const iw = im.implicitWidth, ih = im.implicitHeight, kc = Math.max(W / iw, H / ih);
                let k = kc, dx0, dy0;
                if (sc.ohnisko && sc.ohnisko.length === 2) {
                    const fx = sc.ohnisko[0] * iw, fy = sc.ohnisko[1] * ih, ax = sc.anchorX, ay = sc.anchorY;
                    if (fx > 0) k = Math.max(k, ax / fx);
                    if (iw - fx > 0) k = Math.max(k, (W - ax) / (iw - fx));
                    if (fy > 0) k = Math.max(k, ay / fy);
                    if (ih - fy > 0) k = Math.max(k, (H - ay) / (ih - fy));
                    k = Math.min(k, kc * 3);
                    dx0 = Math.min(0, Math.max(W - iw * k, ax - fx * k));
                    dy0 = Math.min(0, Math.max(H - ih * k, ay - fy * k));
                } else { dx0 = (W - iw * k) / 2; dy0 = (H - ih * k) / 2; }
                const dw = iw * k, dh = ih * k;
                // Canvas si obrázok položky pamätá ako prvý snímok → animácia ide zo snímok PNG podľa currentFrame
                const u = sc.frameDir && sc.frameCount ? frameUrl(Math.min(sc.frameCount - 1, Math.max(0, sc.frame >= 0 ? sc.frame : im.currentFrame))) : "";
                if (u && isImageLoaded(u)) c.drawImage(u, dx0 - ox, dy0 - oy, dw, dh);
                else c.drawImage(im, dx0 - ox, dy0 - oy, dw, dh);
                return;
            }
            c.save(); c.translate(-ox, -oy);
            if (sc.mirror && sc.kind !== "matrix") { c.translate(W, 0); c.scale(-1, 1); }   // písmená sa nezrkadlia
            if (sc.kind === "para") {                   // stĺpce ako para nad šálkou, pomaly dýchajú
                const n = Math.max(6, Math.floor(W / 9));
                for (let i = 0; i < n; i++) {
                    const x = 4 + i * (W - 8) / n, ph = t * (2 * Math.PI / 8) + i * 0.7;
                    const bh = H * (0.25 + 0.55 * (0.5 + 0.5 * Math.sin(ph))) * (1 - 0.35 * (i / n));
                    c.fillStyle = sc.rgba(pc, 0.16 + 0.26 * (1 - i / n));
                    c.fillRect(x, H - bh - 3, 3, bh);
                }
            } else if (sc.kind === "matrix") {          // stekajúci kód v akcente motívu
                const cw = 9, cols = Math.ceil(W / cw), rows = Math.ceil(H / 11), chars = "01LATTE7392ABCDEF";
                c.font = "bold 9px monospace";
                for (let i = 0; i < cols; i++) {
                    const speed = 0.6 + ((i * 37) % 11) / 11, head = ((t * speed * 4 + i * 5.3) % (rows + 8)) - 4;
                    for (let r = 0; r < rows; r++) {
                        const d = head - r; if (d < 0 || d > 7) continue;
                        c.fillStyle = sc.rgba(pc, d < 0.9 ? 0.95 : 0.55 * (1 - d / 8));
                        c.fillText(chars[(i * 7 + r * 3 + Math.floor(t * 2)) % chars.length], i * cw + 1, r * 11 + 9);
                    }
                }
            } else if (sc.kind === "gears") {           // ozubené prevody, pomalé otáčanie
                const gear = (cx, cy, r, teeth, ang, alpha) => {
                    c.beginPath();
                    for (let k = 0; k < teeth * 2; k++) {
                        const a0 = ang + k * Math.PI / teeth, rr = k % 2 ? r * 0.82 : r;
                        c.lineTo(cx + Math.cos(a0) * rr, cy + Math.sin(a0) * rr);
                        c.lineTo(cx + Math.cos(a0 + Math.PI / teeth * 0.6) * rr, cy + Math.sin(a0 + Math.PI / teeth * 0.6) * rr);
                    }
                    c.closePath(); c.fillStyle = sc.rgba(pc, alpha); c.fill();
                    c.beginPath(); c.arc(cx, cy, r * 0.32, 0, 2 * Math.PI); c.fillStyle = sc.base; c.fill();
                };
                const RR = H * 0.42;
                let x = RR * 0.9, big = true, i = 0;
                while (x < W + RR) {
                    const r = big ? RR : RR * 0.62, teeth = big ? 12 : 8, dir = i % 2 ? -1 : 1;
                    gear(x, H * (big ? 0.62 : 0.4), r, teeth, dir * t * (0.5 / (r / RR)) + i, big ? 0.28 : 0.2);
                    x += r * 1.72; big = !big; i++;
                }
            } else if (sc.kind === "glow") {            // pomalé svetlo: mäkké škvrny po dráhach
                for (let k = 0; k < 5; k++) {
                    const cx = W * (0.5 + 0.45 * Math.sin(t * 0.13 + k * 1.7)), cy = H * (0.5 + 0.4 * Math.cos(t * 0.17 + k * 2.3)), r = H * (0.9 + 0.3 * k);
                    const g = c.createRadialGradient(cx, cy, 0, cx, cy, r);
                    g.addColorStop(0, sc.rgba(pc, 0.28)); g.addColorStop(1, sc.rgba(pc, 0));
                    c.fillStyle = g; c.fillRect(0, 0, W, H);
                }
            }
            c.restore();
        }
    }
}
