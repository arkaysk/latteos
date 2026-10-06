-- ClockGoo (čas, kalendár, upozornenia a pohoda, LATTEOS-GOO.md §4.5): voliteľná kvapka, ktorá
-- spája čas a centrum upozornení (predtým TimeGoo a DaNoGoo). V kvapke veľký čas a dátum; guľky počtu upozornení —
-- systémové/kritické červeno-kávové, ostatné žlté (do 4, nad 4 s počtom); nové upozornenie zvlní hladinu.
-- Ľavý klik = UPOZORNENIA A KALENDÁR (používateľ 6. 10.: „upozornenia a kalendárová sekcia vrátane napojených
-- programov, pekne estetický a ergonomický“; ako centrum upozornení vo Windows 11): karta v dvoch stĺpcoch —
--   vľavo upozornenia (ikona aplikácie, nadpis, telo; klik otvorí, pravý klik akcie a Zahodiť), Nerušiť, Vymazať
--   všetko, Nastavenia oznámení; vpravo mesiac (koliesko a šípky), udalosti a úlohy vybraného dňa, nová udalosť
--   do poľa, prepojené kalendáre (Google, iCloud, CalDAV — Noctalia).
-- Pravý klik = KARTA ČASU (lib/cas.luau, údaje spoločné s plochou Kvapky): Prehľad (dátum, týždeň, najbližší budík,
-- digitálna pohoda, svetové hodiny) · Stopky (medzičasy) · Minútka (koliesko nastaví dĺžku) · Budíky · Počasie.
-- Minútka a budíky zvonia, aj keď je karta zatvorená; bežiaca minútka alebo stopky sa ukazujú v kvapke namiesto dátumu.
-- Upozornenia prijíma pleamar — iba jeden proces.
local E = require("lib/engine")
local cas = require("lib/cas")
local DNI = { "ne", "po", "ut", "st", "št", "pi", "so" }
local notes, seen = {}, {}
local MAX = 5                         -- upozornení v karte (ďalšie: „+N ďalších“)
local dnd = false                     -- Nerušiť (Noctalia)

local function paint(d)
    local crit, n = 0, #notes
    for _, x in ipairs(notes) do if (x.urgency or 1) >= 2 then crit = crit + 1 end end
    if n == 0 then d:gulky(0) return end
    d:gulky(n, crit > 0 and "system" or "zlta")
end

-- ── karta času (pravý klik) ──────────────────────────────────────────────────────────────────────────────────
local DNI_PLNE = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local tab = 0
local card
local function chips(d)
    local function t(i, glyph, label) return { glyph = glyph, label = tr(label), on = tab == i, run = function() tab = i card(d, true) end } end
    -- (kalendár je od 6. 10. na ľavom klike spolu s upozorneniami)
    return { t(0, "layout-dashboard", "Overview"), t(1, "stopwatch", "Stopwatch"), t(2, "hourglass", "Timer"), t(3, "alarm", "Alarms"),
             t(5, "cloud", "Weather") }
