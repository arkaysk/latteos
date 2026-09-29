--!nonstrict
-- Text Bar na lište (zadanie 24. 9., bod 5): široký riadok s textom, ikona režimu na okraji, režim sa mení
-- kolieskom alebo šípkami ‹ ›, klik na text otvorí spúšťač v tom režime, pravý klik = rýchle nastavenia.
-- Pri „Bez AI“ (ai.toml provider = "ziadna") režim AI zmizne.
local home = noctalia.getenv("HOME") or ""
local cfg = (noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/latteos"
local all = {
  { id = "local", glyph = "search",     name = "Lokálne",      prefix = "",       hint = "Hľadaj aplikáciu, nastavenie, súbor…" },
  { id = "web",   glyph = "world",      name = "Web",          prefix = "/web ",  hint = "Hľadať na webe…" },
  { id = "ai",    glyph = "sparkles",   name = "AI",           prefix = "/ai ",   hint = "Opýtaj sa AI…" },
  { id = "cmd",   glyph = "terminal-2", name = "Linux príkaz", prefix = "/cmd ",  hint = "Spusti príkaz…" },
}
local modeFile = noctalia.pluginDataDir() .. "/mode"
local modes, index = all, 1

local function aiOff()
  return string.find(noctalia.readFile(cfg .. "/ai.toml") or "", 'provider%s*=%s*"ziadna"') ~= nil
end

local function load()
  modes = {}
  local off = aiOff()
  for _, m in ipairs(all) do if not (off and m.id == "ai") then table.insert(modes, m) end end
  local saved = noctalia.readFile(modeFile) or ""
  index = 1
  for i, m in ipairs(modes) do if string.find(saved, m.id, 1, true) then index = i end end
end

-- spúšťač sa otvorí z ostrova vyhľadávania (fork latte-shell: tvar L; kontext = predpona režimu)
local function open()
  noctalia.togglePanel("launcher", modes[index].prefix)
end

-- šírka hľadania (zadanie 25. 9.): kým je miesto, 400 px a ostrov sa s pribúdajúcimi oknami posúva doprava
-- (je v ľavej časti lišty hneď za oknami); od ~8 okien sa zužuje o 34 px na okno, najviac na polovicu
local render
local windows = 0
local function barWidth()
  return math.max(200, 400 - math.max(0, windows - 8) * 34)
end
local lastCount = -1
local function countWindows()
  noctalia.runAsync({ "sh", "-c", "hyprctl -j clients 2>/dev/null | grep -c '\"mapped\": true'" }, function(r)
    local n = tonumber(string.match(r.stdout or "", "%d+") or "0") or 0
    if n ~= lastCount then lastCount = n; windows = n; render() end
  end)
end

local function setMode(i)
  index = ((i - 1) % #modes) + 1
  noctalia.writeFile(modeFile, modes[index].id)
  render()
end

render = function()
  local m = modes[index]
  local dots = {}
  for i = 1, #modes do
    table.insert(dots, ui.box({ width = i == index and 10 or 5, height = 5, radius = 3, fill = i == index and "primary" or "on_surface/0.25" }))
  end
  barWidget.render(ui.row({ width = barWidth(), height = 34, gap = 4, align = "center" }, {
    ui.button({ glyph = m.glyph, variant = "ghost", controlSize = "sm", tooltip = "Režim: " .. m.name .. " · koliesko alebo ‹ › mení",
                onClick = function() setMode(index + 1) end }),
    ui.row({ flexGrow = 1, height = 34, align = "center", gap = 8, onClick = open, tooltip = "Klik: " .. m.name .. " · pravý klik: rýchle nastavenia" }, {
      ui.label({ text = m.hint, fontSize = 13, color = "on_surface_variant", maxWidth = 250, maxLines = 1 }),
    }),
    ui.row({ gap = 3, align = "center" }, dots),
    ui.button({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", tooltip = "Predošlý režim", onClick = function() setMode(index - 1) end }),
    ui.button({ glyph = "chevron-right", variant = "ghost", controlSize = "sm", tooltip = "Ďalší režim", onClick = function() setMode(index + 1) end }),
  }))
end

-- počet okien pri otvorení/zatvorení okna (latte-hypr-udalosti), update() je záloha každých 20 s
-- (optimalizácia 26. 9.: predtým sh + hyprctl + grep každé 2 s)
local streaming = false
function update()
  noctalia.setUpdateInterval(20000)          -- „Bez AI“ z Nastavení a záloha počtu okien
  if not streaming then
    streaming = true
    noctalia.runStream("latte-hypr-udalosti openwindow closewindow movewindowv2", function(_line) countWindows() end)
  end
  load()
  countWindows()
  render()
end

function onRightClick() noctalia.togglePanel("latteos/textbar:rychle") end

function onScroll(_axis, steps)
  setMode(index + ((steps or 0) > 0 and 1 or -1))
end
