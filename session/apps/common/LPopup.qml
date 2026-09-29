// LPopup — vyskakovacie okno v tvare L, ktoré vyrastie z ostrova na lište (zadanie 25. 9., kresba; stará verzia:
// docs/lista-a-rohy.md, časť 3 a src/latte_shell/reveal.py).
//   päta  = ostrov na lište (foot: {x, y, w, h} v súradniciach obrazovky, z latte-ostrovy); pri otvorení sa
//           nakreslí presne na ostrov, s textúrou
//   kmeň  = pás nad lištou (trunkH) cez celú šírku panelu: textúra + informácie (obsah `trunk`)
//   panel = obsah nad kmeňom (predvolený obsah komponentu)
// Medzi kmeňom a pätou je vyduté zaoblenie (tvar L z kresby). Otváranie: kmeň sa vysunie z hornej hrany päty
// (šírka aj výška naraz, spomalený dobeh), v druhej polovici sa objaví panel. Zatváranie opačne.
// GIF / obrázok (framed): päta bez ikony, ostrov má rám (TileOverlay) a ten sa pri otváraní plynulo roztiahne na obrys
// celého L — pri p = 0 obrys presne kopíruje ostrov (všetky rohy zaoblené), kmeň rastie z jeho hornej hrany.
// side: "left" (App Manager vľavo) alebo "right" (Zariadenia vpravo, zrkadlovo; obsah sa nezrkadlí).
import QtQuick
import Quickshell

