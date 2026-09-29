--!nonstrict
-- Mini obrazovka 96 × 60 s vyznačenou časťou; klik = require("latte.snap").apply(<id>)
local TW, TH = 96, 60
local groups = {
  { "Polovice", { { "lava", 0, 0, 1/2, 1 }, { "prava", 1/2, 0, 1/2, 1 }, { "hore", 0, 0, 1, 1/2 }, { "dole", 0, 1/2, 1, 1/2 } } },
  { "Štvrtiny", { { "lh", 0, 0, 1/2, 1/2 }, { "ph", 1/2, 0, 1/2, 1/2 }, { "ld", 0, 1/2, 1/2, 1/2 }, { "pd", 1/2, 1/2, 1/2, 1/2 } } },
  { "Tretiny a stred", { { "l23", 0, 0, 2/3, 1 }, { "p13", 2/3, 0, 1/3, 1 }, { "stred", 0.15, 0.1, 0.7, 0.8 }, { "cela", 0, 0, 1, 1 } } },
}

local function apply(id)
  panel.close()
  noctalia.runAsync({ "hyprctl", "eval", 'require("latte.snap").apply("' .. id .. '")' })
end

local function mini(l)
  local id, x, y, w, h = l[1], l[2], l[3], l[4], l[5]
  local pad = 3
  local iw, ih = TW - 2 * pad, TH - 2 * pad
  return ui.column({ width = TW, height = TH, padding = pad, radius = 8, fill = "surface_variant", border = "outline", borderWidth = 1,
                     onClick = function() apply(id) end, tooltip = id }, {
    ui.box({ height = math.floor(y * ih), fill = "#00000000" }),
    ui.row({ height = math.floor(h * ih) }, {
      ui.box({ width = math.floor(x * iw), fill = "#00000000" }),
      ui.box({ width = math.floor(w * iw), height = math.floor(h * ih), radius = 5, fill = "primary/0.75" }),
    }),
  })
end

function render()
  local body = {}
  for _, g in ipairs(groups) do
    local row = {}
    for _, l in ipairs(g[2]) do table.insert(row, mini(l)) end
    table.insert(body, ui.label({ text = string.upper(g[1]), fontSize = 11, fontWeight = "bold", color = "on_surface_variant" }))
    table.insert(body, ui.row({ gap = 12 }, row))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "layout-grid", size = 20, color = "primary" }),
      ui.label({ text = "Rozloženie okna", fontSize = 17, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.column({ gap = 8 }, body),
  }))
end

function onOpen(_ctx) render() end
