--!nonstrict
-- Panel času: Čas · Oznámenia · Kalendár (otvára ho hodiny, zvonček alebo dátum na lište).
--   Čas        veľké hodiny, dátum, týždeň; časové pásma; stopky, minútka, budíky; počasie
--   Oznámenia  zoznam oznámení, Nerušiť, oznámenia z mobilu (KDE Connect)
--   Kalendár   mesiac, plánovač udalostí (~/.local/share/latteos/events.json), úlohy (todo.json);
--              zvonenie a pripomenutia strážia hodiny na lište, aj keď je panel zatvorený
local C = require("./common.luau")
local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local dataHome = noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local eventsFile = dataHome .. "/latteos/events.json"
local tabFile = noctalia.pluginDataDir() .. "/panel-tab"

local longDays = { "nedeľa", "pondelok", "utorok", "streda", "štvrtok", "piatok", "sobota" }
local months = { "január", "február", "marec", "apríl", "máj", "jún", "júl", "august", "september", "október", "november", "december" }
local monthsGen = { "januára", "februára", "marca", "apríla", "mája", "júna", "júla", "augusta", "septembra", "októbra", "novembra", "decembra" }
local zoneNames = { ["Europe/London"] = "Londýn", ["America/New_York"] = "New York", ["America/Los_Angeles"] = "Los Angeles",
                    ["Asia/Tokyo"] = "Tokio", ["Asia/Shanghai"] = "Peking", ["Asia/Kolkata"] = "Dillí", ["Australia/Sydney"] = "Sydney",
                    ["Europe/Moscow"] = "Moskva", ["UTC"] = "UTC" }

