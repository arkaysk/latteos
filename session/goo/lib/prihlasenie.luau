-- LatteOS GOO — logika prihlásenia a zámku obrazovky (login.plm, zamok.plm; LATTEOS-GOO.md §6.2). Riadi časovú os úvodu, plní údaje
-- (latte-goo prihlasenie: meno, káva, posledný pád alebo novinky, informačné goo, znaky ikon) a overuje heslo.
-- Režim podľa premennej LATTE_LOGIN:
--   skuska (predvolené)  nič v systéme nemení: heslo „latte“ sedí, iné nie; po prihlásení sa úvod zopakuje;
--                        ponuka napájania iba zapíše do logu
--   zamok                zámok obrazovky (zamok.plm, `kind: lock`, spúšťa latte-zamok): bez úvodu so šálkou, heslo
--                        overí systém (PAM, `auth.check`), po odomknutí scéna skončí
--   greetd               všeobecná relácia prihlasovača (latte-greeter, greeter = "goo"): heslo overí greetd cez
--                        latte-greetd a po úvodnej animácii sa spustí relácia používateľa
return function(vynuteny)
local ok_env, env = pcall(sys.ask, "env", "LATTE_LOGIN")
local REZIM = vynuteny or ((ok_env and type(env) == "string" and env ~= "") and env or "skuska")

