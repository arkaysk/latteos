--!nonstrict
-- Dashboard Noctalie (riadiace centrum) ako malé úzke tlačidlo medzi Súbormi a Správcom zariadení (zadanie 26. 9.:
-- zatiaľ nerozhodnuté, či ostane; nech je po ruke, ale nezavadzia). Klik = otvoriť/zavrieť, rovnako ako Super+A.
local hovered = false

local function render()
  barWidget.render(ui.row({ width = 18, height = 34, radius = 9, fill = hovered and "primary/0.16" or "primary/0.05",
                            align = "center", justify = "center", tooltip = "Dashboard (Noctalia)",
                            onHover = function(state) hovered = state == "true"; render() end },
                          { ui.glyph({ name = "layout-dashboard", size = 13, color = hovered and "primary" or "on_surface_variant" }) }))
end

function update() noctalia.setUpdateInterval(600000); render() end

function onClick() noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "control-center" }) end
