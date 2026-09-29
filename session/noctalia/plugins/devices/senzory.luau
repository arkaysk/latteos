--!nonstrict
-- Senzory na lište (Monitor › Senzory › pravý klik › Pridať na lištu): hodnoty vybraných senzorov
-- vedľa seba, napr. „12 % · 2591 MHz · 45 °C“. Bez výberu je neviditeľný. Klik = Monitor › Senzory.
-- Voľby: ~/.config/latteos/senzory.json { tray: [id], names: { id: názov } }. Obnova raz za 3 s.
local home = noctalia.getenv("HOME") or ""
local cfg = (noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/latteos/senzory.json"

local function trayIds()
  local txt = noctalia.readFile(cfg) or ""
  local block = string.match(txt, '"tray"%s*:%s*%[(.-)%]') or ""
  local ids = {}
  for id in string.gmatch(block, '"([^"]+)"') do table.insert(ids, id) end
  return ids
end

local function fmt(v, unit)
  if unit == "V" then return string.format("%.2f V", v) end
  if unit == "MHz" or unit == "MB" or unit == "ot/min" or math.abs(v) >= 100 then return string.format("%d %s", math.floor(v + 0.5), unit) end
  return (string.gsub(string.format("%.1f", v), "%.", ",")) .. (unit ~= "" and (" " .. unit) or "")
end

function update()
  noctalia.setUpdateInterval(3000)
  local ids = trayIds()
  if #ids == 0 then barWidget.setVisible(false); noctalia.setUpdateInterval(15000); return end
  noctalia.runAsync({ "latte-sysmon", "senzory" }, function(r)
    local out = r.stdout or ""
    local parts, tips = {}, {}
    for _, id in ipairs(ids) do
      local esc = string.gsub(id, "([%.%-%+%%])", "%%%1")
      local label, value, unit = string.match(out, '"id": "' .. esc .. '", "label": "([^"]*)", "value": ([%-%d%.]+), "unit": "([^"]*)"')
      if value then
        table.insert(parts, fmt(tonumber(value), unit))
        table.insert(tips, label .. ": " .. fmt(tonumber(value), unit))
      end
    end
    if #parts == 0 then barWidget.setVisible(false); return end
    barWidget.setVisible(true)
    barWidget.render(ui.row({ height = 26, gap = 6, align = "center", paddingH = 8, radius = 13, fill = "primary/0.08",
                              tooltip = table.concat(tips, "\n") .. "\nklik: Monitor › Senzory" },
      { ui.glyph({ name = "activity", size = 14, color = "primary" }),
        ui.label({ text = table.concat(parts, " · "), fontSize = 12, fontWeight = "bold", color = "on_surface" }) }))
  end)
end

function onClick() noctalia.runAsync({ "latte-app", "monitor", "senzory" }) end
