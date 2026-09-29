// Monitor › Hardvér — karty ako CPU-Z: Procesor, Cache, Doska, Pamäť, SPD, Grafika, Disky, Systém.
// Dáta: latte-sysmon hw (bez správcu) + hw-root (dmidecode, SPD, SMART; so sudo, uložené v ~/.cache/latteos/hw-root.json).
// Takty jadier sa obnovujú zo snímky Monitora (snap.sensors).
import QtQuick
import "../common"

Item {
    id: hv
    required property var theme
    property var hw: null
    property var root: null                 // hw-root (null = ešte nenačítané)
    property var snap: ({})
    property string tab: "cpu"
    property bool rootBusy: false
    property string rootError: ""
    signal refresh()
    signal loadRoot(string password)
    signal saveReport(string text)
    signal copyText(string text)
    signal menu(string text, real x, real y)
    signal openDevices()

    readonly property var tabs: [["cpu", "Procesor"], ["cache", "Cache"], ["board", "Doska"], ["mem", "Pamäť"], ["spd", "SPD"],
                                 ["gpu", "Grafika"], ["disk", "Disky"], ["sys", "Systém"]]
    function human(b) {
        if (!b) return "";
        const u = ["B", "KB", "MB", "GB", "TB"]; let v = b, i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return v.toFixed(v < 10 && i > 0 ? 1 : 0).replace(".", ",") + " " + u[i];
    }
    function sensor(id) {
        for (const g of (snap.sensors || [])) for (const it of g.items) if (it.id === id) return it.value;
        return undefined;
    }
    readonly property var liveClocks: {
        const out = [];
        for (let i = 0; i < 256; i++) { const v = sensor("cpu.clk" + i); if (v === undefined) break; out.push(v); }
        return out.length ? out : (hw && hw.cpuz ? hw.cpuz.clocks : []);
    }
    readonly property var liveUse: {
        const out = [];
        for (let i = 0; i < liveClocks.length; i++) out.push(sensor("cpu.use" + i) || 0);
        return out;
    }

    // ── obsah kariet: [nadpis boxu, [[popis, hodnota], …]] ──────────────────────────────
    readonly property var boxes: boxesFor(tab, hw, root, snap, liveClocks)
    function boxesFor(tab, h, rt, snap, liveClocks) {
        const r = rt || {};
        if (!h) return [];
        const z = h.cpuz || {}, c = h.cpu, rc = r.cpu || {};
        const clk0 = liveClocks[0] || c.curMHz;
        switch (tab) {
        case "cpu": return [
            ["Procesor", [["Názov", c.model], ["Kódové meno", z.codename || "neznáme"], ["Výrobca", c.vendor],
                          ["Pätica", rc.socket || (rt ? "" : "— (podrobnosti so správcom)")], ["Technológia", z.nm ? z.nm + " nm" : ""],
                          ["Napätie jadra", rc.voltage || ""], ["Špecifikácia", c.model],
                          ["Rodina · model · stepping", c.family + " · " + c.modelId + " · " + c.stepping], ["Ext. rodina · ext. model", z.extFamily + " · " + z.extModel],
                          ["Mikrokód", c.microcode], ["Inštrukcie", (z.instructions || []).join(", ")]]],
            ["Takty (jadro #0)", [["Rýchlosť jadra", clk0 ? clk0 + " MHz" : ""], ["Násobič", z.baseMHz && clk0 ? "× " + (clk0 / 100).toFixed(1).replace(".", ",") + " (zbernica 100 MHz)" : ""],
                                  ["Základný takt", z.baseMHz ? z.baseMHz + " MHz" : ""], ["Max (turbo)", c.maxMHz ? c.maxMHz + " MHz" : (rc.maxSpeed || "")],
                                  ["Externý takt", rc.extClock || ""], ["Režim výkonu", c.governor]]],
            ["Cache", (z.caches || []).map(x => [x.level === "L1d" ? "L1 dáta" : (x.level === "L1i" ? "L1 inštrukcie" : x.level), x.text])],
            ["Zloženie", [["Pätice", String(z.sockets || 1)], ["Jadrá", String(c.cores)], ["Vlákna", String(c.threads)], ["Adresy", z.addr],
                          ["Zraniteľnosti bez ochrany", (z.vulns || []).length ? z.vulns.join(", ") : "žiadne"]]]];
        case "cache": return (z.caches || []).map(x => [x.level === "L1d" ? "L1 dátová cache" : (x.level === "L1i" ? "L1 inštrukčná cache" : x.level + " cache"),
            [["Veľkosť", (x.count > 1 ? x.count + " × " : "") + x.size.replace("K", " KB")], ["Asociativita", x.ways ? x.ways + "-cestná" : ""],
             ["Dĺžka riadku", x.line ? x.line + " B" : ""], ["Počet množín", x.sets], ["Zdieľajú vlákna", x.sharedBy]]]);
        case "board": return [
            ["Základná doska", [["Výrobca", h.board.board_vendor], ["Model", h.board.board_name], ["Revízia", h.board.board_version || (r.board || {}).version || ""],
                                ["Čipová sada", (h.chipset || []).map(x => x.vendor + " " + x.name).join(" · ")], ["Sériové číslo", (r.board || {}).serial || ""]]],
            ["BIOS / UEFI", [["Výrobca", h.board.bios_vendor], ["Verzia", h.board.bios_version], ["Dátum", h.board.bios_date],
                             ["Štart", h.board.efi ? "UEFI" : "Legacy BIOS"], ["Secure Boot", h.board.secureBoot === null ? "" : (h.board.secureBoot ? "zapnutý" : "vypnutý")]]],
            ["Počítač", [["Výrobca", h.board.sys_vendor], ["Model", h.board.product_name], ["Verzia", h.board.product_version]]],
            ["Grafická linka", (h.gpu || []).map(g => [g.name.replace(/\s*\[[0-9a-f]+\]$/, ""), g.link ? "PCIe " + g.link + (g.linkMax ? " (max " + g.linkMax + ")" : "") : "—"])]];
        case "mem": {
            const mods = (r.modules || []).filter(m => !m.empty), arr = r.memArray || {};
            const types = [...new Set(mods.map(m => m.type))].join(", ");
            return [
                ["Všeobecne", [["Typ", types || (rt ? "" : "— (podrobnosti so správcom)")], ["Veľkosť", human(h.memory.total)],
                               ["Moduly", rt ? mods.length + " z " + ((r.modules || []).length || "?") + " slotov" : ""],
                               ["Kanály", mods.length >= 2 ? (mods.length % 2 === 0 ? "Dual (odhad podľa počtu modulov)" : "Single / zmiešané") : (mods.length === 1 ? "Single" : "")],
                               ["Max. kapacita dosky", arr.maxCapacity || ""], ["ECC", arr.ecc || ""]]],
                ["Takty", [["Frekvencia", mods[0] ? (mods[0].configured || mods[0].speed) : ""], ["Menovitá", mods[0] ? mods[0].speed : ""],
                           ["Napätie", mods[0] ? mods[0].voltage : ""], ["Časovania (SPD)", (r.spdTimings || []).length ? "pozri kartu SPD" : (rt ? "nedostupné (i2c-tools / ee1004)" : "")]]],
                ["Teraz", [["Použitá", human(snap.mem ? snap.mem.used : 0)], ["Vyrovnávacia (cache)", human(h.memory.cached)], ["Swap", human(h.memory.swap)]]]];
        }
        case "spd": {
            const list = (r.modules || []).map(m => [m.slot + (m.bank ? " · " + m.bank : ""),
                [["Stav", m.empty ? "prázdny" : "osadený"], ["Veľkosť", m.size], ["Typ", m.type + (m.form ? " " + m.form : "")], ["Rýchlosť", m.speed + (m.configured && m.configured !== m.speed ? " (beží " + m.configured + ")" : "")],
                 ["Výrobca", m.maker], ["Číslo dielu", m.part], ["Sériové číslo", m.serial], ["Rank", m.rank], ["Napätie", m.voltage], ["Šírka", m.width]]]);
            if ((r.spdTimings || []).length) list.push(["Časovania SPD", r.spdTimings.map(t => [t[0], t[1]])]);
            return list;
        }
        case "gpu": {
            const gl = h.gl || {}, out = (h.gpu || []).map(g => [g.name.replace(/\s*\[[0-9a-f]+\]$/, ""),
                [["Výrobca", g.vendor.replace(/\s*\[[0-9a-f]+\]$/, "")], ["Ovládač", g.driver], ["VRAM", g.vram ? human(g.vram) : "—"],
                 ["PCIe", g.link ? g.link + (g.linkMax ? " (max " + g.linkMax + ")" : "") : ""], ["Slot", g.slot]]]);
            out.push(["OpenGL / Vulkan", [["OpenGL renderer", gl.renderer], ["OpenGL verzia", gl.version], ["GLSL", gl.glsl], ["OpenGL ES", gl.es]]
                .concat((gl.vulkan || []).map(v => ["Vulkan", v.device + " · API " + v.api + " · " + v.driver]))]);
            out.push(["Vykresľovanie LatteOS", [["Režim", (h.renderer.match(/renderer = "([^"]*)"/) || [, ""])[1]], ["Stupeň", (h.renderer.match(/tier = "([^"]*)"/) || [, ""])[1]]]]);
            return out;
        }
        case "disk": return (h.disks || []).map(d => {
            const s = (r.smart || []).find(x => x.name === d.name) || {};
            return [d.name + " · " + (d.model || "disk"), [["Typ", d.kind + (s.rpm ? " · " + s.rpm + " ot/min" : "")], ["Kapacita", human(d.size)], ["Rozhranie", (d.bus || "").toUpperCase()],
                ["Firmvér", s.firmware || d.rev], ["Sériové číslo", s.serial || ""],
                ["Zdravie (SMART)", s.healthy === true ? "✓ v poriadku" : (s.healthy === false ? "✗ ZLYHÁVA — zálohuj" : (rt ? (s.smart === false ? "disk SMART nepodporuje" : "neznáme") : "— (podrobnosti so správcom)"))],
                ["Teplota", s.temp ? s.temp + " °C" : ""], ["Hodiny v prevádzke", s.hours ? s.hours + " h (" + Math.round(s.hours / 24) + " dní)" : ""],
                ["Zapnutí", s.cycles ? String(s.cycles) : ""], ["Zapísané spolu", s.written ? human(s.written) : ""], ["Opotrebenie", s.wear !== undefined && s.wear !== null ? s.wear + " %" : ""]]];
        });
        case "sys": return [
            ["Systém", [["Systém", h.system.os], ["Jadro", h.system.kernel + " · " + h.system.arch], ["Názov PC", h.system.host],
                        ["Virtualizácia", h.system.virt === "none" ? "skutočný hardvér" : h.system.virt]]]]
            .concat((h.battery || []).map(b => ["Batéria " + b.name, [["Nabitie", b.capacity + " % · " + b.status], ["Zdravie", b.health ? b.health + " %" : ""], ["Cykly", b.cycles], ["Model", b.model]]]));
        }
        return [];
    }
    function reportText() {
        const lines = ["Hardvér LatteOS · " + Qt.formatDateTime(new Date(), "d. M. yyyy H:mm"), ""];
        for (const t of tabs) {
            lines.push("== " + t[1] + " ==");
            for (const b of boxesFor(t[0], hw, root, snap, liveClocks)) {
                lines.push("  [" + b[0] + "]");
                for (const r of b[1]) if (r[1] !== "" && r[1] !== undefined && r[1] !== null) lines.push("    " + r[0] + ": " + r[1]);
            }
            lines.push("");
        }
        return lines.join("\n");
    }

    // ── karty ───────────────────────────────────────────────────────────────────────────────
    Row {
        id: tabRow
        spacing: 4
        Repeater {
            model: hv.tabs
            Rectangle {
                required property var modelData
                readonly property bool on: hv.tab === modelData[0]
                width: tl.implicitWidth + 24; height: 32; radius: 10
                color: on ? Qt.rgba(hv.theme.primary.r, hv.theme.primary.g, hv.theme.primary.b, 0.18) : (tm.containsMouse ? hv.theme.hover : hv.theme.field)
                border { color: on ? hv.theme.primary : "transparent"; width: 1.5 }
                Text { id: tl; anchors.centerIn: parent; text: modelData[1]; color: hv.theme.fg; font { family: hv.theme.fontUi; pixelSize: 12; weight: on ? Font.Bold : Font.Medium } }
                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: hv.tab = modelData[0] }
            }
        }
    }
    Flickable {
        id: hflick
        anchors { top: tabRow.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: foot.top; bottomMargin: 8 }
        contentHeight: hcol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollHint { flick: hflick; colors: hv.theme }
        Column {
            id: hcol
            width: hflick.width - 12; spacing: 12
            Text { visible: !hv.hw; text: "Zisťujem hardvér…"; color: hv.theme.fgDim; font { family: hv.theme.fontUi; pixelSize: 13 } }
            // takty a záťaž jadier (ako HWiNFO Core0…)
            Rectangle {
                visible: hv.tab === "cpu" && hv.liveClocks.length > 0
                width: hcol.width; height: coreCol.implicitHeight + 24; radius: 12; color: hv.theme.field
                Column {
                    id: coreCol; x: 14; y: 12; width: parent.width - 28; spacing: 5
                    Text { text: "JADRÁ · TAKT A ZÁŤAŽ (ŽIVO)"; color: hv.theme.fgDim; font { family: hv.theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.6 } }
                    Repeater {
                        model: hv.liveClocks
                        Row {
                            required property var modelData
                            required property int index
                            spacing: 10
                            Text { width: 60; text: "Jadro " + index; color: hv.theme.fg; font { family: hv.theme.fontUi; pixelSize: 12 } }
                            Text { width: 80; text: modelData + " MHz"; color: hv.theme.fg; font { family: hv.theme.fontMono; pixelSize: 12 } }
                            Rectangle {
                                width: coreCol.width - 250; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(0, 0, 0, 0.2)
                                Rectangle { width: parent.width * Math.min(1, (hv.liveUse[index] || 0) / 100); height: parent.height; radius: 6
                                            color: (hv.liveUse[index] || 0) > 85 ? hv.theme.error : hv.theme.primary
                                            Behavior on width { NumberAnimation { duration: 300 } } }
                            }
                            Text { width: 60; text: (hv.liveUse[index] || 0).toFixed(0) + " %"; color: hv.theme.fgDim; font { family: hv.theme.fontUi; pixelSize: 12 } }
                        }
                    }
                }
            }
            Text {
                visible: (hv.tab === "spd" || hv.tab === "mem" || hv.tab === "disk") && !hv.root
                width: hcol.width; wrapMode: Text.WordWrap; color: hv.theme.fgDim; font { family: hv.theme.fontUi; pixelSize: 12 }
                text: "Moduly pamäte, SPD, pätica procesora a SMART diskov čítajú iba správcovské nástroje (dmidecode, smartctl). Klikni na „Podrobnosti so správcom“ dole — výsledok sa uloží a nabudúce už heslo netreba."
            }
            Text {
                visible: hv.tab === "spd" && !!hv.root && (hv.root.modules || []).length === 0
                width: hcol.width; wrapMode: Text.WordWrap; color: hv.theme.fgDim; font { family: hv.theme.fontUi; pixelSize: 12 }
                text: "Firmvér neuvádza žiadne moduly pamäte (vo virtuálnom počítači bežné)."
            }
            Flow {
                width: hcol.width; spacing: 12
                Repeater {
                    model: hv.boxes
                    Rectangle {
                        id: box
                        required property var modelData
                        readonly property var rows: modelData[1].filter(r => r[1] !== "" && r[1] !== undefined && r[1] !== null)
                        visible: rows.length > 0
                        width: hv.tab === "cpu" && modelData[0] === "Procesor" || hv.tab === "gpu" && modelData[0] === "OpenGL / Vulkan" ? hcol.width : (hcol.width - 12) / 2
                        height: bcol.implicitHeight + 26; radius: 12; color: hv.theme.field; border { color: hv.theme.line; width: 1 }
                        Column {
                            id: bcol; x: 14; y: 12; width: parent.width - 28; spacing: 5
                            Text { text: box.modelData[0].toUpperCase(); color: hv.theme.primary; font { family: hv.theme.fontUi; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.6 } }
                            Repeater {
                                model: box.rows
                                Item {
                                    required property var modelData
                                    width: bcol.width; height: Math.max(22, vt.implicitHeight + 6)
                                    Text { id: lt; width: 150; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: hv.theme.fgDim; elide: Text.ElideRight
                                           font { family: hv.theme.fontUi; pixelSize: 12 } }
                                    Rectangle {                                      // „zapustené“ pole ako v CPU-Z
                                        anchors { left: lt.right; right: parent.right; top: parent.top; bottom: parent.bottom }
                                        radius: 6; color: Qt.rgba(0, 0, 0, hv.theme.mode === "dark" ? 0.22 : 0.05)
                                        Text { id: vt; x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.WordWrap
                                               text: String(modelData[1]); color: hv.theme.fg; font { family: hv.theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton
                                                    onClicked: (m) => { const q = mapToItem(null, m.x, m.y); hv.menu(parent.parent.modelData[0] + ": " + parent.parent.modelData[1], q.x, q.y); } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // ── spodná lišta: obnoviť, správca, správa ──────────────────────────────────────────────
    Row {
        id: foot
        anchors { left: parent.left; bottom: parent.bottom }
        spacing: 8; height: 34
        component Btn: Rectangle {
            id: btn
            property string label; property bool primary: false
            signal clicked()
            width: bl.implicitWidth + 24; height: 34; radius: 10
            color: primary ? hv.theme.primary : (bm.containsMouse ? hv.theme.hover : hv.theme.field)
            Text { id: bl; anchors.centerIn: parent; text: btn.label; color: btn.primary ? hv.theme.fgOnPrimary : hv.theme.fg; font { family: hv.theme.fontUi; pixelSize: 12; weight: Font.Bold } }
            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
        }
        Btn { label: "Obnoviť"; onClicked: hv.refresh() }
        Btn { visible: !pwBox.visible; label: hv.rootBusy ? "Načítavam…" : (hv.root ? "Podrobnosti so správcom ↻" : "Podrobnosti so správcom"); primary: !hv.root
              onClicked: { if (!hv.rootBusy) { pwBox.visible = true; pw.forceActiveFocus(); } } }
        Rectangle {
            id: pwBox
            visible: false
            width: 240; height: 34; radius: 10; color: hv.theme.field; border { color: hv.theme.primary; width: 1 }
            TextInput {
                id: pw
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password; passwordCharacter: "•"
                color: hv.theme.fg; font { family: hv.theme.fontUi; pixelSize: 13 }
                Text { visible: !pw.text; anchors.verticalCenter: parent.verticalCenter; text: "heslo správcu, Enter"; color: hv.theme.fgDim; font: pw.font }
                Keys.onReturnPressed: { hv.loadRoot(pw.text); pw.text = ""; pwBox.visible = false; }
                Keys.onEscapePressed: { pw.text = ""; pwBox.visible = false; }
            }
        }
        Btn { label: "Správca zariadení"; onClicked: hv.openDevices() }
        Btn { label: "Uložiť správu"; onClicked: hv.saveReport(hv.reportText()) }
        Btn { label: "Kopírovať"; onClicked: hv.copyText(hv.reportText()) }
        Text { anchors.verticalCenter: parent.verticalCenter; text: hv.rootError; color: hv.theme.error; font { family: hv.theme.fontUi; pixelSize: 12 } }
    }
}
