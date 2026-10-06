-- engine Goo — Goobar (lišta s oknami, LATTEOS-GOO.md §4.1) prenesený z plochy Kvapky (kvapka.luau › layout):
-- každé okno je kvapka enginu (E.upsert) s ikonou aplikácie; okná tej istej aplikácie sa zlepia do strapca ako ikry
-- (prvé pri lište, ďalšie smerom od nej, „náhodne“, ale pre každé poradie rovnako), čím viac okien, tým menšie
-- (do 72 %); myš nad strapcom ho rozvinie do radu. Aktívne okno je plnšie, minimalizované menšie a stlmené.
--
-- POMENOVANIE OKIEN (problém z plochy Kvapky): služba `window` (wlr-foreign-toplevel) dá iba triedu (app_id),
-- titulok a vlastné id — žiadnu adresu Hyprlandu. Skupina a ikona = aplikácia zo spúšťača (služba `apps`, súbory
-- .desktop): podľa StartupWMClass, id spúšťača alebo jeho koncovky (Flatpak: trieda „firefox“, id
-- „org.mozilla.firefox“), inak podľa mena. Aplikácie LatteOS (Quickshell) majú všetky triedu „org.quickshell“ →
-- podľa titulku („Súbory — LatteOS“ = Name spúšťača), kým nedostanú vlastné app_id (ROADMAP). Okno sa v Hyprlande
-- hľadá podľa triedy, titulku a poradia (`nth_of`: terminály majú často rovnaký titulok „~“).
local E = require("lib/engine")
local M = {}

local HEAD = "goobar"
local SLOTS = 48                    -- okien v lište najviac (Nová architektúra: 48 miest, potom zberná guľôčka)
-- ikry sú menšie než ostatné kvapky (nezamieňajú sa s nimi) a lepia sa iba ku Goobaru: skupina sk = 1 (susedia,
-- voda a vlákna iba v nej a s hlavou; cudzie kvapky od ikier odsúva pravidlo 22). Telo goo je jedno pre všetky
local R0 = 22
local R_TIGHT = 17                  -- pod oknom: menšie, v cik-cak rade pri okraji
local OFFS = { { 0, 0 }, { 1.72, -0.42 }, { 0.78, -1.62 }, { -0.98, -1.3 }, { 2.28, -1.86 },
               { 0.02, -3.0 }, { 1.62, -3.12 }, { -1.25, -2.85 }, { 2.9, -3.0 }, { 0.85, -4.2 },
               { -0.6, -4.3 }, { 2.2, -4.3 }, { 3.4, -1.1 }, { 0.1, -5.4 }, { 1.55, -5.5 },
               { -1.3, -5.2 }, { 3.1, -4.4 }, { -1.9, -1.9 }, { 0.8, -6.6 }, { 2.4, -6.4 } }
local JIT = { { 0, 0 }, { 0.06, -0.04 }, { -0.05, 0.07 }, { 0.08, 0.03 }, { -0.07, -0.05 },
              { 0.05, 0.06 }, { -0.04, 0.05 }, { 0.07, -0.06 }, { -0.06, 0.04 }, { 0.04, -0.07 },
              { 0.03, 0.05 }, { -0.05, -0.03 }, { 0.06, 0.02 }, { -0.03, -0.06 }, { 0.05, 0.04 },
              { -0.06, 0.03 }, { 0.02, -0.05 }, { 0.04, 0.06 }, { -0.04, -0.04 }, { 0.06, -0.02 } }
local ZIG = { 0, 0.46, 0.12, 0.52, 0.04, 0.38, 0.18, 0.5 }   -- cik-cak strapca v páse pod oknom (násobky r)
local MODE_ICON = { plavajuce = "app-window", dlazdice = "layout-grid", paska = "layout-columns" }