local st = { tab = "cas", zones = {}, dnd = false, phone = nil, events = {}, ym = nil, sel = nil, newTitle = "", newTime = "",
             todos = {}, newTodo = "", timers = nil, timerIn = "", alarmIn = "", seq = 0 }   -- seq: nový key = prázdne pole po pridaní

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function iso(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end
local function today() local t = os.date("*t"); return t.year, t.month, t.day end
-- ISO týždeň (Luau os.date nepozná %V)
local function weeksIn(y)
  local function p(x) return (x + x // 4 - x // 100 + x // 400) % 7 end
  return (p(y) == 4 or p(y - 1) == 3) and 53 or 52
end
local function isoWeek(t)
  local wd = (t.wday + 5) % 7 + 1                  -- pondelok = 1 … nedeľa = 7
  local w = (t.yday - wd + 10) // 7
  if w < 1 then return weeksIn(t.year - 1) end
  if w > weeksIn(t.year) then return 1 end
  return w
end
local function daysIn(y, m) return os.date("*t", os.time({ year = y, month = m + 1, day = 0, hour = 12 })).day end

local function loadEvents()
  local raw = noctalia.readFile(eventsFile)
  local ok, list = pcall(function() return raw and noctalia.json.decode(raw) or {} end)
  st.events = (ok and type(list) == "table") and list or {}
end
local function saveEvents()
  table.sort(st.events, function(a, b) return (a.date .. (a.time or "")) < (b.date .. (b.time or "")) end)
  noctalia.mkdirAll(dataHome .. "/latteos")
  noctalia.writeFile(eventsFile, noctalia.json.encode(st.events))
end
local function eventsOn(date)
  local out = {}
  for i, e in ipairs(st.events) do if e.date == date then table.insert(out, { i = i, e = e }) end end
  return out
end

-- počasie (Open-Meteo, bez účtu): poloha z Nastavení (settings.toml [location]), mesto z greeter.conf
local weather, weatherAt = nil, 0
local function wmo(c)
  c = tonumber(c) or 0
  if c == 0 then return "Jasno", "sun" elseif c <= 2 then return "Polojasno", "cloud" elseif c == 3 then return "Zamračené", "cloud"
  elseif c <= 48 then return "Hmla", "cloud" elseif c <= 67 then return "Dážď", "cloud-rain" elseif c <= 77 then return "Sneh", "snowflake"
  elseif c <= 82 then return "Prehánky", "cloud-rain" elseif c <= 86 then return "Snehové prehánky", "snowflake" end
  return "Búrka", "cloud-storm"
end
local function loadWeather()
  if os.time() - weatherAt < 900 and weather then return end
  local st = noctalia.readFile((noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/noctalia/settings.toml") or ""
  local loc = string.match(st, "%[location%]([^%[]*)") or ""
  local lat = string.match(loc, "latitude%s*=%s*([%d%.%-]+)") or "48.74"
  local lon = string.match(loc, "longitude%s*=%s*([%d%.%-]+)") or "19.15"
  local place = string.match(noctalia.readFile("/var/lib/latteos/greeter/greeter.conf") or "", 'place = "([^"]*)"') or ""
  local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. "&longitude=" .. lon
    .. "&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=4"
  noctalia.runAsync({ "curl", "-s", "-m", "6", url }, function(r)
    local ok, d = pcall(noctalia.json.decode, r.stdout or "")
    if ok and type(d) == "table" and d.current then weather = d; weather.place = place; weatherAt = os.time(); render() end
  end, 8000)
end

local function refresh()
  -- ďalšie časové pásma
  local conf = noctalia.readFile(cfgHome .. "/latteos/clock.conf") or ""
  local zs = string.match(conf, 'zones = "([^"]*)"') or ""
  local list = {}
  for z in string.gmatch(zs, "[^,]+") do table.insert(list, z) end
  if #list > 0 then
    local script = "for z in \"$@\"; do printf '%s|' \"$z\"; TZ=\"$z\" date '+%H:%M|%Y-%m-%d'; done"
    local argv = { "sh", "-c", script, "sh" }
    for _, z in ipairs(list) do table.insert(argv, z) end
    noctalia.runAsync(argv, function(r)
      st.zones = {}
      for z, hm, d in string.gmatch(r.stdout or "", "([^|\n]+)|([^|\n]+)|([^|\n]+)") do table.insert(st.zones, { z = z, hm = hm, d = d }) end
      render()
    end)
  else
    st.zones = {}
  end
  noctalia.runAsync({ "noctalia", "msg", "notification-dnd-status" }, function(r)
    local o = string.lower(r.stdout or ""); st.dnd = string.find(o, "on") ~= nil or string.find(o, "true") ~= nil; render()
  end)
  if noctalia.commandExists("kdeconnect-cli") then
    noctalia.runAsync({ "kdeconnect-cli", "-a", "--name-only" }, function(r) st.phone = trim(r.stdout); render() end)
  else
    st.phone = nil
  end
  loadEvents()
end

local function tabButton(id, label, glyph)
  return ui.button({ text = label, glyph = glyph, selected = st.tab == id, variant = st.tab == id and nil or "ghost", flexGrow = 1,
                     onClick = function() st.tab = id; noctalia.writeFile(tabFile, id); if id == "oznamenia" then C.markSeen() end; render() end })
end
local function heading(t) return ui.label({ text = t, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }) end
local function note(t) return ui.label({ text = t, fontSize = 12, color = "on_surface_variant", maxWidth = 370, maxLines = 4 }) end
local function card(children) return ui.column({ fill = "surface_variant", radius = 14, padding = 12, gap = 6, align = "stretch" }, children) end

-- ── Stopky · Minútka · Budík ────────────────────────────────────────────────
local function saveT() C.saveTimers(st.timers) end
function timersSection()
  st.timers = st.timers or C.loadTimers()
  local tm = st.timers
  local sw, tim = tm.sw, tm.timer
  local out = { ui.separator({}), heading("STOPKY") }
  table.insert(out, ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = C.fmtMs(C.swElapsed(sw), not sw.running), fontSize = 28, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = sw.running and "player-pause" or "player-play", variant = "primary", tooltip = sw.running and "Pozastaviť" or "Štart",
                onClick = function()
                  if sw.running then sw.acc = C.swElapsed(sw); sw.running = false else sw.start = noctalia.nowMs(); sw.running = true end
                  saveT(); render()
                end }),
    ui.button({ glyph = "flag", variant = "ghost", tooltip = "Medzičas", enabled = sw.running,
                onClick = function() table.insert(sw.laps, 1, C.swElapsed(sw)); saveT(); render() end }),
    ui.button({ glyph = "refresh", variant = "ghost", tooltip = "Vynulovať",
                onClick = function() tm.sw = { running = false, start = 0, acc = 0, laps = {} }; saveT(); render() end }),
  }))
  for i, lap in ipairs(sw.laps) do
    if i > 5 then break end
    table.insert(out, ui.row({ gap = 8 }, { ui.label({ text = "medzičas " .. (#sw.laps - i + 1), fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
                                           ui.label({ text = C.fmtMs(lap, true), fontSize = 13 }) }))
  end

  table.insert(out, heading("MINÚTKA"))
  if tim.endMs and tim.endMs > 0 then
    table.insert(out, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = C.fmtMs(tim.endMs - noctalia.nowMs() + 999), fontSize = 28, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "player-pause", variant = "ghost", tooltip = "Pozastaviť",
                  onClick = function() tim.left = tim.endMs - noctalia.nowMs(); tim.endMs = 0; saveT(); render() end }),
      ui.button({ glyph = "x", variant = "ghost", tooltip = "Zrušiť", onClick = function() tim.endMs = 0; tim.left = 0; saveT(); render() end }),
    }))
  else
    local row = {}
    if (tim.left or 0) > 0 then
      table.insert(row, ui.button({ text = "Pokračovať " .. C.fmtMs(tim.left), glyph = "player-play", variant = "primary",
                                    onClick = function() tim.endMs = noctalia.nowMs() + tim.left; tim.left = 0; saveT(); render() end }))
    end
    for _, mins in ipairs({ 1, 5, 10, 25 }) do
      table.insert(row, ui.button({ text = mins .. " min", glyph = "hourglass", variant = "outline", controlSize = "sm",
                                    onClick = function() tim.durMs = mins * 60000; tim.endMs = noctalia.nowMs() + tim.durMs; tim.left = 0; saveT(); render() end }))
    end
    table.insert(out, ui.row({ gap = 6, align = "center" }, row))
    table.insert(out, ui.input({ key = "minutka" .. st.seq, focus = st.seq > 0, placeholder = "Vlastná: 90 (min) alebo 1:30 (min:s) · Enter spustí", onChange = "onTimerIn", onSubmit = "onTimerStart" }))
  end

  table.insert(out, heading("BUDÍK"))
  if #tm.alarms == 0 then table.insert(out, note("Žiadny budík. Zvoní aj pri zatvorenom paneli (oznámenie a zvuk).")) end
  for i, a in ipairs(tm.alarms) do
    table.insert(out, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = a.time, fontSize = 20, fontWeight = "bold", width = 70 }),
      ui.label({ text = (a.label ~= "" and a.label) or (a.once and "raz" or "každý deň"), fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.toggle({ checked = a.on == true, onChange = "onAlarm" .. i }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Odstrániť",
                  onClick = function() table.remove(tm.alarms, i); saveT(); render() end }),
    }))
  end
  table.insert(out, ui.input({ key = "budik" .. st.seq, focus = st.seq > 0, placeholder = "Nový budík: 07:00 alebo 07:00 Vstávať · Enter pridá", onChange = "onAlarmIn", onSubmit = "onAlarmAdd" }))
  return out
