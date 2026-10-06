-- LensGoo (univerzálny spúšťač a lupa, LATTEOS-GOO.md §4.3): základná kvapka s lupou — hľadanie,
-- spúšťač a AI. Stojí na mieste Štartu: 88 px vľavo od hlavy GooBaru, GooPower vľavo od nej (trojica sa prelieva).
-- Ľavý klik alebo kláves Windows = okno spúšťača (lib/spustac.luau): režimy Aplikácie, Súbory, Web, Terminál a AI
-- v karte Goo. Dá sa ovládať celé z klávesnice (Tab režimy, šípky riadok, Enter, Esc) — príkaz aj bez myši.
-- Pravý klik = rýchly zoznam: naposledy spustené a obľúbené aplikácie ako dlaždice s ikonami (používateľ 6. 10.).
local spustac = require("lib/spustac")
return {
    id = "lensgoo", nazov = "LensGoo", zaklad = true, ikona = "search", povaha = "pokojna", velkost = 30, rast = 0.09,
    vyska = 21, vznos = 1, gravitacia = 0.3, dosah = 130, zoom = true, pri = "goobar", odstup = -88,
    start = function(d) spustac.start(d) end,
    klik = function(d) spustac.open(d) end,
    pravy = function(d) spustac.quick(d) end,
    popis = function(d) return tr("left: search, apps, files, web, AI · right: recent apps") end,
}
