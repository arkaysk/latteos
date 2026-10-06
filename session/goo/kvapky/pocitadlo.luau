-- Počítadlo: skúška všetkých vstupov myši. Ľavé +1, pravé −1, stredné vynuluje, koliesko ±10, podržanie
-- vynuluje so skokom; prechod myšou ukáže návod. Ukazovateľ (prstenec) = počet do 100.
local function show(d)
    d:text(tostring(d.n))
    d:hodnota((d.n % 100) / 100)
    -- od 10 výstraha v jadre (jantárová), pod nulou hardvér (červená)
    if d.n >= 10 then d:jadro("vystraha", 0.9, false) elseif d.n < 0 then d:jadro("hardver", 0.9, true) else d:jadro() end
end

return {
    id = "pocitadlo", nazov = "Počítadlo", ikona = "number-123", druh = "ukazovatel", povaha = "pokojna",
    velkost = 30,
    start = function(d) d.n = 0 show(d) end,
    klik = function(d) d.n += 1 show(d) end,
    pravy = function(d) d.n -= 1 show(d) end,
    stredny = function(d) d.n = 0 show(d) end,
    koliesko = function(d, smer) d.n += 10 * smer show(d) end,
    podrz = function(d) d.n = 0 show(d) d:poskoc() end,
    popis = function(d)
        return "ľavé +1 · pravé −1 · stredné 0 · koliesko ±10 · podržať 0"
    end,
}
