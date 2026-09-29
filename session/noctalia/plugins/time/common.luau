--!nonstrict
-- spoločné pre widgety (hodiny, zvonček, dátum) a panel: úlohy, časovače, neprečítané oznámenia
local M = {}

local home = noctalia.getenv("HOME") or ""
M.dataHome = noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
M.stateHome = noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
M.eventsFile = M.dataHome .. "/latteos/events.json"
M.todoFile = M.dataHome .. "/latteos/todo.json"
M.timersFile = M.dataHome .. "/latteos/casovace.json"
M.tabFile = noctalia.pluginDataDir() .. "/panel-tab"
M.seenFile = noctalia.pluginDataDir() .. "/oznamenia-videne"
M.historyFile = M.stateHome .. "/noctalia/notification_history.json"
M.days = { "ne", "po", "ut", "st", "št", "pi", "so" }

function M.trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
function M.iso(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end
function M.todayIso() local t = os.date("*t"); return M.iso(t.year, t.month, t.day) end

local function readJson(path, default)
  local raw = noctalia.readFile(path)
  if not raw or raw == "" then return default end
  local ok, v = pcall(noctalia.json.decode, raw)
  return (ok and type(v) == "table") and v or default
end
local function writeJson(path, v)
  noctalia.mkdirAll(M.dataHome .. "/latteos")
  noctalia.writeFile(path, noctalia.json.encode(v))
end
M.readJson = readJson

-- udalosti plánovača a úlohy (to-do)
function M.loadEvents() return readJson(M.eventsFile, {}) end
function M.loadTodos() return readJson(M.todoFile, {}) end
function M.saveTodos(list) writeJson(M.todoFile, list) end

-- počet na lište pri dátume: nesplnené úlohy (bez termínu alebo do dnes) + dnešné udalosti, ktoré ešte len budú
function M.openCount()
  local today, now = M.todayIso(), os.date("%H:%M")
  local n = 0
  for _, t in ipairs(M.loadTodos()) do
    if not t.done and (not t.date or t.date == "" or t.date <= today) then n = n + 1 end
  end
  for _, e in ipairs(M.loadEvents()) do
    if e.date == today and (not e.time or e.time == "" or e.time >= now) then n = n + 1 end
  end
  return n
end

-- časovače: stopky, minútka, budíky (spoločný súbor, odpočet a zvonenie strážia hodiny na lište)
function M.loadTimers()
  local t = readJson(M.timersFile, {})
  t.sw = t.sw or { running = false, start = 0, acc = 0, laps = {} }
  t.sw.laps = t.sw.laps or {}
  t.timer = t.timer or { endMs = 0, durMs = 5 * 60000, left = 0 }
  t.alarms = t.alarms or {}
  return t
end
function M.saveTimers(t) writeJson(M.timersFile, t) end
function M.swElapsed(sw) return (sw.acc or 0) + ((sw.running and sw.start > 0) and (noctalia.nowMs() - sw.start) or 0) end
function M.fmtMs(ms, tenths)
  ms = math.max(0, math.floor(ms))
  local s = ms // 1000
  local h, m, sec = s // 3600, (s // 60) % 60, s % 60
  local out = h > 0 and string.format("%d:%02d:%02d", h, m, sec) or string.format("%02d:%02d", m, sec)
  if tenths then out = out .. "," .. tostring((ms // 100) % 10) end
  return out
end
function M.ring(title, body)
  noctalia.notify(title, body)
  noctalia.runAsync({ "sh", "-c", "for i in 1 2 3; do paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || canberra-gtk-play -i alarm-clock-elapsed 2>/dev/null; done" }, nil, 30000)
end

-- oznámenia: história Noctalie; nové = Noctalia ich ešte neoznačila za videné a prišli po poslednom otvorení zvončeka
function M.notifications()
  local h = readJson(M.historyFile, {})
  local out = {}
  for _, e in ipairs(h.entries or {}) do
    local n = e.notification or {}
    table.insert(out, { app = n.app_name or "", summary = n.summary or "", body = n.body or "", at = n.received_wall_ms or 0, seen = e.seen == true })
  end
  table.sort(out, function(a, b) return a.at > b.at end)
  return out
end
function M.unread()
  local seen = tonumber(M.trim(noctalia.readFile(M.seenFile) or "")) or 0
  local n = 0
  for _, e in ipairs(M.notifications()) do if e.at > seen and not e.seen then n = n + 1 end end
  return n
end
function M.markSeen() noctalia.writeFile(M.seenFile, tostring(noctalia.nowMs())) end

function M.open(tab)
  noctalia.writeFile(M.tabFile, tab)
  noctalia.togglePanel("latteos/time:panel")
end

return M
