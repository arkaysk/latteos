-- latte/tiers.lua — stupne výkonu (ROADMAP: Plný / Štandard / Úsporný / Minimálny + Softvér pre VM).
-- Jedno miesto pravdy pre efekty kompozitora; shell (Noctalia) sa riadi tým istým stupňom.
local T = {}

-- efekty: blur, tiene, žiara aktívneho okna (Hyprland 0.56), animácie a ich rýchlosť
T.levels = {
    plny      = { blur = { size = 6, passes = 2 }, shadow = 22, glow = true,  anim = 1.0, orbit = true },
    standard  = { blur = { size = 4, passes = 1 }, shadow = 14, glow = true,  anim = 1.0, orbit = true },
    usporny   = { blur = nil,                      shadow = nil, glow = false, anim = 1.6 },
    minimalny = { blur = nil,                      shadow = nil, glow = false, anim = nil },
    -- VM bez GPU: každý pohyb stojí CPU (setup/f1/RESULTS.md) → bez efektov a animácií
    softver   = { blur = nil,                      shadow = nil, glow = false, anim = nil },
}

function T.get(name)
    return T.levels[name] or T.levels.softver, T.levels[name] and name or "softver"
end

--- nastaví dekorácie a animácie podľa stupňa
function T.apply(name, colors)
    local t = T.get(name)
    hl.config({
        decoration = {
            blur = t.blur and { enabled = true, size = t.blur.size, passes = t.blur.passes, vibrancy = 0.17 }
                         or { enabled = false },
            shadow = t.shadow and { enabled = true, range = t.shadow, render_power = 3, color = colors.shadow }
                               or { enabled = false },
            glow = t.glow and { enabled = true, range = 10, render_power = 3,
                                color = colors.glow, color_inactive = colors.glow_inactive }
                           or { enabled = false },
        },
        animations = { enabled = t.anim ~= nil },
    })
    if t.anim then
        local s = t.anim   -- > 1 = rýchlejšie (kratšie) animácie
        hl.curve("latteOut",   { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
        hl.curve("latteSpring", { type = "spring", mass = 1, stiffness = 238, dampening = 24 })
        hl.animation({ leaf = "windows",    enabled = true, speed = 4.8 / s, spring = "latteSpring" })
        hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.1 / s, spring = "latteSpring", style = "popin 90%" })
        hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5 / s, bezier = "latteOut", style = "popin 90%" })
        hl.animation({ leaf = "fade",       enabled = true, speed = 3.0 / s, bezier = "latteOut" })
        hl.animation({ leaf = "border",     enabled = true, speed = 5.4 / s, bezier = "latteOut" })
        hl.animation({ leaf = "workspaces", enabled = true, speed = 2.0 / s, bezier = "latteOut", style = "slide" })
        hl.animation({ leaf = "layers",     enabled = true, speed = 3.8 / s, bezier = "latteOut", style = "fade" })
        -- obiehajúci karamelový lem aktívneho okna (prechod farieb v rámiku sa pomaly otáča, cyklus ~10 s)
        hl.curve("latteLin", { type = "bezier", points = { {0, 0}, {1, 1} } })
        hl.animation({ leaf = "borderangle", enabled = t.orbit == true, speed = 100, bezier = "latteLin", style = "loop" })
    end
end

return T
