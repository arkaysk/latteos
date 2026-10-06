-- Goobar (lišta s oknami, LATTEOS-GOO.md §4.1): hlava = obraz režimu okien (plávajúce / dlaždice / páska); vpravo od
-- nej okná ako ikry/hrozno po aplikáciách (lib/goobar.luau). Ľavý klik na hlavu = ďalší režim okien, koliesko =
-- páska sa posúva / ďalšie okno, pravý klik = UKÁZAŤ PLOCHU (ako roh lišty vo Windows 11 a Win+D: okná zmiznú, druhý
-- pravý klik ich vráti; používateľ 6. 10.). Veľkosť hlavy je v Nastaveniach › Kvapky (koliesko patrí oknám). Rozmery a rozostupy ako v ploche Kvapky (TimeGoo 92 px vľavo, PowerGoo ďalších 66).
-- Hlava patrí do oboch skupín (sk = 2): spája sa s TimeGoo aj so svojimi oknami; okná iba s ňou. Všetko je jedno
-- goo telo, takže obrys je spoločný (dve telá kreslili okolo hlavy deliacu čiaru aj tam, kde bola zliata).
local goobar = require("lib/goobar")
return {
    id = "goobar", nazov = "GooBar", zaklad = true, vratit = true, ikona = "app-window", povaha = "pokojna", velkost = 44, vyska = 22, sk = 2,
    poloha = { x = 0.42, y = 22 }, gravitacia = 0.25, vznos = 0.7,
    popis = function(d) return tr("left: window mode · wheel: next window · right: show desktop") end,
    start = function(d) goobar.start() end,
    klik = function(d) goobar.head_click() end,
    koliesko = function(d, smer) goobar.head_wheel(smer) end,
    pravy = function(d) goobar.show_desktop() d:vlnka(3) end,
}
