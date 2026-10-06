-- GooPower (napájanie a monitor systému, LATTEOS-GOO.md §4.2; predtým PowerGoo): základná kvapka.
-- Polomer 19, skoro celý v okraji (stred 3 px nad ním), pri kurzore sa nadnesie najviac zo všetkých (~26 px),
-- 62 px vľavo od LensGoo. Batéria (notebook): guľky 3 zelené (≥ 60 %), 2 žlté (≥ 30 %), 1 červená; pod 10 % jadro
-- pulzuje, pri nabíjaní dýcha. Na stolnom PC žiadne.
--
-- Ľavý klik = KARTA GooPower (používateľ 6. 10.: „estetickejšia, aj profil napájania, portrét účtu a údaje“):
--   profil účtu (portrét, meno, login@počítač, prihlásený od) → Nastavenia › Môj účet; tlačidlá Zamknúť · Odhlásiť;
--   NAPÁJANIE: batéria s pruhom, profil napájania (Úspora · Vyvážený · Výkon — powerprofilesctl); Nastavenia, Monitor;
--   tlačidlá Uspať · Reštartovať · Vypnúť. Akcie relácie robí Noctalia.
-- Pravý klik = PÁS VÝKONU: kvapka sa natiahne pozdĺž okraja do kapsuly (na voľnú stranu, ikona ostane pri nej), susedné
--   goo odtlačí (pravidlo 22 ráta s celou kapsulou) a v nej sú bunky CPU · RAM · GPU · VRAM (latte-sysmon goo,
--   raz za sekundu). Farba hodnoty podľa záťaže (jantárová nad 80 %, červená nad 95 % alebo pri prehriatí), prechod
--   myšou = podrobnosti v bubline, klik = Monitor na tej časti, pravý klik (na bunke aj na kvapke) = pás sa vtiahne
--   a odtlačené goo sa vrátia, ak ich medzitým nikto nepresunul. Zapnutý pás ostane aj po prihlásení (latte-goo pas).
local E = require("lib/engine")
local function session(a) return function() after(200, function() run("noctalia", { "msg", "session", a }) end) end end

-- ── pás výkonu ───────────────────────────────────────────────────────────────────────────────────────────────
local CW, CW_BOK = 64, 50             -- dĺžka bunky pozdĺž okraja: dole a hore / na bokoch (text je vždy vodorovný)
local R_PAS = 22                      -- polomer kapsuly (bunka má názov, hodnotu a pruh pod sebou)
local pas = { on = false, job = nil, cells = {}, snap = {}, keep = nil }

local function gb(b) return string.format("%.1f", (b or 0) / 2 ^ 30):gsub("%.", ",") .. " G" end
local function lvl(p) return math.max(0, math.min(1, (p or 0) / 100)) end
-- záťaž → farba hodnoty: 0 káva, 1 jantárová, 2 červená (aj teplota: CPU nad 80 / 90 °C, GPU nad 85 / 95 °C)
local function state(p, t, t1, t2)
    if (p or 0) >= 95 or (t and t >= t2) then return 2 end
    if (p or 0) >= 80 or (t and t >= t1) then return 1 end
    return 0
end
local function deg(t) return t and ("  ·  " .. t .. " °C") or "" end

