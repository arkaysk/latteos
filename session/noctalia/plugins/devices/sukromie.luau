--!nonstrict
-- Indikátor súkromia na lište: kým niektorá aplikácia používa mikrofón alebo kameru, v ostrove zariadení
-- svieti červená kapsula s ikonou (ako bodka v iOS/Androide). Inak je neviditeľný. Klik = Monitor › Procesy.
-- Zdroj: latte-sysmon sukromie (otvorené /dev zariadenia a streamy PipeWire), raz za 3 s.
local mic, cam = {}, {}

local function render()
  if #mic == 0 and #cam == 0 then barWidget.setVisible(false); return end
  barWidget.setVisible(true)
  local kids = {}
  if #cam > 0 then table.insert(kids, ui.glyph({ name = "camera", size = 15, color = "on_primary" })) end
  if #mic > 0 then table.insert(kids, ui.glyph({ name = "microphone", size = 15, color = "on_primary" })) end
  local tip = {}
  if #cam > 0 then table.insert(tip, "Kamera: " .. table.concat(cam, ", ")) end
  if #mic > 0 then table.insert(tip, "Mikrofón: " .. table.concat(mic, ", ")) end
  barWidget.render(ui.row({ height = 26, gap = 3, align = "center", justify = "center", paddingH = 8, radius = 13,
                            fill = "error", tooltip = table.concat(tip, " · ") .. " · klik: Monitor" }, kids))
end

function update()
  noctalia.setUpdateInterval(3000)
  noctalia.runAsync({ "latte-sukromie" }, function(r)
    mic, cam = {}, {}
    for kind, who in string.gmatch(r.stdout or "", "(%a+)\t([^\n]+)") do
      table.insert(kind == "camera" and cam or mic, who)
    end
    render()
  end)
end

function onClick() noctalia.runAsync({ "latte-app", "monitor", "procesy" }) end
