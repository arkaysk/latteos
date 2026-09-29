-- latte/bars.lua — jednotné okenné tlačidlá LatteOS (zadanie 24. 9.: „minimalizovať, zväčšiť, zavrieť
-- jednotne naprieč aplikáciami“). Titulok a tlačidlá kreslí kompozitor (plugin hyprbars) pre okná, ktoré
-- nemajú vlastnú hlavičku (terminály, Qt/KDE, VLC…). Aplikácie s vlastnou hlavičkou (GTK/libadwaita,
-- Firefox, Electron, Steam, aplikácie LatteOS) druhý pruh nedostanú.
-- Minimalizovať = presun na skrytú plochu special:minimized (späť z lišty alebo Super+Shift+N).
local B = {}

B.plugin = "/usr/lib64/latteos/hyprbars.so"
-- triedy okien s vlastnou hlavičkou (CSD) — bez pruhu kompozitora
B.own_titlebar = "^(org%.quickshell|org%.mozilla%.firefox|firefox|chromium.*|google%-chrome.*|brave.*|"
    .. "com%.discordapp%.Discord|discord|steam|com%.valvesoftware%.Steam|org%.gnome%..*|gnome%-.*|"
    .. "code|Code|code%-oss|electron.*|Spotify|spotify|obsidian|signal|org%.signal%.Signal|"
    .. "com%.heroicgameslauncher%.hgl|heroic|org%.kde%.kdenlive|io%.github%.alainm23%.planify)$"

local function file_exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end

-- Lua vzor → regulárny výraz pre pravidlo okna (Hyprland používa RE2)
local function re(pattern) return (pattern:gsub("%%(%p)", "\\%1")) end

function B.setup(theme)
    latte = latte or {}
    latte.win = latte.win or {}
    function latte.win.minimize()
        local w = hl.get_active_window()
        if w then hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:" .. w.address })) end
    end
    function latte.win.maximize()
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    end
    function latte.win.close() hl.dispatch(hl.dsp.window.close()) end
    -- obnoviť okno z minimalizovaných na aktuálnu plochu
    function latte.win.restore(address)
        local ws = hl.get_active_workspace()
        if address and ws then hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id), window = "address:" .. address })) end
    end

    -- lišta (ovál okien): klik na ikonu = prepnúť na okno; minimalizované sa vráti na aktuálnu plochu
    function latte.win.activate(address)
        for _, w in ipairs(hl.get_windows() or {}) do
            if w.address == address then
                local ws = w.workspace
                if ws and tostring(ws.name or ""):find("^special:minimized") then latte.win.restore(address) end
                hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
                return
            end
        end
    end
    function latte.win.minimize_addr(address)
        hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:" .. address }))
    end

    if not file_exists(B.plugin) then return false end
    local ok = pcall(hl.plugin.load, B.plugin)
    if not ok or not (hl.plugin and hl.plugin.hyprbars) then return false end

    local bg = "rgb(" .. (theme.bar_bg or "261D17") .. ")"
    local fg = "rgb(" .. (theme.bar_fg or "F3EBDD") .. ")"
    hl.config({
        plugin = {
            hyprbars = {
                bar_height = 30,
                bar_color = bg,
                ["col.text"] = fg,
                bar_text_font = "Manrope",
                bar_text_size = 11,
                bar_text_weight = "semibold",
                bar_text_align = "left",
                bar_padding = 12,
                bar_button_padding = 8,
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                on_double_click = "hyprctl eval 'latte.win.maximize()'",
            },
        },
    })
    -- pravý klik na titulok = ponuka okna a podržanie myši nad □ = rozloženia ako vo Windows 11 (záplata LatteOS
    -- resources/patches/hyprbars-latte.patch); nastaví sa iba, ak ju načítaný plugin pozná (starý hyprbars ostáva
    -- v bežiacej relácii až do odhlásenia). Tlačidlá sa počítajú od kraja: 0 ✕, 1 □, 2 –.
    local okv, val = pcall(hl.get_config, "plugin:hyprbars:on_right_click")
    if okv and val ~= nil then
        hl.config({ plugin = { hyprbars = { on_right_click = "latte-ponuka okno {x} {y} {address}" } } })
    end
    local okh, valh = pcall(hl.get_config, "plugin:hyprbars:on_button_hover")
    if okh and valh ~= nil then
        hl.config({ plugin = { hyprbars = { on_button_hover = "latte-ponuka rozlozenia {x} {y} {address} {index}" } } })
    end
    -- tlačidlá sprava doľava: zavrieť, zväčšiť, minimalizovať (ako Windows)
    local accent = "rgb(" .. (theme.border_active or "E4B283") .. ")"
    hl.plugin.hyprbars.add_button({ bg_color = "rgb(C75B4A)", fg_color = "rgb(FFFFFF)", size = 17, icon = "✕", action = "hyprctl eval 'latte.win.close()'" })
    hl.plugin.hyprbars.add_button({ bg_color = accent, fg_color = "rgb(1E1712)", size = 17, icon = "□", action = "hyprctl eval 'latte.win.maximize()'" })
    hl.plugin.hyprbars.add_button({ bg_color = accent, fg_color = "rgb(1E1712)", size = 17, icon = "–", action = "hyprctl eval 'latte.win.minimize()'" })
    hl.window_rule({ name = "latte-vlastna-hlavicka", match = { class = re(B.own_titlebar) }, ["hyprbars:no_bar"] = true })
    return true
end

return B