end
local function setAlarm(i, v) local a = st.timers and st.timers.alarms[i]; if a then a.on = v == "true"; a.last = ""; saveT() end end
function onAlarm1(v) setAlarm(1, v) end
function onAlarm2(v) setAlarm(2, v) end
function onAlarm3(v) setAlarm(3, v) end
function onAlarm4(v) setAlarm(4, v) end
function onAlarm5(v) setAlarm(5, v) end
function onAlarm6(v) setAlarm(6, v) end
function onAlarm7(v) setAlarm(7, v) end
function onAlarm8(v) setAlarm(8, v) end
function onAlarm9(v) setAlarm(9, v) end
function onAlarm10(v) setAlarm(10, v) end
function onTimerIn(t) st.timerIn = t or "" end
function onTimerStart(_t)
  local v = C.trim(st.timerIn)
  local m, sec = string.match(v, "^(%d+):(%d%d)$")
  local ms = m and ((tonumber(m) * 60 + tonumber(sec)) * 1000) or ((tonumber(v) or 0) * 60000)
  if ms <= 0 then noctalia.notifyError("Minútka", "Zadaj minúty (90) alebo min:s (1:30)"); return end
  st.timers.timer.durMs = ms; st.timers.timer.endMs = noctalia.nowMs() + ms; st.timers.timer.left = 0
  st.timerIn = ""; st.seq = st.seq + 1
  saveT(); render()