end
local function overview(d)
    local t = os.date("*t")
    -- týždeň podľa ISO 8601 (Luau os.date nepozná %V): pondelok = 1
    local iso = (t.wday + 5) % 7 + 1
    local week = (t.yday - iso + 10) // 7
    if week < 1 then week = 52 end
    local items = {
        { big = true, off = true, label = os.date("%H:%M") },
        { info = true, glyph = "calendar", label = tr(DNI_PLNE[t.wday]) .. "  " .. t.day .. ". " .. t.month .. ". " .. t.year,
          hint = tr("week") .. " " .. week },
    }
    local parts = {}
    local nxt = cas.next_alarm()
    if nxt then parts[#parts + 1] = tr("Alarm") .. " " .. nxt.time end
    local running, active, left = cas.timer_state()
    if running then parts[#parts + 1] = tr("Timer") .. " " .. cas.fmt(left + 999) end
    if #parts > 0 then items[#items + 1] = { info = true, glyph = "alarm", label = table.concat(parts, "  ·  ") } end
    -- digitálna pohoda: čas pred obrazovkou a tri najpoužívanejšie aplikácie dnes
    local p = cas.pohoda or {}
    items[#items + 1] = { sep = true, glyph = "heart", label = cas.dur(p.spolu or 0) .. " " .. tr("on screen today"), hint = tr("details"),
                          run = function() run("latte-app", { "monitor", "pohoda" }) end }
    local top = math.max((p.aplikacie or {})[1] and p.aplikacie[1].s or 1, 1)
    for _, a in ipairs(p.aplikacie or {}) do
        items[#items + 1] = { info = true, label = a.nazov or "", hint = cas.dur(a.s or 0), bar = (a.s or 0) / top }
    end
    for i, z in ipairs(cas.pasma or {}) do
        items[#items + 1] = { info = true, sep = i == 1, glyph = "world", label = z.mesto or "", hint = (z.hm or "") .. ((z.rozdiel or "") ~= "" and "  ·  " .. z.rozdiel or "") }
    end
    items[#items + 1] = { sep = true, glyph = "settings", label = tr("Date and time settings"), run = function() run("latte-app", { "nastavenia", "cas" }) end }
    return items
end
local function stopwatch(d)
    local sw = cas.timers().sw
    local function again() card(d, true) end
    local items = {
        { big = true, off = true, label = cas.fmt(cas.elapsed(), true) },
        { keep = true, glyph = sw.running and "player-pause" or "player-play", label = tr(sw.running and "Stop" or "Start"), run = function() cas.sw_toggle() again() end },
    }
    if sw.running then items[#items + 1] = { keep = true, glyph = "flag", label = tr("Lap"), run = function() cas.sw_lap() again() end } end
    if sw.running or (sw.acc or 0) > 0 then items[#items + 1] = { keep = true, glyph = "refresh", label = tr("Reset"), run = function() cas.sw_reset() again() end } end
    for i, lap in ipairs(sw.laps) do
        if i > 6 then break end
        items[#items + 1] = { info = true, sep = i == 1, label = tr("Lap") .. " " .. (#sw.laps - i + 1), hint = cas.fmt(lap, true) }
    end
    return items
end
local function timer(d)
    local running, active, left, dur = cas.timer_state()
    local function again() card(d, true) end
    local items = {
        { big = true, off = true, label = cas.fmt(active and (left + (running and 999 or 0)) or dur), bar = active and left / math.max(dur, 1) or 1 },
        { keep = true, glyph = running and "player-pause" or "player-play", label = tr(running and "Pause" or (active and "Resume" or "Start")),
          run = function() cas.timer_toggle() again() end },
    }
    if active then
        items[#items + 1] = { keep = true, glyph = "x", label = tr("Cancel"), run = function() cas.timer_cancel() again() end }
    else
        -- myš prvá: dĺžku nastaví koliesko nad riadkom, alebo jedna z predvolieb nižšie
        items[#items + 1] = { keep = true, glyph = "adjustments-horizontal", label = tr("Length") .. ": " .. math.floor(dur / 60000 + 0.5) .. " min", hint = tr("wheel"),
                              wheel = function(dir) cas.timer_adjust(dir) again() end, run = function() cas.timer_adjust(1) again() end }
        for i, m in ipairs({ 1, 5, 10, 15, 25, 45 }) do
            items[#items + 1] = { keep = true, sep = i == 1, glyph = "hourglass", label = m .. " min", run = function() cas.timer_start(m) again() end }
        end
    end
    return items
end
local function alarms(d)
    local function again() card(d, true) end
    local items, off = {}, 0
    for i, a in ipairs(cas.timers().alarms) do
        if i > 7 then break end
        if not a.on then off = off + 1 end
        items[#items + 1] = { keep = true, glyph = "alarm", on = a.on == true, label = (a.time or "") .. ((a.label or "") ~= "" and "  " .. a.label or ""),
                              hint = tr(a.on and "on" or "off"), run = function() cas.alarm_toggle(i) again() end }
    end
    if #items == 0 then items[1] = { off = true, glyph = "alarm", label = tr("No alarms") } end
    -- nový budík: hodinu a minútu nastaví koliesko (alebo klik = o krok ďalej)
    items[#items + 1] = { keep = true, sep = true, glyph = "clock", label = tr("Hour") .. ": " .. string.format("%02d", cas.alh), hint = tr("wheel"),
                          wheel = function(dir) cas.alh = (cas.alh + dir) % 24 again() end, run = function() cas.alh = (cas.alh + 1) % 24 again() end }
    items[#items + 1] = { keep = true, glyph = "clock", label = tr("Minute") .. ": " .. string.format("%02d", cas.alm), hint = tr("wheel"),
                          wheel = function(dir) cas.alm = (cas.alm + dir * 5) % 60 again() end, run = function() cas.alm = (cas.alm + 5) % 60 again() end }
    items[#items + 1] = { keep = true, glyph = "plus", label = tr("Add alarm") .. " " .. string.format("%02d:%02d", cas.alh, cas.alm), run = function() cas.alarm_add() again() end }
    if off > 0 then items[#items + 1] = { keep = true, danger = true, glyph = "trash", label = tr("Remove alarms that are off"), run = function() cas.alarm_prune() again() end } end
    return items
end
-- ── kalendár (záložka 4): mesiac od pondelka, udalosti a úlohy vybraného dňa. Prevzaté z karty DaNoGoo v Kvapkách,
-- tie isté súbory events.json a todo.json (zápis `latte-kvapky uloz udalosti|ulohy`).
-- Nový záznam do poľa: „10:30 Porada“ (s časom), „Porada“ (celý deň), „! úloha“ (úloha na vybraný deň).
local K = { y = nil, m = nil, sel = nil, events = {}, todos = {}, cells = {} }
local MESIACE = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local DNI_KRATKE = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
local function iso(t) return string.format("%04d-%02d-%02d", t.year, t.month, t.day) end
local function cal_paint()
    local now = os.date("*t")
    K.y, K.m, K.sel = K.y or now.year, K.m or now.month, K.sel or iso(now)
    local today = iso(now)
    local first = os.date("*t", os.time({ year = K.y, month = K.m, day = 1, hour = 12 }))
    local lead = (first.wday + 5) % 7                                   -- pondelok = 0
    local has = {}
    for _, e in ipairs(K.events) do if e.date then has[e.date] = true end end
    local out = {}
    K.cells = {}
    for i = 0, 41 do
        local t = os.date("*t", os.time({ year = K.y, month = K.m, day = 1 - lead + i, hour = 12 }))
        local dd = iso(t)
        K.cells[i + 1] = dd
        out[#out + 1] = { d = tostring(t.day), inm = t.month == K.m, today = dd == today, sel = dd == K.sel and dd ~= today, dot = has[dd] == true }
    end
    model.kal = out
    text.kal_title = tr(MESIACE[K.m]) .. " " .. K.y
    for w = 1, 7 do text["kdn." .. (w - 1)] = tr(DNI_KRATKE[w]) end
end
local function cal_load(done)
    run("latte-goo", { "kalendar" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then
            K.events = type(t.udalosti) == "table" and t.udalosti or {}
            K.todos = type(t.ulohy) == "table" and t.ulohy or {}
        end
        if done then done() end
    end)
end
local function save_events()
    table.sort(K.events, function(a, b) return ((a.date or "") .. (a.time or "")) < ((b.date or "") .. (b.time or "")) end)
    run("latte-kvapky", { "uloz", "udalosti", json.encode(K.events) }, nil, { output = false })
end
local function save_todos() run("latte-kvapky", { "uloz", "ulohy", json.encode(K.todos) }, nil, { output = false }) end
-- ── UPOZORNENIA A KALENDÁR (ľavý klik): karta v dvoch stĺpcoch ──────────────────────────────────────────────
local ncard
-- pravý stĺpec: mesiac, udalosti a úlohy vybraného dňa, nová udalosť, prepojené kalendáre (na výšku 1024 × 768)
local function calendar(d)
    cal_paint()
    local now = os.date("*t")
    local y, m, dd = K.sel:match("(%d+)-(%d+)-(%d+)")
    local st = os.date("*t", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }))
    local items = {
        { col = 2, grid = true },
        { col = 2, info = true, glyph = "calendar", label = (K.sel == iso(now) and (tr("Today") .. " · ") or "") .. tr(DNI_PLNE[st.wday]) .. " " .. tonumber(dd) .. ". " .. tonumber(m) .. "." },
    }
    local evs = {}
    for i, e in ipairs(K.events) do if e.date == K.sel then evs[#evs + 1] = { i = i, e = e } end end
    table.sort(evs, function(a, b) return (a.e.time or "") < (b.e.time or "") end)
    for n, it in ipairs(evs) do
        if n > 2 then
            items[#items + 1] = { col = 2, info = true, glyph = "dots", label = "+" .. (#evs - 2) .. " " .. tr("more") }
            break
        end
        -- (riadok s podponukou nemá miesto na údaj vpravo: čas je pred názvom)
        items[#items + 1] = { col = 2, glyph = "calendar-event", label = ((it.e.time or "") ~= "" and it.e.time or tr("All day")) .. "  " .. (it.e.title or ""),
                              sub = { { danger = true, glyph = "trash", label = tr("Delete event"), run = function() table.remove(K.events, it.i) save_events() ncard(d) end } } }
    end
    local n = 0
    for pass = 1, 2 do                                                  -- najprv nedokončené, potom hotové
        for i, t in ipairs(K.todos) do
            if n < 2 and ((t.date or "") == "" or t.date == K.sel) and (t.done == true) == (pass == 2) then
                n = n + 1
                items[#items + 1] = { col = 2, keep = true, glyph = "square", on = t.done == true, label = t.title or "",
                                      run = function() t.done = not t.done save_todos() ncard(d, true) end }
            end
        end
    end
    items[#items + 1] = { col = 2, input = true, glyph = "plus", label = tr("New event… 10:30 Meeting · ! task"), submit = function(v)
        if v:sub(1, 1) == "!" then
            local title = v:sub(2):gsub("^%s+", "")
            if title ~= "" then K.todos[#K.todos + 1] = { title = title, done = false, date = K.sel } save_todos() end
        else
            local h, mi, title = v:match("^(%d%d?):(%d%d)%s+(.+)$")
            if h and tonumber(h) < 24 and tonumber(mi) < 60 then
                K.events[#K.events + 1] = { date = K.sel, time = string.format("%02d:%02d", tonumber(h), tonumber(mi)), title = title }
            else
                K.events[#K.events + 1] = { date = K.sel, time = "", title = v }
            end
            save_events()
        end
        ncard(d, true)
    end }
    -- napojené programy: kalendárové účty (Google, iCloud, CalDAV, ICS) spravuje Noctalia
    items[#items + 1] = { col = 2, sep = true, glyph = "link", label = tr("Linked calendars"), hint = "Google · iCloud · CalDAV",
                          run = function() run("noctalia", { "msg", "settings-open" }) end }
    return items
end
-- ľavý stĺpec: upozornenia (najnovšie hore), Nerušiť, Vymazať všetko, Nastavenia oznámení
local function notifications(d)
    local items = { { hd = true, label = tr("NOTIFICATIONS"), hint = #notes > 0 and tostring(#notes) or "" } }
    if #notes == 0 then
        items[#items + 1] = { info = true, glyph = "bell-off", label = tr("No notifications"), t2 = tr("New ones appear here and ripple the edge") }
    end
    for i, x in ipairs(notes) do                                        -- služba ich dáva od najnovšieho
        if i > MAX then
            items[#items + 1] = { info = true, glyph = "dots", label = "+" .. (#notes - MAX) .. " " .. tr("more") }
            break
        end
        local crit = (x.urgency or 1) >= 2
        local body = tostring(x.body or ""):gsub("%s+", " ")
        local acts = type(x.actions) == "table" and x.actions or {}
        local icon = (x.icon or "") ~= "" and x.icon or nil
        items[#items + 1] = {
            img = icon, glyph = crit and "alert-triangle" or "bell", danger = crit,
            label = (x.title or "") ~= "" and x.title or (x.app or ""),
            t2 = ((x.app or "") ~= "" and (x.title or "") ~= "" and (x.app .. " · ") or "") .. body,
            run = function()
                pcall(sys.call, "notifications.invoke", x.id, "default")
                pcall(sys.call, "notifications.dismiss", x.id)
            end,
            -- pravý klik: akcie upozornenia (ak má) a Zahodiť; Späť vráti celú kartu
            right = function()
                local kids = { { label = tr("Back"), glyph = "chevron-left", back = nil } }
                for _, a in ipairs(acts) do
                    kids[#kids + 1] = { label = a.label or a.key or "", glyph = "chevron-right", sep = #kids == 1, run = function()
                        pcall(sys.call, "notifications.invoke", x.id, a.key)
                        pcall(sys.call, "notifications.dismiss", x.id)
                    end }
                end
                kids[#kids + 1] = { label = tr("Dismiss"), glyph = "x", sep = true, run = function() pcall(sys.call, "notifications.dismiss", x.id) end }
                kids[1].run, kids[1].keep = function() ncard(d) end, true
                E.menu(kids, 300, { owner = d })
            end,
        }
    end
    local row = { { glyph = dnd and "bell-off" or "bell", label = tr("Do not disturb"), on = dnd, keep = true, run = function()
        dnd = not dnd
        ncard(d, true)
        run("noctalia", { "msg", "notification-dnd-toggle" }, nil, { output = false })
    end } }
    if #notes > 0 then
        row[2] = { glyph = "trash", label = tr("Clear all"), danger = true, keep = true, run = function() pcall(sys.call, "notifications.clear") end }
    end
    items[#items + 1] = { sep = true, pills = row }
    items[#items + 1] = { glyph = "settings", label = tr("Notification settings"), run = function() run("latte-app", { "nastavenia", "oznamenia" }) end }
    return items
end
ncard = function(d, keep)
    local items = notifications(d)
    for _, it in ipairs(calendar(d)) do items[#items + 1] = it end
    E.menu(items, 620, { id = "notes", cols = { 300, 320 }, keep = keep, owner = d })
    if not keep then
        cal_load(function() if E.menuId() == "notes" then ncard(d, true) end end)
        run("noctalia", { "msg", "notification-dnd-status" }, function(out)
            local on = (out or ""):lower():match("true") ~= nil or (out or ""):lower():match("on") ~= nil
            if on ~= dnd then dnd = on if E.menuId() == "notes" then ncard(d, true) end end
        end)
    end
end

-- ── počasie (záložka 5): Open-Meteo cez `latte-goo pocasie`, ikony ako v Kvapkách ────────────────────────────
local wx = nil
local function wx_icon(c)
    c = tonumber(c) or 3
    if c == 0 then return "sun" end
    if c == 1 or c == 2 then return "sun-low" end
    if c == 45 or c == 48 then return "cloud-fog" end
    if c >= 95 then return "cloud-storm" end
    if (c >= 71 and c <= 77) or c == 85 or c == 86 then return "cloud-snow" end
    if (c >= 51 and c <= 67) or (c >= 80 and c <= 82) then return "cloud-rain" end
    return "cloud"
end
local function wx_load(done)
    run("latte-goo", { "pocasie" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" and type(t.teraz) == "table" then wx = t end
        if done then done() end
    end)
end
local function weather(d)
    if not wx then return { { big = true, off = true, label = "—" }, { off = true, glyph = "cloud", label = tr("No forecast yet") } } end
    local function rain(p) return (tonumber(p) or 0) > 0 and ("  ·  " .. p .. " %") or "" end
    local items = { { big = true, off = true, label = wx.teraz.t .. " °C" .. ((wx.miesto or "") ~= "" and "  " .. wx.miesto or "") } }
    local dni = wx.dni or {}
    if dni[1] then
        items[#items + 1] = { info = true, glyph = wx_icon(wx.teraz.kod), label = tr("Today"), hint = dni[1].max .. "° / " .. dni[1].min .. "°" .. rain(dni[1].zrazky) }
    end
    for i, h in ipairs(wx.hodiny or {}) do
        if i > 5 then break end
        items[#items + 1] = { info = true, sep = i == 1, glyph = wx_icon(h.kod), label = h.hm or "", hint = h.t .. "°" }
    end
    for i = 2, math.min(7, #dni) do
        local x = dni[i]
        items[#items + 1] = { info = true, sep = i == 2, glyph = wx_icon(x.kod), label = i == 2 and tr("Tomorrow") or tr(DNI_PLNE[(x.den + 1) % 7 + 1]),
                              hint = x.max .. "° / " .. x.min .. "°" .. rain(x.zrazky) }
    end
    return items
end

local build
card = function(d, keep)
    -- chyba v jednej záložke nesmie kartu potichu zmraziť: zapíše sa do logu
    local ok, err = pcall(build, d, keep)
    if not ok then
        log("goo: clockgoo karta (" .. tab .. "): " .. tostring(err))
        text.hud = "karta " .. tab .. ": " .. tostring(err)
    end
end
build = function(d, keep)
    local items = (tab == 1 and stopwatch or tab == 2 and timer or tab == 3 and alarms or tab == 5 and weather or overview)(d)
    -- pevná výška (horná hrana pri prepínaní záložiek neskáče); ucho = kvapka ClockGoo v rohu karty
    E.menu(items, 400, { id = "clock", chips = chips(d), keep = keep, owner = d, height = 690 })
    if not keep then                                                    -- čerstvé údaje pri otvorení
        local function again() if E.menuId() == "clock" then card(d, true) end end
        cas.load(again)
        wx_load(again)
    end
end

return {
    id = "clockgoo", nazov = "ClockGoo", druh = 2, povaha = "pokojna", velkost = 33, rast = 0.09, vyska = 22,
    poloha = { x = 0.79, y = 22 }, gravitacia = 0.25, dosah = 130, zoom = true,
    kazdych = 10000,
    tik = function(d)
        run("date", { "+%H:%M %w %-d %-m" }, function(out)
            local hm, w, dd, mm = (out or ""):match("(%d+:%d+) (%d) (%d+) (%d+)")
            if hm then
                d.datum = DNI[tonumber(w) + 1] .. " " .. dd .. ". " .. mm .. "."
                d:ikona(hm)
                if not d.alt then d:text(d.datum .. (wx and "  " .. wx.teraz.t .. "°" or "")) end
            end
        end)
    end,
    start = function(d)
        local ok = E.onNotes(function(list)
            -- upozornenia četu (Beeper) má pri sebe ChatGoo, keď je na ploche (LATTEOS-GOO.md §4.6)
            notes = {}
            local chat = E.chatOn()
            for _, x in ipairs(list or {}) do if not (chat and E.isChat(x)) then notes[#notes + 1] = x end end
            local fresh = false
            for _, x in ipairs(notes) do if not seen[x.id] then seen[x.id] = true fresh = true end end
            if fresh then d:vlnka(5) end
            paint(d)
            if E.menuId() == "notes" then ncard(d, true) end          -- otvorená karta sleduje zoznam
        end)
        -- upozornenia neexpirujú samy (kvapka je centrum upozornení, ako v Kvapkách)
        if ok then pcall(sys.call, "notifications.keep", true) end
        -- čas: údaje, stráženie minútky a budíkov, živá karta (stopky a minútka 5× za sekundu, prehľad raz)
        cas.load()
        cal_load()
        -- klik na deň a šípky mesiaca v mriežke kalendára
        E.calendar(function(q)
            local day = K.cells[q + 1]
            if not day then return end
            K.sel = day
            local y, m = day:match("(%d+)-(%d+)")
            K.y, K.m = tonumber(y), tonumber(m)
            ncard(d, true)
        end, function(dir)
            K.m = (K.m or os.date("*t").month) + dir
            if K.m < 1 then K.m = 12 K.y = K.y - 1 elseif K.m > 12 then K.m = 1 K.y = K.y + 1 end
            ncard(d, true)
        end)
        -- počasie: teplota vedľa dátumu v kvapke, nová predpoveď raz za 20 minút
        local function temp() wx_load(function() if wx and d.datum and not d.alt then d:text(d.datum .. "  " .. wx.teraz.t .. "°") end end) end
        after(4000, temp)
        every(20 * 60000, temp)
        cas.guard(function() if E.menuId() == "clock" then card(d, true) end end)
        local n = 0
        every(200, function()
            n = n + 1
            -- (kalendár a počasie sa samy neobnovujú: prepisovali by rozpísané pole a nič sa v nich nehýbe)
            if E.menuId() == "clock" and (tab == 1 or tab == 2 or (tab == 0 or tab == 3) and n % 5 == 0) then card(d, true) end
        end)
        -- bežiaca minútka (prednosť) alebo stopky sa ukazujú v kvapke namiesto dátumu
        every(1000, function()
            local running, active, left = cas.timer_state()
            local sw = cas.timers().sw
            if active then d.alt = true d:text(cas.fmt(left + (running and 999 or 0)))
            elseif sw.running then d.alt = true d:text(cas.fmt(cas.elapsed()))
            elseif d.alt then d.alt = false d.v.text = (d.datum or "") .. (wx and "  " .. wx.teraz.t .. "°" or "") E.publish() end
        end)
    end,
    -- ľavý klik: upozornenia a kalendár; znova klik kartu zavrie
    klik = function(d)
        if E.menuId() == "notes" then fact.ctx_open = false return end
        ncard(d)
    end,
    -- pravý klik: karta času (koliesko nad kvapkou mení veľkosť — spoločné pravidlo)
    pravy = function(d)
        if E.menuId() == "clock" then fact.ctx_open = false return end
        card(d)
    end,
    popis = function(d)
        return (#notes > 0 and (#notes .. " " .. tr("notifications") .. " · ") or "") .. tr("left: notifications and calendar · right: time, timer, alarms, weather")
    end,
}
