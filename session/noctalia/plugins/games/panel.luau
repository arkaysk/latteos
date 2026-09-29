--!nonstrict
-- Herňa: obaly hier v mriežke (5 v rade), filter písaním, klik = latte-games play (herný režim).
local games, filter, loading = {}, "", true

local function human(b)
  if not b or b <= 0 then return "" end
  local gb = b / 1073741824
  return gb >= 1 and string.format("%.1f GB", gb) or string.format("%d MB", math.floor(b / 1048576))
end

local function load()
  loading = true
  noctalia.runAsync({ "latte-games", "list" }, function(r)
    local ok, list = pcall(noctalia.json.decode, r.stdout or "[]")
    games = (ok and type(list) == "table") and list or {}
    loading = false
    render()
  end, 20000)
end

local function play(g)
  panel.close()
  noctalia.runAsync({ "latte-games", "play", g.id })       -- bez callbacku = na pozadí, prežije zatvorenie panela
  noctalia.notify("Herňa", "Spúšťam " .. g.name .. " · herný režim zapnutý")
end

local function tile(g)
  local cover = (g.cover and g.cover ~= "") and ui.image({ path = g.cover, width = 150, height = 200, radius = 10, fit = "cover" })
             or ui.column({ width = 150, height = 200, radius = 10, fill = "primary/0.18", align = "center", justify = "center", gap = 8 }, {
                  ui.glyph({ name = "device-gamepad-2", size = 40, color = "primary" }),
                  ui.label({ text = g.name, fontSize = 13, fontWeight = "bold", maxWidth = 130, maxLines = 3, textAlign = "center" }),
                })
  return ui.column({ width = 150, gap = 4, onClick = function() play(g) end, tooltip = "Hrať · " .. g.source }, {
    cover,
    ui.label({ text = g.name, fontSize = 12, fontWeight = "bold", maxWidth = 150, maxLines = 1 }),
    ui.label({ text = g.source .. (human(g.size) ~= "" and (" · " .. human(g.size)) or ""), fontSize = 11, color = "on_surface_variant" }),
  })
end

function render()
  local body = {}
  local shown = {}
  for _, g in ipairs(games) do
    if filter == "" or string.find(string.lower(g.name), string.lower(filter), 1, true) then table.insert(shown, g) end
  end
  if loading then
    table.insert(body, ui.label({ text = "Hľadám hry…", fontSize = 13, color = "on_surface_variant" }))
  elseif #games == 0 then
    table.insert(body, ui.column({ gap = 10, padding = 20, radius = 14, fill = "surface_variant" }, {
      ui.label({ text = "Zatiaľ tu nie sú žiadne hry", fontSize = 16, fontWeight = "bold" }),
      ui.label({ text = "Nainštaluj Steam alebo Heroic (Epic, GOG, Amazon) v App Manageri. Hry, ktoré v nich nainštaluješ, sa ukážu tu a spustia sa v hernom režime.",
                 fontSize = 13, color = "on_surface_variant", maxWidth = 820, maxLines = 3 }),
      ui.row({ gap = 8 }, {
        ui.button({ text = "Steam", glyph = "download", onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "aplikacie", "objavovat" }) end }),
        ui.button({ text = "Heroic", glyph = "download", variant = "ghost", onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "aplikacie", "objavovat" }) end }),
      }),
    }))
  else
    local row = {}
    for _, g in ipairs(shown) do
      table.insert(row, tile(g))
      if #row == 5 then table.insert(body, ui.row({ gap = 16 }, row)); row = {} end
    end
    if #row > 0 then table.insert(body, ui.row({ gap = 16 }, row)) end
    if #shown == 0 then table.insert(body, ui.label({ text = "Nič pre „" .. filter .. "“", fontSize = 13, color = "on_surface_variant" })) end
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = "device-gamepad-2", size = 22, color = "primary" }),
      ui.label({ text = "Herňa", fontSize = 18, fontWeight = "bold" }),
      ui.label({ text = #games .. (#games == 1 and " hra" or ((#games >= 2 and #games <= 4) and " hry" or " hier")) .. " · klik = hrať v hernom režime", fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", tooltip = "Obnoviť", onClick = function() load() end }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.input({ placeholder = "Hľadať hru…", focus = true, onChange = "onFilter", onSubmit = "onEnter" }),
    ui.scroll({ flexGrow = 1, gap = 16, align = "stretch" }, body),
  }))
end

function onFilter(t) filter = t or ""; render() end
function onEnter(_t)
  for _, g in ipairs(games) do
    if filter == "" or string.find(string.lower(g.name), string.lower(filter), 1, true) then play(g); return end
  end
end
function onOpen(_ctx) filter = ""; render(); load() end
