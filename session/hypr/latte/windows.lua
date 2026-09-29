-- latte/windows.lua — režimy okien LatteOS (GUI návrh: „Okná: páska a režimy“):
--   paska      nekonečná vodorovná páska (Hyprland scrolling layout, od 0.55)
--   dlazdice   dlaždice (dwindle)
--   plavajuce  všetky okná plávajú, prichytávanie ťahaním (ako Windows)
-- Voľba sa pamätá v ~/.local/state/latteos/window-mode.
local W = {}

W.order = { "paska", "dlazdice", "plavajuce" }
W.label = { paska = "Nekonečná páska", dlazdice = "Dlaždice", plavajuce = "Plávajúce okná" }

local function state_path()
    local home = os.getenv("HOME") or ""
    local st = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
    return st .. "/latteos/window-mode"
end

local function load_mode()
    local f = io.open(state_path(), "r")
    if not f then return "paska" end
    local m = (f:read("*l") or ""):match("%a+")
    f:close()
    return W.label[m] and m or "paska"
end

local function save_mode(m)
    os.execute("mkdir -p \"$(dirname '" .. state_path() .. "')\"")
    local f = io.open(state_path(), "w")
    if f then f:write(m .. "\n"); f:close() end
end

local float_rule   -- pravidlo „všetko pláva“, zapína sa len v režime plavajuce

function W.setup()
    hl.config({
        scrolling = {
            column_width = 0.5,             -- stĺpec pásky = pol obrazovky
            fullscreen_on_one_column = true,
            follow_focus = true,
            focus_fit_method = 1,
        },
        dwindle = { preserve_split = true },
    })
    float_rule = hl.window_rule({ name = "latte-plavajuce", match = { class = ".*" }, float = true })
    -- okná otvárané z ostrovov lišty vyrastajú pri svojom ostrove (zadanie 24. 9.): App Manager vľavo dole
    -- nad dlaždicou aplikácií, Správca zariadení vpravo dole; lišta je hrubá 56 px + okraj 10 px
    hl.window_rule({ name = "latte-z-listy-aplikacie", match = { class = "^org\\.quickshell$", title = "^Aplikácie — LatteOS$" },
                     float = true, move = { "12", "monitor_h-window_h-72" } })
    hl.window_rule({ name = "latte-z-listy-zariadenia", match = { class = "^org\\.quickshell$", title = "^Správca zariadení — LatteOS$" },
                     float = true, move = { "monitor_w-window_w-12", "monitor_h-window_h-72" } })
    W.apply(load_mode(), false)
end

--- prepne režim; existujúce okná prispôsobí (v plávajúcom ich uvoľní z dlaždíc a naopak)
function W.apply(mode, notify)
    W.current = mode
    local floating = (mode == "plavajuce")
    hl.config({ general = { layout = (mode == "paska") and "scrolling" or "dwindle" } })
    if float_rule then float_rule:set_enabled(floating) end
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.floating ~= floating then
            hl.dispatch(hl.dsp.window.float({ action = floating and "enable" or "disable", window = "address:" .. w.address }))
        end
    end
    save_mode(mode)
    if notify then
        hl.exec_cmd("notify-send -a LatteOS -i view-grid 'Režim okien' '" .. W.label[mode] .. "'")
    end
end

function W.cycle()
    local idx = 1
    for i, m in ipairs(W.order) do if m == W.current then idx = i end end
    W.apply(W.order[idx % #W.order + 1], true)
end

return W