end
function onAlarmIn(t) st.alarmIn = t or "" end
function onAlarmAdd(_t)
  local h, mi, label = string.match(C.trim(st.alarmIn), "^(%d%d?):(%d%d)%s*(.*)$")
  if not h or tonumber(h) > 23 or tonumber(mi) > 59 then noctalia.notifyError("Budík", "Čas v tvare 07:00"); return end
  if #st.timers.alarms >= 10 then noctalia.notifyError("Budík", "Najviac 10 budíkov"); return end
  table.insert(st.timers.alarms, { time = string.format("%02d:%02d", tonumber(h), tonumber(mi)), label = label or "", on = true, last = "" })
  table.sort(st.timers.alarms, function(a, b) return a.time < b.time end)
  st.alarmIn = ""; st.seq = st.seq + 1
  saveT(); render()
end

-- ── Čas ──────────────────────────────────────────────────────────────────────
local function tabTime()
  local t = os.date("*t")
  local body = {
    ui.label({ text = string.format("%02d:%02d", t.hour, t.min), fontSize = 54, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = string.format("%s %d. %s %d", longDays[t.wday], t.day, monthsGen[t.month], t.year), fontSize = 15, color = "on_surface" }),
    ui.label({ text = "týždeň " .. isoWeek(t) .. " · " .. t.yday .. ". deň v roku", fontSize = 12, color = "on_surface_variant" }),
    ui.separator({}),
    heading("ČASOVÉ PÁSMA"),
  }
  local todayIso = iso(t.year, t.month, t.day)
  if #st.zones == 0 then
    table.insert(body, note("Pridaj mestá v Nastaveniach (Systém › Dátum, čas a poloha) a uvidíš tu ich čas."))
  end
  for _, z in ipairs(st.zones) do
    local diff = (z.d > todayIso) and "zajtra" or ((z.d < todayIso) and "včera" or "dnes")
    table.insert(body, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = zoneNames[z.z] or z.z, fontSize = 14, flexGrow = 1 }),
      ui.label({ text = diff, fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = z.hm, fontSize = 18, fontWeight = "bold" }),
    }))
  end
  -- stopky, minútka, budík
  for _, n in ipairs(timersSection()) do table.insert(body, n) end
  -- počasie
  table.insert(body, ui.separator({}))
  table.insert(body, heading("POČASIE" .. ((weather and weather.place ~= "") and (" · " .. weather.place) or "")))
  if weather and weather.current then
    local txt, g = wmo(weather.current.weather_code)
    table.insert(body, ui.row({ gap = 12, align = "center" }, {
      ui.glyph({ name = g, size = 34, color = "primary" }),
      ui.label({ text = string.format("%d °C", math.floor(weather.current.temperature_2m + 0.5)), fontSize = 26, fontWeight = "bold" }),
      ui.label({ text = txt .. " · vietor " .. math.floor(weather.current.wind_speed_10m + 0.5) .. " km/h", fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
    }))
    local days = { "ne", "po", "ut", "st", "št", "pi", "so" }
    local row = {}
    for i = 2, math.min(4, #(weather.daily.time or {})) do
      local y, mo, dd = string.match(weather.daily.time[i], "(%d+)-(%d+)-(%d+)")
      local wd = os.date("*t", os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(dd), hour = 12 })).wday
      local _, dg = wmo(weather.daily.weather_code[i])
      table.insert(row, ui.column({ fill = "surface_variant", radius = 12, padding = 10, gap = 2, flexGrow = 1, align = "center" }, {
        ui.label({ text = days[wd], fontSize = 12, color = "on_surface_variant" }),
        ui.glyph({ name = dg, size = 20, color = "primary" }),
        ui.label({ text = math.floor(weather.daily.temperature_2m_min[i] + 0.5) .. "° / " .. math.floor(weather.daily.temperature_2m_max[i] + 0.5) .. "°", fontSize = 12 }),
      }))
    end
    table.insert(body, ui.row({ gap = 8 }, row))
  else
    table.insert(body, note("Počasie sa načítava… (potrebuje internet)"))
  end
  table.insert(body, ui.button({ text = "Upraviť pásma a polohu", glyph = "settings", variant = "ghost", contentAlign = "start",
                                 onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "nastavenia", "cas" }) end }))
  return body
