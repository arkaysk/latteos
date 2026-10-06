-- Sklo okien aplikácií (1. 10. 2026): plugin Hyprglass (github.com/hyprnux/hyprglass, BSD-3, stavaný na Hyprland
-- 0.56.2) — lom svetla na okrajoch, dúhová chromatická aberácia (perleťové okraje, ako v ricu „Caelestia +
-- Hyprglass“ od používateľa), matné rozmazanie, odlesk. Iba plocha LatteOS Goo (Kvapky) a iba sklenené materiály
-- tém (sklo, fazety, mráz, jantár); kovové témy majú textúru v oknách Goo, nie sklo. Sklo platí pre trochu priehľadné
-- okná: aktívne 86 %, neaktívne 78 % (1. 10.: pri 93/87 % sklo nebolo vidieť — aplikácie kreslia plné pozadie); celá obrazovka (hry, video) zostáva plná a bez skla.
-- Vrstvy (lišty, scéna Kvapiek) nechá tak: pleamar si sklo kreslí sám.
-- Vypnutie: ~/.config/latteos/bez-skla
local S = {}
S.plugin = "/usr/lib64/latteos/hyprglass.so"
local GLASS = { sklo = true, fazety = true, mraz = true, jantar = true }

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

-- herný režim (latte.game v hyprland.lua): bez skla a bez priehľadných okien
local function game_on()
    local f = io.open(((os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/latteos/game-mode"), "r")
    if not f then return false end
    local v = f:read("*l"); f:close()
    return v == "1"
end

local function apply(theme)
    local hg = hl.plugin.hyprglass
    local game = game_on()
    -- predvoľba skôr, než ju config označí za predvolenú (inak „Unknown default_preset“)
    -- perleť: silnejšia dúha na okrajoch a lom, jemné rozmazanie, aby text v okne ostal čitateľný
    hg.preset("latte", {
        glass_opacity = 0.85,
        blur_strength = 2.2,
        refraction_strength = 0.9,
        chromatic_aberration = 1.2,
        edge_thickness = 0.12,
        specular_strength = 0.8,
        fresnel_strength = 0.6,
    })
    hg.config({
        enabled = not game,
        default_theme = theme.effective_mode == "light" and "light" or "dark",
        default_preset = "latte",
        layers = { enabled = false },
    })
    hl.config({ decoration = { active_opacity = game and 1.0 or 0.86, inactive_opacity = game and 1.0 or 0.78, fullscreen_opacity = 1.0 } })
end

function S.setup(theme, goo)
    local cfg = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
    local want = goo and GLASS[theme.material or ""] and not file_exists(cfg .. "/latteos/bez-skla") and file_exists(S.plugin)
    if not want then
        -- iná téma / plocha: plugin sa neodpája (odpájanie pluginu so shadermi vie zhodiť Hyprland), iba sa vypne
        if hl.plugin and hl.plugin.hyprglass then pcall(hl.plugin.hyprglass.config, { enabled = false }) end
        return false
    end
    -- Pri načítaní konfigurácie hl.plugin.load Hyprglass nenačíta (overené 1. 10.: po štarte ani po reload-e nebol
    -- v `hyprctl plugin list`, za behu sa načíta hneď) — preto ešte raz po štarte a po reload-e konfigurácie
    local function go()
        pcall(hl.plugin.load, S.plugin)
        if hl.plugin and hl.plugin.hyprglass then apply(theme); return true end
        return false
    end
    if not go() then
        hl.on("hyprland.start", go)
        hl.on("config.reloaded", go)
    end
    return true
end

return S