-- bunky z jedného riadku latte-sysmon goo
local function cells_of(s)
    local out = {}
    local top = type(s.top) == "table" and s.top.name and ("  ·  " .. tr("most") .. ": " .. s.top.name .. " " .. (s.top.cpu or 0) .. " %") or ""
    out[#out + 1] = { id = "cpu", l = "CPU", v = (s.cpu or 0) .. " %", lvl = lvl(s.cpu), c = state(s.cpu, s.cpuT, 80, 90), sec = "procesy",
                      tip = tr("Processor") .. " " .. (s.cpu or 0) .. " %" .. ((s.mhz or 0) > 0 and ("  ·  " .. string.format("%.2f", s.mhz / 1000):gsub("%.", ",") .. " GHz") or "") .. deg(s.cpuT) .. top }
    local rp = (s.ramT or 0) > 0 and math.floor(100 * (s.ram or 0) / s.ramT + 0.5) or 0
    out[#out + 1] = { id = "ram", l = "RAM", v = gb(s.ram), lvl = lvl(rp), c = state(rp), sec = "procesy",
                      tip = tr("Memory") .. " " .. gb(s.ram) .. " / " .. gb(s.ramT) .. "  (" .. rp .. " %)" .. ((s.swap or 0) > 0 and ("  ·  swap " .. gb(s.swap)) or "") }
    if s.gpu ~= nil then
        out[#out + 1] = { id = "gpu", l = "GPU", v = s.gpu .. " %", lvl = lvl(s.gpu), c = state(s.gpu, s.gpuT, 85, 95), sec = "vykon",
                          tip = tr("Graphics") .. " " .. s.gpu .. " %" .. deg(s.gpuT) }
    end
    if (s.vramT or 0) > 0 then
        local vp = math.floor(100 * (s.vram or 0) / s.vramT + 0.5)
        out[#out + 1] = { id = "vram", l = "VRAM", v = gb(s.vram), lvl = lvl(vp), c = state(vp), sec = "vykon",
                          tip = tr("Video memory") .. " " .. gb(s.vram) .. " / " .. gb(s.vramT) .. "  (" .. vp .. " %)" }
    end
    return out
end