local wins = {}                     -- zoznam okien (služba window), v jej poradí
local hidden = {}                   -- index → minimalizované (plocha special:minimized)
local live = {}                     -- id kvapky okna → true (na zmazanie zatvorených)
local group_order = {}              -- poradie aplikácií, ktoré si používateľ nastavil ťahaním
local spans = {}                    -- kľúč skupiny → stred strapca (px od hlavy)
local hot, hot_gen = nil, 0         -- strapec pod myšou (rozvinutý)
local mode = "plavajuce"
-- okná nad lištou (návrh používateľa, Kvapky 30. 9.): každé ako úsek pozdĺž okraja v px od stredu hlavy { a0, a1, gap }
-- (gap = voľno medzi oknom a okrajom). Strapec sa nezrovnáva podľa hocijakého okna, iba podľa okien priamo nad sebou:
-- kým tam okno nie je, zhromaždí sa do výšky (hrozno); keby okno prekryl, uhne k okraju do radu.
local blocks = {}
local low_was = {}                  -- kľúč strapca → bol naposledy stiahnutý (hysterézia, aby neblikal)
local function free_above(x0, x1)
    local g = 999
    for _, b in ipairs(blocks) do
        if b.a1 > x0 and b.a0 < x1 then g = math.min(g, b.gap) end
    end
    return g
end

-- ── okno → aplikácia ─────────────────────────────────────────────────────────────────────────────────────────
local apps_by = { wm = {}, id = {}, tail = {}, name = {} }
local function index_apps(list)
    apps_by = { wm = {}, id = {}, tail = {}, name = {} }
    for _, a in ipairs(list or {}) do
        if a.wmclass and a.wmclass ~= "" then apps_by.wm[a.wmclass:lower()] = a end
        if a.id then
            local id = a.id:lower()
            local tail = (id:match("([^%.]+)$") or id)
            apps_by.id[id] = a
            apps_by.tail[tail] = apps_by.tail[tail] or a
        end
        if a.name then apps_by.name[a.name:lower()] = apps_by.name[a.name:lower()] or a end
    end
end
local function latte_title(w) return ((w.title or ""):match("^(.-) — ") or w.title or "") end
function M.app_of(w)
    local c = (w.class or ""):lower()
    if c == "org.quickshell" then return apps_by.name[latte_title(w):lower()] end
    return apps_by.wm[c] or apps_by.id[c] or apps_by.tail[c] or apps_by.name[c]
end
-- aplikácia zo spúšťača podľa časti mena (ChatGoo: „beeper“ → pôvodná ikona Beepera)
function M.find_app(part)
    for _, t in ipairs({ apps_by.wm, apps_by.id, apps_by.name }) do
        for k, a in pairs(t) do if k:find(part, 1, true) then return a end end
    end
end
function M.group_key(w)
    local a = M.app_of(w)
    if a then return "app:" .. (a.id or a.name) end
    if (w.class or "") == "org.quickshell" then return "latte:" .. latte_title(w) end
    return w.class or "?"
end
-- ikona zo spúšťača; okno bez spúšťača (aj bez ikony v téme) dostane znak okna (pole `ikona`), nie prázdnu guľu
local function icon_of(w)
    local a = M.app_of(w)
    return (a and a.icon and a.icon ~= "") and a.icon or ""
end
function M.wins() return wins end
local function app_name(w)
    local a = M.app_of(w)
    return (a and a.name) or (w.class ~= "org.quickshell" and w.class) or latte_title(w)
end

-- koľké okno s tou istou triedou a titulkom je okno i (Hyprland ho hľadá rovnako, latte/bars.lua)
local function nth_of(i)
    local w, n = wins[i], 0
    if w and w._nth then return w._nth end                 -- poradie medzi VŠETKÝMI oknami (wins sú iba z tohto monitora)
    for j = 1, i do
        local o = wins[j]
        if o and o.class == w.class and o.title == w.title then n = n + 1 end
    end
    return n
end
local function win_eval(fn, i)
    local w = wins[i]
    if w then run("hyprctl", { "eval", string.format("latte.win.%s(%q, %q, %d)", fn, w.class or "", w.title or "", nth_of(i)) }) end
end

-- ── rozloženie (kvapka.luau › layout, bez okien nad lištou a „tight“ — zatiaľ) ─────────────────────────────────
local function index_of(id) for i, w in ipairs(wins) do if ("w:" .. tostring(w.id or i)) == id then return i end end end

