-- Pošta: skúška farebného jadra ako upozornenia. Každých 12 s príde „nová správa“: jadro sa rozsvieti modrou
-- (softvér) a pulzuje, hladina sa zachveje; klik ju prečíta (jadro zhasne). Pravý klik prepne farbu jadra.
local FARBY = { "softver", "siet", "hardver", "vystraha", "svetlo", "ine" }
return {
    id = "posta", nazov = "Pošta", ikona = "mail", povaha = "pokojna", velkost = 24,
    start = function(d) d.f = 1 end,
    kazdych = 12000,
    tik = function(d)
        if not d.nova then d.nova = true d:jadro(FARBY[d.f], 1, true) d:vibruj(3) end
    end,
    klik = function(d) d.nova = false d:jadro() end,
    pravy = function(d)
        d.f = d.f % #FARBY + 1
        d.nova = true
        d:jadro(FARBY[d.f], 1, true)
        d:bublina("jadro: " .. FARBY[d.f])
    end,
    popis = function(d) return "nová správa = farebné jadro · klik: prečítať · pravý: iná farba" end,
}
