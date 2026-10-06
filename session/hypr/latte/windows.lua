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
    -- okno z kvapky (plocha Goo, 1. 10., pravidlo 9): kvapka zapíše titulok okna, bod svojho ucha a smer rastu
    -- (`latte-kvapky miesto`); okno s tým titulkom sa pri otvorení prisunie ROHOM k uchu (App Manager z QueenGoo,
    -- Správca zariadení…). Záznam platí 10 s, potom sa zahodí.
    local place_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/latteos/kvapky-miesto"
    hl.on("window.open", function(w)
        local f = io.open(place_file, "r")
        if not f or not w then if f then f:close() end return end
        local line = f:read("*l") or ""
        f:close()
        local title, ax, ay, sx, sy, t = line:match("^(.-)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%d+)$")
        if not title then os.remove(place_file) return end
        if os.time() - tonumber(t) > 10 then os.remove(place_file) return end
        if w.title ~= title then return end
        os.remove(place_file)
        local sw = (type(w.size) == "table" and (w.size.x or w.size[1])) or 800
        local sh = (type(w.size) == "table" and (w.size.y or w.size[2])) or 600
        local m = w.monitor
        local x = (m and m.x or 0) + (tonumber(sx) > 0 and tonumber(ax) or tonumber(ax) - sw)
        local y = (m and m.y or 0) + (tonumber(sy) > 0 and tonumber(ay) or tonumber(ay) - sh)
        hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = "address:" .. w.address }))
    end)
    -- okno z bubliny (plocha Goo, 1. 10., pravidlo 14): kvapka sa nafúkla na obdĺžnik budúceho okna
    -- (`latte-kvapky okno TITUL X Y W H`); okno s tým titulkom naskočí presne naň, bez vlastnej animácie
    -- (vznik okna je bublina). Záznam platí 10 s.
    local bubble_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/latteos/kvapky-okno"
    hl.on("window.open", function(w)
        local f = io.open(bubble_file, "r")
        if not f or not w then if f then f:close() end return end
        local line = f:read("*l") or ""
        f:close()
        local title, x, y, ww, hh, t = line:match("^(.-)|(%-?%d+)|(%-?%d+)|(%d+)|(%d+)|(%d+)$")
        if not title then os.remove(bubble_file) return end
        if os.time() - tonumber(t) > 10 then os.remove(bubble_file) return end
        if w.title ~= title then return end
        os.remove(bubble_file)
        local sel = "address:" .. w.address
        local m = w.monitor
        hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = sel }))
        if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = sel })) end
        hl.dispatch(hl.dsp.window.resize({ x = tonumber(ww), y = tonumber(hh), window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = (m and m.x or 0) + tonumber(x), y = (m and m.y or 0) + tonumber(y), window = sel }))
    end)
    -- páska ako v niri: okno sa neminimalizuje, iba odíde z pohľadu (páska sa posunie na ďalšie okno)
    latte = latte or {}
    function latte.tape_on() return W.current == "paska" end
    function latte.tape_away(w)
        local a = hl.get_active_window()
        if w and a and a.address == w.address and latte.win and latte.win.cycle then latte.win.cycle(1) end
    end
    W.apply(load_mode(), false)
end

-- minimalizované okná (skrytá plocha special:minimized) sa pri prepnutí do pásky vrátia na pásku — v páske
-- nie je nič schované, ako v niri
local function restore_minimized()
    local ws = hl.get_active_workspace()
    if not ws then return end
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.workspace and tostring(w.workspace.name or ""):find("^special:minimized") then
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id), follow = false, window = "address:" .. w.address }))
        end
    end
    if latte and latte.win and latte.win.hide_special then latte.win.hide_special() end
end

--- prepne režim; existujúce okná prispôsobí (v plávajúcom ich uvoľní z dlaždíc a naopak)
function W.apply(mode, notify)
    W.current = mode
    local floating = (mode == "plavajuce")
    hl.config({ general = { layout = (mode == "paska") and "scrolling" or "dwindle" } })
    if float_rule then float_rule:set_enabled(floating) end
    if mode == "paska" then restore_minimized() end
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.floating ~= floating then
            hl.dispatch(hl.dsp.window.float({ action = floating and "enable" or "disable", window = "address:" .. w.address }))
        end
    end
    save_mode(mode)
    if latte and latte.tape_motion then latte.tape_motion() end
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
