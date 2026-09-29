// LatteOS — výbehy maskota z ostrova (zadanie 24./25. 9.). Postavy sú balíčky /usr/share/latteos/maskoti/<id>/
// (snímky PNG + pet.json; väčšinu vyrezalo resources/art/maskoti/vyrez.py z koncepčných listov používateľa).
// Správanie podľa povahy (pet.json › profile):
//   sliz      (Homebrew)  plazí sa po lište, k titulku okna sa natiahne a pritiahne sa, na okne sa rozleje, kvapká
//   drak      (drak, svetluška, dráčik)  vzlietne, sadne si na titulok a stráži, občas chrlí oheň; svetluška lieta v noci
//   macka     (Latte, Mokka, Ktulu, Líška)  skáče na okná, plíži sa, uhýba kurzoru; keď sa dlho nič nedeje,
//             priblíži sa „z monitora“ a pozerá na teba (zväčšená uprostred dole)
//   maid      beží po lište, zametá ju (prach), sedí na nej a hojdá nohami, pri kurzore srdiečka ♥
//   kapybara  najpokojnejšia: sadne si do bazénika vedľa ostrova; občas jej vypadne gumová kačička, odrazí sa
//             a kapybara sa pre ňu lenivo vyberie a vráti sa do bazénika
//   turista   (Robot, Mýval)  zvedavo obchádza rohy okien, ovoniava („?“), občas si ich odfotí (blesk)
//   teleport  (Tieň)  teleportuje sa (fialové čiastočky), občas akoby niečo vzal a potom to vráti na miesto
// Keď si 3 min nečinný, mačky sa pozerajú, ostatné si zdriemnu pri kurzore. Pri hre / celej obrazovke sa schová.
// Pomenované animácie z pet.json › anim ({ frames, fps, loop }, listy používateľa z 26. 9.) a zábery zblízka (closeup):
//   Foxy Maid  vyjde a odíde dverami, zametá lištu, oprašuje a leští okná, dá si kávu, selfie, z okna padá na padáku,
//              pri kurzore srdiečka, dlho mierený kurzor = zazerá, pravý klik = urazená; pri nečinnosti vykukne z kraja
//   Robot      vznáša sa, na diaľku boost, okná skenuje a fotí, spí na nabíjačke, zblízka ťa odfotí
//   Kávový drak vzlietne, letí, pristane, stráži, chrlí oheň, sedí v šálke; kurzor tesne pri ňom = zľakne sa a odletí
// Klik = pohladkať (♥), pravý klik = domov. Kliky mimo postavy prechádzajú (maska okna = postava).
// Synchronizácia s widgetom lišty: $XDG_RUNTIME_DIR/latteos/maskot-von (vychadza | von | prichadza | domov | hrat).
// Domov (ostrov maskota): ~/.config/latteos/mascot-home „x“ (inak odhad vpravo dole). Softvér 6 krokov/s, GPU 24.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: mk
    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string cfg: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos"
    readonly property string runFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/latteos/maskot-von"
    readonly property string packs: "/usr/share/latteos/maskoti/"
    // vlastné a komunitné balíčky (latte-maskoti pridaj): ~/.local/share/latteos/maskoti/<id>/ — iba PNG a pet.json
    readonly property string userPacks: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/latteos/maskoti/"
    property string base: packs
    readonly property bool gpu: ["softver", "minimalny", "safe"].indexOf(Quickshell.env("LATTE_TIER") || "softver") < 0
    readonly property int fps: gpu ? 24 : 6
    readonly property real dt: 1 / fps
    readonly property var scr: Quickshell.screens.length ? Quickshell.screens[0] : null
    readonly property int sw: scr ? scr.width : 1920
    readonly property int sh: scr ? scr.height : 1080
    readonly property int barY: sh - 52                         // chodidlá na hornej hrane lišty
    property int homeX: sw - 258
    readonly property int boxW: 200
    readonly property int boxH: 170
    readonly property var legacy: ({ macka: "latte", zrnko: "latte", void: "cdrak" })

    property string kind: "homebrew"
    property var meta: ({ profile: "macka", flyer: false, facing: "none", idle: ["sedi"], move: ["sedi"], frames: ["sedi"] })
    property string mode: "world"
    property bool out: false            // postava je mimo ostrova
    property bool waiting: false        // čaká, kým widget prehrá odchod
    property int waitTicks: 0
    property real fx: homeX             // chodidlá (stred spodku postavy)
    property real fy: barY
    property string frame: "sedi"
    property bool mirrored: false
    property real sy: 1                 // natiahnutie (sliz)
    property real alpha: 1
    property real rot: 0
    property var queue: []
    property var cur: null              // práve vykonávaný krok
    property real tripStart: 0
    property string tripKind: ""
    property string sitOn: ""
    property real sitDx: 0
    property var wins: []
    property point cursor: Qt.point(sw / 2, sh / 2)
    property bool fullscreen: false
    property int tick: 0
    property var parts: []              // čiastočky: { x, y, vx, vy, life, kind }
    property bool staring: false        // mačky: pozerá sa z monitora
    property real stareScale: 0.3

    function trim(s) { return (s || "").trim(); }
    function img(f) { return "file://" + base + kind + "/" + f + ".png"; }
    function has(f) { return (meta.frames || []).indexOf(f) >= 0; }
    function anim(n) { return n && meta.anim && meta.anim[n] ? meta.anim[n] : null; }
    // krok „póza s animáciou“: bez secs trvá raz celá (slučka ~ podľa secs)
    function act(n, secs, extra) {
        const A = anim(n); if (!A) return null;
        return Object.assign({ t: "pose", frame: A.frames[0], act: n, secs: secs !== undefined ? secs : A.frames.length / A.fps + 0.4 }, extra || {});
    }
    function pushAct(q, n, secs, extra) { const a = act(n, secs, extra); if (a) q.push(a); return !!a; }
    property real nearSince: 0          // kurzor pri postave od (zazeranie)
    function pick(a) { return a[Math.floor(Math.random() * a.length)]; }
    readonly property string profile: meta.profile || "macka"
    readonly property bool flyer: !!meta.flyer

    FileView { path: mk.cfg + "/mascot"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: { const k = mk.trim(text()); mk.kind = mk.legacy[k] || k || "homebrew"; } onLoadFailed: mk.kind = "homebrew" }
    FileView { path: mk.packs + mk.kind + "/pet.json"; printErrors: false
               onLoaded: { try { mk.meta = JSON.parse(text()); mk.base = mk.packs; } catch (e) {} }
               onLoadFailed: userPet.reload() }
    FileView { id: userPet; path: mk.userPacks + mk.kind + "/pet.json"; printErrors: false; preload: false
               onLoaded: { try { mk.meta = JSON.parse(text()); mk.base = mk.userPacks; } catch (e) {} } }
    FileView { path: mk.cfg + "/mascot-mode"; printErrors: false; watchChanges: true; onFileChanged: reload()
               onLoaded: mk.mode = mk.trim(text()) || "world"; onLoadFailed: mk.mode = "world" }
    FileView { path: mk.cfg + "/mascot-home"; printErrors: false
               onLoaded: { const v = parseInt(text()); if (v) mk.homeX = v; } }
    FileView {
        id: run
        path: mk.runFile; printErrors: false; watchChanges: true; onFileChanged: reload()
        onLoaded: {
            const v = mk.trim(text());
            if (v === "domov" && mk.out) mk.goHome();
            if (v === "hrat" && !mk.out && !mk.waiting) mk.startTrip("hra");
        }
    }
    Process { running: true; command: ["mkdir", "-p", mk.runFile.replace(/\/[^/]*$/, "")] }
    function setRun(v) { run.setText(v); }
    readonly property bool active: kind !== "ziadny" && (mode === "world" || mode === "chaos")
    onKindChanged: if (out) goHome()
    onActiveChanged: if (!active && out) arrive()

    // okná aktuálnej plochy a celá obrazovka cez IPC Quickshellu (bez procesov; optimalizácia 26. 9.: predtým každé
    // 2,5 s sh + 3× hyprctl), kurzor jedným hyprctl — pri výlete každý krok, doma raz za ~10 s
    function readWins() {
        const ws = Hyprland.focusedWorkspace;
        if (!ws) return;
        const all = Hyprland.toplevels.values.map(t => t.lastIpcObject).filter(c => c && c.workspace && c.size && c.at);
        mk.wins = all.filter(c => c.workspace.id === ws.id && c.mapped !== false && !c.hidden && c.size[0] > 200 && c.at[1] > 60)
                     .map(c => ({ a: c.address, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], fs: c.fullscreen }));
        mk.fullscreen = all.some(c => c.workspace.id === ws.id && (c.fullscreen === 2 || c.fullscreen === true));
        mk.followWindow();
    }
    Connections { target: Hyprland; function onRawEvent(e) { if (/^(openwindow|closewindow|movewindow|fullscreen|workspace|changefloatingmode)/.test(e.name)) winTimer.restart(); } }
    Timer { id: winTimer; interval: 150; onTriggered: { Hyprland.refreshToplevels(); Qt.callLater(mk.readWins); } }
    Process {
        id: curProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector { onStreamFinished: { const m = this.text.match(/(-?\d+),\s*(-?\d+)/); if (m) mk.cursor = Qt.point(parseInt(m[1]), parseInt(m[2])); } }
    }
    property int tickN: 0
    Timer {
        interval: mk.out ? 700 : 2500; repeat: true; running: mk.active; triggeredOnStart: true
        onTriggered: {
            Hyprland.refreshToplevels(); mk.readWins();
            if ((mk.out || ++mk.tickN % 4 === 0) && !curProc.running) curProc.running = true;
        }
    }
    IdleMonitor { id: idle; timeout: 180; respectInhibitors: true }

    // ── kedy vybehne ───────────────────────────────────────────────────────────────────────
    Timer {
        interval: 45000; repeat: true; running: mk.active
        onTriggered: {
            if (mk.out || mk.waiting || mk.fullscreen) return;
            const h = new Date().getHours(), night = h >= 23 || h < 6;
            if (idle.isIdle) { mk.startTrip("nečinnosť"); return; }
            if (night && mk.kind !== "svetluska") return;
            const p = mk.mode === "chaos" ? 0.45 : (mk.profile === "kapybara" ? 0.05 : (mk.kind === "svetluska" && night ? 0.3 : 0.1));
            if (Math.random() < p) mk.startTrip("výlet");
        }
    }
    Connections { target: idle; function onIsIdleChanged() {
        if (idle.isIdle && mk.active && !mk.fullscreen) { if (!mk.out && !mk.waiting) mk.startTrip("nečinnosť"); else { mk.queue = []; mk.cur = null; mk.planIdle(); } }
        if (!idle.isIdle && mk.staring) mk.stopStare();
    } }

    function startTrip(k) {
        if (!active || out || waiting) return;
        tripKind = k; tripStart = Date.now();
        setRun("vychadza");
        waiting = true; waitTicks = fps * 2;
        fx = homeX; fy = barY; queue = []; cur = null; sitOn = "";
    }
    function beginOut() {
        waiting = false; out = true; setRun("von");
        frame = (meta.idle || ["sedi"])[0]; alpha = 1; sy = 1; rot = 0;
        if (tripKind === "nečinnosť") planIdle(); else plan();
        // vyjde dverami (maid) alebo vzlietne (drak) priamo z ostrova
        const first = act(meta.door ? meta.door.out : "") || act(meta.takeoff || "");
        if (first) queue = [first].concat(queue);
    }
    function goHome() {
        if (!out) return;
        stopStare();
        sitOn = ""; queue = moveSteps(homeX, barY, profile === "teleport" ? "teleport" : (flyer ? "fly" : "walk"));
        pushAct(queue, meta.land || "");                              // drak pristane
        pushAct(queue, meta.door ? meta.door.in : "");                // maid odíde dverami
        queue.push({ t: "home" }); cur = null;
    }
    // pravý klik: domov; maid sa najprv urazí
    function sendHome() {
        if (!out) return;
        const o = act(meta.offended || "", 2.5);
        if (o) { stopStare(); sitOn = ""; cur = null; queue = [o, { t: "tohome" }]; } else goHome();
    }
    function arrive() { out = false; waiting = false; staring = false; queue = []; cur = null; parts = []; duck.visible = false; fx = homeX; fy = barY; setRun("prichadza"); }

    // ── plánovanie podľa povahy ─────────────────────────────────────────────────────────────
    function windowSpot() {
        if (!wins.length) return null;
        const w = pick(wins);
        const dx = 30 + Math.random() * Math.max(1, w.w - 60);
        return { x: w.x + dx, y: w.y + 2, a: w.a, dx: dx, w: w };
    }
    function barSpot() { return { x: 60 + Math.random() * (sw - 120), y: barY, a: "" }; }
    function moveSteps(x, y, how) {
        // chodiace postavy: z okna najprv zoskočia na lištu, po lište idú, pod cieľom vyšplhajú / natiahnu sa / vyskočia
        if (how === "fly" || how === "teleport" || how === "jump") return [{ t: "move", x: x, y: y, how: how }];
        const s = [];
        if (fy < barY - 2 && (Math.abs(x - fx) > 4 || y > fy)) s.push({ t: "move", x: fx, y: barY, how: anim(meta.parachute || "") ? "parachute" : "drop" });
        if (Math.abs(x - fx) > 2) s.push({ t: "move", x: x, y: barY, how: how });
        if (y < barY - 2) s.push({ t: "move", x: x, y: y, how: how === "crawl" ? "stretch" : "climb" });
        return s;
    }
    function sitAt(spot) { sitOn = spot.a || ""; sitDx = spot.dx || 0; }
    function pose(f, secs, extra) { return Object.assign({ t: "pose", frame: f, secs: secs }, extra || {}); }
    function idleFrames() { return meta.idle && meta.idle.length ? meta.idle : ["sedi"]; }

    function plan() {
        const long = Date.now() - tripStart > (tripKind === "hra" ? 50000 : 150000);
        if (long) { goHome(); return; }
        const q = [], idl = idleFrames();
        const ws = windowSpot(), bs = barSpot();
        switch (profile) {
        case "sliz": {
            const s = ws && Math.random() < 0.7 ? ws : bs;
            q.push(...moveSteps(s.x, s.y, "crawl"));
            q.push({ t: "sit", spot: s });
            q.push(pose(has("rozliaty") ? "rozliaty" : idl[0], 6 + Math.random() * 8, { fx: "drip" }));
            q.push(pose(idl[0], 4));
            break; }
        case "drak": {
            const s = ws && Math.random() < 0.75 ? ws : bs;
            pushAct(q, meta.takeoff || "");
            q.push(...moveSteps(s.x, s.y, "fly"));
            pushAct(q, meta.land || "");
            q.push({ t: "sit", spot: s });
            const guard = 8 + Math.random() * 10;
            if (anim(meta.cup) && Math.random() < 0.35) q.push(act(meta.cup, guard, { startle: true }));
            else if (anim("strazi")) q.push(act("strazi", guard, { startle: true }));
            else q.push(pose(has("na-salke") ? "na-salke" : idl[0], guard, { anim: idl }));
            if (Math.random() < 0.5) { if (!pushAct(q, meta.fire || "", undefined, { fx: "fire" }) && has("ohen")) q.push(pose("ohen", 1.5, { fx: "fire" })); }
            break; }
        case "macka": {
            if (tripKind === "hra" || mode === "chaos") { q.push(...moveSteps(Math.max(40, Math.min(sw - 40, cursor.x)), barY, "walk")); q.push(pose(idl[0], 3, { dodge: true })); break; }
            const s = ws && Math.random() < 0.6 ? ws : bs;
            if (Math.random() < 0.35 && has("plazi")) q.push(...moveSteps(s.x, barY, "sneak"));
            q.push(...(s.y < barY - 2 ? [...moveSteps(s.x - 60, barY, "walk"), { t: "move", x: s.x, y: s.y, how: "jump" }] : moveSteps(s.x, s.y, "walk")));
            q.push({ t: "sit", spot: s });
            q.push(pose(idl[0], 6 + Math.random() * 10, { anim: idl, dodge: true }));
            break; }
        case "maid": {
            const r = Math.random();
            if (anim("kava") && r >= 0.4 && r < 0.55) {                // prestávka na kávu na lište
                q.push(...moveSteps(bs.x, barY, "run"));
                q.push(act("kava", 10 + Math.random() * 8, { hearts: true }));
            } else if (anim("selfie") && r >= 0.55 && r < 0.65) {      // selfie (blesk na konci)
                q.push(...moveSteps(bs.x, barY, "run"));
                q.push(act("selfie", 4, { fx: "selfie" }));
            } else if (ws && anim("oprasuje") && r >= 0.65 && r < 0.9) { // oprašuje alebo leští titulok okna
                q.push(...moveSteps(ws.x, ws.y, "run"));
                q.push({ t: "sit", spot: ws });
                pushAct(q, "predklon");
                q.push(act(Math.random() < 0.5 || !anim("lesti") ? "oprasuje" : "lesti", 6 + Math.random() * 6, { hearts: true }));
            } else if (r < 0.4) {                                      // zametá lištu tam a späť
                const a = 80 + Math.random() * (sw / 2), b = a + 200 + Math.random() * 300;
                q.push(...moveSteps(a, barY, "run"));
                for (let i = 0; i < 3; i++) { q.push({ t: "move", x: b, y: barY, how: "sweep" }); q.push({ t: "move", x: a, y: barY, how: "sweep" }); }
            } else if (r < 0.75) {                                     // sedí na lište a hojdá nohami
                q.push(...moveSteps(bs.x, barY, "run"));
                q.push(pose(idl[0], 10 + Math.random() * 10, { swing: true, hearts: true }));
            } else {
                const s = ws || bs;
                q.push(...moveSteps(s.x, s.y, "run"));
                q.push({ t: "sit", spot: s });
                q.push(pose(idl[0], 8, { swing: true, hearts: true }));
            }
            break; }
        case "kapybara": {
            const poolX = Math.max(80, homeX - 150);
            q.push(...moveSteps(poolX, barY, "lazy"));
            q.push(pose(has("bazen") ? "bazen" : idl[0], 20 + Math.random() * 25));
            if (Math.random() < 0.8) { q.push({ t: "duck" }); q.push(pose(has("bazen") ? "bazen" : idl[0], 15 + Math.random() * 20)); }
            q.push({ t: "tohome" });
            break; }
        case "turista": {
            const s = ws ? pick([{ x: ws.w.x + 20, y: ws.w.y + 2, a: ws.a, dx: 20 }, { x: ws.w.x + ws.w.w - 20, y: ws.w.y + 2, a: ws.a, dx: ws.w.w - 20 }, ws]) : bs;
            const far = Math.hypot(s.x - fx, s.y - fy) > 400;
            q.push(...moveSteps(s.x, s.y, flyer ? (far && anim(meta.fast || "") ? "boost" : "fly") : (has("boost") && s.y < barY - 2 ? "boost" : "walk")));
            q.push({ t: "sit", spot: s });
            if (!pushAct(q, meta.scan || "", 3 + Math.random() * 3)) q.push(pose(idl[0], 2, { bubble: "?" }));
            q.push(pose(pick(idl), 3 + Math.random() * 4, { anim: idl }));
            if (Math.random() < 0.35 && !pushAct(q, meta.photo || "", undefined, { fx: "photoAt2" })) q.push(pose(idl[0], 1, { fx: "photo" }));
            break; }
        case "teleport": {
            const s = ws || bs;
            q.push({ t: "move", x: s.x, y: s.y, how: "teleport" });
            q.push({ t: "sit", spot: s });
            q.push(pose(idl[0], 5 + Math.random() * 6));
            if (has("drzi") && Math.random() < 0.5) {                  // „vezme“ blok, odnesie ho a vráti
                const o = windowSpot() || barSpot();
                q.push(pose("drzi", 2));
                q.push({ t: "move", x: o.x, y: o.y, how: "teleport", keep: "drzi" });
                q.push(pose("drzi", 4));
                q.push({ t: "move", x: s.x, y: s.y, how: "teleport", keep: "drzi" });
                q.push(pose(idl[0], 3));
            }
            break; }
        default:
            q.push(...moveSteps(bs.x, bs.y, "walk")); q.push(pose(idl[0], 5));
        }
        queue = q;
    }
    function planIdle() {                                  // nečinnosť: mačky sa pozerajú, ostatné si zdriemnu pri kurzore
        if (profile === "macka" || (meta.closeup && meta.closeup.length && Math.random() < 0.5)) { queue = [{ t: "stare" }]; return; }
        const x = Math.max(40, Math.min(sw - 40, cursor.x + 60)), q = [];
        if (profile === "kapybara") { plan(); return; }
        q.push(...moveSteps(x, Math.min(barY, Math.max(80, cursor.y + 40)), profile === "teleport" ? "teleport" : (flyer ? "fly" : "walk")));
        const sleepAct = act(meta.charge || (meta.cup && profile === "drak" ? meta.cup : "") || (profile === "maid" ? "zivne" : ""), 600, { zz: true, untilActive: true, hold: true });
        q.push(sleepAct || pose(meta.sleep || idleFrames()[0], 600, { zz: true, untilActive: true }));
        queue = q;
    }
    function followWindow() {
        if (!out || sitOn === "" || (cur && cur.t === "move")) return;
        const w = wins.find(x => x.a === sitOn);
        if (!w) { sitOn = ""; queue = [{ t: "move", x: fx, y: barY, how: "drop" }].concat(queue); cur = null; return; }
        fx = w.x + sitDx; fy = w.y + 2;
    }

    // ── vykonávanie ────────────────────────────────────────────────────────────────────────
    Timer {
        interval: 1000 / mk.fps; repeat: true; running: mk.active && (mk.out || mk.waiting)
        onTriggered: mk.step()
    }
    function speedOf(how) {
        return ({ walk: 110, run: 170, sweep: 120, sneak: 45, lazy: 38, crawl: 55, climb: 70, stretch: 140, drop: 380, parachute: 70, fly: 170, boost: 320, jump: 1, teleport: 1 })[how] || 100;
    }
    function moveFrames(how) {
        const mv = meta.move && meta.move.length ? meta.move : idleFrames();
        if (how === "sweep" && anim("zameta")) return anim("zameta").frames;
        if (how === "parachute" && anim(meta.parachute)) { const P = anim(meta.parachute).frames; return P.length > 1 ? P.slice(1) : P; }
        if (how === "boost" && anim(meta.fast || "boost")) return anim(meta.fast || "boost").frames;
        if (how === "fly" && anim("let")) return anim("let").frames;
        if (how === "sneak" && has("plazi")) return ["plazi"];
        if (how === "crawl") return has("plazi") ? ["plazi", "sedi"] : mv;
        if (how === "stretch") return [has("natiahnuty") ? "natiahnuty" : mv[0]];
        if (how === "jump") return [has("skok") ? "skok" : mv[0]];
        if (how === "boost") return has("boost") ? ["boost", "boost-2"] : mv;
        if (how === "drop") return [has("kvapka-2") ? "kvapka-2" : mv[0]];
        return mv;
    }
    function facingFor(f, dir) {                           // zrkadliť, aby postava hľadela smerom pohybu
        const natural = (meta.rightFacing || []).indexOf(f) >= 0 ? "right" : (meta.facing || "none");
        if (natural === "none" || dir === 0) return mirrored;
        return (natural === "left") === (dir > 0);
    }
    function step() {
        tick++;
        stepParts();
        if (fullscreen && (out || waiting)) { arrive(); return; }
        if (waiting) { if (--waitTicks <= 0) beginOut(); return; }
        if (!out) return;
        if (!cur) {
            if (!queue.length) { if (tripKind === "nečinnosť" && profile !== "macka") planIdle(); else plan(); }
            if (!queue.length) return;
            cur = queue.shift(); cur.t0 = Date.now(); cur.sx = fx; cur.sy = fy;
        }
        const c = cur;
        if (c.t === "home") { arrive(); return; }
        if (c.t === "tohome") { cur = null; goHome(); return; }
        if (c.t === "sit") { sitAt(c.spot); cur = null; return; }
        if (c.t === "stare") { if (!staring) startStare(); if (!idle.isIdle) { cur = null; goHome(); } return; }
        if (c.t === "duck") { if (!duck.visible && !c.started) { c.started = true; duck.launch(fx, fy - 30); } if (duck.done) { cur = null; } else stepDuck(); return; }
        if (c.t === "pose") {
            const el = (Date.now() - c.t0) / 1000;
            const A = anim(c.act);
            let ai = 0;
            if (A) { ai = Math.floor(el * A.fps); frame = A.frames[A.loop ? ai % A.frames.length : Math.min(ai, A.frames.length - 1)]; ai = A.loop ? ai % A.frames.length : Math.min(ai, A.frames.length - 1); }
            else frame = c.anim && c.anim.length > 1 ? c.anim[Math.floor(el / 1.6) % c.anim.length] : c.frame;
            if (c.fx === "photoAt2" && ai === 2 && !c.flashed) { c.flashed = true; flash.restart(); }
            if (c.fx === "selfie" && ai === 3 && !c.flashed) { c.flashed = true; flash.restart(); }
            rot = c.swing ? Math.sin(el * 3) * 4 : 0;
            if (c.zz && tick % fps === 0) addPart(fx + 20, fy - 60, 0, -18, 2.5, "z");
            if (c.fx === "drip" && tick % (fps * 2) === 0) addPart(fx + (Math.random() * 30 - 15), fy, 0, 60, 3, "drip");
            if (c.fx === "fire" && tick % 2 === 0 && (!A || ai >= 2)) addPart(fx + (mirrored ? -30 : 30), fy - 25, mirrored ? -120 : 120, -10, 0.8, "fire");
            if (c.fx === "photo" && tick % fps === 0) flash.restart();
            if (c.bubble && tick % (fps * 2) === 0) addPart(fx + 18, fy - 70, 0, -8, 1.8, "q");
            const near = Math.hypot(cursor.x - fx, cursor.y - (fy - 30));
            if (c.hearts && near < 140 && tick % fps === 0) addPart(fx + (Math.random() * 30 - 15), fy - 60, 0, -30, 2, "heart");
            if (c.hearts && near < 140) {                   // srdiečka (animácia, ak ju postava má)
                const H = anim(meta.hearts || "");
                frame = H ? H.frames[Math.floor(el * H.fps) % H.frames.length] : (has("srdce") ? "srdce" : frame);
            }
            // dlho mierený kurzor: zazerá (maid)
            if (near < 110) { if (!nearSince) nearSince = Date.now(); } else nearSince = 0;
            const G = anim(meta.glare || "");
            if (G && nearSince && Date.now() - nearSince > 3000) frame = G.frames[Math.floor(el * G.fps) % G.frames.length];
            // kurzor tesne pri drakovi: zľakne sa a odletí inam
            if (c.startle && near < 70 && anim(meta.startle || "")) {
                const s2 = windowSpot() || barSpot();
                cur = null; sitOn = ""; nearSince = 0;
                queue = [act(meta.startle), ...moveSteps(s2.x, s2.y, "fly")].concat(pushAct([], meta.land || "") ? [act(meta.land)] : [], [{ t: "sit", spot: s2 }], queue);
                return;
            }
            if (c.dodge && near < 90) {                    // mačka uhne kurzoru skokom
                const nx = Math.max(40, Math.min(sw - 40, fx + (cursor.x > fx ? -160 : 160)));
                cur = null; sitOn = ""; rot = 0;
                queue = [{ t: "move", x: nx, y: fy, how: "jump" }].concat(queue);
                return;
            }
            if (c.untilActive ? !idle.isIdle : el >= c.secs) { cur = null; rot = 0; }
            return;
        }
        if (c.t === "move") {
            const dx = c.x - fx, dy = c.y - fy, dist = Math.hypot(dx, dy);
            if (Math.abs(dx) > 0.5) mirrored = facingFor(moveFrames(c.how)[0], Math.sign(dx));
            if (c.how === "teleport") {                    // zmizne, čiastočky, objaví sa inde
                const el = (Date.now() - c.t0) / 1000;
                if (c.keep) frame = c.keep;
                if (el < 0.5) { alpha = 1 - el * 2; if (tick % 2 === 0) for (let i = 0; i < 2; i++) addPart(fx + Math.random() * 40 - 20, fy - Math.random() * 60, Math.random() * 40 - 20, -40, 0.9, "tp"); return; }
                if (!c.jumped) { c.jumped = true; fx = c.x; fy = c.y; }
                alpha = Math.min(1, (el - 0.5) * 2);
                if (el < 0.9 && tick % 2 === 0) addPart(fx + Math.random() * 40 - 20, fy - Math.random() * 60, 0, -30, 0.8, "tp");
                if (el >= 1) { alpha = 1; cur = null; }
                return;
            }
            if (c.how === "jump") {                        // parabola
                const T = Math.max(0.35, Math.hypot(c.x - c.sx, c.y - c.sy) / 420), u = Math.min(1, (Date.now() - c.t0) / 1000 / T);
                frame = moveFrames("jump")[0];
                fx = c.sx + (c.x - c.sx) * u;
                fy = c.sy + (c.y - c.sy) * u - Math.max(60, Math.abs(c.y - c.sy) * 0.4) * 4 * u * (1 - u);
                if (u >= 1) { fx = c.x; fy = c.y; cur = null; }
                return;
            }
            if (c.how === "stretch") {                     // sliz: natiahne sa hore, potom sa pritiahne
                const el = (Date.now() - c.t0) / 1000, reach = Math.abs(c.sy - c.y);
                frame = moveFrames("stretch")[0];
                if (el < 1.0) { sy = 1 + Math.min(1, el) * Math.min(3, reach / 60); return; }
                if (!c.snap) { c.snap = true; fx = c.x; fy = c.y; }
                sy = Math.max(1, sy - dt * 4);
                if (sy <= 1.01) { sy = 1; cur = null; }
                return;
            }
            const sp = speedOf(c.how) * dt;
            const mf = moveFrames(c.how);
            frame = mf[Math.floor(tick / Math.max(1, Math.round(fps / (c.how === "lazy" || c.how === "sneak" ? 2 : 4)))) % mf.length];
            if (c.how === "sweep" && tick % 2 === 0) addPart(fx + (mirrored ? 20 : -20), fy - 4, (mirrored ? 40 : -40), -15, 0.8, "dust");
            if (dist <= sp) { fx = c.x; fy = c.y; cur = null; return; }
            fx += dx / dist * sp; fy += dy / dist * sp;
        }
    }

    // ── čiastočky ──────────────────────────────────────────────────────────────────────────
    function addPart(x, y, vx, vy, life, k) { const p = parts.slice(-24); p.push({ x: x, y: y, vx: vx, vy: vy, life: life, max: life, k: k }); parts = p; }
    function stepParts() {
        if (!parts.length) return;
        const n = [];
        for (const p of parts) {
            p.life -= dt; if (p.life <= 0) continue;
            p.x += p.vx * dt; p.y += p.vy * dt;
            if (p.k === "drip") { p.vy += 300 * dt; if (p.y > barY) continue; }
            n.push(p);
        }
        parts = n;
    }

    // ── kapybara: gumová kačička sa odráža po lište ────────────────────────────────────────
    QtObject {
        id: duck
        property bool visible: false
        property bool done: false
        property real x: 0; property real y: 0; property real vx: 0; property real vy: 0
        property int stage: 0             // 0 letí/odráža sa, 1 leží, 2 kapybara ide po ňu, 3 nesie ju späť
        function launch(x0, y0) { x = x0; y = y0; vx = (Math.random() < 0.5 ? -1 : 1) * (90 + Math.random() * 90); vy = -320; visible = true; done = false; stage = 0; }
    }
    property real poolX: 0
    function stepDuck() {
        if (duck.stage === 0) {
            duck.vy += 900 * dt; duck.x += duck.vx * dt; duck.y += duck.vy * dt;
            if (duck.y >= barY) { duck.y = barY; duck.vy = -duck.vy * 0.55; duck.vx *= 0.8; if (Math.abs(duck.vy) < 40) { duck.vy = 0; duck.stage = 1; } }
            duck.x = Math.max(20, Math.min(sw - 20, duck.x));
            return;
        }
        if (duck.stage === 1) { poolX = fx; duck.stage = 2; return; }
        const target = duck.stage === 2 ? duck.x : poolX, dx = target - fx, sp = speedOf("lazy") * dt;
        const mf = moveFrames("lazy");
        frame = mf[Math.floor(tick / Math.max(1, fps / 2)) % mf.length];
        if (Math.abs(dx) > 0.5) mirrored = facingFor(mf[0], Math.sign(dx));
        if (Math.abs(dx) <= sp) {
            fx = target;
            if (duck.stage === 2) { duck.stage = 3; }                 // zdvihla ju (kačička ide s ňou)
            else { duck.visible = false; duck.done = true; }
            return;
        }
        fx += Math.sign(dx) * sp;
        if (duck.stage === 3) { duck.x = fx; duck.y = fy - 45; }
    }

    // ── mačky: pozerajú sa z monitora ──────────────────────────────────────────────────────
    function startStare() { staring = true; stareScale = 0.3; }
    function stopStare() { staring = false; }
    Timer { interval: 1000 / mk.fps; repeat: true; running: mk.staring
            onTriggered: { if (mk.stareScale < 1) mk.stareScale = Math.min(1, mk.stareScale + mk.dt * 0.35); } }

    // ── okná ───────────────────────────────────────────────────────────────────────────────
    Timer { id: happyOff; interval: 2000 }
    Timer { id: flash; interval: 160 }
    Process { id: petProc }
    function pet() {
        happyOff.restart();
        for (let i = 0; i < 3; i++) addPart(fx + (i - 1) * 14, fy - 60, (i - 1) * 10, -35, 1.8, "heart");
        petProc.command = ["python3", "-c", "import json,os,time;p=os.path.expanduser('~/.local/state/latteos/maskot.json');d=json.load(open(p)) if os.path.exists(p) else {};d['nalada']=min(100,d.get('nalada',80)+12);d['posledne']=int(time.time());os.makedirs(os.path.dirname(p),exist_ok=True);json.dump(d,open(p,'w'))"];
        petProc.running = true;
    }

    PanelWindow {
        id: win
        visible: mk.active && mk.out && !mk.fullscreen && !mk.staring
        anchors { top: true; left: true }
        margins { left: Math.round(mk.fx - mk.boxW / 2); top: Math.round(mk.fy - mk.boxH) }
        implicitWidth: mk.boxW; implicitHeight: mk.boxH
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "latte-maskot"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region { item: sprite }

        Image {
            id: sprite
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            source: mk.img(happyOff.running && mk.has("srdce") ? "srdce" : mk.frame)
            width: sourceSize.width * (mk.meta.scale || 1); height: sourceSize.height * (mk.meta.scale || 1)
            smooth: !mk.gpu ? false : true; opacity: mk.alpha
            transform: [
                Scale { origin.x: sprite.width / 2; origin.y: sprite.height; xScale: mk.mirrored ? -1 : 1; yScale: mk.sy },
                Rotation { origin.x: sprite.width / 2; origin.y: sprite.height; angle: mk.rot }
            ]
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                onClicked: (m) => { if (m.button === Qt.RightButton) mk.sendHome(); else mk.pet(); }
            }
        }
        Rectangle { anchors.fill: sprite; color: "white"; opacity: flash.running ? 0.8 : 0; radius: 6 }
        // čiastočky relatívne k chodidlám
        Repeater {
            model: mk.parts
            Text {
                required property var modelData
                x: modelData.x - (mk.fx - mk.boxW / 2) - 6; y: modelData.y - (mk.fy - mk.boxH) - 10
                opacity: Math.min(1, modelData.life / modelData.max * 1.5)
                text: ({ heart: "♥", z: "z", drip: "●", fire: "✹", dust: "·", tp: "✦", q: "?" })[modelData.k] || "·"
                color: ({ heart: "#FF6FA8", z: "#E4B283", drip: "#6B3E1F", fire: "#FF8A2A", dust: "#CDBCA6", tp: "#D070FF", q: "#FFE46B" })[modelData.k] || "white"
                font { pixelSize: modelData.k === "dust" ? 22 : (modelData.k === "drip" ? 9 : 16); bold: true }
            }
        }
    }
    // gumová kačička (samostatne, môže odskočiť ďaleko)
    PanelWindow {
        visible: mk.active && duck.visible && !mk.fullscreen
        anchors { top: true; left: true }
        margins { left: Math.round(duck.x - 14); top: Math.round(duck.y - 26) }
        implicitWidth: 28; implicitHeight: 26
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "latte-maskot-kacka"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {}
        Image { anchors.fill: parent; source: "file://" + mk.packs + "kapybara/kacka.png"; fillMode: Image.PreserveAspectFit; smooth: false }
    }
    // mačka sa priblíži „z monitora“ a pozerá na teba
    readonly property var closeup: meta.closeup && meta.closeup.length ? meta.closeup : null
    readonly property bool peekRight: !!closeup && meta.closeupAt === "right"
    PanelWindow {
        visible: mk.active && mk.staring && !mk.fullscreen
        anchors { bottom: true; right: mk.peekRight }
        margins { bottom: mk.peekRight ? Math.round(mk.sh * 0.3) : 58; right: 0 }
        implicitWidth: 420; implicitHeight: 360
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "latte-maskot-pozera"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region { item: big }
        Image {
            id: big
            // záber zblízka (closeup) sa strieda po 2 s; maid vykukne spoza pravého okraja (vysunie sa zboku)
            anchors { horizontalCenter: mk.peekRight ? undefined : parent.horizontalCenter; right: mk.peekRight ? parent.right : undefined; bottom: parent.bottom }
            anchors.rightMargin: mk.peekRight ? -width * (1 - Math.min(1, mk.stareScale * 1.4)) : 0
            source: mk.closeup ? mk.img(mk.closeup[Math.floor(mk.tick / (mk.fps * 2)) % mk.closeup.length])
                               : mk.img(mk.has("zmurk") && Math.floor(mk.tick / (mk.fps * 3)) % 4 === 3 ? "zmurk" : (mk.has("hero") ? "hero" : "sedi"))
            width: mk.closeup ? Math.min(parent.width, sourceSize.width * (mk.peekRight ? 1 : mk.stareScale))
                              : Math.min(parent.width, sourceSize.width * 1.6 * mk.stareScale * (sourceSize.width < 120 ? 3 : 1))
            height: width * sourceSize.height / Math.max(1, sourceSize.width)
            fillMode: Image.PreserveAspectFit; smooth: !!mk.closeup          // zábery zblízka sú maľované, nie pixel-art
            MouseArea { anchors.fill: parent; onClicked: { mk.stopStare(); mk.pet(); mk.goHome(); } }
        }
    }
}
