--!nonstrict
-- Súbory na lište (zadanie 25. 9.): výrazná dlaždica ako šálka — väčšia ikona priečinka vo farbe akcentu.
-- Klik = Súbory (Domov), stredný klik = Plocha, pravý klik = Stiahnuté.
local hovered = false
local function render()
  barWidget.render(ui.row({ width = 52, height = 34, align = "center", justify = "center", radius = 12,
                            fill = hovered and "primary/0.28" or "primary/0.18", border = "primary/0.45", borderWidth = 1,
                            onHover = function(state) hovered = state == "true"; render() end,
                            tooltip = "Súbory · klik: Domov · stredný: Plocha · pravý: Stiahnuté" },
                          { ui.glyph({ name = "folder", size = 22, color = "primary" }) }))
end
function update() noctalia.setUpdateInterval(60000); render() end
function onClick() noctalia.runAsync({ "latte-app", "subory" }) end
function onMiddleClick() noctalia.runAsync({ "sh", "-c", 'latte-app subory "$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Plocha")"' }) end
function onRightClick() noctalia.runAsync({ "sh", "-c", 'latte-app subory "$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Stiahnuté")"' }) end