Item {
    id: lp
    required property var theme
    property var foot: ({ x: 12, y: 896, w: 100, h: 42 })
    property string side: "left"
    property real panelW: 660
    property real panelH: 560
    property real trunkH: 50
    property bool open: false
    property string sceneSpec: "para"
    property string motion: "vzdy"
    property real dim: 0.55                 // stlmenie textúry pod textom kmeňa
    property var islands: []                // všetky ostrovy lišty (latte-ostrovy): L nesmie prekryť susedné položky
    property real gap: 10                   // medzera kmeňa nad lištou, ako maximalizované okno (Hyprland gaps_out)
    property string footGlyph: ""           // ikona ostrova (päta ho prekryje, preto ju nakreslí znova; pri GIF / obrázku nie)
    readonly property bool framed: sceneSpec.startsWith("file:")
    readonly property color frameColor: framed ? theme.primary : theme.outline
    readonly property real frameWidth: framed ? 1.5 : 1
    property int frame: -1                  // snímok zo spoločného GifZdroj
    property var image: null                // spoločný AnimatedImage pre GIF textúru (päta, kmeň aj dlaždica na lište)
    property string frameDir: ""            // snímky GIF ako PNG (z TileOverlay)
    property int frameCount: 0
    property var ohnisko: null                // ohnisko pohybu GIF → padne do ostrova (ako v TileOverlay)
    property real footRadius: 16            // zaoblenie ostrova na lište (capsule_radius)
    readonly property real panelRadius: 22
    default property alias content: body.data
    property alias trunk: trunkContent.data
    readonly property bool anim: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    readonly property int openMs: anim ? 380 : 220
    property real p: 0                      // 0 zatvorené … 1 otvorené
    signal closed()
    anchors.fill: parent

    onOpenChanged: { pa.stop(); pa.from = p; pa.to = open ? 1 : 0; pa.duration = (open ? openMs : openMs * 0.8) * Math.abs(pa.to - p); pa.start(); }
    NumberAnimation { id: pa; target: lp; property: "p"; easing.type: Easing.Linear; onFinished: if (!lp.open) lp.closed() }
    function easeOut(x) { x = Math.max(0, Math.min(1, x)); return 1 - Math.pow(1 - x, 3); }
    function smooth(x) { x = Math.max(0, Math.min(1, x)); return x * x * (3 - 2 * x); }
    readonly property real armP: easeOut(p / 0.75)
    readonly property real panelP: smooth((p - 0.5) / 0.5)

    // geometria (obrazovka): pravý roh je zrkadlový
    readonly property bool isRight: side === "right"
    readonly property real footBottom: foot.y + foot.h
    readonly property real left0: isRight ? foot.x + foot.w - panelW : foot.x
    readonly property real armW: foot.w + (panelW - foot.w) * armP
    readonly property real armX: isRight ? foot.x + foot.w - armW : foot.x
    // spodok kmeňa = vrch najvyššieho ostrova pod panelom (iné položky lišty ostanú celé viditeľné)
    readonly property real barTop: {
        let t = foot.y;
        for (const o of islands) if (o.x < left0 + panelW && o.x + o.w > left0) t = Math.min(t, o.y);
        return t;
    }
    // voľné miesto vedľa päty smerom k panelu (vyduté zaoblenie sa zmestí iba do medzery k susedovi)
    readonly property real sideGap: {
        let g = 16;
        for (const o of islands) {
            if (o.x === foot.x && o.w === foot.w) continue;
            if (!isRight && o.x >= foot.x + foot.w) g = Math.min(g, o.x - (foot.x + foot.w) - 1);
            if (isRight && o.x + o.w <= foot.x) g = Math.min(g, foot.x - (o.x + o.w) - 1);
        }
        return Math.max(0, g);
    }
    readonly property real trunkBottom: barTop - gap
    // spodok kmeňa počas otvárania: vychádza z hornej hrany ostrova a dvíha sa do medzery nad lištou
    readonly property real tbE: foot.y - (foot.y - trunkBottom) * armP
    readonly property real trunkY: tbE - trunkH * armP
    readonly property real rad: 16
    // spoločné plátno textúry (kmeň + päta); TileOverlay na lište ukazuje ten istý výsek päty
    readonly property real sceneH: trunkH + foot.y + foot.h - trunkBottom
    readonly property real sceneTop: trunkBottom - trunkH          // vrch plátna na obrazovke (pevný počas animácie)
    readonly property real footOx: foot.x - left0
    readonly property real footTopR: footRadius * (1 - armP)       // horné rohy päty: kým kmeň nevyrastie, päta = ostrov
    // rohy obrysu (spoločné pre obrys aj orezanie textúry): pri p = 0 rohy ostrova, potom rohy panelu
    readonly property real shapeTop: panelP > 0.01 ? trunkY - panelH * panelP : trunkY
    readonly property real roomW: Math.max(0, (armW - foot.w) / 2)
    readonly property real rOuter: Math.min(footRadius + (panelRadius - footRadius) * armP, (foot.y + foot.h - shapeTop) / 2)
    readonly property real rFar: roomW >= 1 ? Math.min(rOuter, (tbE - shapeTop) / 2) : rOuter   // kmeň je spočiatku nízky
    readonly property real rTrunk: Math.min(rad, roomW, (tbE - shapeTop) / 2)

    // spoločný čas textúry (päta a kmeň kreslia ten istý obraz vo fáze)
    property real t: 0
    Timer { interval: 1000 / (lp.anim ? 24 : 8); repeat: true; running: lp.p > 0 && lp.motion !== "vypnute"; onTriggered: lp.t += interval / 1000 }

    // ── pozadie L: panel + kmeň + päta ───────────────────────────────────────────────
    // panel (nad kmeňom): zaoblené horné rohy
    Rectangle {
        id: panelBg
        x: lp.left0; width: lp.panelW
        y: lp.trunkY - lp.panelH * lp.panelP; height: lp.panelH * lp.panelP + lp.rad
        visible: lp.panelP > 0.01
        radius: lp.panelRadius; color: glass.active ? "transparent" : lp.theme.surface      // obrys kreslí spoločný obrys L (nižšie)
        opacity: lp.panelP
        // matné sklo (rozmazaná tapeta pod panelom, bez GPU); vrstva má počiatok v ľavom hornom rohu obrazovky
        Sklo { id: glass; anchors.fill: parent; theme: lp.theme; screenX: panelBg.x; screenY: panelBg.y
               radii: [lp.panelRadius, lp.panelRadius, 0, 0]; visible: lp.panelP > 0.01 }
    }
    // kmeň: textúra, zaoblený vonkajší dolný roh
    Item {
        id: trunkClip
        x: lp.armX; y: lp.trunkY; width: lp.armW; height: lp.tbE - lp.trunkY
        visible: lp.armP > 0.01
        Scena {
            id: trunkScene
            anchors.fill: parent
            colors: lp.theme; spec: lp.sceneSpec; motion: lp.motion; time: lp.t; mirror: lp.isRight; image: lp.image; frame: lp.frame; frameDir: lp.frameDir; frameCount: lp.frameCount
            ohnisko: lp.ohnisko; anchorX: lp.footOx + lp.foot.w / 2; anchorY: lp.sceneH - lp.foot.h / 2
            // vonkajší dolný roh kmeňa; horné rohy iba kým nie je panel (potom ich kreslí panel)
            readonly property real ro: lp.panelP > 0.01 ? 0 : Math.min(lp.rOuter, height)
            readonly property real rf: lp.panelP > 0.01 ? 0 : Math.min(lp.rFar, height / 2)
            radii: lp.isRight ? [rf, ro, 0, lp.rTrunk] : [ro, rf, lp.rTrunk, 0]
            dim: lp.isRight ? [lp.dim, 0.05] : [0.05, lp.dim]           // stlmenie pod textom: pri päte textúra, pod písmom pokoj
            ox: trunkClip.x - lp.left0; oy: lp.trunkY - lp.sceneTop; canvasW: lp.panelW; canvasH: lp.sceneH
        }
        Item { id: trunkContent; anchors.fill: parent; opacity: lp.panelP }
    }
    // päta = ostrov na lište (prekryje ho, rovnaká textúra ako kmeň)
    Item {
        id: footClip
        // od vrchu lišty (ak je susedný ostrov vyšší, päta sa k kmeňu dotiahne stĺpcom nad vlastným ostrovom)
        x: lp.foot.x; y: lp.tbE; width: lp.foot.w; height: lp.foot.y + lp.foot.h - lp.tbE
        visible: lp.p > 0.01
        Scena {
            anchors.fill: parent
            colors: lp.theme; spec: lp.sceneSpec; motion: lp.motion; time: lp.t; mirror: lp.isRight; image: lp.image; frame: lp.frame; frameDir: lp.frameDir; frameCount: lp.frameCount
            ohnisko: lp.ohnisko; anchorX: lp.footOx + lp.foot.w / 2; anchorY: lp.sceneH - lp.foot.h / 2
            // spodok päty = tvar ostrova; vonkajší horný roh pokračuje oblúkom obrysu, kým je kmeň nízky
            readonly property real ro: Math.max(0, lp.rOuter - (lp.tbE - lp.trunkY))
            radii: lp.isRight ? [lp.footTopR, ro, lp.footRadius, lp.footRadius] : [ro, lp.footTopR, lp.footRadius, lp.footRadius]
            ox: lp.foot.x - lp.left0; oy: lp.tbE - lp.sceneTop; canvasW: lp.panelW; canvasH: lp.sceneH
        }
        Rectangle {
            visible: lp.footGlyph !== "" && !lp.framed
            x: (parent.width - 30) / 2; y: parent.height - lp.foot.h / 2 - 15; width: 30; height: 30; radius: 10
            color: Qt.rgba(lp.theme.surfaceVariant.r, lp.theme.surfaceVariant.g, lp.theme.surfaceVariant.b, 0.85)
            Glyph { anchors.centerIn: parent; name: lp.footGlyph || "apps"; size: 18; color: lp.theme.primary }
        }
    }
    // vyduté zaoblenie medzi kmeňom a pätou (vnútorný roh L)
    Canvas {
        id: notch
        // vyduté zaoblenie leží v medzere nad lištou (nezasahuje do susedných ostrovov)
        readonly property real s: lp.gap > 1 ? Math.min(lp.rad, lp.gap) : Math.min(lp.rad, lp.sideGap)
        x: lp.isRight ? lp.foot.x - s : lp.foot.x + lp.foot.w; y: lp.tbE
        width: Math.max(1, s); height: Math.max(1, s)
        visible: lp.armP > 0.5 && s >= 2
        onSChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            c.fillStyle = lp.theme.surfaceVariant;
            c.beginPath();
            if (lp.isRight) { c.moveTo(s, 0); c.lineTo(s, s); c.quadraticCurveTo(s, 0, 0, 0); }
            else { c.moveTo(0, 0); c.lineTo(0, s); c.quadraticCurveTo(0, 0, s, 0); }
            c.closePath(); c.fill();
        }
    }
    // jeden obrys celého tvaru L (panel, kmeň, vydutý roh, päta so zaoblením ostrova) — ako obrys okna predtým
    Canvas {
        id: outline
        anchors.fill: parent
        visible: lp.p > 0.01
        readonly property real sig: lp.p + lp.foot.x + lp.foot.y + lp.foot.w + lp.panelW + lp.panelH + lp.gap + lp.frameWidth
        onSigChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            if (!visible) return;
            const f = lp.foot, fw = f.w, W = lp.armW, Rf = lp.footRadius, room = lp.roomW, top = lp.shapeTop;
            const tb = lp.tbE, fb = f.y + f.h, s = Math.min(notch.s, room), Rt = lp.rTrunk;
            // horné rohy: pri p = 0 rohy ostrova, potom rohy panelu (obrys sa plynulo presunie z ostrova na celé okno)
            const Rp = lp.rOuter, Rr = lp.rFar, h = lp.frameWidth / 2;
            // u = vzdialenosť od vonkajšej hrany päty (vľavo pri App Manageri, vpravo pri Zariadeniach: zrkadlo);
            // čiara leží celá vnútri tvaru (posun o polovicu hrúbky), oblúky presne cez arc (arcTo robil výbežky)
            c.save();
            if (lp.isRight) { c.translate(f.x + f.w, 0); c.scale(-1, 1); } else c.translate(f.x, 0);
            c.strokeStyle = lp.frameColor; c.lineWidth = lp.frameWidth;
            const P = Math.PI;
            c.beginPath();
            c.moveTo(h, top + Rp);
            c.arc(Rp, top + Rp, Rp - h, P, 1.5 * P);
            c.lineTo(W - Rr, top + h);
            c.arc(W - Rr, top + Rr, Rr - h, 1.5 * P, 2 * P);
            if (room >= 1) {
                c.lineTo(W - h, tb - Rt);
                if (Rt > h) c.arc(W - Rt, tb - Rt, Rt - h, 0, 0.5 * P);
                if (s >= 2) { c.lineTo(fw + s, tb - h); c.quadraticCurveTo(fw - h, tb - h, fw - h, tb + s); }
                else c.lineTo(fw - h, tb - h);
            }
            c.lineTo(fw - h, fb - Rf);
            c.arc(fw - Rf, fb - Rf, Rf - h, 0, 0.5 * P);
            c.lineTo(Rf, fb - h);
            c.arc(Rf, fb - Rf, Rf - h, 0.5 * P, P);
            c.closePath();
            c.stroke();
            c.restore();
        }
    }
    // obsah panelu (nad kmeňom)
    Item {
        id: body
        x: lp.left0; width: lp.panelW
        y: lp.trunkY - lp.panelH; height: lp.panelH
        opacity: lp.panelP
        visible: lp.panelP > 0.02
        transform: Translate { y: (1 - lp.panelP) * 18 }
    }
}
