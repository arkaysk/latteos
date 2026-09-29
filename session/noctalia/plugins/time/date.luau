--!nonstrict
-- Dátum na lište s počtom otvorených úloh a dnešných udalostí: „št 24. 9. (3)“. Klik = Kalendár a úlohy.
local C = require("./common.luau")
local longDays = { "nedeľa", "pondelok", "utorok", "streda", "štvrtok", "piatok", "sobota" }
local months = { "januára", "februára", "marca", "apríla", "mája", "júna", "júla", "augusta", "septembra", "októbra", "novembra", "decembra" }

function update()
  noctalia.setUpdateInterval(10000)
  local t = os.date("*t")
  local n = C.openCount()
  barWidget.setText(string.format("%s %d. %d.", C.days[t.wday], t.day, t.month) .. (n > 0 and (" (" .. n .. ")") or ""))
  barWidget.setTooltip({ { "Dnes", string.format("%s %d. %s %d", longDays[t.wday], t.day, months[t.month], t.year) },
                         { "Úlohy a udalosti", n > 0 and tostring(n) or "nič otvorené" },
                         { "Klik", "kalendár a úlohy" } })
end

function onClick() C.open("kalendar") end
function onRightClick() C.open("kalendar") end
