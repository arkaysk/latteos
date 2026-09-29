--!nonstrict
-- Kapsa: navrchu posledná odložená vec (veľká karta, pri obrázku náhľad), pod ňou sloty histórie.
-- Klik na slot ju vytiahne navrch (skopíruje späť). Pravý klik kdekoľvek (slot, karta navrchu, výrez, hlavička)
-- = kontextová ponuka ako vo Windows (Win+V: Pripnúť/Odstrániť/Vymazať všetko). „Vysypať“ vymaže históriu.
local C = require("./common.luau")
local items = {}
local preview = noctalia.pluginDataDir() .. "/navrchu.png"
local vecFile = (noctalia.getenv("XDG_STATE_HOME") or ((noctalia.getenv("HOME") or "") .. "/.local/state")) .. "/latteos/kapsa-vec"

local function load()
  noctalia.runAsync({ "sh", "-c", "cliphist list 2>/dev/null | head -24" }, function(r)
    items = C.parse(r.stdout)
    local top = items[1]
    if top and top.image then
      noctalia.runAsync({ "sh", "-c", "cliphist decode \"$1\" > \"$2\"", "sh", top.id, preview }, function() render() end)
    end
    render()
  end)
end

local function pick(it)
  noctalia.runAsync({ "sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", it.id }, function() load() end)
end
local function drop(it)
  noctalia.runAsync({ "sh", "-c", "cliphist list | awk -F '\t' -v id=\"$1\" '$1 == id' | cliphist delete", "sh", it.id }, function() load() end)
end

-- kontextová ponuka (fork: onRightClick na riadkoch a kartách, panel.openContextMenu pri kurzore)
local function wipe() noctalia.runAsync({ "cliphist", "wipe" }, function() load() end) end
local function menuItem(i)
  local it = items[i]
  if not it then return end
  panel.openContextMenu({ onActivate = "onMenu", context = i, items = {
    { kind = "header", label = it.image and "Obrázok v Kapse" or "Text v Kapse" },
    { id = "pick", label = i == 1 and "Skopírovať znova" or "Dať navrch a skopírovať" },
    { id = "drop", label = "Vyhodiť z Kapsy" },
    { kind = "separator" },
    { id = "wipe", label = "Vysypať celú Kapsu" },
  } })
end
local function menuVec()
  panel.openContextMenu({ onActivate = "onMenu", context = "vec", items = {
    { id = "open", label = "Otvoriť" },
    { id = "folder", label = "Otvoriť priečinok" },
    { id = "copypath", label = "Kopírovať cestu" },
    { kind = "separator" },
    { id = "unvec", label = "Vybrať z Kapsy" },
  } })
end
local function menuPanel()
  panel.openContextMenu({ onActivate = "onMenu", context = "panel", items = {
    { id = "reload", label = "Obnoviť" },
    { id = "wipe", label = "Vysypať celú Kapsu" },
    { kind = "separator" },
    { id = "close", label = "Zavrieť" },
  } })
end
function onMenu(id, ctx)
  local vec = string.match(noctalia.readFile(vecFile) or "", "^%s*(.-)%s*$") or ""
  if id == "pick" and items[ctx] then pick(items[ctx])
  elseif id == "drop" and items[ctx] then drop(items[ctx])
  elseif id == "wipe" then wipe()
  elseif id == "open" and vec ~= "" then noctalia.runAsync({ "xdg-open", vec })
  elseif id == "folder" and vec ~= "" then noctalia.runAsync({ "latte-app", "subory", string.match(vec, "^(.*)/[^/]*$") or vec })
  elseif id == "copypath" and vec ~= "" then noctalia.runAsync({ "wl-copy", vec })
  elseif id == "unvec" then noctalia.removeFile(vecFile); render()
  elseif id == "reload" then load()
  elseif id == "close" then panel.close() end
end

