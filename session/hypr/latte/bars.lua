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
        if w and latte.tape_on and latte.tape_on() then latte.tape_away(w); return end
        if w and latte.goo_min then pcall(latte.goo_min, w) end
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
                latte.win.hide_special()
                return
            end
        end
    end
    function latte.win.minimize_addr(address)
        if latte.tape_on and latte.tape_on() then return end
        hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:" .. address }))
    end
    -- okno podľa triedy a titulku (kvapka pozná okná zo zoznamu wlr-foreign-toplevel, nie adresy Hyprlandu).
    -- nth: koľké okno s tou istou triedou a titulkom (1 = prvé) — päť terminálov „~“ sú päť rôznych okien;
    -- oba zoznamy (Hyprland aj foreign-toplevel) idú v poradí otvorenia
    local function by(class, title, nth)
        local hit, seen = nil, 0
        nth = tonumber(nth) or 1
        for _, w in ipairs(hl.get_windows() or {}) do
            if w.class == class then
                if w.title == title then
                    seen = seen + 1
                    if seen == nth then return w end
                    hit = hit or w
                end
                hit = hit or w
            end
        end
        return hit
    end
    -- klik na okno v lište-kvapke, ako vo Windows: neaktívne sa ukáže (aj z minimalizovaných), aktívne sa minimalizuje
    function latte.win.toggle_by(class, title, nth)
        local w = by(class, title, nth)
        if not w then return end
        local a = hl.get_active_window()
        local hidden = w.workspace and tostring(w.workspace.name or ""):find("^special:minimized")
        if a and a.address == w.address and not hidden then
            -- v páske sa nič neminimalizuje: klik na aktívne okno ho iba vycentruje
            if latte.tape_on and latte.tape_on() then hl.dispatch(hl.dsp.layout("center"))
            else latte.win.minimize_addr(w.address) end
        else latte.win.activate(w.address) end
    end
    -- skrytá plocha minimalizovaných nesmie ostať ukázaná: nové okná by sa otvárali na nej (vyzerali by minimalizované)
    function latte.win.hide_special()
        for _, m in ipairs(hl.get_monitors() or {}) do
            local sp = m.active_special_workspace
            if sp and tostring(sp.name or ""):find("^special:minimized") then
                hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
                return
            end
        end
    end
    -- koliesko nad lištou-kvapkou: ďalšie / predošlé okno na aktuálnej ploche, bez minimalizovaných
    -- (prepnutie na minimalizované cez Wayland ukázalo celú skrytú plochu). Poradie zľava doprava (v páske
    -- je to poradie stĺpcov, fokus pásku posunie), na konci dokola
    function latte.win.cycle(dir)
        local ws = hl.get_active_workspace()
        local a = hl.get_active_window()
        local list, cur = {}, 0
        for _, w in ipairs(hl.get_windows() or {}) do
            if w.workspace and ws and w.workspace.id == ws.id then
                list[#list + 1] = w
                if a and w.address == a.address then cur = #list end
            end
        end
        if #list == 0 then return end
        local cur_w = list[cur]
        table.sort(list, function(p, q)
            if p.at.x ~= q.at.x then return p.at.x < q.at.x end
            return p.at.y < q.at.y
        end)
        cur = 0
        for i, w in ipairs(list) do if cur_w and w.address == cur_w.address then cur = i end end
        local nxt = ((cur - 1 + (dir or 1)) % #list) + 1
        hl.dispatch(hl.dsp.focus({ window = "address:" .. list[nxt].address }))
        latte.win.hide_special()
    end
    function latte.win.focus_by(class, title, nth)
        local w = by(class, title, nth)
        if w then latte.win.activate(w.address) end
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