end

-- ── Oznámenia ────────────────────────────────────────────────────────────────
local function tabNotifications()
  local body = {
    ui.row({ align = "center", gap = 10 }, {
      ui.toggle({ checked = st.dnd, onChange = "onDnd" }),
      ui.label({ text = "Nerušiť", fontSize = 14, flexGrow = 1 }),
    }),
    ui.button({ text = "Vymazať históriu", glyph = "trash", variant = "ghost", contentAlign = "start",
                onClick = function() noctalia.runAsync({ "noctalia", "msg", "notification-clear-history" }, function() render() end); noctalia.notify("Oznámenia", "História vymazaná") end }),
    ui.separator({}),
  }
  local list = C.notifications()
  if #list == 0 then table.insert(body, note("Žiadne oznámenia.")) end
  local now = noctalia.nowMs()
  for i, n in ipairs(list) do
    if i > 30 then break end
    local ago = (now - n.at) // 60000
    local when = ago < 1 and "teraz" or (ago < 60 and ("pred " .. ago .. " min") or os.date("%d. %m. %H:%M", n.at // 1000))
    table.insert(body, card({
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = n.app ~= "" and n.app or "Systém", fontSize = 11, color = "primary", flexGrow = 1 }),
        ui.label({ text = when, fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.label({ text = n.summary, fontSize = 13, fontWeight = "bold", maxWidth = 370, maxLines = 2 }),
      n.body ~= "" and note(n.body) or nil,
    }))
  end
  table.insert(body, ui.separator({}))
  table.insert(body, heading("OZNÁMENIA Z MOBILU"))
  if st.phone == nil then
    table.insert(body, card({
      ui.label({ text = "KDE Connect nie je nainštalovaný", fontSize = 13, fontWeight = "bold" }),
      note("Android: aplikácia KDE Connect → oznámenia, SMS, schránka a súbory na PC. iPhone: KDE Connect pre iOS (Apple obmedzuje oznámenia)."),
      ui.button({ text = "Nainštalovať (dnf install kde-connect)", glyph = "download", variant = "ghost", contentAlign = "start",
                  onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "instalator", "--nazov=KDE_Connect", "install", "kde-connect" }) end }),
    }))
  elseif st.phone == "" then
    table.insert(body, card({ ui.label({ text = "Žiadny spárovaný mobil", fontSize = 13, fontWeight = "bold" }),
                              note("Otvor KDE Connect v mobile a spáruj ho s týmto PC (rovnaká sieť).") }))
  else
    table.insert(body, card({ ui.label({ text = "Pripojené: " .. st.phone, fontSize = 13, fontWeight = "bold" }),
                              note("Oznámenia z mobilu prichádzajú ako bežné oznámenia LatteOS.") }))
  end
  return body
end

