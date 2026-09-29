// LatteTheme — farby aktívnej témy LatteOS pre aplikácie (Súbory, Nastavenia…).
// ~/.config/latteos/theme → /usr/share/latteos/themes/<id>.theme → paleta Noctalie (JSON).
// Súbory sa sledujú: `latte-theme set …` prefarbí bežiace aplikácie hneď.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: t
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string cfgHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")

    property string themeId: "latte"
    property string themeName: "Latte"
    property string themeMode: "dark"      // režim z témy
    property string modePref: "tema"       // ~/.config/latteos/theme-mode: tema | dark | light | auto
    property bool daylight: { const h = new Date().getHours(); return h >= 7 && h < 19; }
    readonly property string mode: modePref === "dark" || modePref === "light" ? modePref
                                 : (modePref === "auto" ? (daylight ? "light" : "dark") : themeMode)
    property string paletteName: "Latte"
    property var p: ({})

    // farby (s predvolenými hodnotami palety Latte, kým sa súbory nenačítajú)
    readonly property color surface:        p.mSurface || "#1B1410"
    readonly property color surfaceVariant: p.mSurfaceVariant || "#261D17"
    readonly property color fg:      p.mOnSurface || "#F3EBDD"
    readonly property color fgDim: p.mOnSurfaceVariant || "#CDBCA6"
    readonly property color primary:        p.mPrimary || "#E4B283"
    readonly property color fgOnPrimary:      p.mOnPrimary || "#1E1712"
    readonly property color outline:        p.mOutline || "#4A3B30"
    readonly property color hover:          p.mHover || "#3A2D24"
    readonly property color error:          p.mError || "#E07A5F"
    // stav NET nezávisle od palety (zapnutý = zelené plné koliesko, vypnutý = červené prázdne — tvar aj pre farboslepých)
    readonly property color netOnColor:  "#3FB950"
    readonly property color netOffColor: "#E5484D"
    readonly property color field: Qt.rgba(0, 0, 0, mode === "dark" ? 0.25 : 0.06)
    readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.10)

    readonly property string fontUi: "Manrope"
    readonly property string fontDisplay: "Fraunces"
    readonly property string fontMono: "JetBrains Mono"
    readonly property int radius: 14
    // animácie: pri stupni Softvér/Minimálny (VM, slabé PC) žiadne — kreslí CPU
    readonly property string tier: Quickshell.env("LATTE_TIER") || ""
    // sklo: okná LatteOS nechajú bočný panel polopriehľadný a Hyprland rozmaže, čo je za ním (blur je iba pri Plnom a Štandarde)
    readonly property bool glass: tier === "plny" || tier === "standard"
    readonly property int animMs: (tier === "softver" || tier === "minimalny" || tier === "safe") ? 0 : 180

    FileView {
        path: t.cfgHome + "/latteos/theme-mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: t.modePref = (text().trim() || "tema")
        onLoadFailed: t.modePref = "tema"
    }
    // automatický režim: približne podľa dňa (presný východ/západ slnka rieši Noctalia podľa polohy)
    Timer { interval: 300000; repeat: true; running: t.modePref === "auto"; onTriggered: { const h = new Date().getHours(); t.daylight = h >= 7 && h < 19; } }

    FileView {
        path: t.cfgHome + "/latteos/theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: t.themeId = (text().trim() || "latte")
        onLoadFailed: t.themeId = "latte"
    }
    FileView {
        path: "/usr/share/latteos/themes/" + t.themeId + ".theme"
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const m = line.match(/^(\w+) = (.*)$/);
                if (!m) continue;
                if (m[1] === "name") t.themeName = m[2];
                else if (m[1] === "mode") t.themeMode = m[2];
                else if (m[1] === "palette") t.paletteName = m[2];
            }
        }
    }
    FileView {
        path: "/usr/share/latteos/noctalia/palettes/" + t.paletteName + ".json"
        printErrors: false
        onLoaded: {
            try { t.pj = JSON.parse(text()); } catch (e) { console.warn("LatteTheme: paleta", t.paletteName, e); }
        }
    }
    property var pj: ({})
    onModeChanged: p = pj[mode] || pj.dark || {}
    onPjChanged: p = pj[mode] || pj.dark || {}
}