function render()
  local top = items[1]
  local body = {}
  -- vec vo výreze (súbor pretiahnutý na Kapsu na lište)
  local vec = string.match(noctalia.readFile(vecFile) or "", "^%s*(.-)%s*$") or ""
  if vec ~= "" then
    table.insert(body, ui.row({ fill = "surface_variant", radius = 14, padding = 10, gap = 8, align = "center", onRightClick = menuVec }, {
      ui.glyph({ name = "file", size = 18, color = "primary" }),
      ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({ text = "VO VÝREZE", fontSize = 10, fontWeight = "bold", color = "on_surface_variant" }),
        ui.label({ text = string.match(vec, "[^/]+$") or vec, fontSize = 13, maxWidth = 280, maxLines = 1 }),
      }),
      ui.button({ glyph = "external-link", variant = "ghost", tooltip = "Otvoriť", onClick = function() noctalia.runAsync({ "xdg-open", vec }) end }),
      ui.button({ glyph = "x", variant = "ghost", tooltip = "Vybrať z Kapsy", onClick = function() noctalia.removeFile(vecFile); render() end }),
    }))
  else
    table.insert(body, ui.label({ text = "Výrez je prázdny: pretiahni súbor na jamku Kapsy na lište.", fontSize = 12, color = "on_surface_variant", maxWidth = 400, maxLines = 2 }))
  end
  if top then
    local card = { ui.label({ text = "NAVRCHU", fontSize = 11, fontWeight = "bold", color = "on_primary" }) }
    if top.image then
      table.insert(card, ui.image({ path = preview, width = 380, height = 180, fit = "contain" }))
    end
    table.insert(card, ui.label({ text = C.label(top, 300), fontSize = 14, color = "on_primary", maxWidth = 390, maxLines = 5 }))
    table.insert(body, ui.column({ fill = "primary", radius = 16, padding = 14, gap = 6, align = "stretch",
                                   onClick = function() pick(top) end, onRightClick = function() menuItem(1) end, tooltip = "klik: skopírovať znova · pravý klik: ponuka" }, card))
  else
    table.insert(body, ui.label({ text = "Kapsa je prázdna. Skopíruj niečo (Ctrl+C) a odloží sa sem.", fontSize = 13, color = "on_surface_variant", maxWidth = 400, maxLines = 3 }))
  end
  if #items > 1 then
    table.insert(body, ui.label({ text = "V KAPSE", fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }))
    local row = {}
    for i = 2, #items do
      local it = items[i]
      table.insert(row, ui.column({ fill = "surface_variant", radius = 12, padding = 10, gap = 4, width = 196, height = 74,
                                    onClick = function() pick(it) end, onRightClick = function() menuItem(i) end,
                                    tooltip = "klik: navrch · pravý klik: ponuka" }, {
        ui.row({ gap = 6, align = "center" }, {
          ui.glyph({ name = it.image and "photo" or "file-text", size = 14, color = "primary" }),
          ui.label({ text = it.image and "obrázok" or "text", fontSize = 10, color = "on_surface_variant", flexGrow = 1 }),
          ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", onClick = function() drop(it) end, onRightClick = function() menuItem(i) end }),
        }),
        ui.label({ text = C.label(it, 60), fontSize = 12, maxWidth = 176, maxLines = 2 }),
      }))
      if #row == 2 then table.insert(body, ui.row({ gap = 8 }, row)); row = {} end
    end
    if #row > 0 then table.insert(body, ui.row({ gap = 8 }, row)) end
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ gap = 8, align = "center", onRightClick = menuPanel }, {
      ui.glyph({ name = "basket", size = 20, color = "primary" }),
      ui.label({ text = "Kapsa", fontSize = 17, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ text = "Vysypať", glyph = "trash", variant = "ghost", onClick = function()
        noctalia.runAsync({ "cliphist", "wipe" }, function() load() end) end }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.scroll({ flexGrow = 1, gap = 10, align = "stretch" }, body),
  }))
end

function onOpen(_ctx) render(); load() end