-- ── Kalendár ─────────────────────────────────────────────────────────────────
local function tabCalendar()
  local ty, tm, td = today()
  local y, m = st.ym and st.ym[1] or ty, st.ym and st.ym[2] or tm
  st.sel = st.sel or iso(ty, tm, td)
  local first = os.date("*t", os.time({ year = y, month = m, day = 1, hour = 12 }))
  local lead = (first.wday + 5) % 7          -- pondelok = prvý deň týždňa
  local n = daysIn(y, m)

  local body = {
    ui.row({ align = "center", gap = 4 }, {
      ui.button({ glyph = "chevron-left", variant = "ghost", onClick = function() m = m - 1; if m < 1 then m = 12; y = y - 1 end; st.ym = { y, m }; render() end }),
      ui.label({ text = months[m] .. " " .. y, fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ text = "Dnes", variant = "ghost", onClick = function() st.ym = nil; st.sel = iso(ty, tm, td); render() end }),
      ui.button({ glyph = "chevron-right", variant = "ghost", onClick = function() m = m + 1; if m > 12 then m = 1; y = y + 1 end; st.ym = { y, m }; render() end }),
    }),
  }
  local head = {}
  for _, d in ipairs({ "po", "ut", "st", "št", "pi", "so", "ne" }) do
    table.insert(head, ui.button({ text = d, width = 46, controlSize = "sm", variant = "ghost", enabled = false }))
  end
  table.insert(body, ui.row({ gap = 4 }, head))
  local day = 1 - lead
  for _ = 1, 6 do
    if day > n then break end
    local row = {}
    for _ = 1, 7 do
      if day >= 1 and day <= n then
        local date = iso(y, m, day)
        local isToday = (y == ty and m == tm and day == td)
        local busy = #eventsOn(date) > 0          -- deň s udalosťou: iný štýl tlačidla (nie iba farba: aj výplň)
        table.insert(row, ui.button({ text = tostring(day), width = 46, controlSize = "sm",
                                      tooltip = busy and (#eventsOn(date) .. " udalosť(i)") or nil,
                                      variant = (st.sel == date) and "primary" or (isToday and "outline" or (busy and "secondary" or "ghost")),
                                      onClick = function() st.sel = date; render() end }))
      else
        table.insert(row, ui.spacer({ width = 46 }))
      end
      day = day + 1
    end
    table.insert(body, ui.row({ gap = 4 }, row))
  end

  -- plánovač vybraného dňa
  local sy, sm, sd = string.match(st.sel, "(%d+)-(%d+)-(%d+)")
  table.insert(body, ui.separator({}))
  table.insert(body, heading(string.upper(string.format("%d. %s", tonumber(sd), monthsGen[tonumber(sm)]))))
  local list = eventsOn(st.sel)
  if #list == 0 then table.insert(body, note("Žiadne udalosti.")) end
  for _, it in ipairs(list) do
    table.insert(body, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = (it.e.time and it.e.time ~= "") and it.e.time or "celý deň", fontSize = 12, color = "primary", width = 64 }),
      ui.label({ text = it.e.title, fontSize = 13, flexGrow = 1, maxWidth = 250, maxLines = 2 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Odstrániť",
                  onClick = function() table.remove(st.events, it.i); saveEvents(); render() end }),
    }))
  end
  table.insert(body, ui.row({ gap = 6, align = "center" }, {
    ui.input({ placeholder = "14:00", width = 70, onChange = "onNewTime", onSubmit = "onAdd" }),
    ui.input({ key = "udalost" .. st.seq, focus = st.seq > 0, placeholder = "Nová udalosť… (Enter pridá)", flexGrow = 1, onChange = "onNewTitle", onSubmit = "onAdd" }),
  }))

  -- úlohy (to-do): počet nesplnených je na lište pri dátume
  table.insert(body, ui.separator({}))
  table.insert(body, heading("ÚLOHY"))
  local open, done = {}, {}
  for i, t in ipairs(st.todos) do table.insert(t.done and done or open, { i = i, t = t }) end
  if #st.todos == 0 then table.insert(body, note("Žiadne úlohy. Nesplnené úlohy uvidíš na lište pri dátume.")) end
  for _, group in ipairs({ open, done }) do
    for _, it in ipairs(group) do
      table.insert(body, ui.row({ align = "center", gap = 8 }, {
        ui.button({ glyph = it.t.done and "square-check" or "square", variant = "ghost", controlSize = "sm", tooltip = it.t.done and "Znovu otvoriť" or "Hotovo",
                    onClick = function() it.t.done = not it.t.done; C.saveTodos(st.todos); render() end }),
        ui.label({ text = it.t.title, fontSize = 13, flexGrow = 1, maxWidth = 250, maxLines = 2, color = it.t.done and "on_surface_variant" or "on_surface" }),
        (it.t.date and it.t.date ~= "") and ui.label({ text = it.t.date == C.todayIso() and "dnes" or string.sub(it.t.date, 9, 10) .. ". " .. tonumber(string.sub(it.t.date, 6, 7)) .. ".", fontSize = 11, color = "primary" }) or ui.spacer({ width = 0 }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Odstrániť",
                    onClick = function() table.remove(st.todos, it.i); C.saveTodos(st.todos); render() end }),
      }))
    end
  end
  table.insert(body, ui.input({ key = "todo" .. st.seq, focus = st.seq > 0, placeholder = "Nová úloha… (Enter pridá, na vybraný deň: začni „!“)", onChange = "onNewTodo", onSubmit = "onTodoAdd" }))

  table.insert(body, ui.separator({}))
  table.insert(body, heading("ÚČTY KALENDÁROV"))
  table.insert(body, note("Google Kalendár, Apple iCloud, Nextcloud/CalDAV a odkazy ICS (Outlook, Proton, Todoist, TickTick, Microsoft To Do) sa pripájajú v kalendári Noctalie; ich udalosti uvidíš tam."))
  table.insert(body, ui.button({ text = "Otvoriť kalendár a účty", glyph = "calendar", contentAlign = "start",
                                 onClick = function() panel.close(); noctalia.runAsync({ "noctalia", "msg", "panel-open", "control-center", "calendar" }) end }))
  return body
