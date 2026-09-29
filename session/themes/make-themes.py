#!/usr/bin/env python3
"""Vygeneruje témy LatteOS: session/themes/<id>.theme + session/noctalia/palettes/<Paleta>.json.

Farby sú vytiahnuté z inspo/LatteOS – návrh plochy (obrazovky „témy materiálov“ a „drahokamy a klasické“).
Materiál (pohyblivé textúry: mráz, brúsený kov, kameň, jantár, fazety) je zatiaľ iba popis a kľúč
`material`; kresliť ho bude fork Noctalie (shadery) a zapne sa iba pri stupni Plný/Štandard.

Použitie: session/themes/make-themes.py   (prepíše vygenerované súbory; Latte.json nechá tak)
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PAL = os.path.join(HERE, "..", "noctalia", "palettes")

# id: (názov, popis, mode, paleta, material, efekty,
#      primary, onPrimary, surface, surfaceVariant, onSurface, onSurfaceVariant, outline, hover, tapeta)
THEMES = {
    "latte":      ("Latte", "Predvolená · teplé tmavé sklo · jemné animácie", "dark", "Latte", "sklo", "jemne",
                   None, None, None, None, None, None, None, None, "latteos-wallpaper2.jpg"),
    "mraz":       ("Mráz", "Ľad · kresby rastú pri nečinnosti · para nad šálkou topí mráz", "light", "LatteMraz", "mraz", "plne",
                   "#3B8FC4", "#FFFFFF", "#EAF4FB", "#D6ECFA", "#10283D", "#3A5A74", "#A9C9DE", "#CFE4F3", ""),
    "hlinik":     ("Brúsený hliník", "Brúsený kov · odlesk podľa myši · okno sa vlní ako plech", "light", "LatteHlinik", "kov", "plne",
                   "#5D6B78", "#FFFFFF", "#D9DDE1", "#C9CED3", "#1C2126", "#4A525A", "#A3AAB1", "#BFC5CB", ""),
    "striebro":   ("Striebro", "Leštené striebro · chladný odlesk", "light", "LatteStriebro", "kov", "plne",
                   "#7A8794", "#FFFFFF", "#E6E9EC", "#D6DADF", "#1A1D21", "#50575F", "#B4BBC2", "#CDD2D7", ""),
    "zlato":      ("Zlato", "Brúsené zlato · teplý odlesk podľa myši", "light", "LatteZlato", "kov", "plne",
                   "#9C7A2E", "#FFF8E6", "#EFE2C4", "#E3CF9F", "#2B1F08", "#5E4A22", "#C7AE74", "#E0CB95", ""),
    "bielyonyx":  ("Biely onyx", "Priesvitný biely kameň so žilkovaním · profesionálny svetlý vzhľad", "light", "LatteBielyOnyx", "kamen", "jemne",
                   "#8C7B6B", "#FFFFFF", "#F6F2EC", "#E6E0D8", "#2A2622", "#6E6358", "#CFC6BB", "#EAE3DA", ""),
    "onyx":       ("Onyx", "Tmavý priesvitný kameň · svetlo presvitá cez žilky", "dark", "LatteOnyx", "kamen", "jemne",
                   "#D9C7B0", "#1E1C1A", "#1E1C1A", "#2A2724", "#EDE6DC", "#BDB3A6", "#4A443E", "#36322E", "latteos-wallpaper1.jpg"),
    "jantar":     ("Jantár", "Teplá priesvitnosť s bublinkami a inklúziami", "dark", "LatteJantar", "jantar", "jemne",
                   "#E2963C", "#2A1606", "#2A1606", "#3D2210", "#FFE6B4", "#E0B98A", "#6B4220", "#4A2B14", ""),
    "rubin":      ("Rubín", "Fazety · iskrenie pri pohybe myši · okno sa rozpadne na fazety", "dark", "LatteRubin", "fazety", "plne",
                   "#FF96AA", "#3A0712", "#3A0712", "#52101F", "#FFEFF2", "#F2B8C4", "#7D0F24", "#5E1426", ""),
    "zirkon":     ("Zirkón", "Číry kryštál · dúhový oheň na hranách", "light", "LatteZirkon", "fazety", "plne",
                   "#4F8FC9", "#FFFFFF", "#E8EEF5", "#D8E2EE", "#1C2430", "#4E5B6D", "#B3C2D4", "#CCD8E6", ""),
    "kancelaria": ("Klasik – kancelária", "Inšpirované Windows · plochá svetlá lišta · bez efektov", "light", "LatteKancelaria", "ziadny", "ziadne",
                   "#2B6CD6", "#FFFFFF", "#FAFAFA", "#E6E6E6", "#1B1B1B", "#555555", "#D0D0D0", "#DDDDDD", ""),
    "launcher":   ("Klasik – herný launcher", "Inšpirované Steamom · tmavomodré plochy, modrý akcent", "dark", "LatteLauncher", "ziadny", "ziadne",
                   "#66C0F4", "#171D25", "#171D25", "#1B2838", "#C7D5E0", "#8BA3B8", "#2A475E", "#22324A", ""),
    "svetlesklo": ("Klasik – svetlé sklo", "Inšpirované macOS · svetlé priesvitné ostrovy, veľké zaoblenia", "light", "LatteSvetleSklo", "sklo", "jemne",
                   "#3478F6", "#FFFFFF", "#ECEEF2", "#FFFFFF", "#1D1D1F", "#5B5B60", "#D2D5DB", "#E2E5EA", ""),
    "usporna":    ("Úsporná (FPS)", "Plné farby · bez priehľadnosti, tieňov, blur a animácií", "dark", "LatteUsporna", "ziadny", "ziadne",
                   "#9AD36A", "#111111", "#1C1C1C", "#2E2E2E", "#DADADA", "#A0A0A0", "#3A3A3A", "#333333", ""),
}


def terminal(surface, fg, primary, dark):
    base = {"black": surface, "red": "#C8574A", "green": "#7FA35B", "yellow": "#C9A458",
            "blue": "#4F7FB8", "magenta": "#A0679B", "cyan": "#4F9C99", "white": fg}
    return {"background": surface, "foreground": fg, "cursor": primary, "cursorText": surface,
            "selectionBg": primary, "selectionFg": surface, "normal": base, "bright": base}


def palette(t):
    _, _, mode, _, _, _, p, op, s, sv, os_, osv, ol, hv, _ = t
    side = {"mPrimary": p, "mOnPrimary": op, "mSecondary": p, "mOnSecondary": op, "mTertiary": p,
            "mOnTertiary": op, "mError": "#D0453A", "mOnError": "#FFFFFF", "mSurface": s, "mOnSurface": os_,
            "mSurfaceVariant": sv, "mOnSurfaceVariant": osv, "mOutline": ol, "mShadow": "#000000",
            "mHover": hv, "mOnHover": os_, "terminal": terminal(s, os_, p, mode == "dark")}
    return {"dark": side, "light": side}   # téma má jeden vzhľad; svetlá/tmavá určuje `mode`


for tid, t in THEMES.items():
    name, desc, mode, pal, material, effects = t[:6]
    primary = t[6] or "#E4B283"
    outline = t[12] or "#4A3B30"
    wallpaper = t[14]
    with open(os.path.join(HERE, tid + ".theme"), "w") as f:
        f.write(f"# LatteOS téma — vygeneroval make-themes.py\n")
        f.write(f"name = {name}\ndesc = {desc}\nmode = {mode}\npalette = {pal}\n")
        f.write(f"material = {material}\neffects = {effects}\n")
        f.write(f"border_active = {primary.lstrip('#')}\nborder_inactive = {outline.lstrip('#')}\n")
        f.write(f"wallpaper = {wallpaper}\n")
    if tid != "latte":
        with open(os.path.join(PAL, pal + ".json"), "w") as f:
            json.dump(palette(t), f, indent=2, ensure_ascii=False)
print(f"{len(THEMES)} tém")
