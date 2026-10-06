-- engine Goo — logika: register kvapiek. Jedny pravidlá pre všetky kvapky; kvapka je iba DEFINÍCIA (tabuľka)
-- s číslami (povaha) a voliteľnými háčikmi (správanie). Scéna (goo.plm) robí fyziku a vstupy myši, táto vrstva
-- rozhoduje, čo sa stane: klik, pravé a stredné tlačidlo, podržanie, koliesko, prechod, ťahanie a pustenie,
-- nečinnosť. Pravidlá plochy sú v LATTEOS-GOO.md (§2, §3): kontextový klik iba tam, kde ho má funkcia (8) —
-- čo kvapka nemá, nerobí nič; engine za ňu robí iba spoločné veci (ťahanie, prilepenie k lište, uloženie, hra).
--
-- Zdroje kvapiek (README.md):
--   programátor  modul Luau v kvapky/<meno>.luau, vracia definíciu (aj s háčikmi); zoznam.luau = gen.py
--   používateľ   JSON v ~/.config/latteos/goo/kvapky/*.json (latte-goo zoznam); kedykoľvek, bez reštartu
--
-- Definícia (všetko voliteľné okrem id):
--   id, nazov, ikona (meno Tabler alebo znak), text, popis (bublina pri prechode myšou)
--   povaha     "pokojna" | "zvedava" | "lepkava" | "tazka" | "hrava" — balík čísel nižšie
--   velkost    polomer (px)   (farbu nemá: kvapky sú vždy káva podľa Baristu — pravidlo 6)
--   gravitacia 0…1 (kurzor iba priťahuje)   dosah px   vznos 0…1 (nadnesenie pri priblížení kurzora)
--   lepivost 0…1   trhanie px   svetlo 0…1   rast (nafúknutie nad kvapkou)   tahat (bool)
--   hmotnost 0…1 (po pustení padne na lištu)   zoom (bool, predvolene áno: koliesko mení veľkosť, ak kvapka nemá
--              vlastný háčik — „zväčšovať sa dajú všetky“, používateľ 6. 10.; okná GooBaru nie)
--   kw, kd     kapsula: polovica rovnej časti (px) a smer, kam rastie pozdĺž okraja (0 obe strany, −1 / +1 jedna —
--              pás výkonu GooPower); pravidlo 22 ráta s celou dĺžkou   fix (bool: nesadá si v pokoji)
--   efekt      "dych" "kmit" "tras" "obeh" "tlkot" (+ sila 0…2); rezerva: čísla 6–9 a kanály e1…e4
--   druh       "ikona" | "ukazovatel" (prstenec podľa hodnota 0…1)
--   poloha     { x = 0…1 šírky, y = px nad lištou }   (inak sa kvapky radia zľava po lište)
--   pri, odstup  kvapka vedľa inej o presný odstup v px (napr. PowerGoo 66 px vľavo od TimeGoo)
--   vyska      výška stredu nad lištou v px, keď na nej sedí (inak 0,8 · velkost)
--   vznos      0…2 (1 = nadnesie sa o 0,75 polomeru; PowerGoo v Kvapkách skoro 1,4)
-- Háčiky (funkcie, dostanú kvapku `d`, na ktorej sú metódy nižšie):
--   start(d) · klik(d) · pravy(d) · stredny(d) · podrz(d) · koliesko(d, smer ±1) · nad(d) · prec(d)
--   popis(d) → text bubliny · tahanie(d) · pustenie(d, x, y) → false = nepresúvať · necinnost(d, uroven 0…3)
--   tik(d) každých `kazdych` ms
-- Metódy kvapky: d:text(s) d:ikona(meno) d:hodnota(v) d:nazov(s) d:efekt(meno, sila) d:rezerva(i, v)
--   d:velkost(z) d:presun(x, y) d:domov() d:poskoc() d:bublina(text) d:nastav{…pole = hodnota…}
--   d:jadro(farba, sila, pulz) — farebné jadro (predvolene upozornenie): "hardver" "siet" "softver" "vystraha"
--     "svetlo" "ine"; d:jadro() zhasne · d:vlnka(sila) kameň do vody pri kvapke · d:vibruj(sila)
-- Hladina: E.vlnka(x_px, sila, "kamen"|"vibracia"); zvonka `pleamar --say goo "emit goo_kamen 512"` (x v px),
--   napr. minimalizované okno padne do lišty (pravidlo 14: „žblnkne ako voda“)

local E = {}
local N = type(fact.miesta) == "number" and fact.miesta or 128   -- miesta v scéne (gen.py --n): menšia scéna stojí menej
-- (Goobar nesie okná ako ikry/hrozno, pri veľkej RAM ich je veľa — preto až 128; bežne stačí 32)
E.N = N

-- efekty scény (čísla v goo.plm); 6–9 rezerva pre efekty, ktoré ešte nie sú
local EFEKTY = { nic = 0, dych = 1, kmit = 2, tras = 3, obeh = 4, tlkot = 5 }
local DRUHY = { ikona = 0, ukazovatel = 1, hodiny = 2 }
-- jadro: farby upozornení podľa pravidla 15 (červená hardvér, zelená sieť, modrá softvér) + výstraha, svetlo, iné
local JADRO = { hardver = 0, siet = 1, softver = 2, vystraha = 3, svetlo = 4, ine = 5 }
-- povahy: balíky čísel (dajú sa prepísať jednotlivo v definícii)
E.POVAHY = {
    pokojna = { gravitacia = 0.12, lepivost = 0.2, efekt = "dych", sila = 0.6 },
    zvedava = { gravitacia = 0.6, dosah = 280, efekt = "dych", rast = 0.12 },
    lepkava = { gravitacia = 0.25, lepivost = 0.9, trhanie = 120, efekt = "kmit", sila = 0.4 },
    tazka   = { gravitacia = 0.05, hmotnost = 1, lepivost = 0.35, velkost = 30, vznos = 0.5 },
    hrava   = { gravitacia = 0.4, dosah = 240, efekt = "kmit", sila = 0.8, hrava = true },
}
local PREDVOLENE = { velkost = 26, gravitacia = 0.3, dosah = 220, vznos = 1, lepivost = 0, trhanie = 90, svetlo = 0.5,
                     rast = 0.08, tahat = true, hmotnost = 0, efekt = "nic", sila = 1, druh = "ikona", zoom = true }
local ZOOM_MIN, ZOOM_MAX = 0.5, 2.2        -- veľkosť 50–220 % (používateľ 5. 10.: vyfúknutá môže byť polovičná);
                                           -- s veľkosťou rastie aj ikona a text, pod 80 % ukáže goo menej detailov

local slots = {}          -- k (0…N−1) → kvapka
local byId = {}           -- id → kvapka
local glyphs = {}         -- meno ikony → znak (latte-goo ikony)
local saved = {}          -- id → { x, y, z } (latte-goo stav)
local dirty, publishing = false, false
local Kvapka = {}
Kvapka.__index = Kvapka

local function num(v, d) return type(v) == "number" and v or d end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- meno ikony (napr. "eye", "123") vs. hotový znak písma (jeden znak mimo ASCII, napr. "\u{EA38}")
local function isName(s) return type(s) == "string" and s ~= "" and s:byte(1) < 128 end

-- logika → scéna pre jednu kvapku: `emit` v Luau nenesie hodnotu, preto počítadlo (scéna: on change)
local function bump(name, k)
    local n = name .. "." .. k
    fact[n] = (fact[n] or 0) + 1
end
E.bump = bump

local function hud(s)
    if E.ladenie then text.hud = s end
end

-- okraj kvapky (d.edge): 0 dole, 1 vľavo, 2 hore, 3 vpravo. d.x je zlomok DĹŽKY okraja, d.y vzdialenosť od neho (px)
local function side(d) return (d.edge or 0) % 2 == 1 end
local function elen(d)
    local l = num(side(d) and fact.sh or fact.sw, 0)
    return l > 0 and l or (side(d) and 1080 or 1920)
end
local function along(d) return d.x * elen(d) + (d.ox or 0) end
E.len, E.along = elen, along

-- rohová lišta Noctalie (latte-goo okna › roh, vpravo dole) je pre Goo ZAKÁZANÁ ZÓNA (používateľ 5. 10.): má
-- premenlivú šírku — pribúdajú do nej widgety a doplnky Noctalie — preto sa číta priebežne a kvapky jej ustúpia.
-- „Lišta sa zmestí po kraj obrazovky a zastaví pred rohovými prvkami“ (Nová architektúra, GooBar)
local roh = nil
local function hiAlong(d)                                -- najďalej pozdĺž okraja, kam smie stred kvapky (px)
    local l = elen(d)
    local hi, r = 0.98 * l, d.v.velkost * d.z
    if roh and (roh.w or 0) > 0 then
        if (d.edge or 0) == 0 and roh.x > l * 0.5 then hi = math.min(hi, roh.x - 8 - r) end
        if (d.edge or 0) == 3 and roh.y > l * 0.5 then hi = math.min(hi, roh.y - 8 - r) end
    end
    return hi
end
E.hiAlong = hiAlong

-- ── záznam pre scénu ─────────────────────────────────────────────────────────────────────────────────────────
local function record(d)
    local v = d.v
    local ik = v.ikona or ""
    -- meno ikony → znak (kým nepríde, bez ikony); druh 2 (hodiny) má v poli ikony veľký text, nie ikonu
    if isName(ik) and v.druh ~= 2 then ik = glyphs[ik] or "" end
    return {
        on = not d.hidden, hx = d.x, ox = d.ox or 0, hy = d.y, r = v.velkost, z = d.z, rast = v.rast,
        grav = d.pinned and 0 or clamp(num(v.gravitacia, 0), 0, 1), dosah = v.dosah, vz = clamp(num(v.vznos, 1), 0, 2),
        lep = v.lepivost, trh = v.trhanie, svetlo = v.svetlo, tahat = v.tahat,
        fx = EFEKTY[v.efekt] or num(v.efekt, 0), fa = v.sila,
        e1 = d.e[1], e2 = d.e[2], e3 = d.e[3], e4 = d.e[4],
        druh = DRUHY[v.druh] or num(v.druh, 0), hodnota = num(v.hodnota, 0),
        ikona = ik, text = v.text or "",
        jadro = d.jadroS or 0, jf = d.jadroF or 0, jp = d.jadroP or false,
        obr = v.obr or "", img = (v.obr or "") ~= "", tlm = d.tlm or 0,
        gn = d.gn or 0, gf = d.gf or 0, gt = d.gt or "", sk = num(v.sk, 0), zl = num(v.zliatie, 1), ml = num(v.mlaka, 1),
        ed = d.edge or 0, nad = v.koruna and (glyphs[v.koruna] or "") or "",
        kw = num(v.kw, 0), t2 = v.t2 or "", kr = (v.t2 or "") ~= "" and 2 or 1,
        kd = num(v.kd, 0), fix = v.fix == true,
        jmp = v.jmp == true, ja = num(v.ja, 0), jb = num(v.jb, 0), jv = num(v.jv, 0),
    }
end

-- susedia na lište: kvapky, ktoré na nej sedia, zoradené zľava; susedné do vzdialenosti ~2,6 súčtu polomerov sa
-- navzájom nadnášajú, nakláňajú a spája ich goo vlákno (ako vypínač ↔ Hodiny ↔ hlava v Kvapkách). Logika nepozná
-- šírku obrazovky: poradie a medzera sa rátajú pri bežnej šírke 1920 px, scéna polohu prepočíta presne.
local NOMINAL_W = 1920
-- najväčšia vzdialenosť stredov, na ktorú sa susedia ešte spoja vláknom (v súčtoch polomerov); ďalej sa pretrhne.
-- Používateľ 5. 10.: vzdialenosť krajných kvapiek na jeho snímke (~2,3) „nech je maximum“ (bolo 2,6)
local THREAD_MAX = 2.3
local function neighbours(list)
    local docked = {}
    for _, d in ipairs(list) do
        d.nl, d.nr = nil, nil
        -- ťahaná nie je susedom (inak by k jej starému miestu viselo dlhé vlákno)
        if d.y < d.v.velkost * 1.6 and not d.dragging and not d.hidden then table.insert(docked, d) end
    end
    table.sort(docked, function(a, b)
        if (a.edge or 0) ~= (b.edge or 0) then return (a.edge or 0) < (b.edge or 0) end
        return along(a) < along(b)
    end)
    -- susedia iba v rámci jedného goo tela: ikry Goobaru (sk 1) s hlavou (sk 2) a navzájom, ostatné (sk 0) s hlavou
    local function same_body(a, b)
        local x, y = num(a.v.sk, 0), num(b.v.sk, 0)
        return x == y or x == 2 or y == 2
    end
    for i = 1, #docked - 1 do
        local a, b = docked[i], docked[i + 1]
        local gap = along(b) - along(a)
        if (a.edge or 0) == (b.edge or 0) and same_body(a, b) and gap < THREAD_MAX * (a.v.velkost * a.z + b.v.velkost * b.z) then a.nr, b.nl = b, a end
    end
end

-- ── kvapky sa nikdy úplne neprekryjú (pravidlo 22) ───────────────────────────────────────────────────────────
-- Dve kvapky smú byť pri sebe a zlievať sa, ale stredy musia ostať aspoň 0,72 súčtu polomerov od seba. Ak nie (napr.
-- jedna pustená na druhú), jedna sa plynule odsunie: kvapka na lište pozdĺž lišty, voľná smerom od druhej. Ustúpi
-- tá, ktorú možno posunúť — nie okná Goobaru (rozloženie) ani kvapky pripnuté k inej (TimeGoo, PowerGoo); z dvoch
-- posunuteľných ustúpi tá, na ktorú niečo pustili. Odsunutie sa reťazí (najviac 10 kôl) a uloží.
local save                 -- nižšie (uloženie polôh)
-- mená kvapiek pred „Novou architektúrou“ (5. 10.): uložená poloha a veľkosť prejdú na novú kvapku
local STARE = { lensgoo = "timegoo", clockgoo = "danogoo", goopower = "powergoo" }
local MIN_GAP = 0.95        -- stredy aspoň 0,95 súčtu polomerov: dotýkajú sa a zlievajú, neprekrývajú (pri 0,72 veľká
                            -- kvapka malú skoro celú zakryla: TimeGoo pod hlavou Goobaru, latte-lab 5. 10.)
local GAP_IKRY = 1.2        -- cudzia kvapka pri ikrách okien: mimo dosahu zliatia (ikry sa lepia iba ku Goobaru)
local sepDirty, sepPrefer = false, nil
-- kvapka pripnutá k inej (pri) neustupuje — iba kapsule so smerom (pás výkonu), ktorá sa jej sama nedrží (inak by ju
-- kapsula naháňala): pás natiahnutý k LensGoo ju inak celú prekryl (latte-lab 6. 10.); po vtiahnutí ju GooPower vráti
local function movable(d, other)
    if d.zdroj == "dyn" or d.dragging then return false end
    if not d.def.pri then return true end
    return other ~= nil and num(other.v.kd, 0) ~= 0 and (other.moved == true or other.def.pri ~= d.def.id)
end
-- kapsula (pás výkonu GooPower): jej stred leží mimo stredu kvapky (kd = smer) a pozdĺž okraja siaha o kw ďalej —
-- susedia sa odsunú od CELEJ kapsuly (používateľ 6. 10.: „keď sa zväčší na kapsulu, okolné goo odtlačí od seba“)
local function capOff(d) return num(d.v.kw, 0) * num(d.v.kd, 0) end
local function reach(d) return d.v.velkost * d.z + num(d.v.kw, 0) end
E.capOff = capOff
local function separate()
    local sw = num(fact.sw, 0)
    if sw <= 0 then sw = 1920 end
    local list = {}
    for k = 0, N - 1 do if slots[k] and not slots[k].hidden then table.insert(list, slots[k]) end end
    local moved = {}
    -- pred rohovou lištou sa kvapka zastaví (nie ikry — tie rozkladá Goobar po voľnú dĺžku)
    for _, d in ipairs(list) do
        if d.zdroj ~= "dyn" and not d.dragging and d.y < d.v.velkost * d.z * 1.6 and along(d) > hiAlong(d) + 0.5 then
            d.x = (hiAlong(d) - (d.ox or 0)) / elen(d)
            moved[d] = true
        end
    end
    for _ = 1, 10 do
        local any = false
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                -- všetky kvapky sú v jednom goo tele. Ikry okien (sk 1) rozkladá Goobar: medzi sebou a s jeho
                -- hlavou (sk 2) sa neodsúvajú; cudzia kvapka od nich ustúpi ďalej, aby sa s nimi nezliala
                local sa, sb = num(a.v.sk, 0), num(b.v.sk, 0)
                local ikra = sa == 1 or sb == 1
                if (a.edge or 0) == (b.edge or 0) and not (ikra and (sa == sb or sa == 2 or sb == 2)) then
                    local sw = elen(a)
                    local ax, ay = along(a) + capOff(a), a.y
                    local bx, by = along(b) + capOff(b), b.y
                    local need = (ikra and GAP_IKRY or MIN_GAP) * (reach(a) + reach(b))
                    local dx, dy = bx - ax, by - ay
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < need - 0.5 then
                        -- kto ustúpi: posunuteľná; z dvoch tá, na ktorú pustili (sepPrefer = pustená ostáva)
                        local mv, other
                        if movable(b, a) and (b ~= sepPrefer or not movable(a, b)) then mv, other = b, a
                        elseif movable(a, b) then mv, other = a, b end
                        if mv then
                            local ox, oy = along(mv) + capOff(mv), mv.y
                            local px, py = along(other) + capOff(other), other.y
                            local vx, vy = ox - px, oy - py
                            local docked = oy < mv.v.velkost * mv.z * 1.6
                            if docked then vy = 0 end
                            local len = math.sqrt(vx * vx + vy * vy)
                            if len < 0.5 then vx, vy, len = 1, 0, 1 end      -- presne na sebe: doprava
                            local push = need - dist + 2
                            mv.x = clamp((ox + vx / len * push - capOff(mv) - (mv.ox or 0)) / sw, 0.02, hiAlong(mv) / sw)
                            mv.y = math.max(0, oy + vy / len * push)
                            -- pri okraji obrazovky nemá kam: odsunie sa na druhú stranu
                            if (mv.x <= 0.02 or mv.x >= hiAlong(mv) / sw - 0.0005) and docked then
                                mv.x = clamp((px - vx / len * need - capOff(mv) - (mv.ox or 0)) / sw, 0.02, 0.98)
                            end
                            mv.moved = true
                            moved[mv] = true
                            any = true
                        end
                    end
                end
            end
        end
        if not any then break end
    end
    for d in pairs(moved) do bump("sqn", d.k) end          -- odsunutá sa zachveje
    if next(moved) then save() end
    sepPrefer = nil
end
function E.setCorner(r)
    local a, b = roh or {}, r or {}
    if a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h then return end
    roh = r
    E.separate() E.publish()
end
function E.separate(prefer) sepDirty, sepPrefer = true, prefer or sepPrefer end

-- kotva (pri): kým kvapku nikto sám nepresunul, drží sa AKTUÁLNEJ polohy svojej kotvy — aj keď kotvu potiahnu
-- alebo ju odsunie pravidlo 22 (ikry okien pri hlave Goobaru, PowerGoo pri TimeGoo)
local postPublish = {}
local function anchor(d, depth)
    local a = d.def.pri and byId[d.def.pri]
    if not a or d.moved or d.dragging or d.wander or depth > 4 then return end
    anchor(a, depth + 1)
    d.x, d.ox, d.edge = a.x, (a.ox or 0) + num(d.def.odstup, 0), a.edge or 0
end

local function publish()
    if publishing then dirty = true return end
    publishing = true
    after(16, function()                                 -- viac zmien v jednom kroku = jeden zápis
        for k = 0, N - 1 do if slots[k] then anchor(slots[k], 0) end end
        if sepDirty then
            sepDirty = false
            separate()
            for k = 0, N - 1 do if slots[k] then anchor(slots[k], 0) end end
        end
        local live = {}
        for k = 0, N - 1 do if slots[k] then table.insert(live, slots[k]) end end
        neighbours(live)
        local list = {}
        for k = 0, N - 1 do
            local d = slots[k]
            if d then
                local r = record(d)
                if d.nl then r.nl, r.nlh, r.nlo = true, d.nl.x, d.nl.ox or 0 end
                if d.nr then r.nr, r.nrh, r.nro, r.nry, r.nrr = true, d.nr.x, d.nr.ox or 0, d.nr.y, d.nr.v.velkost * d.nr.z end
                list[k + 1] = r
            else
                list[k + 1] = { on = false }
            end
        end
        model.goo = list
        -- čo musí prísť do scény v tom istom kroku ako nový domov (inak by kvapka na snímku skočila)
        local q = postPublish
        postPublish = {}
        for _, f in ipairs(q) do f() end
        publishing = false
        if dirty then dirty = false publish() end
    end)
end
E.publish = publish

-- ── uloženie polôh a veľkostí (latte-goo stav / uloz-stav) ─────────────────────────────────────────────────────
local saveTimer
save = function()
    if saveTimer then cancel(saveTimer) end
    saveTimer = after(1200, function()
        saveTimer = nil
        local out = {}
        for id, d in pairs(byId) do
            if d.moved or d.z ~= 1 then out[id] = { x = d.x, y = d.y, z = d.z, e = d.edge or 0 } end
        end
        run("latte-goo", { "uloz-stav", json.encode(out) }, nil, { output = false })
    end)
end
E.save = function() save() end

-- ── metódy kvapky (pre háčiky) ───────────────────────────────────────────────────────────────────────────────
function Kvapka:nastav(t) for key, val in pairs(t) do self.v[key] = val end publish() end
function Kvapka:text(s) self.v.text = s or "" publish() end
function Kvapka:nazov(s) self.v.nazov = s or "" publish() end
function Kvapka:ikona(s) self.v.ikona = s if self.v.druh ~= 2 then E.needGlyph(s) end publish() end
function Kvapka:hodnota(x) self.v.hodnota = x publish() end
function Kvapka:efekt(meno, sila) self.v.efekt = meno self.v.sila = sila or self.v.sila publish() end
function Kvapka:rezerva(i, x) self.e[i] = x publish() end
function Kvapka:velkost(z)
    local old = self.z
    self.z = clamp(z, ZOOM_MIN, ZOOM_MAX)
    -- sediaca kvapka rastie od hladiny: výška stredu nad okrajom sa mení s veľkosťou (inak by väčšej kvapke okraj
    -- obrazovky orezal spodok obsahu)
    if old > 0 and self.y < self.v.velkost * old * 1.6 then self.y = self.y / old * self.z end
    E.separate(self) publish() save()
end
function Kvapka:presun(x, y) self.x, self.y, self.ox = clamp(x, 0.02, 0.98), math.max(0, y), 0 self.moved = true publish() save() end
function Kvapka:domov() self.x, self.y, self.ox, self.z, self.moved, self.edge = self.hx0, self.hy0, self.ox0, 1, false, self.edge0 or 0 publish() save() end
function Kvapka:poskoc() bump("hopn", self.k) end
function Kvapka:stlac() bump("sqn", self.k) end
function Kvapka:zavibruj() bump("vibn", self.k) end   -- „tu nič nie je“: klik tlačidlom bez funkcie
function Kvapka:bublina(s) text.tip = s or "" end
-- guľky pri kvapke (pravidlo 15): počet 0…5+, farba ("hardver" červená, "siet" zelená, "softver" modrá, "zlta",
-- "system" červeno-kávová, "svetlo"); nad 4 sa ukáže počet v poslednej
local GULKY = { hardver = 0, siet = 1, softver = 2, zlta = 3, system = 4, svetlo = 5 }
-- farba: jedna pre všetky, alebo zoznam po guľkách { "hardver", "siet", "softver" } (QueenGoo)
function Kvapka:gulky(n, farba)
    n = math.max(0, math.floor(n or 0))
    local code = 0
    for j = 0, 3 do
        local f = type(farba) == "table" and (farba[j + 1] or farba[#farba]) or farba
        code = code + (GULKY[f] or num(f, 3)) * 8 ^ j
    end
    self.gn, self.gf, self.gt = math.min(n, 5), code, n > 4 and tostring(n) or ""
    publish()
end
function Kvapka:obrazok(meno) self.v.obr = meno or "" publish() end
function Kvapka:stlm(x) self.tlm = x or 0 publish() end
function Kvapka:jadro(farba, sila, pulz)
    if farba == nil then self.jadroS = 0
    else self.jadroS, self.jadroF, self.jadroP = sila or 1, JADRO[farba] or num(farba, 5), pulz ~= false end
    publish()
end
-- poloha kvapky v px (vlnky): šírku obrazovky povie scéna (fact sw)
function Kvapka:px() return along(self) end      -- poloha pozdĺž jej okraja (px); dole = x na obrazovke
function Kvapka:vlnka(sila) E.vlnka(self:px(), sila or 6, "kamen") end
function Kvapka:vibruj(sila) E.vlnka(self:px(), sila or 3, "vibracia") end

-- ── hladina: vlnky (4 naraz, strieda sa) ───────────────────────────────────────────────────────────────────────
local nextRipple = 0
function E.vlnka(x, sila, druh)
    local i = nextRipple
    nextRipple = (nextRipple + 1) % 4
    fact["rpx." .. i], fact["rpa." .. i], fact["rpk." .. i] = x, sila or 6, druh == "vibracia" and 1 or 0
    bump("rpn", i)
end
on("goo_kamen", function(x) E.vlnka(x, 8, "kamen") end)
on("goo_vibracia", function(x) E.vlnka(x, 3, "vibracia") end)

-- ── registrácia ──────────────────────────────────────────────────────────────────────────────────────────────
local function freeSlot()
    local first, free = nil, 0
    for k = 0, N - 1 do if not slots[k] then first = first or k free = free + 1 end end
    if free <= 4 and E.miesta then after(50, E.miesta) end     -- miesta dochádzajú: o väčšiu scénu (nižšie)
    return first
end

-- miesto na lište pre kvapku bez polohy: zľava doprava, rozostupy podľa veľkosti
local function nextDock()
    local x = 0.03
    if E.prva then x = E.prva end                       -- test: ďalšie kvapky od tohto miesta (trojica ostane sama)
    for k = 0, N - 1 do
        local d = slots[k]
        if d and d.hy0 < d.v.velkost * 1.6 and not d.def.pri and d.zdroj ~= "dyn" and d.hx0 < (E.prvaKoniec or 1) then x = math.max(x, d.hx0 + 0.03) end
    end
    return x
end

function E.define(def, zdroj)
    assert(type(def) == "table" and type(def.id) == "string", "kvapka potrebuje id")
    local prev = byId[def.id]                            -- znova (zmenený JSON): ostane, kde ju používateľ nechal
    if prev then
        saved[def.id] = { x = prev.x, y = prev.y, z = prev.z, e = prev.edge }
        E.remove(def.id)
    end
    local k = freeSlot()
    if not k then log("goo: plno (" .. N .. " miest), kvapka " .. def.id .. " sa nezmestí") return nil end
    local v = {}
    for key, val in pairs(PREDVOLENE) do v[key] = val end
    if def.povaha and E.POVAHY[def.povaha] then for key, val in pairs(E.POVAHY[def.povaha]) do v[key] = val end end
    for key, val in pairs(def) do v[key] = val end
    local d = setmetatable({ id = def.id, k = k, v = v, def = def, zdroj = zdroj or "luau", e = { 0, 0, 0, 0 } }, Kvapka)
    local seat = num(v.vyska, v.velkost * 0.8)          -- výška stredu nad lištou, keď na nej sedí
    local anchor = def.pri and byId[def.pri]
    d.ox0 = 0
    if anchor then                                      -- pri inej kvapke o presný odstup (px)
        d.hx0, d.hy0, d.ox0 = anchor.hx0, seat, (anchor.ox0 or 0) + num(def.odstup, 0)
    elseif type(def.poloha) == "table" then
        d.hx0, d.hy0 = num(def.poloha.x, 0.5), num(def.poloha.y, seat)
    else
        d.hx0, d.hy0 = nextDock(), seat
    end
    local s = saved[def.id] or saved[STARE[def.id] or ""]     -- poloha spred premenovania kvapiek
    d.x, d.y, d.z = s and s.x or d.hx0, s and s.y or d.hy0, clamp(num(s and s.z, 1), ZOOM_MIN, ZOOM_MAX)
    d.ox = s and 0 or d.ox0
    d.moved = s ~= nil
    d.edge0 = anchor and (anchor.edge0 or 0) or clamp(math.floor(num(def.okraj, 0)), 0, 3)
    d.edge = clamp(math.floor(num(s and s.e, d.edge0)), 0, 3)
    -- gravitácia: nič nevisí vo vzduchu — kvapka uložená alebo zadaná mimo okraja si naň sadne
    if d.y >= v.velkost * d.z * 1.6 then d.y = seat end
    if d.hy0 >= v.velkost * 1.6 then d.hy0 = seat end
    slots[k], byId[def.id] = d, d
    E.separate()
    E.needGlyph(v.ikona)
    E.needGlyph(v.koruna)
    -- chyba jednej kvapky nezhodí ostatné (zapíše sa do logu)
    local function safe(name, f) local ok, err = pcall(f, d) if not ok then log("goo: " .. d.id .. "." .. name .. ": " .. tostring(err)) end end
    if def.kazdych and def.tik then
        d.timer = every(def.kazdych, function() safe("tik", def.tik) end)
        safe("tik", def.tik)
    end
    if def.start then safe("start", def.start) end
    publish()
    return d
end

-- pridá kvapku, alebo zmení existujúcu bez preskočenia (miesto, poloha a animácia ostanú): pre kvapky, ktoré
-- vznikajú za behu (okná v Goobari, upozornenia). Nová poloha domova platí, ak ju používateľ nepresunul.
function E.upsert(def)
    local d = byId[def.id]
    if not d then return E.define(def, "dyn") end
    d.def = def
    for key, val in pairs(def) do d.v[key] = val end
    local anchor = def.pri and byId[def.pri]
    local seat = num(def.vyska, d.v.velkost * 0.8)
    if anchor then
        d.hx0, d.ox0, d.hy0 = anchor.hx0, (anchor.ox0 or 0) + num(def.odstup, 0), seat
    elseif type(def.poloha) == "table" then
        d.hx0, d.hy0 = num(def.poloha.x, d.hx0), num(def.poloha.y, seat)
    end
    if not d.moved then d.x, d.y, d.ox = d.hx0, d.hy0, d.ox0 end
    E.separate()
    publish()
    return d
end

function E.remove(id)
    local d = byId[id]
    if not d then return end
    if d.timer then cancel(d.timer) end
    slots[d.k], byId[id] = nil, nil
    publish()
end

function E.get(id) return byId[id] end
function E.each(fn) for k = 0, N - 1 do if slots[k] then fn(slots[k]) end end end

-- ikony: mená → znaky písma Tabler (latte-goo ikony; Noctalia ho má v /usr/share/noctalia)
local wanted, glyphTimer = {}, nil
local ctx_items, ctx_width, ctx_opts = nil, nil, nil       -- práve otvorená ponuka Goo (E.menu)
function E.needGlyph(name)
    if not isName(name) or glyphs[name] then return end
    wanted[name] = true
    if glyphTimer then return end
    glyphTimer = after(50, function()
        glyphTimer = nil
        local names = {}
        for n in pairs(wanted) do table.insert(names, n) end
        wanted = {}
        run("latte-goo", { "ikony", table.unpack(names) }, function(out)
            local ok, t = pcall(json.decode, out or "")
            if not (ok and type(t) == "table") then return end
            for n, g in pairs(t) do glyphs[n] = g end
            for _, n in ipairs(names) do glyphs[n] = glyphs[n] or "" end   -- neznáme meno: už sa nepýtať
            publish()
            -- ponuka otvorená skôr, než prišli znaky: nakresliť ju znova s ikonami (prvé otvorenie po štarte)
            if fact.ctx_open and ctx_items then
                local o = {} for kk, vv in pairs(ctx_opts or {}) do o[kk] = vv end
                o.keep = true
                E.menu(ctx_items, ctx_width, o)
            end
        end)
    end)
end

-- ── ponuka Goo (pravidlá 9–11): karta pri mieste kliku; položky { label, glyph (meno Tabler), hint, on, off, danger,
-- sep, sub = { … } (podponuka so „Späť“), run = funkcia }. Miesto si scéna zapamätá pri stlačení kvapky.
local ctx_actions, ctx_wheel, chip_actions = {}, {}, {}
local ctx_id = nil
local raised = nil                       -- kvapka, ktorá je práve uchom otvorenej karty (vystúpila od okraja)
local RISE = 74                          -- ako vysoko (px): vzdialenosť ako v ploche Kvapky
local ctx_hmax = 0
local ctx_input = nil                    -- čo urobiť s textom z poľa karty (Enter); true = text v poli nechať
local ctx_change = nil                   -- volá sa pri písaní do poľa (s krátkou pauzou)
local ctx_rights = {}                    -- pravý klik na riadok
local ctx_rows, ctx_selectable, ctx_lastsel = {}, {}, -1
local key_sel = nil                      -- riadok vybraný šípkami (ovládanie bez myši)
local wheel_used = 0
local emit_chip
local CTX_MAX = 24                       -- = model ctx max v scéne
-- ktorá karta je práve otvorená (opts.id), aby ju jej majiteľ mohol obnovovať a neprepísal cudziu ponuku
function E.menuId() return fact.ctx_open and ctx_id or nil end
-- kvapka-ucho sa vráti na okraj (karta sa zavrela): padne späť a ponorí sa
function E.menuRelease()
    local d = raised
    if not d then return end
    raised = nil
    d.pinned = false
    if d.yRest then d.y, d.yRest = d.yRest, nil end
    bump("dipn", d.k)
    publish()
end
-- kam karta vyrastie, keď ju neotvoril klik myšou (kláves Windows → spúšťač): k miestu kvapky na jej okraji
function E.menuAt(d)
    local W, H = num(fact.sw, 1920), num(fact.sh, 1080)
    local e, a, n = d.edge or 0, along(d), d.y + d.v.velkost * d.z * 0.5
    local x = (e == 1 and 6 + n) or (e == 3 and W - 6 - n) or a
    local y = (e == 0 and H - 6 - n) or (e == 2 and 6 + n) or a
    fact["ctx.x"], fact["ctx.y"], fact.ctx_up = x, y, y > H / 2
end
-- Karta Goo. Položky ako doteraz, navyše: info = údaj na čítanie (neklikateľný, čitateľný), big = veľký nadpis (čas, stopky), bar = pruh priebehu 0…1, keep = klik
-- kartu nezavrie (prepínač, štart/stop), wheel = funkcia(smer ±1) pre koliesko nad riadkom.
-- opts.chips = { { label, glyph, on, run } … } záložky hore; opts.keep = obnovenie otvorenej karty (živé údaje:
-- nemení zvýraznený riadok)
-- Rozloženie (6. 10.):
--   t2 = druhý riadok pod názvom (telo upozornenia; riadok je vyšší) · hd = nadpis sekcie (malé tučné, neklikateľný)
--   pro = profil účtu: img = portrét (cesta), label = meno, t2 = údaje; glyph = náhrada bez portrétu
--   pills = { položky } — rad tlačidiel vedľa seba (každé ako položka: label, glyph, on = vybrané, danger, run…)
--   tiles = { položky }, per = koľko v rade — dlaždice aplikácií (img = ikona, label = názov pod ňou)
--   opts.cols = { šírka1, šírka2 } — karta v dvoch stĺpcoch; položka s col = 2 ide do pravého (mriežka kalendára aj)
local function est(label) return math.floor((utf8.len(label or "") or #(label or "")) * 7.4) end   -- šírka názvu tlačidla (Inter 14, 600)
function E.menu(items, width, opts)
    opts = opts or {}
    ctx_actions, ctx_wheel, chip_actions, ctx_rights = {}, {}, {}, {}
    ctx_items, ctx_width, ctx_opts = items, width, opts
    ctx_id = opts.id
    local chips = {}
    for i, c in ipairs(opts.chips or {}) do
        if i > 6 then break end
        E.needGlyph(c.glyph)
        local g = c.glyph and (glyphs[c.glyph] or "") or ""
        chips[i] = { label = c.label or "", glyph = g, on = c.on == true, solo = (c.label or "") == "" }
        chip_actions[i] = c.run
    end
    local sel = -1
    for i, c in ipairs(chips) do if c.on then sel = i - 1 end end
    fact.chip_sel = sel
    -- rozmery karty (px): riadok 44, veľký nadpis 64, záložky 58, mriežka kalendára 300; šírka o pätinu väčšia než
    -- zadaná (karty boli malé). Najmenšie rozlíšenie 1024 × 768: riadky, ktoré by sa nezmestili, sa nepridajú
    local width0 = width
    width = math.floor((width or 248) * 1.2)
    -- dva stĺpce: ľavý od 0, pravý od šírky ľavého (opts.cols v tých istých jednotkách ako šírka)
    local colx, colw = { 0, 0 }, { 0, 0 }
    if opts.cols then
        local w1, w2 = math.floor(opts.cols[1] * 1.2), math.floor(opts.cols[2] * 1.2)
        width = w1 + w2
        colx, colw = { 0, w1 }, { w1, w2 }
    end
    local sh, sw = num(fact.sh, 768), num(fact.sw, 1024)
    width = math.min(width, sw - 24)
    local maxH = math.max(400, sh - 24)
    -- UCHO (pravidlo 9, ako v ploche Kvapky): kvapka, z ktorej karta rastie, vystúpi od okraja a sedí v jej rohu
    local owner = opts.owner
    if owner and owner.zdroj ~= "dyn" and (owner.y < owner.v.velkost * owner.z * 1.6 or raised == owner) then
        if raised and raised ~= owner then E.menuRelease() end
        if raised ~= owner then
            raised, owner.yRest, owner.pinned = owner, owner.y, true
            owner.y = RISE
            publish()
        end
        local x, y = E.screenXY(owner)
        local e = owner.edge or 0
        fact["ctx.x"], fact["ctx.y"] = x, y
        fact.ctx_up = (e == 0) or (e ~= 2 and y > sh / 2)
        fact.ctx_ear = owner.v.velkost * owner.z
        -- karta sa musí zmestiť od ucha po okraj obrazovky, inak by ucho nesedelo v jej rohu
        maxH = math.max(300, math.min(maxH, (e == 2 and sh - y or y) - 12))
    elseif not opts.keep then
        if raised then E.menuRelease() end
        fact.ctx_ear = 10
    end
    if not fact.ctx_open then ctx_hmax = 0 end
    local out = {}
    local y0 = #chips > 0 and 58 or 8
    local ys, nin = { y0, y0 }, { 0, 0 }                 -- výška stĺpca a počet riadkov v ňom
    local kal_y, kal_x, kal_w, in_y, in_m, in_x, in_w = -1, 0, 0, -1, -1, 0, 0
    local selectable = {}
    ctx_input, ctx_change = nil, nil
    -- čo urobí klik na riadok (aj tlačidlo a dlaždicu)
    local function action(it)
        if it.sub then
            local parent = items
            return function()
                local kids = { { label = tr("Back"), glyph = "chevron-left", back = parent } }
                for j, c in ipairs(it.sub) do
                    local c2 = {} for kk, vv in pairs(c) do c2[kk] = vv end
                    if j == 1 then c2.sep = true end
                    kids[#kids + 1] = c2
                end
                -- podponuka nechá záložky, ale stratí meno karty (majiteľ ju neprepíše živým obnovením)
                local o = {} for kk, vv in pairs(opts) do o[kk] = vv end
                o.id, o.keep, o.parent, o.cols = nil, nil, opts, nil
                -- z dvojstĺpcovej karty má podponuka šírku svojho stĺpca (Späť vráti oba stĺpce)
                E.menu(kids, opts.cols and opts.cols[it.col == 2 and 2 or 1] or width0, o)
            end
        elseif it.back then
            return function() E.menu(it.back, width0, opts.parent or opts) end
        elseif it.keep or it.input then
            return function() if it.run then it.run() end end
        end
        return function() fact.ctx_open = false if it.run then it.run() end end
    end
    -- jeden riadok výstupu (x, w: stĺpec alebo tlačidlo v rade; h: výška)
    local function emit(it, c, y, x, w, h, kind)
        E.needGlyph(it.glyph)
        local pl = it.pl or 1
        out[#out + 1] = { label = it.label or "", on = it.on and 1 or 0, off = it.off == true,
                          glyph = (it.glyph and (glyphs[it.glyph] or (isName(it.glyph) and "" or it.glyph))) or "",
                          hint = it.hint or "", danger = it.danger == true, sub = it.sub ~= nil or it.back ~= nil,
                          back = it.back ~= nil, sep = it.sep == true and nin[c] > 0 and kind ~= "pill" and kind ~= "tile", y = y,
                          big = it.big == true, bar = num(it.bar, -1), info = it.info == true or (it.para == true and it.run == nil),
                          img = it.img or "", im = (it.img or "") ~= "", para = it.para == true, pl = pl,
                          x = x, w = w, h = h, pill = kind == "pill", tile = kind == "tile", pro = it.pro == true, hd = it.hd == true,
                          t2 = it.t2 or "", lw = kind == "pill" and est(it.label) or 0 }
        local n = #out
        if not it.input and not it.off and not it.info and not it.hd and not (it.para and not it.run) then selectable[#selectable + 1] = n end
        if it.right then ctx_rights[n] = it.right end
        if it.wheel then ctx_wheel[n] = it.wheel end
        if it.input then in_y, in_m, in_x, in_w, ctx_input, ctx_change = y, n - 1, x, w, it.submit, it.change end   -- textové pole: názov riadku je nápoveď
        ctx_actions[n] = action(it)
    end
    for _, it in ipairs(items) do
        if #out >= CTX_MAX then break end
        local c = (opts.cols and it.col == 2) and 2 or 1
        local cx, cw = colx[c], colw[c]
        local y = ys[c]
        if it.grid then                                   -- mriežka kalendára (model kal plní majiteľ karty)
            kal_y, kal_x, kal_w = y, cx, cw
            ys[c] = y + 300
            nin[c] = nin[c] + 1
            E.needGlyph("chevron-left") E.needGlyph("chevron-right")
            text.kal_l, text.kal_r = glyphs["chevron-left"] or "‹", glyphs["chevron-right"] or "›"
            continue
        end
        if it.sep and nin[c] > 0 then y = y + 14 end
        if it.pills or it.tiles then
            -- rad tlačidiel alebo dlaždíc: šírka stĺpca (bez okrajov) sa delí rovnako
            local list = it.pills or it.tiles
            local per = it.pills and math.max(#list, 1) or (it.per or 4)
            local h = it.pills and 46 or 88
            local inner = (cw > 0 and cw or width) - 16
            local lines = math.ceil(#list / per)
            if y + h * lines > maxH - 8 then continue end
            for j, b in ipairs(list) do
                if #out >= CTX_MAX then break end
                local col, row = (j - 1) % per, (j - 1) // per
                emit(b, c, y + row * h, cx + 8 + col * inner / per, inner / per, h, it.pills and "pill" or "tile")
            end
            ys[c] = y + h * lines
            nin[c] = nin[c] + 1                          -- (rad tlačidiel má nad sebou iba medzeru, bez čiary)
            continue
        end
        -- odsek (odpoveď AI): koľko riadkov zaberie, odhadom podľa šírky karty
        local pl = 1
        if it.para then
            local cpl = math.max(20, math.floor(((cw > 0 and cw or width) - 78) / 7.3))
            pl = 0
            for line in ((it.label or "") .. "\n"):gmatch("(.-)\n") do pl = pl + math.max(1, math.ceil((utf8.len(line) or #line) / cpl)) end
            pl = math.min(pl, 14)
            it.pl = pl
        end
        local h = (it.big and 64) or (it.para and pl * 20 + 24) or (it.pro and 84) or (it.hd and 30) or ((it.t2 or "") ~= "" and 54) or 44
        if y + h > maxH - 8 then continue end            -- nezmestí sa na obrazovku: riadok sa nepridá
        emit(it, c, y, cx, cw, h, "row")
        ys[c] = y + h
        nin[c] = nin[c] + 1
    end
    -- nový obsah (otvorenie, iná záložka): riadky nabehnú postupne
    if not opts.keep or sel ~= ctx_lastsel then fact.ctx_gen = num(fact.ctx_gen, 0) + 1 key_sel = nil end
    ctx_lastsel = sel
    ctx_rows, ctx_selectable = out, selectable
    if key_sel and not out[key_sel] then key_sel = nil end
    model.ctx = out
    model.chip = chips
    if fact.kal_y ~= kal_y then fact.kal_y = kal_y end
    if fact.kal_x ~= kal_x then fact.kal_x = kal_x end
    if fact.kal_w ~= kal_w then fact.kal_w = kal_w end
    if fact.ctx_in_y ~= in_y then fact.ctx_in_y = in_y end
    fact.ctx_in_m, fact.ctx_in_x, fact.ctx_in_w = in_m, in_x, in_w
    fact.ctx_w = width
    -- HORNÁ HRANA NESKÁČE (používateľ 5. 10.): karta so záložkami má pevnú výšku (opts.height), ostatné sa počas
    -- otvorenia iba zväčšujú (podponuka a návrat kartu nezmenšia) — obsah začína vždy v tej istej výške
    local y = math.max(ys[1], ys[2])
    local h = math.max(y + 8, math.min(num(opts.height, 0), maxH), opts.height and 0 or ctx_hmax)
    ctx_hmax = math.max(ctx_hmax, h)
    fact.ctx_h = math.min(h, maxH)
    if not opts.keep then fact.ctx_hot = -1 end
    fact.ctx_open = #out > 0
end
on("ctx_pick", function(k)
    local f = ctx_actions[(k or 0) + 1] if f then f() end
    -- režim klávesnice: voľba, ktorá kartu zavrela (spustená aplikácia, akcia), ho ukončí — dá sa písať do okna
    after(200, function() if fact.kb and not fact.ctx_open then emit("kb_out") end end)
end)
on("ctx_close", function() ctx_actions, ctx_wheel, chip_actions, ctx_rights = {}, {}, {}, {} ctx_items = nil end)
on("ctx_scroll", function(v)
    local f = ctx_wheel[(v or 0) // 2 + 1]
    if f then wheel_used = os.clock() f((v or 0) % 2 == 1 and 1 or -1) end
end)
on("ctx_chip", function(c) local f = chip_actions[(c or 0) + 1] if f then f() end end)
on("ctx_submit", function()
    -- riadok vybraný šípkami má prednosť pred textom v poli
    if key_sel and ctx_actions[key_sel] then
        local f = ctx_actions[key_sel]
        key_sel = nil
        fact.ctx_hot = -1
        f()
        return
    end
    local v = (text.ctxq or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local keep = ctx_input and v ~= "" and ctx_input(v) == true
    if not keep then
        text.ctxq = ""
        fact.ctx_in_empty = true
    end
end)
-- šípky hore / dole: výber riadku bez myši (zvýraznenie je to isté ako pod kurzorom)
on("ctx_key", function(v)
    local list = ctx_selectable
    if #list == 0 then return end
    local at = 0
    for i, r in ipairs(list) do if r == key_sel then at = i end end
    at = (v or 1) == 1 and (at % #list + 1) or ((at - 2) % #list + 1)
    key_sel = list[at]
    local r = ctx_rows[key_sel]
    fact.ctx_hy, fact.ctx_hx, fact.ctx_hw, fact.ctx_hh = r.y, r.x or 0, r.w or 0, r.h or 44
    fact.ctx_hp = r.pill == true or r.tile == true
    fact.ctx_hd = r.danger == true
    fact.ctx_hot = key_sel - 1
end)
local typing = nil
on("text:ctxq", function()
    fact.ctx_in_empty = (text.ctxq or "") == ""
    if not ctx_change then return end
    if typing then cancel(typing) end
    typing = after(140, function()                      -- až po krátkej pauze v písaní
        typing = nil
        if ctx_change and fact.ctx_open then ctx_change(text.ctxq or "") end
    end)
end)
function E.menuText(v) if v ~= nil then text.ctxq = v fact.ctx_in_empty = v == "" end return text.ctxq or "" end
on("ctx_right", function(k) local f = ctx_rights[(k or 0) + 1] if f then f() end end)
-- koliesko kdekoľvek v karte prepína záložky; riadok s vlastným kolieskom (dĺžka minútky, hodina budíka) má
-- prednosť — scéna pošle koliesko obom, preto sa tu chvíľu počká, či si ho nevzal riadok
on("ctx_bgw", function(v)
    after(30, function()
        if os.clock() - wheel_used < 0.12 or not fact.ctx_open then return end
        emit_chip(v)
    end)
end)
-- Tab / Shift+Tab: ďalšia (1) / predošlá (0) záložka
on("ctx_chipw", function(v) emit_chip(v) end)
emit_chip = function(v)
    local n = 0
    for i in pairs(chip_actions) do n = math.max(n, i) end
    if n == 0 then return end
    local cur = num(fact.chip_sel, -1)
    local f = chip_actions[(cur + ((v or 1) == 1 and 1 or -1)) % n + 1]
    if f then f() end
end
-- mriežka kalendára: klik na deň (0…41) a šípky mesiaca (−1 / +1) pre majiteľa karty
local kal_pick, kal_nav = nil, nil
function E.calendar(pick, nav) kal_pick, kal_nav = pick, nav end
on("kal_pick", function(q) if kal_pick and fact.ctx_open then kal_pick(q or 0) end end)
on("kal_nav", function(v) if kal_nav and fact.ctx_open then kal_nav((v or 0) == 1 and 1 or -1) end end)

-- ── vstupy zo scény ──────────────────────────────────────────────────────────────────────────────────────────
local function hook(d, name, ...)
    local f = d.def[name]
    if type(f) == "function" then
        local ok, res = pcall(f, d, ...)
        if not ok then log("goo: " .. d.id .. "." .. name .. ": " .. tostring(res)) return true end
        return true, res
    end
    return false
end
E.hook = hook

local function at(k) return slots[k] end

-- klik = pustenie ľavého bez ťahania a bez podržania. Scéna posiela iba stlačenie a pustenie; poradie drží logika
-- (pravé, stredné, podržanie a ťahanie rozrobený klik rušia)
local down = nil                                        -- miesto, na ktorom je stlačené ľavé
on("goo_down", function(k) down = k end)
on("goo_up", function(k)
    local was = down
    down = nil
    local d = at(k) if not d or was ~= k then return end
    hud("klik · " .. d.id)
    if not hook(d, "klik") then d:zavibruj() end        -- tlačidlo bez funkcie: goo zavibruje (pravidlo 8 platí ďalej)
end)
on("goo_right", function(k)
    down = nil
    local d = at(k) if not d then return end
    hud("pravé · " .. d.id)
    if not hook(d, "pravy") then d:zavibruj() end
end)
on("goo_middle", function(k)
    down = nil
    local d = at(k) if not d then return end
    hud("stredné · " .. d.id)
    if not hook(d, "stredny") then d:zavibruj() end
end)
on("goo_hold", function(k)
    if down ~= k then return end                        -- podržanie iba ľavým
    down = nil
    local d = at(k) if not d then return end
    hud("podržanie · " .. d.id)
    hook(d, "podrz")
end)
on("goo_scroll", function(v)
    local k, up = v // 2, v % 2 == 1
    local d = at(k) if not d then return end
    hud("koliesko " .. (up and "hore" or "dole") .. " · " .. d.id)
    -- veľkosť kolieskom: všetky kvapky, ktoré koliesko nepotrebujú na iné (hlava GooBaru ním prepína okná — jej veľkosť
    -- je v Nastaveniach › Kvapky); nie okná GooBaru (tie rozkladá GooBar)
    if not hook(d, "koliesko", up and 1 or -1) and d.v.zoom and d.zdroj ~= "dyn" then d:velkost(d.z + (up and 0.1 or -0.1)) end
end)
-- ── ovládanie z klávesnice (LATTEOS-GOO.md §6.1) ──────────────────────────────────────────────────────────────────
-- Myš ostáva prvá; toto je doplnok pre prácu bez nej. Win+T (latte/skratky.lua) vstúpi do Goo: scéna drží klávesnicu,
-- šípky chodia po kvapkách po obvode obrazovky, Enter / medzerník = ľavý klik, Menu / Shift+F10 = pravý, + a − =
-- koliesko, Esc zavrie kartu a druhý Esc režim opustí. Je to NAVIGÁCIA pre núdzu bez myši, nie presúvanie kvapiek
-- (používateľ 6. 10.: „posúvanie kvapky po obrazovke som nemyslel“) — rozloženie sa z klávesnice nemení.
-- Režim je dočasný (do aplikácií sa v ňom nedá písať): skončí sám po kliku na okno, po voľbe v karte a po minúte
-- bez klávesu.
local kbIdle
local function kbOut() if fact.kb then emit("kb_out") end if kbIdle then cancel(kbIdle) kbIdle = nil end end
local function kbTouch()
    if kbIdle then cancel(kbIdle) end
    kbIdle = after(60000, kbOut)
end
-- kvapky v poradí po obvode: dolný okraj zľava doprava, pravý, horný, ľavý
local function kbRing()
    local list = {}
    E.each(function(d) if not d.hidden then table.insert(list, d) end end)
    local rank = { [0] = 0, [3] = 1, [2] = 2, [1] = 3 }
    local function key(d)
        local e, a = d.edge or 0, along(d)
        if e == 3 or e == 2 then a = elen(d) - a end       -- pravý zdola hore, horný sprava doľava: obvod dokola
        return (rank[e] or 0) * 1e6 + a
    end
    table.sort(list, function(a, b) return key(a) < key(b) end)
    return list
end
-- text bubliny: názov a popis, ako pri prechode myšou (obsah kvapky sa výberom nemení, §3)
local function tipText(d)
    local has, res = hook(d, "popis")
    local p = has and res or d.v.popis
    local n = d.v.nazov or ""
    return (p and p ~= "" and p ~= n) and (n ~= "" and n .. " · " .. p or p) or n
end
local function kbSelect(d)
    if not d then return end
    fact.kbk = d.k
    d:bublina(tipText(d))
    after(50, function() if fact.kb and fact.kbk == d.k then emit("kb_sel", d.k) end end)   -- až keď scéna vie, ktorá to je
end
local function kbCurrent() return slots[num(fact.kbk, -1)] end
on("kb_toggle", function()
    if fact.kb then return kbOut() end
    local list = kbRing()
    if #list == 0 then return end
    fact.kb = true
    kbTouch()
    kbSelect(byId.lensgoo and not byId.lensgoo.hidden and byId.lensgoo or list[1])
    hud("klávesnica")
end)
on("kb_exit", function() if kbIdle then cancel(kbIdle) kbIdle = nil end hud("klávesnica von") end)
-- šípka v smere okraja = ďalšia / predošlá po obvode; na dolnom okraji ← →, na bočných ↑ ↓
local KB_STEP = { [0] = { [1] = 1, [0] = -1 }, [3] = { [2] = 1, [3] = -1 }, [2] = { [0] = 1, [1] = -1 }, [1] = { [3] = 1, [2] = -1 } }
on("kb_nav", function(dir)
    if not fact.kb then return end
    kbTouch()
    local list, cur = kbRing(), kbCurrent()
    if #list == 0 then return end
    local i = 1
    for j, d in ipairs(list) do if d == cur then i = j end end
    local step = cur and (KB_STEP[cur.edge or 0] or {})[dir or 0]
    if not step then return end
    kbSelect(list[(i - 1 + step) % #list + 1])
end)
on("kb_act", function(a)
    if not fact.kb then return end
    kbTouch()
    local d = kbCurrent() if not d then return end
    if a == 0 then
        hud("klávesnica · klik · " .. d.id)
        if not hook(d, "klik") then d:zavibruj() end
        if d.zdroj == "dyn" then after(150, kbOut) end        -- okno z GooBaru: klávesnica patrí zase jemu
    elseif a == 1 then
        hud("klávesnica · pravé · " .. d.id)
        if not hook(d, "pravy") then d:zavibruj() end
    elseif a == 2 or a == 3 then
        local up = a == 2
        if not hook(d, "koliesko", up and 1 or -1) and d.v.zoom and d.zdroj ~= "dyn" then d:velkost(d.z + (up and 0.1 or -0.1)) end
        after(60, function() if fact.kb then kbSelect(d) end end)             -- bublina na novom mieste
    end
end)
on("goo_enter", function(k)
    local d = at(k) if not d then return end
    hud("nad · " .. d.id)
    hook(d, "nad")
end)
on("goo_leave", function(k)
    local d = at(k) if not d then return end
    hook(d, "prec")
end)
on("goo_hover", function(k)
    local d = at(k) if not d then return end
    -- bublina: názov a popis (obsah kvapky sa hoverom nemení, §3)
    local has, res = hook(d, "popis")
    local p = has and res or d.v.popis
    local n = d.v.nazov or ""
    d:bublina((p and p ~= "" and p ~= n) and (n ~= "" and n .. " · " .. p or p) or n)
end)
on("goo_drag", function(k)
    down = nil
    fact["fh." .. k] = 0                                -- chytená počas pádu: pád končí
    local d = at(k) if not d then return end
    hud("ťahanie · " .. d.id)
    d.dragging = true
    publish()
    hook(d, "tahanie")
end)
-- Pustenie po ťahaní (pravidlá 16, 20 a §3): kvapka nikdy neostane visieť vo vzduchu.
--   · pri ľavom, pravom alebo hornom okraji (do STICK px) sa k nemu PRILEPÍ — kvapky sa lepia ku každému okraju;
--   · inak na ňu platí GRAVITÁCIA: spadne rovno dole na hladinu, s prestrelením a odrazom (pružina `pada`),
--     ponorí sa, vynorí a hladina sa zvlní;
--   · kvapka s `vratit` (GooBar: lišta sa dá preniesť k inému okraju) sa pri pustení uprostred vráti, kde bola.
local STICK = 130
local GRAV = 800            -- px/s², rovnaké ako `let GRAV` v scéne: logika z neho počíta čas dopadu
on("goo_drop", function(k)
    local d = at(k) if not d then return end
    local X, Y = num(fact.rx, 0), num(fact.ry, 0)
    local W, H = num(fact.sw, 0), num(fact.sh, 0)
    if W <= 0 then W = 1920 end
    if H <= 0 then H = 1080 end
    d.dragging = false
    d.drops = (d.drops or 0) + 1
    local r = d.v.velkost * d.z
    -- najbližší okraj v dosahu prilepenia; dole je vždy (gravitácia)
    local edge, best = 0, math.huge
    for e, dist in ipairs({ H - Y, X, Y, W - X }) do                 -- dole, vľavo, hore, vpravo
        if dist < STICK and dist < best then edge, best = e - 1, dist end
    end
    local stuck = best < math.huge
    local fell = not stuck                                            -- nebola pri žiadnom okraji: padá
    local has, res = hook(d, "pustenie", X, Y, edge)
    local fh = 0                                                      -- výška pádu nad novým domovom (px)
    local back = (has and res == false) or (fell and d.v.vratit)
    if back then
        hud("pustenie · " .. d.id .. " · späť")
    else
        d.edge = edge
        d.x = clamp(((edge % 2 == 1) and Y / H or X / W), 0.02, 0.98)
        d.x = math.min(d.x, hiAlong(d) / elen(d))                     -- nie pod rohovú lištu
        d.y = num(d.v.vyska, d.v.velkost * 0.8) * d.z
        d.moved, d.ox = true, 0
        if fell then fh = math.max(0, (H - 6 - d.y) - Y) end
        save()
        hud(string.format("pustenie · %s · okraj %d · %.2f%s", d.id, edge, d.x, fell and " · padá" or ""))
    end
    -- návrat k okraju: ponorí sa pod hladinu a vynorí (Marea); po páde až pri dopade, hladina sa zvlní (iba dole)
    -- pád trvá √(2·výška/g): až pri dopade sa sploští a zvlní hladinu; ponor urobí sama pružina (prestrelí pod
    -- hladinu a vráti sa). Kvapka prilepená k okraju sa ponorí a vynorí hneď.
    local wait = fh > 0 and math.sqrt(2 * fh / GRAV) * 1000 or 0
    after(wait, function()
        if byId[d.id] ~= d or d.dragging or back then return end       -- vrátená na miesto: bez ponoru a vlnky
        if fh > 0 then bump("sqn", k) else bump("dipn", k) end
        if (d.edge or 0) == 0 then
            after(fh > 0 and 60 or 200, function() E.vlnka(along(d), (fh > 0 and 3 + math.min(fh, 900) * 0.008 or 4) + r * 0.12, "kamen") end)
        end
    end)
    -- pustená na inú: jedna sa odsunie (pravidlo 22); pustená ostane, kde ju pustili
    E.separate(d)
    -- nový domov, koniec ťahania a výška pádu prídu do scény v jednom kroku (inak by kvapka na snímok skočila)
    table.insert(postPublish, function()
        fact["dx." .. k], fact["dy." .. k], fact["drg." .. k], fact["tr." .. k] = 0, 0, 0, 0
        fact.nk = -1
        fact["fh." .. k] = fh
        if fh > 0 then bump("falln", k) end
    end)
    publish()
end)

-- ── okno z bubliny, prasknutie, pád minimalizovaného okna (pravidlo 14) ──────────────────────────────────────
-- kde je kvapka na obrazovke (px) a ktorým smerom od svojho okraja
local function screenXY(d)
    local W, H = num(fact.sw, 1920), num(fact.sh, 1080)
    local e, a = d.edge or 0, along(d)
    if e == 1 then return 6 + d.y, a, 1, 0 elseif e == 3 then return W - 6 - d.y, a, -1, 0
    elseif e == 2 then return a, 6 + d.y, 0, 1 end
    return a, H - 6 - d.y, 0, -1
end
E.screenXY = screenXY
-- kvapka vypľuje bublinu, ktorá preletí na stred budúceho okna a nafúkne sa na jeho rozmer; `E.bubbleDone()` keď
-- okno naskočilo (bublina zmizne)
function E.bubble(d, cx, cy, w, h)
    local x, y, nx, ny = screenXY(d)
    fact["bub.sx"], fact["bub.sy"], fact["bub.nx"], fact["bub.ny"], fact["bub.sr"] = x, y, nx, ny, d.v.velkost * d.z
    fact["bub.x"], fact["bub.y"], fact["bub.w"], fact["bub.h"] = cx, cy, w, h
    fact.bub_n = num(fact.bub_n, 0) + 1
    d:stlac()
end
function E.bubbleDone() fact.bub_d = num(fact.bub_d, 0) + 1 end
-- zatvorené okno z bubliny praskne (stred a polomer prstenca)
function E.pop(cx, cy, r)
    fact["pop.x"], fact["pop.y"], fact["pop.r"] = cx, cy, r or 200
    fact.pop_n = num(fact.pop_n, 0) + 1
end
-- minimalizované okno (Hyprland: latte.goo_min nastaví wm.x, wm.y, wm.w, wm.h a pošle win_min): zmenší sa do kvapky,
-- voľným pádom spadne k GooBaru, žblnkne a objaví sa medzi ikrami
E.onWinMin = nil
on("win_min", function()
    local x, y, w, h = num(fact["wm.x"], 0), num(fact["wm.y"], 0), num(fact["wm.w"], 0), num(fact["wm.h"], 0)
    local W, H = num(fact.sw, 1920), num(fact.sh, 1080)
    if w <= 0 or h <= 0 or x < 0 or y < 0 or x >= W or y >= H then return end      -- okno na inom monitore
    local cx, cy = x + w / 2, y + h / 2
    local head = byId.goobar
    local x1 = (head and (head.edge or 0) == 0) and math.min(along(head) + 90, hiAlong(head)) or cx
    local T = math.sqrt(2 * math.max(40, H - 6 - cy) / GRAV)
    fact["mf.x0"], fact["mf.y0"], fact["mf.x1"], fact["mf.w"], fact["mf.h"], fact["mf.T"] = cx, cy, x1, w, h, T
    fact.mf_n = num(fact.mf_n, 0) + 1
    after((T + 0.2) * 1000, function() E.vlnka(x1, 7, "kamen") end)
    if E.onWinMin then after(250, E.onWinMin) end                       -- GooBar hneď prekreslí ikry
end)

-- ── nečinnosť: živé bytosti (LATTEOS-GOO.md §3.1) ─────────────────────────────────────────────────────────────────
-- stupeň 1 (1 min) zaspávajú — menšie nadnesenie robí scéna; 2 (3 min) počasie — rezerva, háčik necinnost(d, 2);
-- 3 (6 min) hra hravých kvapiek: naháňačka so zámernou zrážkou a odrazom (squish), behanie po lište, skákanie.
-- Prebudenie hneď: všetky sa zachvejú a vrátia na svoje miesto (poloha z Nastavení sa nemení).
local play
local busy = false          -- beží jeden beh alebo naháňačka (ďalší počká)
local function stopPlay()
    if play then cancel(play) play = nil end
    busy = false
    E.each(function(d)
        if d.wander then d.x, d.y, d.wander = d.wx, d.wy, nil end
        d.v.jmp = false                                      -- rozrobený skok: kvapku zase vedie pružina (domov)
    end)
    publish()
end
local function wander(d)
    if not d.wander then d.wander, d.wx, d.wy = true, d.x, d.y end
end
-- pravidlo 22 platí aj pri hre: bežiaca kvapka nikoho neprekryje — ostatné na lište jej UHNÚ (reťazovo, od nej
-- preč) a po hre sa všetko vráti na svoje miesto. Ikry okien a hlava Goobaru neuhýbajú (k nim sa nebeží).
local function px(d) local sw = num(fact.sw, 0) return d.x * (sw > 0 and sw or 1920) + (d.ox or 0) end
local function rad(d) return d.v.velkost * d.z end
local function docked(d) return d.y < rad(d) * 1.6 and not d.hidden and (d.edge or 0) == 0 end
local function toFrac(d, x) local sw = num(fact.sw, 0) return (x - (d.ox or 0)) / (sw > 0 and sw or 1920) end
-- miesto pre d na x: komu treba uhnúť a kam ({ kvapka = x }); nil = nezmestí sa (okraj obrazovky, Goobar)
local function shove(d, x)
    local sw = num(fact.sw, 0) if sw <= 0 then sw = 1920 end
    if x < 0.03 * sw or x > math.min(0.97 * sw, hiAlong(d)) then return nil end
    local others, fixed = {}, {}
    E.each(function(o)
        if o ~= d and docked(o) and not o.dragging then
            table.insert(num(o.v.sk, 0) >= 1 and fixed or others, o)
        end
    end)
    for _, q in ipairs(fixed) do
        if math.abs(px(q) - x) < (rad(d) + rad(q)) * GAP_IKRY then return nil end
    end
    table.sort(others, function(a, b) return math.abs(px(a) - x) < math.abs(px(b) - x) end)
    local placed, moves = { { x = x, r = rad(d) } }, {}
    for _, o in ipairs(others) do
        local ox = px(o)
        local side = ox >= x and 1 or -1
        for _, p in ipairs(placed) do
            local need = (p.r + rad(o)) * MIN_GAP
            if math.abs(ox - p.x) < need then ox = p.x + side * need end
        end
        if ox ~= px(o) then
            if ox < 0.02 * sw or ox > hiAlong(o) then return nil end
            for _, q in ipairs(fixed) do
                if math.abs(px(q) - ox) < (rad(o) + rad(q)) * MIN_GAP then return nil end
            end
            moves[o] = ox
        end
        table.insert(placed, { x = ox, r = rad(o) })
    end
    return moves
end
-- ── hra ako v starých Worms (používateľ 6. 10.) ──────────────────────────────────────────────────────────────────────
-- Skok je BALISTICKÝ oblúk s gravitáciou enginu (scéna: skn, jv, ja → jb), nie pružina: pred odrazom sa kvapka
-- prikrčí, letí rovnomerne dopredu a jv·t − ½·g·t² nahor, pri dopade sa sploští a hladina sa zvlní. Druhy hry:
-- plíženie (pár nízkych skokov za sebou: prikrčenie, výskok), veľký skok oblúkom aj ponad ostatné, naháňačka so
-- zrážkou a výskok na mieste. Občas sa tempo zrýchli. Kam kvapka doskočí, ostatné na lište uhnú (pravidlo 22);
-- po výlete sa všetko vráti na svoje miesto.
local tempo = 1                                              -- 1 pokojne, menej = rýchlejšia hra (kratšie pauzy)
local function hopT(v0) return 2 * v0 / GRAV end             -- ako dlho letí (s)
local function sirka() local sw = num(fact.sw, 0) return sw > 0 and sw or 1920 end
-- jeden skok d na x (px pozdĺž lišty), odraz rýchlosťou v0 (px/s): výška v0² / 2g, let 2·v0 / g
local function jump(d, x, v0, done)
    d:stlac()                                                -- prikrčenie
    after(260, function()
        if not play then return end
        local from = d.v.jmp and num(d.v.jb, px(d)) or px(d)
        bump("skn", d.k)                                     -- čas odrazu skôr než údaje (inak by na snímku stála v cieli)
        d.v.jmp, d.v.ja, d.v.jb, d.v.jv = true, from, x, v0
        d.x = toFrac(d, x)
        publish()
        after(hopT(v0) * 1000, function()
            if not play then return end
            d:stlac() E.vlnka(x, 2 + v0 / 150, "kamen")       -- dopad: sploští sa, hladina sa zvlní podľa výšky
            if done then after(140, done) end
        end)
    end)
end
-- výskok na mieste pre kvapku, ktorá nie je na výlete (napr. tá, do ktorej narazili)
local function spot(o, v0)
    jump(o, px(o), v0, function() after(300, function() if not o.wander then o.v.jmp = false publish() end end) end)
end
-- návrat: ostatní späť na miesta, d jedným skokom domov
local function back(d, moved, v0)
    if not play then return end
    for o in pairs(moved) do if o.wander then o.x, o.y, o.wander = o.wx, o.wy, nil end end
    jump(d, d.wx * sirka() + (d.ox or 0), v0, function()
        d.x, d.y, d.wander = d.wx, d.wy, nil
        publish()
        after(450, function() d.v.jmp = false publish() busy = false end)
    end)
end
-- postupnosť skokov { { x, v0, pauza_ms }, … }; kam sa nezmestí (okraj, Goobar), tam výlet končí
local function hops(d, list, finish)
    busy = true
    wander(d)
    local moved = {}
    local function step(i)
        if not play then return end
        local h = list[i]
        local moves = h and shove(d, h[1])
        if not h or not moves then return finish(moved) end
        for o, ox in pairs(moves) do wander(o) o.x = toFrac(o, ox) moved[o] = true end
        jump(d, h[1], h[2], function() after(h[3] or 300, function() step(i + 1) end) end)
    end
    step(1)
end
local function game()
    if busy then return end
    local players = {}
    E.each(function(d) if d.v.hrava and not d.wander and not d.dragging and docked(d) then table.insert(players, d) end end)
    if #players == 0 then return end
    if math.random() < 0.14 then tempo = tempo == 1 and 0.4 or 1 end      -- občas rýchlejšia hra, potom zase pokoj
    local d = players[math.random(#players)]
    local sw, x0, r = sirka(), px(d), math.random()
    local dir = math.random() < 0.5 and -1 or 1
    local lo, hi = 0.03 * sw, math.min(0.97 * sw, hiAlong(d))
    if r < 0.32 then                                         -- plíženie: prikrčenie, nízky výskok, znova — 3 až 5 ráz
        local n = 3 + math.random(0, 2)
        if x0 + dir * n * 70 < lo or x0 + dir * n * 70 > hi then dir = -dir end
        local list, x = {}, x0
        for i = 1, n do
            x = clamp(x + dir * (36 + math.random() * 34), lo, hi)
            list[i] = { x, 250 + math.random() * 70, (240 + math.random() * 360) * tempo }
        end
        hops(d, list, function(moved) after(600 * tempo, function() back(d, moved, 500 + math.random() * 140) end) end)
    elseif r < 0.58 then                                     -- veľký skok oblúkom (aj ponad ostatné) a späť
        local x = clamp(x0 + dir * (0.07 + 0.17 * math.random()) * sw, lo, hi)
        if math.abs(x - x0) < rad(d) * 2 then x = clamp(x0 - dir * 0.12 * sw, lo, hi) end
        hops(d, { { x, 540 + math.random() * 170, 800 * tempo } },
            function(moved) back(d, moved, 520 + math.random() * 170) end)
    elseif r < 0.82 then                                     -- naháňačka: doskáče k inej, vrazí do nej, tá odskočí
        local all = {}
        -- iba za kvapkou nablízku (do tretiny lišty): cez pol obrazovky by to bol jeden dlhý plochý skok
        E.each(function(o)
            if o ~= d and docked(o) and num(o.v.sk, 0) == 0 and not o.wander and math.abs(px(o) - x0) < 0.33 * sw then table.insert(all, o) end
        end)
        local other = #all > 0 and all[math.random(#all)]
        if not other then return spot(d, 380 + math.random() * 200) end
        local side = x0 < px(other) and -1 or 1
        local cil = px(other) + side * (rad(d) + rad(other)) * MIN_GAP
        local list, x, step = {}, x0, (cil > x0 and 1 or -1) * (90 + math.random() * 50)
        while math.abs(cil - x) > math.abs(step) * 1.3 and #list < 7 do
            x = x + step
            list[#list + 1] = { x, 330 + math.random() * 70, (120 + math.random() * 160) * tempo }
        end
        list[#list + 1] = { cil, 360 + math.random() * 80, 60 }
        hops(d, list, function(moved)
            if math.abs(px(d) - cil) < 4 and not moved[other] then          -- dobehla: zrážka, obe sa stlačia
                other:stlac()
                spot(other, 340 + math.random() * 160)
            end
            after(900 * tempo, function() back(d, moved, 480 + math.random() * 160) end)
        end)
    else                                                     -- výskok na mieste, občas dva za sebou
        local dva = math.random() < 0.35
        busy = true
        jump(d, x0, 400 + math.random() * 240, function()
            if dva and play then
                jump(d, x0, 300 + math.random() * 120, function() after(300, function() d.v.jmp = false publish() busy = false end) end)
            else
                after(300, function() d.v.jmp = false publish() busy = false end)
            end
        end)
    end
end

-- ── obloha a počasie na hladine (LATTEOS-GOO.md §3.1 stupeň 2; deň a noc) ───────────────────────────────────────
-- Raz za 10 minút `latte-goo obloha`: výška slnka → svetlo v kvapkách a žiara nad horizontom (scéna: den, zlata);
-- dážď, sneh a vietor sa ukážu až pri nečinnosti (stupeň 2+): kvapky dopadajú na spodný okraj a vlnky zvlnia hladinu
-- aj pripnuté kvapky, vietor ženie vlny pozdĺž okraja, jasno = iba dýchanie.
local wx = { zrazky = 0, sneh = false, vietor = 0 }
local wxRain, wxWind, windX = nil, nil, 0
local lowBattery = false
pcall(sys.watch, "battery", function(b)
    lowBattery = type(b) == "table" and b.present == true and (tonumber(b.percent) or 100) < 20 and b.charging ~= true
end)
local TIER = (function() local ok, v = pcall(sys.ask, "env", "LATTE_TIER") return ok and type(v) == "string" and v or "" end)()
-- kedy nie (§3.1): vypínač Živé správanie, stupeň výkonu Softvér, batéria pod 20 %, úsporný profil napájania,
-- okno na celú obrazovku (hra, film). Zamknutú obrazovku rieši kompozitor: scéna vtedy nie je vidno.
local function allowed(cb)
    if fact.zive == false or TIER == "softver" or lowBattery then return cb(false) end
    run("hyprctl", { "activewindow", "-j" }, function(out)
        local ok, w = pcall(json.decode, out or "")
        if ok and type(w) == "table" and (tonumber(w.fullscreen) or 0) > 0 then return cb(false) end
        run("latte-goo", { "profil" }, function(o2)
            local ok2, p = pcall(json.decode, o2 or "")
            cb(not (ok2 and type(p) == "table" and p.aktivny == "power-saver"))
        end)
    end)
end
local function weatherOff()
    if wxRain then cancel(wxRain) wxRain = nil end
    if wxWind then cancel(wxWind) wxWind = nil end
    fact.prsi = 0
end
local function weatherOn()
    weatherOff()
    local sw = num(fact.sw, 1920)
    if wx.zrazky > 0 then
        fact.snezi, fact.prsi = wx.sneh, wx.zrazky
        if not wx.sneh then
            wxRain = every(wx.zrazky == 2 and 650 or 1500, function()
                E.vlnka(math.random() * sw, wx.zrazky == 2 and 2.6 or 1.8, "kamen")
            end)
        end
    elseif wx.vietor >= 30 then
        windX = 0
        wxWind = every(420, function()
            E.vlnka(windX, 3.2, "kamen")
            windX = windX + sw / 18
            if windX > sw then windX = 0 end
        end)
    end
end
local function sky()
    run("latte-goo", { "obloha" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if not ok or type(t) ~= "table" then return end
        wx.zrazky, wx.sneh, wx.vietor = tonumber(t.zrazky) or 0, t.sneh == true, tonumber(t.vietor) or 0
        local a = type(t.nebo) == "table" and type(t.nebo.slnko) == "table" and tonumber(t.nebo.slnko.vyska) or 30
        fact.den = clamp((a + 6) / 12, 0, 1)                  -- občiansky súmrak … slnko 6° nad obzorom
        fact.zlata = clamp(1 - math.abs(a - 2) / 10, 0, 1)    -- svitanie a súmrak: slnko medzi −8° a 12°
    end)
end
E.obloha = { zapni = weatherOn, vypni = weatherOff, stav = wx }   -- aj na skúšanie (README)
after(1500, sky)
every(600000, sky)

-- ── počet miest podľa potreby ───────────────────────────────────────────────────────────────────────────────────
-- Scéna počíta každú snímku všetky miesta, aj prázdne (128 miest 42 % jadra, 32 miest 17 %; latte-lab 6. 10.). Engine
-- preto beží na najmenšej scéne, do ktorej sa zmestí (32 / 64 / 128; menšie vyrába gen.py --n pri inštalácii),
-- a keď miesta dochádzajú, povie si o väčšiu: `latte-kvapky miesta N` scénu vymení (kvapky na chvíľu zmiznú a vrátia
-- sa na svoje miesta). Späť na menšiu až po troch minútach, keď je dlho voľno.
local function potreba(used) return used <= 24 and 32 or (used <= 56 and 64 or 128) end
local menej, ziadane = 0, false
local function miesta()
    if ziadane or E.vedlajsi then return end                 -- vedľajší monitor má pevnú malú scénu
    local used = 0
    for k = 0, N - 1 do if slots[k] then used = used + 1 end end
    local chce = potreba(used)
    if chce > N then
        menej = 0
    elseif chce < N then
        menej = menej + 1
        if menej < 3 then return end
    else
        menej = 0
        return
    end
    ziadane = true
    log("goo: miesta " .. N .. " → " .. chce .. " (obsadených " .. used .. ")")
    save()
    after(1400, function() run("latte-kvapky", { "miesta", tostring(chce) }, nil, { output = false }) end)
end
E.miesta = miesta
after(8000, miesta)
every(60000, miesta)

on("goo_idle", function(level)
    hud("nečinnosť " .. level)
    E.each(function(d) hook(d, "necinnost", level) end)
    if level == 0 then
        local had = play ~= nil
        weatherOff()
        stopPlay()
        if had then E.each(function(d) d:stlac() end) end     -- vyrušené: zachvejú sa
        return
    end
    if level < 2 then return end
    allowed(function(smie)
        if not smie or num(fact.idle, 0) < level then return end   -- nesmie, alebo sa medzitým prebudili
        weatherOn()
        if level >= 3 and not play then
            -- hra: nový kúsok, keď predošlý skončil; v rýchlom tempe hneď, inak s oddychom
            play = every(1300, function() if not busy and (tempo < 1 or math.random() < 0.55) then game() end end)
            game()
        end
    end)
end)
-- skúška počasia bez čakania a bez ohľadu na skutočné: pleamar --say goo "emit goo_pocasie N"
-- (0 vypnúť, 1 riedky dážď, 2 dážď, 3 sneh, 4 vietor); scéna ho ukazuje iba pri nečinnosti (idle ≥ 2)
on("goo_pocasie", function(n)
    n = tonumber(n) or 0
    wx.zrazky, wx.sneh, wx.vietor = (n == 1 or n == 2) and n or (n == 3 and 2 or 0), n == 3, n == 4 and 40 or 0
    if n == 0 then weatherOff() else weatherOn() end
end)

-- ── Nastavenia › Kvapky (~/.config/latteos/kvapky.json, ten istý súbor ako plocha Kvapky): voliteľné kvapky sa dajú
-- skryť, základné (zaklad = true: GooBar, GooPower, LensGoo) nie; veľkosť 100–220 %; vrátenie na miesto ──────────
local lastReset = nil
local hideSet = {}                -- vypnuté v Nastaveniach
local function applyHidden()
    local changed = false
    for id, d in pairs(byId) do
        local h = (hideSet[id] == true or d.absent == true) and not d.def.zaklad and d.zdroj ~= "dyn"
        if h ~= (d.hidden == true) then d.hidden = h changed = true end
    end
    return changed
end
-- kvapka, ktorá má zmysel iba niekedy (ChatGoo: Beeper je nainštalovaný alebo beží), sa vie sama schovať a ukázať
function Kvapka:pritomna(on)
    local a = on == false
    if a ~= (self.absent == true) then
        self.absent = a
        if applyHidden() then E.separate() publish() end
    end
end
-- upozornenia: jedno sledovanie služby pre všetky kvapky (ClockGoo, ChatGoo); každá dostane celý zoznam
local notesSubs, notesOn = {}, false
function E.onNotes(fn)
    notesSubs[#notesSubs + 1] = fn
    if notesOn then return true end
    notesOn = sys.watch("notifications", function(list)
        for _, f in ipairs(notesSubs) do pcall(f, list or {}) end
    end) and true or false
    return notesOn
end
-- upozornenie patrí četu (Beeper) a kvapka ChatGoo je na ploche → ukáže ho ona, nie ClockGoo
function E.isChat(x) return tostring(x and x.app or ""):lower():find("beeper", 1, true) ~= nil end
function E.chatOn() return byId.chatgoo ~= nil and not byId.chatgoo.hidden end
local function settings()
    run("latte-goo", { "nastavenia" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if not ok or type(t) ~= "table" then return end
        fact.zive = t.zive ~= false                               -- vypínač Živé správanie (predvolene zapnuté)
        if fact.zive == false then weatherOff() end
        local hide = {}
        for _, id in ipairs(type(t.skryte) == "table" and t.skryte or {}) do hide[id] = true end
        hideSet = hide
        local changed = applyHidden()
        for id, d in pairs(byId) do
            local z = type(t.zoom) == "table" and tonumber(t.zoom[id])
            if z and math.abs(clamp(z, ZOOM_MIN, ZOOM_MAX) - (d.zset or 0)) > 0.001 then
                d.zset = clamp(z, ZOOM_MIN, ZOOM_MAX)             -- iba keď sa zmenilo v Nastaveniach (koliesko ostáva)
                d:velkost(d.zset)
            end
        end
        local r = type(t.reset) == "table" and t.reset
        if r and r.t ~= lastReset then
            if lastReset ~= nil and byId[r.k] then byId[r.k]:domov() end
            lastReset = r.t
        elseif not r and lastReset == nil then
            lastReset = 0
        end
        if changed then E.separate() publish() end
    end)
end

-- ── štart ────────────────────────────────────────────────────────────────────────────────────────────────────
function E.start(opts)
    opts = opts or {}
    E.vedlajsi, E.monitorId = opts.vedlajsi == true, opts.monitor_id   -- inštancia vedľajšieho monitora (iba GooBar)
    E.ladenie = opts.ladenie
    E.prva = opts.prva
    E.prvaKoniec = opts.prva_koniec
    fact.ladenie = opts.ladenie and true or false
    run("latte-goo", { "stav" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then saved = t end
        local defs = {}
        for _, name in ipairs(opts.moduly or {}) do
            local ok2, def = pcall(require, "kvapky/" .. name)
            if ok2 and type(def) == "table" then table.insert(defs, def)
            else log("goo: modul kvapky/" .. name .. ": " .. tostring(def)) end
        end
        -- kvapka `pri` inej prichádza až po nej (PowerGoo po TimeGoo, tá po hlave Goobaru)
        for _ = 1, #defs do
            local rest = {}
            for _, def in ipairs(defs) do
                if def.pri and not byId[def.pri] then table.insert(rest, def) else E.define(def, "luau") end
            end
            defs = rest
            if #defs == 0 then break end
        end
        for _, def in ipairs(defs) do log("goo: " .. def.id .. ": kotva " .. tostring(def.pri) .. " nie je") E.define(def, "luau") end
        if opts.pouzivatel ~= false then require("lib/pouzivatel").start(E, opts) end
        settings()
        every(2000, settings)
        -- karta sa zavrela (klik mimo, Esc, voľba): ucho sa vráti na okraj, až keď sa karta zloží
        every(120, function() if raised and not fact.ctx_open then E.menuRelease() end end)
        -- rozmer obrazovky príde zo scény až po štarte (a zmení sa s rozlíšením): polohy a zakázanú zónu prepočítať
        local lw, lh = 0, 0
        every(1000, function()
            local w, h = num(fact.sw, 0), num(fact.sh, 0)
            if w ~= lw or h ~= lh then lw, lh = w, h E.separate() publish() end
        end)
        publish()
    end)
    -- káva (pravidlo 6): pomer vody a mlieka z Baristu, ako plocha Kvapky
    local function kava()
        run("latte-goo", { "kava" }, function(out)
            local ok, k = pcall(json.decode, out or "")
            if ok and type(k) == "table" and #k == 2 then
                if fact.voda ~= k[1] then fact.voda = k[1] end
                if fact.mlieko ~= k[2] then fact.mlieko = k[2] end
            end
        end)
    end
    kava()
    every(3000, kava)
end

return E
