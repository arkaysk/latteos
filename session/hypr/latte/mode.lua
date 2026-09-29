-- latte/mode.lua — režim a stupeň výkonu z /run/latteos/mode.toml (zapísal latte-boot select).
-- Používateľ môže stupeň vynútiť v ~/.config/latteos/tier (jedno slovo: plny|standard|usporny|minimalny|softver).
local M = {}

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- vráti { mode, renderer, tier, reason }
function M.load()
    local out = { mode = "normal", renderer = "sw-gl", tier = "softver", reason = "" }
    local toml = read_file("/run/latteos/mode.toml")
    if toml then
        -- iba sekcia [mode]; [probe] ďalej nečítame
        local section = toml:match("%[mode%](.-)\n%[") or toml
        for key, val in section:gmatch('\n(%w+) = "([^"]*)"') do
            if out[key] ~= nil then out[key] = val end
        end
    end
    local home = os.getenv("HOME") or ""
    local cfg = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    local forced = read_file(cfg .. "/latteos/tier")
    if forced then
        forced = forced:match("^%s*(%a+)")
        if forced then out.tier = forced; out.tier_forced = true end
    end
    return out
end

--- téma LatteOS (~/.config/latteos/theme → /usr/share/latteos/themes/<id>.theme)
function M.theme()
    local home = os.getenv("HOME") or ""
    local cfg = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    local id = (read_file(cfg .. "/latteos/theme") or "latte"):match("^%s*([%w_-]+)") or "latte"
    local body = read_file("/usr/share/latteos/themes/" .. id .. ".theme")
              or read_file("/usr/share/latteos/themes/latte.theme") or ""
    local t = { id = id }
    for k, v in body:gmatch("\n?([%w_]+) = ([^\n]*)") do t[k] = v end
    -- farby okenného pruhu z palety v účinnom režime (theme-mode: tema | dark | light | auto)
    local pref = ((read_file(cfg .. "/latteos/theme-mode") or "tema"):match("%a+")) or "tema"
    local m = (pref == "dark" or pref == "light") and pref or (t.mode or "dark")
    if pref == "auto" then local h = tonumber(os.date("%H")); m = (h >= 7 and h < 19) and "light" or "dark" end
    t.effective_mode = m
    local pal = read_file("/usr/share/latteos/noctalia/palettes/" .. (t.palette or "Latte") .. ".json") or ""
    local sect = pal:match('"' .. m .. '"%s*:%s*(%b{})') or ""
    local function col(key) local c = sect:match('"' .. key .. '"%s*:%s*"#(%x%x%x%x%x%x)') return c end
    t.bar_bg = col("mSurfaceVariant") or col("mSurface")
    t.bar_fg = col("mOnSurface")
    return t
end

return M