end

local function live()
  local tm = st.timers
  return st.tab == "cas" and tm ~= nil and (tm.sw.running or (tm.timer.endMs or 0) > 0)
end

function render()
  panel.setWantsSecondTicks(live())
  local content = st.tab == "oznamenia" and tabNotifications() or (st.tab == "kalendar" and tabCalendar() or tabTime())
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ gap = 6, align = "center" }, {
      tabButton("cas", "Čas", "clock"),
      tabButton("oznamenia", "Oznámenia", "bell"),
      tabButton("kalendar", "Kalendár", "calendar"),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.scroll({ flexGrow = 1, gap = 10, align = "stretch" }, content),
  }))
end

function onNewTodo(t) st.newTodo = t or "" end
function onTodoAdd(_t)
  local title = C.trim(st.newTodo)
  local dated = string.sub(title, 1, 1) == "!"
  if dated then title = C.trim(string.sub(title, 2)) end
  if title == "" then return end
  table.insert(st.todos, { title = title, done = false, date = dated and st.sel or "" })
  C.saveTodos(st.todos)
  st.newTodo = ""; st.seq = st.seq + 1
  render()
end

-- stopky a minútka v paneli bežia naživo (tik panelu raz za sekundu, iba keď niečo beží)
function update()
  if not live() then panel.setWantsSecondTicks(false); return end
  local fresh = C.loadTimers()               -- hodiny na lište mohli minútku medzitým ukončiť
  if (fresh.timer.endMs or 0) == 0 then st.timers.timer.endMs = 0 end
  render()
end

function onDnd(value)
  st.dnd = value == "true"
  noctalia.runAsync({ "noctalia", "msg", "notification-dnd-set", st.dnd and "on" or "off" }, function() refresh() end)
end
function onNewTitle(t) st.newTitle = t or "" end
function onNewTime(t) st.newTime = t or "" end
function onAdd(_t)
  local title = trim(st.newTitle)
  if title == "" then return end
  local time = trim(st.newTime)
  if time ~= "" and not string.match(time, "^%d%d?:%d%d$") then noctalia.notifyError("Kalendár", "Čas v tvare 14:00"); return end
  if string.match(time, "^%d:%d%d$") then time = "0" .. time end
  table.insert(st.events, { date = st.sel, time = time, title = title })
  saveEvents()
  st.newTitle = ""; st.seq = st.seq + 1
  render()
end

function onOpen(ctx)
  loadWeather()
  local saved = trim(noctalia.readFile(tabFile) or "")
  if saved == "cas" or saved == "oznamenia" or saved == "kalendar" then st.tab = saved end
  -- Win+N = oznámenia, Win+Alt+D = kalendár (panel-toggle latteos/time:panel <záložka>)
  local want = type(ctx) == "string" and trim(ctx) or ""
  if want == "cas" or want == "oznamenia" or want == "kalendar" then st.tab = want end
  loadEvents()
  st.todos = C.loadTodos()
  st.timers = C.loadTimers()
  if st.tab == "oznamenia" then C.markSeen() end
  render()
  refresh()
end
