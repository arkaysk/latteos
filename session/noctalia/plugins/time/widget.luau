--!nonstrict
-- Hodiny na lište („07:33“). Klik = panel Čas (pásma, stopky, budík, minútka, počasie).
-- Hodiny strážia aj pripomenutia plánovača, budíky a minútku (zvonia, aj keď je panel zatvorený);
-- keď beží stopky alebo minútka, ukazujú ich priebeh vedľa času.
local C = require("./common.luau")
local reminded = {}      -- pripomenuté udalosti v tomto behu (dátum|čas|názov)

local function remind(t)
  local date, hm = C.iso(t.year, t.month, t.day), string.format("%02d:%02d", t.hour, t.min)
  for _, e in ipairs(C.loadEvents()) do
    local key = (e.date or "") .. "|" .. (e.time or "") .. "|" .. (e.title or "")
    if e.date == date and e.time == hm and not reminded[key] then
      reminded[key] = true
      noctalia.notify("Kalendár · " .. hm, e.title or "")
    end
  end
end

function update()
  local t = os.date("*t")
  local hm = string.format("%02d:%02d", t.hour, t.min)
  local tm = C.loadTimers()
  local changed, extra = false, ""
  -- minútka
  if tm.timer.endMs and tm.timer.endMs > 0 then
    local left = tm.timer.endMs - noctalia.nowMs()
    if left <= 0 then
      tm.timer.endMs = 0; changed = true
      C.ring("Minútka", "Čas vypršal (" .. C.fmtMs(tm.timer.durMs) .. ")")
    else
      extra = "  ⏳ " .. C.fmtMs(left + 999)
    end
  end
  if tm.sw.running then extra = extra .. "  ⏱ " .. C.fmtMs(C.swElapsed(tm.sw)) end
  -- budíky
  local today = C.todayIso()
  for _, a in ipairs(tm.alarms) do
    if a.on and a.time == hm and a.last ~= today then
      a.last = today; changed = true
      C.ring("Budík · " .. hm, (a.label and a.label ~= "") and a.label or "Budík LatteOS")
      if a.once then a.on = false end
    end
  end
  if changed then C.saveTimers(tm) end
  noctalia.setUpdateInterval(extra ~= "" and 1000 or 5000)
  -- výraznejšie hodiny (zadanie 25. 9.): hrubé písmo vo farbe akcentu, minútka/stopky tlmene za nimi
  barWidget.render(ui.row({ gap = 4, align = "center", height = 30 }, {
    ui.label({ text = hm, fontSize = 15, fontWeight = "bold", color = "primary" }),
    extra ~= "" and ui.label({ text = extra, fontSize = 12, color = "on_surface_variant" }) or nil,
  }))
  barWidget.setTooltip({ { "Klik", "časové pásma, stopky, budík, minútka" } })
  remind(t)
end

function onClick() C.open("cas") end
function onRightClick() C.open("cas") end
