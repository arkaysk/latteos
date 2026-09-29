--!nonstrict
-- Ponuka okna z oválu (pravý klik), ako vo Windows: prepnúť, minimalizovať/obnoviť, zväčšiť, plávať,
-- presunúť na plochu, NET, zavrieť.
local C = require("./common.luau")
local w = nil

local function load()
  local addr = string.match(noctalia.readFile(C.targetFile) or "", "0x%x+") or ""
  noctalia.runAsync({ "hyprctl", "-j", "clients" }, function(r)
    local ok, list = pcall(noctalia.json.decode, r.stdout or "")
    w = nil
    if ok and type(list) == "table" then
      for _, x in ipairs(list) do if x.address == addr then w = x end end
    end
    render()
  end)
end

local function act(code) C.eval(code); panel.close() end
local function item(glyph, text, onClick, variant)
  return ui.button({ glyph = glyph, text = text, variant = variant or "ghost", contentAlign = "start", onClick = onClick })
end

function render()
  if not w then
    panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, {
      ui.label({ text = "Okno už nie je otvorené.", fontSize = 13, color = "on_surface_variant" }),
      item("close", "Zavrieť ponuku", function() panel.close() end),
    }))
    return
  end
  local a = w.address
  local min = C.isMin(w)
  local body = {
    ui.row({ gap = 10, align = "center" }, {
      C.icon(w) and ui.image({ path = C.icon(w), width = 28, height = 28, fit = "contain" })
        or ui.glyph({ name = C.glyph(w) or "app-window", size = 24, color = "primary" }),
      ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({ text = C.name(w), fontSize = 14, fontWeight = "bold", maxWidth = 220, maxLines = 2 }),
        ui.label({ text = (w.class or "") .. (min and " · minimalizované" or ""), fontSize = 11, color = "on_surface_variant", maxWidth = 220, maxLines = 1 }),
      }),
    }),
    ui.separator({}),
    item("app-window", "Prepnúť na okno", function() act('latte.win.activate("' .. a .. '")') end),
    min and item("arrow-up", "Obnoviť", function() act('latte.win.activate("' .. a .. '")') end)
        or item("minus", "Minimalizovať", function() act('latte.win.minimize_addr("' .. a .. '")') end),
    item("square", "Zväčšiť / obnoviť veľkosť", function() act('latte.win.activate("' .. a .. '"); latte.win.maximize()') end),
    item(w.floating and "layout-grid" or "app-window", w.floating and "Ukotviť do rozloženia" or "Plávať (voľné okno)",
         function() act('hl.dispatch(hl.dsp.window.float({ action = "toggle", window = "address:' .. a .. '" }))') end),
  }
  local ws = {}
  for i = 1, 4 do
    table.insert(ws, ui.button({ text = tostring(i), variant = (w.workspace and w.workspace.id == i) and "primary" or "outline", controlSize = "sm", flexGrow = 1,
                                 tooltip = "Presunúť na plochu " .. i,
                                 onClick = function() act('hl.dispatch(hl.dsp.window.move({ workspace = "' .. i .. '", follow = false, window = "address:' .. a .. '" }))') end }))
  end
  table.insert(body, ui.label({ text = "PRESUNÚŤ NA PLOCHU", fontSize = 11, fontWeight = "bold", color = "on_surface_variant" }))
  table.insert(body, ui.row({ gap = 6 }, ws))
  table.insert(body, item("network", "NET tejto aplikácie…", function()
    panel.close()
    noctalia.runAsync({ "latte-net", "status", w.class or "" }, function(r)
      local off = string.find(r.stdout or "", "off") ~= nil
      noctalia.runAsync({ "latte-net", off and "on" or "off", w.class or "" }, function(r2)
        if r2.exitCode == 0 then noctalia.notify("NET " .. (off and "zapnutý" or "vypnutý") .. ": " .. (w.class or ""), "Platí od ďalšieho spustenia aplikácie.")
        else noctalia.notifyError("NET", "Aplikácia sa nenašla medzi spúšťačmi.") end
      end)
    end)
  end))
  table.insert(body, ui.separator({}))
  table.insert(body, item("x", "Zavrieť okno", function() act('hl.dispatch(hl.dsp.window.close({ window = "address:' .. a .. '" }))') end, "destructive"))
  panel.render(ui.column({ flexGrow = 1, gap = 6, align = "stretch" }, body))
end

function onOpen(_ctx) w = nil; render(); load() end
