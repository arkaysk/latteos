--!nonstrict
-- Šálka Latte na lište: klik otvorí systémové menu. V režime SAFE je šálka zvýraznená.
local mode = "normal"

function update()
  noctalia.setUpdateInterval(30000)
  local toml = noctalia.readFile("/run/latteos/mode.toml") or ""
  mode = string.match(toml, 'mode = "(%a+)"') or "safe"
  -- širšie tlačidlo šálky (zadanie 24. 9.): dlaždica ako pri aplikáciách, v SAFE s nápisom
  -- šálka je dôležité tlačidlo (zadanie 25. 9.): väčšia ikona vo farbe akcentu na výraznejšej dlaždici
  local kids = { ui.glyph({ name = "coffee", size = 24, color = mode == "safe" and "on_primary" or "primary" }) }
  if mode == "safe" then table.insert(kids, ui.label({ text = "SAFE", fontSize = 11, fontWeight = "bold", color = "on_primary" })) end
  barWidget.render(ui.row({ width = 60, height = 34, gap = 4, align = "center", justify = "center", radius = 12,
                            fill = mode == "safe" and "primary" or "primary/0.18", border = "primary/0.45", borderWidth = 1, tooltip = "Šálka: účet, Nastavenia, Monitor, napájanie" }, kids))
end

function onClick()
  noctalia.togglePanel("latteos/system:menu")
end
