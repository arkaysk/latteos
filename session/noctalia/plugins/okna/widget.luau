--!nonstrict
-- Ovál okien: ikona režimu + ikony okien (aktívne zvýraznené, minimalizované tlmené).
local C = require("./common.luau")
local home = noctalia.getenv("HOME") or ""
local stateDir = (noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/latteos"
local wins, activeAddr, hovered = {}, "", nil
local modes = { paska = { "layout-columns", "Páska" }, dlazdice = { "layout-grid", "Dlaždice" }, plavajuce = { "app-window", "Plávajúce" } }

local function mode()
  local m = string.match(noctalia.readFile(stateDir .. "/window-mode") or "", "%a+") or "paska"
  return modes[m] and m or "paska"
end

local quietUntil = 0      -- po pravom kliku (ponuka okna) chvíľu bez náhľadu
local function setHover(addr)
  hovered = addr
  if addr and noctalia.nowMs() < quietUntil then return end
  noctalia.mkdirAll(C.stateDir)
  noctalia.writeFile(C.hoverFile, addr or "")
end

local function render()
  local m = mode()
  local kids = {
    -- prepínač režimu okien nevyzerá ako okno (zadanie 25. 9.): menší štvorec s rámikom, šípka a oddeľovač od okien
    ui.row({ height = 24, paddingH = 5, gap = 2, radius = 7, align = "center", justify = "center", fill = "surface/0.6",
             border = "outline", borderWidth = 1,
             tooltip = "Režim okien: " .. modes[m][2] .. " · klik: ďalší (Super+W)",
             onClick = function() C.eval('require("latte.windows").cycle()') end },
           { ui.glyph({ name = modes[m][1], size = 13, color = "on_surface_variant" }),
             ui.glyph({ name = "chevron-right", size = 10, color = "on_surface_variant" }) }),
    ui.box({ width = 1, height = 20, fill = "outline" }),
    ui.spacer({ width = 3 }),
  }
  for _, w in ipairs(wins) do
    local addr, min = w.address, C.isMin(w)
    local icon = C.icon(w)
    local active = addr == activeAddr
    local inner = icon and ui.image({ path = icon, width = 20, height = 20, fit = "contain" })
                  or ui.glyph({ name = C.glyph(w) or "app-window", size = 17, color = C.glyph(w) and "primary" or "on_surface" })
    table.insert(kids, ui.row({
      key = addr, width = 32, height = 28, radius = 10, align = "center", justify = "center",
      fill = active and "primary/0.30" or (hovered == addr and "on_surface/0.10" or "surface_variant/0"),
      border = active and "primary" or "surface_variant/0", borderWidth = 1,
      opacity = min and 0.45 or 1.0,
      tooltip = C.name(w) .. (min and " · minimalizované" or ""),
      -- ako panel úloh Windows: klik na aktívne okno ho minimalizuje, inak ho prenesie dopredu
      onClick = function()
        if active and not min then C.eval('latte.win.minimize_addr("' .. addr .. '")')
        else C.eval('latte.win.activate("' .. addr .. '")') end
      end,
      onHover = function(state) if state == "true" then setHover(addr) elseif hovered == addr then setHover(nil) end end,
    }, { inner }))
  end
  if #wins == 0 then
    table.insert(kids, ui.label({ text = "žiadne okná", fontSize = 11, color = "on_surface_variant" }))
  end
  barWidget.render(ui.row({ gap = 3, align = "center", paddingH = 4, height = 32, radius = 16, fill = "surface_variant" }, kids))
end

-- okná sa obnovia pri udalosti Hyprlandu (latte-hypr-udalosti, jeden trvalý proces); update() je už iba záloha
-- každých 20 s (optimalizácia 26. 9.: predtým sh + 2× hyprctl každých 1,5 s)
local streaming, busy, again = false, false, false
local refresh
local function startStream()
  if streaming then return end
  streaming = true
  noctalia.runStream("latte-hypr-udalosti openwindow closewindow activewindowv2 movewindowv2 windowtitlev2 workspacev2 changefloatingmode fullscreen minimized",
                     function(_line) refresh() end)
end

function update()
  noctalia.setUpdateInterval(20000)
  startStream()
  refresh()
end

refresh = function()
  if busy then again = true; return end
  busy = true
  noctalia.runAsync({ "sh", "-c", "hyprctl -j clients; echo '@@'; hyprctl -j activewindow" }, function(r)
    busy = false
    if again then again = false; refresh() end
    local a, b = string.match(r.stdout or "", "^(.-)@@(.*)$")
    local ok, list = pcall(noctalia.json.decode, a or "")
    local ok2, act = pcall(noctalia.json.decode, b or "")
    local out = {}
    if ok and type(list) == "table" then
      for _, w in ipairs(list) do
        -- iba skutočné okná: bez skrytých špeciálnych plôch (okrem minimalizovaných) a bez pomocných vrstiev
        local wsname = type(w.workspace) == "table" and tostring(w.workspace.name or "") or ""
        if w.mapped ~= false and (not string.find(wsname, "^special:") or C.isMin(w)) then table.insert(out, w) end
      end
      -- poradie: plocha, potom poloha zľava (ako páska)
      table.sort(out, function(x, y)
        local wx, wy = (x.workspace and x.workspace.id or 0), (y.workspace and y.workspace.id or 0)
        if C.isMin(x) ~= C.isMin(y) then return not C.isMin(x) end
        if wx ~= wy then return wx < wy end
        return (x.at and x.at[1] or 0) < (y.at and y.at[1] or 0)
      end)
    end
    wins = out
    activeAddr = (ok2 and type(act) == "table" and act.address) or ""
    render()
  end)
end

-- stredný klik: nové okno tej istej aplikácie (ako Windows)
function onMiddleClick()
  if not hovered then return end
  for _, w in ipairs(wins) do
    if w.address == hovered then noctalia.runAsync({ "latte-nove-okno", w.class or "" }); return end
  end
end

-- pravý klik: ponuka pre okno pod myšou (alebo aktívne)
function onRightClick()
  local target = hovered or activeAddr
  if not target or target == "" then return end
  noctalia.writeFile(C.targetFile, target)
  noctalia.writeFile(C.hoverFile, "")        -- skryť náhľad; okno pod myšou si widget pamätá ďalej
  quietUntil = noctalia.nowMs() + 4000
  noctalia.togglePanel("latteos/okna:menu")
end