local function safe(what, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then log("login · " .. what .. ": " .. tostring(err)) end
end

local relacie = {}                                   -- relácie na výber: { subor, meno, prikaz }
local ucet = ""                                      -- kto sa prihlasuje (login)

-- ── údaje ────────────────────────────────────────────────────────────────────────────────────────────────────
local function data()
    run("latte-goo", { "prihlasenie" }, function(out)
        local ok, d = pcall(json.decode, out or "")
        if not ok or type(d) ~= "table" then log("login · latte-goo prihlasenie nič nevrátil") return end
        -- meno je predvyplnené naposledy prihláseným; čo doň používateľ napísal, sa ďalším načítaním neprepíše
        if ucet == "" then ucet = d.login or "" text.ucet = ucet end
        if type(d.kava) == "table" then fact.voda, fact.mlieko = tonumber(d.kava[1]) or 0.55, tonumber(d.kava[2]) or 0 end
        local g = d.ikony or {}
        text.g_power, text.g_sip, text.g_spat, text.g_znova = g.power or "", g["arrow-right"] or "", g.moon or "", g.refresh or ""
        local rows = {}
        for _, t in ipairs(d.riadky or {}) do rows[#rows + 1] = { t = t } end
        model.riadky = rows
        fact.panel = (d.panel == "pad" and 1) or (d.panel == "novinky" and 2) or 0
        local inf = {}
        for _, i in ipairs(d.info or {}) do inf[#inf + 1] = { g = g[i.ikona] or "", v = tostring(i.text or ""), on = true } end
        -- skúška na počítači bez batérie a bez úloh: vzorové goo, aby bolo vidno, ako sa vynoria
        if REZIM == "skuska" and #inf == 0 then
            inf = { { g = g["battery-3"] or "", v = "82 %", on = true }, { g = g.bell or "", v = "3", on = true }, { g = g["calendar-event"] or "", v = "2", on = true } }
        end
        model.inf = inf
        if tonumber(d.goopower) then fact.tox = tonumber(d.goopower) end
        -- obloha: cez deň slnko, v noci mesiac (ak je nad obzorom), každé na svojom mieste; dážď a sneh podľa počasia
        local n = type(d.nebo) == "table" and d.nebo or {}
        local s, m = n.slnko or {}, n.mesiac or {}
        if (tonumber(s.t) or -1) >= 0 then
            fact.nb, fact.nt, fact.nv = 1, s.t, math.max(0, tonumber(s.vyska) or 0)
        elseif (tonumber(m.t) or -1) >= 0 then
            fact.nb, fact.nt, fact.nv = 2, m.t, math.max(0, tonumber(m.vyska) or 0)
            fact.nf, fact.nd = tonumber(m.faza) or 1, m.dorasta == true
        else
            fact.nb = 0
        end
        fact.zrazky, fact.sneh = tonumber(d.zrazky) or 0, d.sneh == true
        local w = type(d.pocasie) == "table" and d.pocasie or nil
        if w then
            text.w_t, text.w_g, text.w_m, fact.wk = w.t or "", g[w.ikona] or "", w.miesto or "", tonumber(w.trieda) or 0
        else
            text.w_t, fact.wk = "", 0
        end
        -- relácie na výber (vývojárska verzia): prvé načítanie nastaví naposledy použitú, ďalšie výber nemenia
        local prve = #relacie == 0
        relacie = type(d.relacie) == "table" and d.relacie or {}
        local rel = {}
        for _, r in ipairs(relacie) do rel[#rel + 1] = { t = r.meno or r.subor or "?" } end
        model.rel = rel
        text.g_rel = g["device-desktop"] or ""
        fact.dev = d.dev == true and #relacie > 1 and REZIM ~= "zamok"
        if prve then fact.rel_sel = math.max(0, math.min(#relacie - 1, tonumber(d.relacia) or 0)) end
        local r = relacie[(fact.rel_sel or 0) + 1]
        text.rel_meno = r and (r.meno or r.subor) or ""
    end)
end

local function clock()
    run("date", { "+%H:%M|%A %-d. %B" }, function(out)
        local c, d = (out or ""):match("^(%d+:%d+)|(.-)%s*$")
        if c then text.cas, text.datum = c, d or "" end
    end)
end

-- ── časová os úvodu ──────────────────────────────────────────────────────────────────────────────────────────
local function uvod()
    after(700, function() emit("e_skok") end)        -- šálka chvíľu stojí (nadväzuje na úvodnú obrazovku)
    after(1900, function() emit("e_val") end)
    after(2900, function() emit("e_riadok") end)
    after(3500, function() emit("e_hladina") end)
end

-- ── heslo ────────────────────────────────────────────────────────────────────────────────────────────────────
local function over(pw, hotovo)
    if REZIM == "zamok" then
        local ok, valid = pcall(sys.ask, "auth.check", pw)
        return hotovo(ok and valid == true)
    end
    if REZIM == "greetd" then
        -- heslo nejde v argumentoch: do súkromného súboru prihlasovača (tmpfs), latte-greetd ho prečíta a zmaže
        local r = relacie[(fact.rel_sel or 0) + 1] or { subor = "latteos", prikaz = { "/usr/bin/latte-session" } }
        local kto = (text.ucet or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if kto == "" then kto = ucet end
        local args = { "prihlas", kto, r.subor or "", "--" }
        for _, c in ipairs(r.prikaz or {}) do args[#args + 1] = c end
        if #args == 4 then args[5] = "/usr/bin/latte-session" end
        -- iný účet než predvyplnený: LoginGoo padne tam, kde má GooPower ON (každý účet má svoje rozloženie)
        if kto ~= ucet then
            run("latte-goo", { "goopower-miesto", kto }, function(out)
                local x = tonumber((out or ""):match("[%d.]+"))
                fact.tox = (x and x > 0 and x < 1) and x or 0.14
            end)
        end
        local okw, err = pcall(sys.call, "files.write", "h.json", { p = pw })
        if not okw then log("login · heslo sa nedalo odovzdať: " .. tostring(err)) return hotovo(false) end
        run("latte-greetd", args, function(out)
            local ok, d = pcall(json.decode, out or "")
            if not (ok and type(d) == "table" and d.ok == true) then
                log("login · greetd: " .. tostring(ok and type(d) == "table" and d.chyba or out))
            end
            hotovo(ok and type(d) == "table" and d.ok == true)
        end)
        return
    end
    hotovo(pw == "latte")
end

on("e_odosli", function()
    safe("heslo", function()
        local pw = text.heslo or ""
        if pw == "" or fact.caka then return end
        fact.caka = true
        after(REZIM == "skuska" and 500 or 16, function()
            over(pw, function(dobre)
                text.heslo = ""
                fact.caka = false
                if dobre then
                    emit("e_ok")
                    if REZIM == "skuska" then
                        after(4200, function() emit("e_znova") uvod() end)
                    elseif REZIM == "zamok" then
                        -- LoginGoo odíde, zámok sa otvorí (kompozitor vráti plochu) a scéna skončí
                        after(1900, function() fact.zamknute = false end)
                        after(2300, function() run("pleamar", { "--say", "zamok", "quit" }, nil, { output = false }) end)
                    elseif REZIM == "greetd" then
                        -- relácia je pripravená: po odchode LoginGoo skončí všeobecná relácia a greetd ju spustí
                        after(2300, function() run("latte-greetd", { "koniec" }, nil, { output = false }) end)
                    end
                else
                    emit("e_zle")
                end
            end)
        end)
    end)
end)

on("text:heslo", function() emit("e_zobud") end)     -- písanie vráti informačné goo pod hladinu

on("e_rel", function(i)
    local r = relacie[(i or 0) + 1]
    if not r then return end
    text.rel_meno = r.meno or r.subor or ""
    log("login · relácia: " .. tostring(r.subor) .. " (" .. table.concat(r.prikaz or {}, " ") .. ")")
end)

local MOC = { "suspend", "reboot", "poweroff" }
on("e_moc", function(k)
    local co = MOC[(k or 0) + 1]
    if not co then return end
    if REZIM == "skuska" then log("login · napájanie (skúška, nič sa nevykoná): " .. co) return end
    run("systemctl", { co }, nil, { output = false })
end)

fact.ostane = REZIM ~= "skuska"                      -- pozadie mizne iba pri skúške nad plochou
data()
clock()
every(5000, clock)
every(60000, data)                                   -- novinky a batéria sa občas obnovia
if REZIM == "zamok" then
    -- rozloženie podľa najmenšieho monitora (zámok má jedno, vycentrované na každom)
    local okw, w = pcall(sys.ask, "env", "LATTE_ZAMOK_W")
    local okh, h = pcall(sys.ask, "env", "LATTE_ZAMOK_H")
    if okw and tonumber(w) and tonumber(w) >= 800 then fact.zw = tonumber(w) end
    if okh and tonumber(h) and tonumber(h) >= 600 then fact.zh = tonumber(h) end
    local okm, m = pcall(sys.ask, "env", "LATTE_ZAMOK_MW")
    fact.mw = (okm and tonumber(m) and tonumber(m) >= 800) and tonumber(m) or fact.zw
    fact.zamknute = true                             -- kým to neplatí, zámok neexistuje (kind: lock, open: zamknute)
    after(80, function() emit("e_hned") end)         -- bez šálky: riadok rovno na hladine
else
    uvod()
end
log("login · režim " .. REZIM)
end