-- dĺžka kapsuly podľa počtu buniek; smer: na stranu, kde je voľno (predvolene od LensGoo preč — doľava / hore)
local function shape(d)
    local n = math.max(#pas.cells, 1)
    local cw = (d.edge or 0) % 2 == 1 and CW_BOK or CW
    local kw = n * cw / 2 + 3
    local reach = 2 * kw + R_PAS * d.z + 8
    local kd = (E.along(d) - reach > 0.02 * E.len(d)) and -1 or 1
    d:nastav({ kw = kw, kd = kd })
    fact.mon_k, fact.mon_ed, fact.mon_kd, fact.mon_cw = d.k, d.edge or 0, kd, cw
    E.separate(d)                     -- odtlačí susedov od celej kapsuly (GooPower sama je pripnutá k LensGoo)
    E.publish()
end

local function paint(d, s)
    local cells = cells_of(s)
    local grew = #cells ~= #pas.cells
    pas.cells = cells
    local m = {}
    for i, c in ipairs(cells) do m[i] = { l = c.l, v = c.v, lvl = c.lvl, c = c.c } end
    model.mon = m
    if grew then shape(d) end
end

local function stream(d)
    if pas.job then pcall(cancel, pas.job) end
    pas.job = spawn("latte-sysmon", { "goo", "1" }, function(line)
        local ok, s = pcall(json.decode, line or "")
        if ok and type(s) == "table" and pas.on then paint(d, s) end
    end, function()
        pas.job = nil
        if pas.on then after(3000, function() if pas.on and not pas.job then stream(d) end end) end    -- spadol: znova
    end)
end

local function pas_on(d, quiet)
    if pas.on then return end
    pas.on = true
    -- kvapka sa zdvihne do celej kapsuly (z okraja vidno iba pol GooPower) a prestane sadať a nakláňať sa ku kurzoru
    pas.keep = { velkost = d.v.velkost, y = d.y, vyska = d.v.vyska, vznos = d.v.vznos, gravitacia = d.v.gravitacia, rast = d.v.rast }
    -- poloha ostatných kvapiek pred odtlačením: po vtiahnutí pásu sa vrátia (ak ich medzitým nikto neťahal)
    pas.snap = {}
    E.each(function(o)
        if o ~= d and o.zdroj ~= "dyn" then pas.snap[o] = { x = o.x, y = o.y, edge = o.edge, moved = o.moved, drops = o.drops } end
    end)
    d.y = math.max(d.y, (R_PAS + 4) * d.z)
    d:nastav({ velkost = R_PAS, vyska = R_PAS + 4, vznos = 0, gravitacia = 0, rast = 0.04, fix = true })      -- vyska: aj po presune
    pas.cells = cells_of({ cpu = 0, ram = 0, ramT = 0 })
    model.mon = {}
    shape(d)
    fact.mon_on = true
    if not quiet then
        d:stlac()
        d:vlnka(4)
        run("latte-goo", { "pas", "on" }, nil, { output = false })
    end
    stream(d)
end

local function pas_off(d)
    if not pas.on then return end
    pas.on = false
    if pas.job then pcall(cancel, pas.job) pas.job = nil end
    fact.mon_on = false
    local k = pas.keep or {}
    d.y = k.y or d.y
    d:nastav({ kw = 0, kd = 0, fix = false, velkost = k.velkost or 19, vyska = k.vyska or 3, vznos = k.vznos or 1.8, gravitacia = k.gravitacia or 0.3, rast = k.rast or 0.21 })
    -- odtlačené goo späť na svoje miesto (iba tie, ktoré odvtedy nikto nepresunul)
    local back = false
    for o, p in pairs(pas.snap) do
        if E.get(o.id) == o and (o.drops or 0) == (p.drops or 0) and (o.x ~= p.x or o.y ~= p.y) then
            o.x, o.y, o.edge, o.moved = p.x, p.y, p.edge, p.moved
            back = true
        end
    end
    pas.snap = {}
    if back then E.save() end
    E.separate()
    E.publish()
    d:vlnka(3)
    run("latte-goo", { "pas", "off" }, nil, { output = false })
end

-- ── karta (ľavý klik) ────────────────────────────────────────────────────────────────────────────────────────
local acc, prof = nil, nil
local card
local PROFILY = {
    { id = "power-saver", label = "Saver", glyph = "leaf" },
    { id = "balanced", label = "Balanced", glyph = "scale" },
    { id = "performance", label = "Performance", glyph = "rocket" },
}
local function items(d)
    local a = acc or {}
    local who = (a.login or "") ~= "" and (a.login .. "@" .. (a.pocitac or "")) or ""
    if (a.od or "") ~= "" then who = who .. "  ·  " .. tr("since") .. " " .. a.od end
    local list = {
        { pro = true, img = (a.obrazok or "") ~= "" and a.obrazok or nil, glyph = "user", label = a.meno or "…", t2 = who,
          run = function() run("latte-app", { "nastavenia", "mojucet" }) end },
        { pills = { { glyph = "lock", label = tr("Lock"), run = function() after(200, function() run("latte-zamok", {}, nil, { output = false }) end) end },
                    { glyph = "logout", label = tr("Log out"), run = session("logout") } } },
    }
    -- NAPÁJANIE: batéria (notebook) a profil napájania
    list[#list + 1] = { hd = true, sep = true, label = tr("POWER") }
    if d.bp then
        list[#list + 1] = { info = true, glyph = d.charging and "battery-charging" or (d.bp >= 60 and "battery-3" or d.bp >= 30 and "battery-2" or "battery-1"),
                            label = tr("Battery") .. " " .. d.bp .. " %", hint = d.charging and tr("charging") or "", bar = d.bp / 100 }
    end
    if prof and prof.aktivny then
        local row = {}
        for _, p in ipairs(PROFILY) do
            local has = #(prof.dostupne or {}) == 0
            for _, x in ipairs(prof.dostupne or {}) do if x == p.id then has = true end end
            if has then
                row[#row + 1] = { glyph = p.glyph, label = tr(p.label), on = prof.aktivny == p.id, keep = true,
                                  run = function()
                                      prof.aktivny = p.id
                                      card(d, true)
                                      run("latte-goo", { "profil-nastav", p.id }, function(out)
                                          local ok, t = pcall(json.decode, out or "")
                                          if ok and type(t) == "table" and t.aktivny then prof = t end
                                          if E.menuId() == "power" then card(d, true) end
                                      end)
                                  end }
            end
        end
        if #row > 0 then list[#list + 1] = { pills = row } end
    end
    list[#list + 1] = { sep = true, glyph = "settings", label = tr("Settings"), run = function() run("latte-app", { "nastavenia" }) end }
    list[#list + 1] = { glyph = "chart-bar", label = tr("Monitor"), hint = tr(pas.on and "strip on" or "right click: strip"),
                        run = function() run("latte-app", { "monitor" }) end }
    list[#list + 1] = { sep = true, pills = { { glyph = "moon", label = tr("Sleep"), run = session("suspend") },
                                              { glyph = "refresh", label = tr("Restart"), run = session("reboot") },
                                              { glyph = "power", label = tr("Shut down"), danger = true, run = session("shutdown") } } }
    return list
end
card = function(d, keep)
    -- ucho = kvapka GooPower v rohu karty; so zapnutým pásom ostane pás na mieste a karta vyrastie pri mieste kliku
    E.menu(items(d), 320, { id = "power", keep = keep, owner = not pas.on and d or nil })
end

return {
    id = "goopower", nazov = "GooPower", zaklad = true, ikona = "power", povaha = "pokojna", velkost = 19, rast = 0.21, vyska = 3,
    vznos = 1.8, gravitacia = 0.3, dosah = 110, zoom = true, pri = "lensgoo", odstup = -62,
    start = function(d)
        sys.watch("battery", function(b)
            if not b or not b.present then d.bat, d.bp = nil, nil d:gulky(0) d:jadro() return end
            local p = tonumber(b.percent) or 0
            if p >= 60 then d:gulky(3, "siet") elseif p >= 30 then d:gulky(2, "zlta") else d:gulky(1, "hardver") end
            if p < 10 and not b.charging then d:jadro("hardver", 0.8, true) else d:jadro() end
            d:efekt(b.charging and "dych" or "nic", 0.7)
            d.bp, d.charging = math.floor(p), b.charging == true
            d.bat = d.bp .. " %" .. (b.charging and " · " .. tr("charging") or "")
        end)
        -- pás výkonu: bunky (prechod, klik, pravý klik), zapnutý pri poslednom odhlásení ostane
        on("mon_hover", function(u) local c = pas.cells[(u or 0) + 1] if c then d:bublina(c.tip) end end)
        on("mon_pick", function(u)
            local c = pas.cells[(u or 0) + 1]
            if not c then return end
            run("latte-app", { "monitor", c.sec })
        end)
        on("mon_close", function() pas_off(d) end)
        run("latte-goo", { "pas" }, function(out) if (out or ""):match("on") then after(1500, function() pas_on(d, true) end) end end)
        -- pás sleduje GooPower, keď ju niekto presunie alebo zmení veľkosť (smer a okraj kapsuly)
        every(1000, function() if pas.on and (fact.mon_ed ~= (d.edge or 0)) then shape(d) end end)
    end,
    klik = function(d)
        if E.menuId() == "power" then fact.ctx_open = false return end
        card(d)
        run("latte-goo", { "ucet" }, function(out)
            local ok, t = pcall(json.decode, out or "")
            if ok and type(t) == "table" then acc = t end
            if E.menuId() == "power" then card(d, true) end
        end)
        run("latte-goo", { "profil" }, function(out)
            local ok, t = pcall(json.decode, out or "")
            prof = ok and type(t) == "table" and t or nil
            if E.menuId() == "power" then card(d, true) end
        end)
    end,
    pravy = function(d) if pas.on then pas_off(d) else pas_on(d) end end,
    -- pustená inde: pás sa prestaví podľa nového okraja (smer na voľnú stranu)
    pustenie = function(d) if pas.on then after(400, function() if pas.on then shape(d) end end) end end,
    popis = function(d)
        return (d.bat and (d.bat .. " · ") or "") .. tr(pas.on and "left: menu · right: hide strip" or "left: menu · right: performance strip")
    end,
}