local function layout()
    local groups, first = {}, {}
    local over = #wins > SLOTS
    for i, w in ipairs(wins) do
        if i > SLOTS then break end
        local k = (over and i == SLOTS) and "~viac" or M.group_key(w)
        if not groups[k] then groups[k] = {} first[#first + 1] = k end
        table.insert(groups[k], i)
    end
    local order, used = {}, {}
    for _, k in ipairs(group_order) do if groups[k] and not used[k] then order[#order + 1] = k used[k] = true end end
    for _, k in ipairs(first) do if not used[k] then order[#order + 1] = k used[k] = true end end
    local paska = mode == "paska"
    local lay, u = {}, 52                 -- u: ľavý okraj ďalšieho strapca (px od stredu hlavy, hlava má polomer 44)
    for _, key in ipairs(order) do
        local idx = groups[key]
        local m = #idx
        local r = (paska and 24 or R0) * math.max(0.72, 1 - 0.07 * (m - 1))
        local lo, hi, top = 0, 0, 0
        for j = 1, math.min(m, #OFFS) do
            local ox = OFFS[j][1] + JIT[j][1]
            lo, hi, top = math.min(lo, ox), math.max(hi, ox), math.max(top, -(OFFS[j][2] + JIT[j][2]))
        end
        -- nad strapcom musí byť voľno na jeho výšku (+ nadnesenie), inak uhne k okraju do radu
        local need = top * r + r + 56 + (low_was[key] and 16 or 0)
        local tight = free_above(u, u + (hi - lo) * r + 2 * r) < need
        low_was[key] = tight
        local row = tight or m == 1 or key == hot or m > #OFFS
        if key == hot and not tight then r = paska and 24 or R0 end
        if tight then r = math.min(r, R_TIGHT) end
        if row and tight and m > 1 then
            -- pod oknom: strapec využije pás po spodok okna, nepravidelne (cik-cak), bez prekrytia okna
            local step = r * 1.45
            for j, i in ipairs(idx) do
                lay[i] = { x = u + r + (j - 1) * step, y = -ZIG[((j - 1) % #ZIG) + 1] * r, r = r * (1 + 0.05 * (((j - 1) * 37) % 5 - 2) / 2), tight = true }
            end
            u = u + 2 * r + (m - 1) * step + 12
        elseif row then
            local step = r * 1.86
            for j, i in ipairs(idx) do lay[i] = { x = u + r + (j - 1) * step, y = 0, r = r, tight = tight } end
            u = u + 2 * r + (m - 1) * step + 12
        else
            local ax = u + r - lo * r
            for j, i in ipairs(idx) do
                local rr = r * (1 + 0.06 * (((j - 1) * 37) % 5 - 2) / 2)
                lay[i] = { x = ax + (OFFS[j][1] + JIT[j][1]) * r, y = (OFFS[j][2] + JIT[j][2]) * r, r = rr }
            end
            u = ax + hi * r + r + 12
        end
    end
    -- šnúra sa musí zmestiť po kraj: všetko sa zmenší rovnakým pomerom (čím viac ikier, tým menšie)
    local head = E.get(HEAD)
    local sw = head and E.len(head) or 0
    if head and sw > 0 then
        local avail = E.hiAlong(head) - E.along(head) - 20   -- po koniec okraja (alebo po rohovú lištu), na ktorom lišta je
        if u > avail and u > 0 then
            local f = math.max(avail / u, 0.25)
            for _, e in pairs(lay) do e.x = e.x * f e.y = e.y * math.max(f, 0.5) e.r = e.r * math.max(f, 0.5) end
        end
    end
    -- kvapky okien: pridať / zmeniť / zmazať zatvorené
    local now = {}
    for i, w in ipairs(wins) do
        local e = lay[i]
        if e then
            local id = "w:" .. tostring(w.id or i)
            now[id] = true
            local more = over and i == SLOTS
            local r = e.r * (hidden[i] and 0.84 or 1) * (w.active and 1.06 or 1)
            local d = E.upsert({
                id = id, nazov = more and tr("More windows") or (w.title or ""), popis = more and "" or app_name(w),
                obr = more and "preferences-system-windows" or icon_of(w), velkost = r,
                ikona = "app-window",            -- bez spúšťača (žiadna ikona aplikácie): znak okna
                pri = HEAD, odstup = e.x, vyska = r * 0.8 - e.y, povaha = "pokojna",
                gravitacia = 0.15, vznos = e.tight and 0.15 or 0.55, lepivost = 0.35, rast = 0.1, dosah = 160, okno = i,
                sk = 1,                          -- skupina Goobaru: lepí sa iba k nemu
                zliatie = 0.35, mlaka = 0.15,    -- jednotlivé bobule hrozna s tenkými spojmi, nie jedna hmota
                klik = function(dd) M.click(dd) end, pravy = function(dd) M.menu(dd) end,
                nad = function(dd) M.hover(dd) end, prec = function(dd) M.unhover(dd) end,
                -- miesto pustenia pozdĺž okraja lišty (na bočnom okraji je to y)
                pustenie = function(dd, x, y) local h = E.get(HEAD) return M.drop(dd, h and (h.edge or 0) % 2 == 1 and y or x) end,
            })
            if d then d:stlm(hidden[i] and 1 or 0) end
        end
    end
    for id in pairs(live) do if not now[id] then E.remove(id) end end
    live = now
    spans = {}
    for _, key in ipairs(order) do
        local sx, n = 0, 0
        for _, i in ipairs(groups[key]) do sx = sx + (lay[i] and lay[i].x or 0) n = n + 1 end
        spans[#spans + 1] = { key = key, x = n > 0 and sx / n or 0 }
    end
end
M.layout = layout

-- ── vstupy na oknách ─────────────────────────────────────────────────────────────────────────────────────────
-- ľavý klik ako vo Windows: neaktívne okno sa ukáže, aktívne sa minimalizuje (LatteOS plocha special:minimized —
-- Hyprland žiadosť o minimalizáciu z wlr-foreign-toplevel ignoruje); „ďalšie okná“ = prehľad
function M.click(d)
    local i = index_of(d.id)
    if not i then return end
    if #wins > SLOTS and i == SLOTS then run("noctalia", { "msg", "panel-toggle", "latteos/overview:panel" }) return end
    win_eval("toggle_by", i)
end
function M.hover(d)
    local i = index_of(d.id)
    hot_gen = hot_gen + 1
    local key = i and M.group_key(wins[i])
    if key ~= hot then hot = key layout() end
end
function M.unhover(d)
    hot_gen = hot_gen + 1
    local mine = hot_gen
    after(500, function() if mine == hot_gen and hot then hot = nil layout() end end)
end
-- pustená po ťahaní: jej aplikácia sa presunie pred strapec, nad ktorým je (poradie aplikácií), okno ostane v lište
function M.drop(d, x)
    local i = index_of(d.id)
    local head = E.get(HEAD)
    if not i or not head then return false end
    local key = M.group_key(wins[i])
    local rel = x - E.along(head)                   -- x: miesto pustenia pozdĺž okraja lišty (px)
    local keys = {}
    for _, sp in ipairs(spans) do if sp.key ~= key then keys[#keys + 1] = sp end end
    local at = #keys + 1
    for k, sp in ipairs(keys) do if rel < sp.x then at = k break end end
    local new = {}
    for k, sp in ipairs(keys) do
        if k == at then new[#new + 1] = key end
        new[#new + 1] = sp.key
    end
    if at > #keys then new[#new + 1] = key end
    group_order = new
    after(30, layout)
    return false
end

-- ponuka okna (pravý klik, ako vo Windows): Obnoviť, Minimalizovať, Maximalizovať, Rozloženie ›, Navrchu,
-- Na plochu ›, Zavrieť — akcie robí Hyprland (latte/okno.lua), okno sa najprv aktivuje, aby malo adresu
function M.menu(d)
    local i = index_of(d.id)
    if not i or (#wins > SLOTS and i == SLOTS) then return end
    win_eval("focus_by", i)
    after(120, function()
        run("hyprctl", { "-j", "activewindow" }, function(out)
            local ok, w = pcall(json.decode, out or "")
            if not ok or type(w) ~= "table" or not w.address then return end
            local a = w.address
            local function q(lua) return function() run("hyprctl", { "eval", lua }) end end
            local function ok_(fn, arg) return q(string.format("latte.okno.%s('%s'%s)", fn, a, arg and ("," .. arg) or "")) end
            local function lay(z, label, glyph) return { label = tr(label), glyph = glyph, run = q(string.format("latte.okno.rozlozenie('%s','%s')", a, z)) } end
            local ws = (type(w.workspace) == "table" and tonumber(w.workspace.id)) or 0
            local desks = {}
            for n = 1, 4 do desks[#desks + 1] = { label = tr("Desktop") .. " " .. n, on = ws == n, run = ok_("na_plochu", n) } end
            desks[#desks + 1] = { label = tr("New desktop"), glyph = "plus", run = ok_("na_plochu", 0) }
            E.menu({
                { label = tr("Restore"), glyph = "arrows-minimize", run = ok_("obnovit") },
                { label = tr("Minimize"), glyph = "minus", run = ok_("minimalizovat") },
                { label = tr("Maximize"), glyph = "square", off = w.fullscreen == 1, run = ok_("maximalizovat") },
                { label = tr("Layout"), glyph = "layout-grid", sub = {
                    lay("lava", "Left half", "layout-sidebar"), lay("prava", "Right half", "layout-sidebar-right"),
                    lay("lh", "Top left", "layout-grid"), lay("ph", "Top right", "layout-grid"),
                    lay("ld", "Bottom left", "layout-grid"), lay("pd", "Bottom right", "layout-grid"),
                    lay("stred", "Center", "focus-centered") } },
                { label = tr("Always on top (all desktops)"), glyph = "pin", on = w.pinned == true, run = ok_("navrchu") },
                { label = tr("Move to desktop"), glyph = "stack-2", sub = desks },
                { label = tr("Close"), glyph = "x", hint = "Alt+F4", danger = true, sep = true, run = ok_("zavriet") },
            }, 320)
        end)
    end)
end

-- ── hlava: režim okien ───────────────────────────────────────────────────────────────────────────────────────
local function read_mode()
    run("latte-goo", { "rezim" }, function(out)
        local m = (out or ""):match("%a+")
        if m and MODE_ICON[m] and m ~= mode then
            mode = m
            local h = E.get(HEAD)
            if h then h:ikona(MODE_ICON[m]) h:nazov(tr(({ plavajuce = "Floating windows", dlazdice = "Tiles", paska = "Tape" })[m])) end
            layout()
        end
    end)
end
-- ľavý klik = ďalší režim okien; koliesko: páska = posun, plávajúce = ďalšie okno (Alt+Tab), dlaždice = nič
function M.head_click() run("hyprctl", { "eval", 'require("latte.windows").cycle()' }, function() after(250, read_mode) end) end
-- pravý klik = ukázať plochu (Win+D v Hyprlande, latte/skratky.lua: prázdna plocha; znova = späť na okná)
function M.show_desktop() run("hyprctl", { "eval", "latte.keys.show_desktop()" }) end
function M.head_wheel(dir)
    if mode == "paska" then
        local px = math.floor((tonumber(fact.sw) or 1920) * 0.25)
        run("hyprctl", { "eval", string.format('hl.dispatch(hl.dsp.layout("move %s%d"))', dir > 0 and "-" or "+", px) })
    elseif mode == "plavajuce" then
        run("hyprctl", { "eval", "latte.win.cycle(" .. dir .. ")" })
    end
end

-- ── minimalizované okná (plocha special:minimized): priradenie cez triedu, titulok a poradie ─────────────────────
-- Zoznam okien zo služby `window` nevie, na ktorom monitore okno je; vie to Hyprland. Preto sa `raw` (všetky okná)
-- spáruje s `hyprctl clients` a do `wins` idú iba okná monitora tejto inštancie (E.monitorId; GooBar je na každom
-- monitore so svojimi oknami, ako panel úloh Windows). Bez Hyprlandu alebo bez čísla monitora idú všetky.
local raw = {}
-- okno četu (Beeper) nepatrí lište, ale kvapke ChatGoo, keď je na ploche: tu sa iba zistí, či beží a či je schované
local chat = { running = false, minimized = false, title = "" }
function M.chat() return chat end
local function mark_hidden()
    run("hyprctl", { "-j", "clients" }, function(out)
        local ok, list = pcall(json.decode, out or "")
        if not ok or type(list) ~= "table" then
            if #wins ~= #raw then wins = raw layout() end
            return
        end
        local seen_raw, nw, nh = {}, {}, {}
        local nc = { running = false, minimized = false, title = "" }
        for _, c in ipairs(list) do
            if (tostring(c.class or "") .. " " .. tostring(c.initialClass or "")):lower():find("beeper", 1, true) then
                nc.running, nc.title = true, tostring(c.title or "")
                nc.minimized = c.workspace ~= nil and tostring(c.workspace.name or ""):find("^special:minimized") ~= nil
            end
        end
        chat = nc
        local skip_chat = nc.running and E.chatOn()
        for _, w in ipairs(raw) do
            local key = (w.class or "") .. "\0" .. (w.title or "")
            seen_raw[key] = (seen_raw[key] or 0) + 1
            local want, seen, found = seen_raw[key], 0, nil
            for _, c in ipairs(list) do
                if c.class == w.class and c.title == w.title then
                    seen = seen + 1
                    if seen == want then found = c break end
                end
            end
            local mon = found and tonumber(found.monitor)
            -- okno, ktoré Hyprland (ešte) nepozná pod týmto titulkom, ukáže iba hlavný monitor — nie obe lišty
            if skip_chat and tostring(w.class or ""):lower():find("beeper", 1, true) then
                -- okno Beepera: žiadna ikra v lište, drží ho ChatGoo
            elseif E.monitorId == nil or mon == E.monitorId or (mon == nil and not E.vedlajsi) then
                w._nth = want
                nw[#nw + 1] = w
                nh[#nw] = (found and found.workspace and tostring(found.workspace.name or ""):find("^special:minimized") ~= nil) or false
            end
        end
        local changed = #nw ~= #wins
        for i, w in ipairs(nw) do
            local o = wins[i]
            if not o or o.id ~= w.id or o.title ~= w.title or o.active ~= w.active or (nh[i] or false) ~= (hidden[i] or false) then changed = true break end
        end
        wins, hidden = nw, nh
        if changed then layout() end
    end)
end

-- okná nad lištou → úseky pozdĺž okraja v px od stredu hlavy (latte-goo okna: Hyprland, na skúšky Sway)
local blocks_sig = ""
function M.read_blocks()
    run("latte-goo", { "okna" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        local head = E.get(HEAD)
        if not ok or type(t) ~= "table" or not head or (t.h or 0) <= 0 then return end
        E.setCorner(type(t.roh) == "table" and t.roh or nil)
        local hx = E.along(head)
        local nb = {}
        -- uhýbanie oknám má zmysel iba na dolnom okraji (okná „nad lištou“); na inom okraji ikry neuhýbajú
        for _, w in ipairs((head.edge or 0) == 0 and t.okna or {}) do
            local gap = t.h - (w.y + w.h)
            if gap < 400 and w.y < t.h then nb[#nb + 1] = { a0 = w.x - hx, a1 = w.x + w.w - hx, gap = math.max(0, gap) } end
        end
        local sig = json.encode(nb)
        if sig ~= blocks_sig then blocks_sig, blocks = sig, nb layout() end
    end)
end

function M.start()
    sys.watch("apps", function(list) index_apps(list) layout() end)
    -- `window` dá zoznam iba cez wlr-foreign-toplevel (na Hyprlande so záplatou PLEAMAR_GENERIC=window)
    local ok = sys.watch("window", function(v) raw = (v and v.list) or {} mark_hidden() end)
    if not ok then log("goobar: tento systém nehlási okná") end
    read_mode()
    every(2000, function() read_mode() mark_hidden() end)
    every(700, M.read_blocks)
    E.onWinMin = mark_hidden                 -- okno práve padlo do lišty: ikra sa stlmí hneď, nie až o 2 s
end

return M
